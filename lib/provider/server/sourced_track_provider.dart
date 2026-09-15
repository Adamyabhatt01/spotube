import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

class SourcedTrackNotifier
    extends AutoDisposeFamilyAsyncNotifier<SourcedTrack, SpotubeFullTrackObject> {
  @override
  FutureOr<SourcedTrack> build(query) {
    // Phase 2 perf (2.2): only the audio-source PLUGIN is watched here.
    // `audioSourcePresetsProvider` was previously watched too, so every
    // quality-preset tweak rebuilt all live instances and re-ran a full
    // `streams()` manifest fetch — yet `fetchFromTrack` never consumes
    // presets (the manifest is quality-agnostic; quality is picked
    // dynamically in `SourcedTrack.url` via `ref.read`). Dropping the watch
    // is behavior-preserving. See test/sourced_track_presets_test.dart.
    ref.watch(audioSourcePluginProvider);

    return SourcedTrack.fetchFromTrack(query: query, ref: ref);
  }

  Future<SourcedTrack> refreshStreamingUrl() async {
    return await update((prev) async {
      return await prev.refreshStream();
    });
  }

  Future<SourcedTrack> copyWithSibling() async {
    return await update((prev) async {
      return prev.copyWithSibling();
    });
  }

  Future<SourcedTrack> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    return await update((prev) async {
      return await prev.swapWithSibling(sibling) ?? prev;
    });
  }

  Future<SourcedTrack> swapWithNextSibling() async {
    return await update((prev) async {
      return await prev.swapWithSibling(prev.siblings.first) as SourcedTrack;
    });
  }
}

final sourcedTrackProvider = AutoDisposeAsyncNotifierProviderFamily<
    SourcedTrackNotifier, SourcedTrack, SpotubeFullTrackObject>(
  () => SourcedTrackNotifier(),
);

/// Tracks whose resolved manifests stay in memory: the active track plus
/// the next-up track. Everything else in [sourcedTrackProvider] is
/// transient (one-shot resolutions auto-dispose when unlistened), so a
/// long session cannot accumulate every manifest ever resolved.
///
/// Playback lifecycle this protects:
/// resolve A → pre-warm A → resolve others → A stays (retained here) →
/// completion → A evictable → later use re-resolves from DB + network.
/// Manifests are small (URLs, not audio); eviction only costs a
/// re-resolution, never correctness.
List<SpotubeFullTrackObject> retainedSourcedTracks({
  required List<SpotubeTrackObject> tracks,
  required int currentIndex,
}) {
  final retained = <SpotubeFullTrackObject>[];
  for (final index in [currentIndex, currentIndex + 1]) {
    if (index < 0 || index >= tracks.length) continue;
    final track = tracks[index];
    // Local tracks never enter the family (argument is Full-only).
    if (track is SpotubeFullTrackObject) retained.add(track);
  }
  return retained;
}

/// Holds [retainedSourcedTracks] alive by subscription. Watched from the
/// app root for the app lifetime; rebuilds (releasing changed-out tracks)
/// only on queue structural changes, never on playing/loop/shuffle.
/// Auto-dispose so releasing the last watcher cascades to the family
/// instances (verified by the lifecycle test).
final sourcedTrackRetentionProvider = AutoDisposeProvider<void>((ref) {
  final queue = ref.watch(
    audioPlayerProvider.select((s) => (s.tracks, s.currentIndex)),
  );
  for (final track in retainedSourcedTracks(
    tracks: queue.$1,
    currentIndex: queue.$2,
  )) {
    ref.listen(sourcedTrackProvider(track), (_, __) {});
  }
});
