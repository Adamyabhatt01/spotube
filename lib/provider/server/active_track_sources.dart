import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

final activeTrackSourcesProvider = FutureProvider<
    ({
      SourcedTrack? source,
      SourcedTrackNotifier? notifier,
    SpotubeTrackObject track,
  })?>((ref) async {
  // Phase 2 perf (W.2): only activeTrack is consumed here. Selecting it
  // avoids rebuilding on playing/loop/shuffle/queue edits that leave the
  // active track unchanged. See test/player_active_track_select_test.dart.
  final activeTrack =
      ref.watch(audioPlayerProvider.select((s) => s.activeTrack));

  if (activeTrack == null) {
    return null;
  }

  if (activeTrack is SpotubeLocalTrackObject) {
    return (
      source: null,
      notifier: null,
      track: activeTrack,
    );
  }

  final sourcedTrack = await ref.watch(
    sourcedTrackProvider(
      // ignore: unnecessary_cast — removal is a compile error
      // (argument_type_not_assignable); the analyzer mis-fires here because
      // SpotubeTrackObject is a freezed union and promotion does not narrow
      // past the local-track early return above.
      activeTrack as SpotubeFullTrackObject,
    ).future,
  );
  final sourcedTrackNotifier = ref.watch(
    sourcedTrackProvider(
      // ignore: unnecessary_cast — see above.
      activeTrack as SpotubeFullTrackObject,
    ).notifier,
  );

  return (
    source: sourcedTrack,
    track: activeTrack,
    notifier: sourcedTrackNotifier,
  );
});
