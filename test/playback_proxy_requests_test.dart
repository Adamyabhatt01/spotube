// PR 4 (C5): the playback proxy must not repeat upstream work that mpv already
// caused, and must not re-resolve paths that never change.
//
// mpv probes a stream URL with HEAD before it asks for the body, so the proxy
// sees a HEAD and then a GET for the same track seconds apart. The HEAD half
// asked upstream for the headers; the GET half asked *again*, only to read the
// content type out of the answer before opening the stream. Each track start
// therefore paid for the same upstream round trip twice, plus a
// platform-channel round trip per request for the music-cache directory.
//
// Everything here runs against a real loopback upstream, so the request counts
// are the server's own.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio_lib;
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/routes/playback.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

final _refProbeProvider = Provider<Ref>((ref) => ref);

/// path_provider stand-in that counts the platform-channel round trips.
class _CountingPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _CountingPathProvider(this.root);

  final String root;
  int cacheDirCalls = 0;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async {
    cacheDirCalls++;
    return root;
  }
}

/// Preferences with the music cache off: these tests are about what the proxy
/// asks *upstream*, and the cache branch answers from disk instead.
class _StubPrefsNotifier extends UserPreferencesNotifier {
  _StubPrefsNotifier(this.stub);

  final PreferencesTableData stub;

  @override
  PreferencesTableData build() => stub;
}

class _EmptyMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() async => const MetadataPluginState();
}

class _FixedPresetsNotifier extends AudioSourceAvailableQualityPresetsNotifier {
  _FixedPresetsNotifier(this.initial);

  final AudioSourcePresetsState initial;

  @override
  AudioSourcePresetsState build() => initial;
}

/// The audio-source plugin's answer for one track: a stream on the test
/// upstream, plus a counted `refreshStreamingUrl` standing in for re-signing.
class _FakeSourcedTrackNotifier extends SourcedTrackNotifier {
  _FakeSourcedTrackNotifier(this.sourceRef, this.url);

  final Ref sourceRef;
  String url;

  /// What the upstream serves once a URL has been re-signed.
  String refreshedUrl = '';
  int refreshCalls = 0;

  SourcedTrack trackAt(String url) {
    return SourcedTrack(
      ref: sourceRef,
      info: SpotubeAudioSourceMatchObject(
        id: 'match-1',
        title: 'Proxy Test Track',
        artists: const ['Test Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/1',
      ),
      query: _testTrack(),
      source: 'youtube',
      siblings: const [],
      sources: [
        SpotubeAudioSourceStreamObject(
          url: url,
          container: 'webm',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ],
    );
  }

  /// The current URL wrapped, the way the live provider hands it to the proxy.
  SourcedTrack get current => trackAt(url);

  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) => current;

  @override
  Future<SourcedTrack> refreshStreamingUrl() async {
    refreshCalls++;
    url = refreshedUrl;
    return current;
  }
}

SpotubeFullTrackObject _testTrack() {
  return SpotubeFullTrackObject(
    id: 'proxy-test-track',
    name: 'Proxy Test Track',
    externalUri: 'https://example.test/track/1',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'alb1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000003',
    explicit: false,
  );
}

/// Loopback "CDN": counts what the proxy actually asks it for.
class _Upstream {
  _Upstream._(this.server, this.body) {
    server.listen(_handle);
  }

  static Future<_Upstream> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _Upstream._(server, List.generate(4096, (i) => i % 251));
  }

  final HttpServer server;
  final List<int> body;

  int headCount = 0;
  int getCount = 0;
  final List<String> requestedPaths = [];

  /// A path the upstream refuses on GET only — a URL that died between the
  /// probe and the stream.
  String? failGetOn;

  /// Paths served as an HLS playlist instead of audio.
  final Set<String> hlsPaths = {};

  String url(String path) =>
      'http://${server.address.host}:${server.port}$path';

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requestedPaths.add(path);
    final isHls = hlsPaths.contains(path);
    final contentType =
        isHls ? 'application/vnd.apple.mpegurl' : 'audio/webm';

    if (req.method == 'HEAD') {
      headCount++;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', contentType)
        ..headers.set('content-length', '${body.length}')
        ..headers.set('accept-ranges', 'bytes');
      await req.response.close();
      return;
    }

    getCount++;
    if (failGetOn == path) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    final range = req.headers.value('range');
    if (range != null && !isHls) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final rawEnd = match.group(2);
        final end = (rawEnd == null || rawEnd.isEmpty)
            ? body.length - 1
            : int.parse(rawEnd);
        final slice = body.sublist(start, end + 1);
        req.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-type', contentType)
          ..headers.set('content-length', '${slice.length}')
          ..headers.set('content-range', 'bytes $start-$end/${body.length}');
        req.response.add(slice);
        await req.response.close();
        return;
      }
    }

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-type', contentType)
      ..headers.set('content-length', '${body.length}');
    req.response.add(body);
    await req.response.close();
  }
}

Future<List<int>> _readBody(dio_lib.Response response) async {
  final data = response.data;
  final stream = data is dio_lib.ResponseBody
      ? data.stream
      : data as Stream<List<int>>;
  return (await stream.fold<List<int>>(
    [],
    (acc, chunk) => acc..addAll(chunk),
  ));
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;
  late _CountingPathProvider pathProvider;
  late _Upstream upstream;
  late ProviderContainer container;
  late _FakeSourcedTrackNotifier sourced;
  late ServerPlaybackRoutes routes;
  late ProviderSubscription subscription;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('proxy_requests_');
    pathProvider = _CountingPathProvider(tempRoot.path);
    PathProviderPlatform.instance = pathProvider;
    // The cache directory is resolved once per process; each test needs its own
    // temp root, so the memo starts fresh.
    UserPreferencesNotifier.resetMusicCacheDirForTest();
    upstream = await _Upstream.start();

    container = ProviderContainer(
      overrides: [
        userPreferencesProvider.overrideWith(
          () => _StubPrefsNotifier(
            PreferencesTable.defaults().copyWith(
              downloadLocation: tempRoot.path,
              cacheMusic: false,
            ),
          ),
        ),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        metadataPluginsProvider
            .overrideWith(() => _EmptyMetadataPluginNotifier()),
        audioSourcePresetsProvider.overrideWith(
          () => _FixedPresetsNotifier(
            AudioSourcePresetsState(
              presets: [
                SpotubeAudioSourceContainerPreset.lossy(
                  type: SpotubeMediaCompressionType.lossy,
                  name: 'webm',
                  qualities: [
                    SpotubeAudioLossyContainerQuality(bitrate: 128000),
                  ],
                ),
              ],
            ),
          ),
        ),
        sourcedTrackProvider.overrideWith(
          // Built on first read, by which time `container` exists.
          () => sourced = _FakeSourcedTrackNotifier(
            container.read(_refProbeProvider),
            upstream.url('/stream.webm'),
          )..refreshedUrl = upstream.url('/refreshed.webm'),
        ),
      ],
    );
    // Held open so the family has exactly one live instance for the test.
    subscription = container.listen(
      sourcedTrackProvider(_testTrack()),
      (_, __) {},
    );
    await container.read(sourcedTrackProvider(_testTrack()).future);
    routes = container.read(serverPlaybackRoutesProvider);
  });

  tearDown(() async {
    subscription.close();
    await upstream.close();
    container.dispose();
    await tempRoot.delete(recursive: true);
  });

  Request proxyRequest({String method = 'GET', String? range}) {
    return Request(
      method,
      Uri.parse('http://127.0.0.1:1/stream/${_testTrack().id}'),
      headers: {if (range != null) 'range': range},
    );
  }

  /// What mpv does at track start: a HEAD for the headers, then the GET.
  Future<void> playOnce() async {
    await routes.streamTrackInformation(proxyRequest(method: 'HEAD'), sourced.current);
    await routes.streamTrack(proxyRequest(), sourced.current, {});
  }

  test('mpv probing then streaming sends one upstream HEAD', () async {
    await playOnce();

    // ignore: avoid_print
    print(
      'track start: upstream HEADs=${upstream.headCount} '
      'GETs=${upstream.getCount} path_provider calls=${pathProvider.cacheDirCalls}',
    );

    expect(upstream.getCount, 1);
    expect(upstream.headCount, 1, reason: 'the GET re-probed a just-probed URL');
  });

  test('a re-signed url is probed again', () async {
    await playOnce();
    final afterFirst = upstream.headCount;

    sourced.url = upstream.url('/stream.webm?sig=2');
    await playOnce();

    expect(upstream.headCount - afterFirst, 1);
  });

  test('the music cache directory is resolved once per process', () async {
    await playOnce();
    await playOnce();
    await playOnce();

    // ignore: avoid_print
    print('3 track starts: path_provider calls=${pathProvider.cacheDirCalls}');
    expect(pathProvider.cacheDirCalls, 1, reason: 're-resolved per request');
  });

  test('an hls url is redirected to the playlist, probe or no probe', () async {
    upstream.hlsPaths.add('/stream.webm');

    final head = await routes
        .streamTrackInformation(proxyRequest(method: 'HEAD'), sourced.current);
    expect(
      head.headers.value('content-type'),
      'application/vnd.apple.mpegurl',
    );

    final res = await routes.streamTrack(proxyRequest(), sourced.current, {});
    expect(res.statusCode, 301);
    expect(
      res.headers.value('location'),
      upstream.url('/stream.webm'),
      reason: 'mpv must be sent to the playlist, not the proxied body',
    );
  });

  test('a non-hls url is not redirected after an hls probe of another url',
      () async {
    upstream.hlsPaths.add('/hls.webm');
    await routes.streamTrack(
      proxyRequest(),
      sourced.trackAt(upstream.url('/hls.webm')),
      {},
    );

    final res = await routes.streamTrack(proxyRequest(), sourced.current, {});
    expect(res.statusCode, 200);
  });

  test('range requests keep their 206 slice through the proxy', () async {
    await routes
        .streamTrackInformation(proxyRequest(method: 'HEAD'), sourced.current);

    final res = await routes.streamTrack(
      proxyRequest(range: 'bytes=100-199'),
      sourced.current,
      {'range': 'bytes=100-199'},
    );

    expect(res.statusCode, 206);
    expect(res.headers.value('content-range'), 'bytes 100-199/4096');
    expect(await _readBody(res), upstream.body.sublist(100, 200));
  });

  test('an expired url is re-signed before the proxy asks for anything',
      () async {
    sourced.url = upstream.url('/stream.webm?expire=1000');

    await routes.streamTrack(proxyRequest(), sourced.current, {});

    expect(sourced.refreshCalls, 1);
    expect(upstream.requestedPaths.last, '/refreshed.webm');
  });

  test('a stream that fails still reaches the fallback cascade', () async {
    // Probe first so the stream takes the reused answer, then make the body
    // request fail: the failure handling must be untouched by the skipped probe.
    await routes
        .streamTrackInformation(proxyRequest(method: 'HEAD'), sourced.current);
    upstream.failGetOn = '/stream.webm';

    await expectLater(
      routes.streamTrack(proxyRequest(), sourced.current, {}),
      throwsA(anything),
    );
    expect(upstream.getCount, 1, reason: 'the GET never happened');
  });
}
