// Integration tests for the ACTUAL DownloadManagerNotifier cancel path
// (audit H1). These drive addToQueue/cancel/retry against a real loopback
// HTTP server with a delayed body — no CancelToken stubs.
//
// Covered:
//  - cancel during transfer cancels the live Dio request, leaves the task
//    `canceled`, deletes the partial file, and the late server completion
//    cannot flip the task to `completed`.
//  - retry after cancellation re-queues with a FRESH CancelToken and the
//    download then completes (a spent token would fail immediately).

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

/// Serves the fake temp directory chunkDownload asks path_provider for
/// (same pattern as test/chunk_download_test.dart). Avoiding
/// TestWidgetsFlutterBinding keeps real loopback HTTP working.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _StubPrefsNotifier extends UserPreferencesNotifier {
  PreferencesTableData stub;

  _StubPrefsNotifier(this.stub);

  @override
  PreferencesTableData build() => stub;
}

class _EmptyMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() async => const MetadataPluginState();
}

/// Fixed presets so the download worker immediately sees the test's `weba`
/// container — no dependency on the plugin-loading rebuild lifecycle.
class _FixedPresetsNotifier extends AudioSourceAvailableQualityPresetsNotifier {
  _FixedPresetsNotifier(this.initial);

  final AudioSourcePresetsState initial;

  @override
  AudioSourcePresetsState build() => initial;
}

class _LazySourcedTrackNotifier extends SourcedTrackNotifier {
  _LazySourcedTrackNotifier(this.sourceRef, this.url);

  final Ref sourceRef;
  final String url;

  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) {
    return SourcedTrack(
      ref: sourceRef,
      info: SpotubeAudioSourceMatchObject(
        id: 'match-1',
        title: 'Cancel Test Track',
        artists: const ['Test Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/1',
      ),
      query: query,
      source: 'youtube',
      siblings: const [],
      sources: [
        SpotubeAudioSourceStreamObject(
          url: url,
          container: 'weba',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ],
    );
  }
}

SpotubeFullTrackObject _testTrack() {
  return SpotubeFullTrackObject(
    id: 'cancel-test-track',
    name: 'Cancel Test Track',
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
    isrc: 'TEST00000002',
    explicit: false,
  );
}

Future<HttpServer> _startSlowServer(List<int> payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (req.method == 'HEAD') {
      req.response
        ..headers.set('content-length', '${payload.length}')
        ..headers.set('accept-ranges', 'bytes');
      await req.response.close();
      return;
    }
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-length', '${payload.length}');
    // Dribble in 6 segments so cancellation happens mid-body.
    final chunk = (payload.length / 6).ceil();
    for (var i = 0; i < payload.length; i += chunk) {
      req.response.add(
        payload.sublist(i, i + chunk > payload.length
            ? payload.length
            : i + chunk),
      );
      await req.response.flush();
      await Future.delayed(const Duration(milliseconds: 80));
    }
    await req.response.close();
  });
  return server;
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;
  late HttpServer server;
  late List<int> payload;
  late ProviderContainer container;
  late _StubPrefsNotifier prefs;
  final track = _testTrack();

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('dl_cancel_');
    // Dio's chunkDownload stages parts under getTemporaryDirectory().
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
    payload = List.generate(60 * 1024, (i) => i % 256);
    server = await _startSlowServer(payload);

    prefs = _StubPrefsNotifier(
      PreferencesTable.defaults().copyWith(downloadLocation: tempRoot.path),
    );
    final streamUrl =
        'http://${server.address.host}:${server.port}/stream.weba';

    // Presets must expose a container matching the test stream so
    // `_pickDownloadUrl` resolves.
    final presetsState = AudioSourcePresetsState(
      presets: [
        SpotubeAudioSourceContainerPreset.lossy(
          type: SpotubeMediaCompressionType.lossy,
          name: 'weba',
          qualities: [SpotubeAudioLossyContainerQuality(bitrate: 128000)],
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        userPreferencesProvider.overrideWith(() => prefs),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        metadataPluginsProvider
            .overrideWith(() => _EmptyMetadataPluginNotifier()),
        audioSourcePresetsProvider.overrideWith(
          () => _FixedPresetsNotifier(presetsState),
        ),
        sourcedTrackProvider.overrideWith(
          // `container` is initialized by the time the provider is read.
          () => _LazySourcedTrackNotifier(
            container.read(_refProbeProvider),
            streamUrl,
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await server.close(force: true);
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  DownloadTask? taskState() => container
      .read(downloadManagerProvider)
      .firstWhereOrNull((e) => e.track.id == track.id);

  test('cancel during transfer stops the download and cannot become completed',
      () async {
    container.read(downloadManagerProvider.notifier).addToQueue(track);

    // Wait until the worker actually starts transferring.
    await _waitFor(
      () => taskState()?.status == DownloadStatus.downloading,
      'download to start',
      describe: () => 'last state: ${taskState()?.status}',
    );

    container.read(downloadManagerProvider.notifier).cancel(track);

    expect(
      taskState()!.cancelToken.isCancelled,
      isTrue,
      reason: 'notifier cancel must reach the live Dio CancelToken',
    );
    expect(taskState()!.status, DownloadStatus.canceled);

    // Let the server finish streaming after cancellation.
    await Future.delayed(const Duration(milliseconds: 800));

    expect(
      taskState()?.status,
      DownloadStatus.canceled,
      reason: 'late completion must not flip a canceled task to completed',
    );
    final leftovers = tempRoot
        .listSync()
        .where((e) => e.path.contains('Cancel Test Track'))
        .toList();
    expect(leftovers, isEmpty, reason: 'partial file must not survive cancel');
  });

  test('retry after cancel uses a fresh token and completes', () async {
    final notifier = container.read(downloadManagerProvider.notifier);
    notifier.addToQueue(track);
    await _waitFor(
      () => taskState()?.status == DownloadStatus.downloading,
      'download to start',
      describe: () => 'last state: ${taskState()?.status}',
    );
    notifier.cancel(track);
    final spentToken = taskState()!.cancelToken;
    expect(spentToken.isCancelled, isTrue);

    notifier.retry(track);

    final retried = taskState()!;
    // The pool claims synchronously, so the task may already be past
    // `queued` — the point is that it left `canceled` and runs again.
    expect(
      [DownloadStatus.queued, DownloadStatus.downloading],
      contains(retried.status),
    );
    expect(
      identical(retried.cancelToken, spentToken),
      isFalse,
      reason: 'a spent CancelToken must be rotated on retry',
    );

    await _waitFor(
      () => taskState()?.status == DownloadStatus.completed,
      'retried download to complete',
      timeoutMs: 8000,
      describe: () => 'last state: ${taskState()?.status}',
    );
    expect(taskState()!.status, DownloadStatus.completed);
    expect(
      tempRoot
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.weba')),
      isTrue,
    );
  });
}

final _refProbeProvider = Provider<Ref>((ref) => ref);

Future<void> _waitFor(
  bool Function() condition,
  String what, {
  int timeoutMs = 5000,  required String Function() describe,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Timed out waiting for $what; ${describe()}');
}
