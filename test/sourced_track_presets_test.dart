// Regression test for Phase 2 change#2: audio quality preset changes must
// NOT rebuild `sourcedTrackProvider` instances (preset state is not a
// resolution input — the manifest fetch is quality-agnostic and quality is
// picked dynamically in `SourcedTrack.url`).
//
// Runs in a bare ProviderContainer: the audio-source plugin is overridden to
// resolve `null`, so `fetchFromTrack` fails fast deterministically without
// touching hetu, the database, or the network.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';

/// Stub that fails fast without touching the database, hetu, or plugins.
/// The real `MetadataPluginNotifier.build` opens a Drift stream subscription
/// that requires Flutter bindings + native sqlite — unavailable in unit
/// tests. An error state is sufficient here: the edge under test is
/// `sourcedTrack -> audioSourcePresets`, and both of those providers are
/// real.
class _FailingMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() {
    throw StateError('no metadata plugins in unit tests');
  }
}

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

void main() {
  test(
    'changing audio quality presets does not rebuild sourcedTrack resolution',
    () async {
      final container = ProviderContainer(
        overrides: [
          audioSourcePluginProvider.overrideWith((ref) => Future.value()),
          metadataPluginsProvider
              .overrideWith(() => _FailingMetadataPluginNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final track = _testTrack();
      var notifications = 0;
      container.listen(
        sourcedTrackProvider(track),
        (_, __) => notifications++,
      );

      // Initial build: fetchFromTrack throws (null plugin) -> error state.
      container.read(sourcedTrackProvider(track));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        container.read(sourcedTrackProvider(track)).hasError,
        isTrue,
        reason: 'test setup: resolution must fail fast with null plugin',
      );
      final notificationsAfterBuild = notifications;

      // Change quality presets. State is assigned directly to avoid the
      // SharedPreferences/network persistence side-channel, which is
      // unrelated to resolution inputs.
      final presetsNotifier =
          container.read(audioSourcePresetsProvider.notifier);
      presetsNotifier.state = presetsNotifier.state.copyWith(
        selectedStreamingQualityIndex: 1,
        selectedStreamingContainerIndex: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        notifications,
        notificationsAfterBuild,
        reason: 'preset change must not rebuild sourcedTrack instances',
      );
    },
  );
}
