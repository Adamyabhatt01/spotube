// Proxy-level test for Phase 2 proactive expiry: an expired selected URL
// must trigger exactly one refresh before serving; fresh/unknown URLs must
// not refresh; refresh failure must fall back to the stale URL (existing
// reactive path) rather than throwing.
//
// Hermetic: the audio-source plugin resolves null, metadata plugins fail
// fast (no hetu/DB), and the sourcedTrack family is overridden with a fake
// that only counts refresh calls. The real ServerPlaybackRoutes
// selection branch is under test.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/routes/playback.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

class _FailingMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() {
    throw StateError('no metadata plugins in unit tests');
  }
}

class _FakeSourcedTrackNotifier extends SourcedTrackNotifier {
  int refreshCalls = 0;
  SourcedTrack? refreshedTrack;
  Object? refreshError;

  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) {
    throw StateError('unused in this test');
  }

  @override
  Future<SourcedTrack> refreshStreamingUrl() async {
    refreshCalls++;
    if (refreshError != null) throw refreshError!;
    return refreshedTrack!;
  }
}

final _refProbeProvider = Provider<Ref>((ref) => ref);

SpotubeFullTrackObject _testTrack() {
  return SpotubeFullTrackObject(
    id: 'test-track-1',
    name: 'Test Track',
    externalUri: 'https://example.test/track/1',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'test-artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

String _streamUrlWithExpire(Object expire) =>
    'https://rr1.googlevideo.com/videoplayback?expire=$expire&id=abc&itag=251';

SpotubeAudioSourceStreamObject _stream(String url) {
  return SpotubeAudioSourceStreamObject(
    url: url,
    container: 'webm',
    type: SpotubeMediaCompressionType.lossy,
    bitrate: 128000.0,
  );
}

void main() {
  AppLogger.initialize(false);

  late ProviderContainer container;
  late Ref ref;
  late _FakeSourcedTrackNotifier fake;

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        audioSourcePluginProvider.overrideWith((ref) => Future.value()),
        metadataPluginsProvider
            .overrideWith(() => _FailingMetadataPluginNotifier()),
        sourcedTrackProvider.overrideWith(() {
          fake = _FakeSourcedTrackNotifier();
          return fake;
        }),
      ],
    );

    // Let the overridden plugin future settle (loading -> data) BEFORE
    // assigning presets state: presets rebuilds on that transition, which
    // would otherwise discard the assignment below.
    await container.read(audioSourcePluginProvider.future);

    // Presets must offer a container/quality matching the test streams so
    // `SourcedTrack.url` resolves instead of throwing on empty presets.
    final presetsNotifier =
        container.read(audioSourcePresetsProvider.notifier);
    presetsNotifier.state = AudioSourcePresetsState(
      presets: [
        SpotubeAudioSourceContainerPreset.lossy(
          type: SpotubeMediaCompressionType.lossy,
          name: 'webm',
          qualities: [
            SpotubeAudioLossyContainerQuality(bitrate: 128000),
          ],
        ),
      ],
    );

    ref = container.read(_refProbeProvider);
  });

  tearDown(() => container.dispose());

  SourcedTrack makeSourcedTrack(String url) {
    final track = _testTrack();
    return SourcedTrack(
      ref: ref,
      info: SpotubeAudioSourceMatchObject(
        id: 'match-1',
        title: 'Test Track',
        artists: const ['Test Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/1',
      ),
      query: track,
      source: 'youtube',
      siblings: const [],
      sources: [_stream(url)],
    );
  }

  test('expired URL triggers exactly one refresh before serving', () async {
    final pastSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
    final freshSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final stale = makeSourcedTrack(_streamUrlWithExpire(pastSeconds));

    // Mount the fake notifier, then arm its refresh result.
    container.read(sourcedTrackProvider(stale.query).notifier);
    fake.refreshedTrack = makeSourcedTrack(_streamUrlWithExpire(freshSeconds));

    final routes = ServerPlaybackRoutes(ref);
    final url = await routes.resolveServingUrl(stale);

    expect(url, _streamUrlWithExpire(freshSeconds));
    expect(fake.refreshCalls, 1);
  });

  test('fresh URL is served without refresh', () async {
    final freshSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final freshUrl = _streamUrlWithExpire(freshSeconds);
    final track = makeSourcedTrack(freshUrl);

    container.read(sourcedTrackProvider(track.query).notifier);

    final routes = ServerPlaybackRoutes(ref);
    expect(await routes.resolveServingUrl(track), freshUrl);
    expect(fake.refreshCalls, 0);
  });

  test('unknown expiry is served without refresh', () async {
    const plainUrl = 'https://example.test/audio/track-1.webm';
    final track = makeSourcedTrack(plainUrl);

    container.read(sourcedTrackProvider(track.query).notifier);

    final routes = ServerPlaybackRoutes(ref);
    expect(await routes.resolveServingUrl(track), plainUrl);
    expect(fake.refreshCalls, 0);
  });

  test('refresh failure falls back to the stale URL', () async {
    final pastSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
    final staleUrl = _streamUrlWithExpire(pastSeconds);
    final track = makeSourcedTrack(staleUrl);

    container.read(sourcedTrackProvider(track.query).notifier);
    fake.refreshError = StateError('all sources dead');

    final routes = ServerPlaybackRoutes(ref);
    expect(await routes.resolveServingUrl(track), staleUrl);
    expect(fake.refreshCalls, 1);
  });
}
