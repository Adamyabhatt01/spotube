import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';

final queryingTrackInfoProvider = Provider<bool>((ref) {
  // Phase 2 perf (W.2): only activeTrack is consumed here. Selecting it
  // avoids rebuilding on playing/loop/shuffle/queue edits that leave the
  // active track unchanged. See test/player_active_track_select_test.dart.
  final activeTrack =
      ref.watch(audioPlayerProvider.select((s) => s.activeTrack));

  if (activeTrack == null) {
    return false;
  }

  if (activeTrack is! SpotubeFullTrackObject) {
    return false;
  }

  return ref
      .watch(
        sourcedTrackProvider(activeTrack),
      )
      .isLoading;
});

/// Whether the active track is still resolving and has never produced audio.
///
/// [queryingTrackInfoProvider] alone is too broad: a downloaded/local fallback
/// can already be playing while the source manifest is still settling, and a
/// paused track keeps its source provider loading in the background. Playback
/// controls must stay usable in both states.
///
/// `playing` is not enough to tell an initial resolve from a pause: both are
/// silent. `hasStarted` records that the current active track has actually
/// produced audio, so once it has, pausing shows the play icon instead of
/// turning the button back into a spinner. It is reset when the active track
/// changes. Reading playback flags only after the query is known to be in
/// flight keeps ordinary play/pause toggles from rebuilding every observer of
/// this provider.
final isResolvingActiveTrackProvider = Provider<bool>((ref) {
  if (!ref.watch(queryingTrackInfoProvider)) {
    return false;
  }

  final (:hasStarted, :playing) = ref.watch(
    audioPlayerProvider.select(
      (s) => (hasStarted: s.hasStarted, playing: s.playing),
    ),
  );

  return !hasStarted && !playing;
});
