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

/// Whether the active track is still resolving and there is no audible
/// playback to control.
///
/// [queryingTrackInfoProvider] alone is too broad: a downloaded/local fallback
/// can already be playing while the source manifest is still settling. Playback
/// controls must stay usable in that state. Reading `playing` only after the
/// query is known to be in flight keeps ordinary play/pause toggles from
/// rebuilding every observer of this provider.
final isResolvingActiveTrackProvider = Provider<bool>((ref) {
  if (!ref.watch(queryingTrackInfoProvider)) {
    return false;
  }

  return !ref.watch(audioPlayerProvider.select((s) => s.playing));
});
