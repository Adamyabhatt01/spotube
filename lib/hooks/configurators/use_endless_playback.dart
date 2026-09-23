import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

/// Single-flight + served marker for queue-end radio fetches.
///
/// Without it the tail fires twice: the effect calls `listener` manually on
/// mount-at-end *and* subscribes to `currentIndexChangedStream`, and it
/// re-subscribes on every queue mutation (including the `addTracks` the
/// listener itself performs). One slot is enough — only the current tail can
/// trigger, and a served tail stays served until the queue moves it (which
/// changes the tail id, so no reset hook is needed).
@visibleForTesting
class EndlessRadioGate {
  String? _serving;
  String? _served;

  /// First claim for [trackId] wins; repeat and concurrent claims lose.
  bool claim(String trackId) {
    if (_served == trackId || _serving == trackId) return false;
    _serving = trackId;
    return true;
  }

  /// The claim failed or came back empty: a later tail event may retry.
  void release(String trackId) {
    if (_serving == trackId) _serving = null;
  }

  /// The claim appended (even zero rows after dupe-filtering): this tail is
  /// done. A later event for the same id would only re-append duplicates
  /// that `removeWhere` drops again, so skipping it saves a whole fetch.
  void serve(String trackId) {
    if (_serving == trackId) _serving = null;
    _served = trackId;
  }
}

final _endlessRadioGate = EndlessRadioGate();

void useEndlessPlayback(WidgetRef ref) {
  final playback = ref.watch(audioPlayerProvider.notifier);
  // Perf: the effect only depends on queue shape + position, not on
  // playing/loop/shuffle toggles.
  final queueTracks =
      ref.watch(audioPlayerProvider.select((s) => s.tracks));
  final currentIndex =
      ref.watch(audioPlayerProvider.select((s) => s.currentIndex));
  final endlessPlayback =
      ref.watch(userPreferencesProvider.select((s) => s.endlessPlayback));
  final metadataPlugin = ref.watch(metadataPluginProvider.future);

  useEffect(
    () {
      if (!endlessPlayback) return null;

      void listener(int index) async {
        try {
          final playlist = ref.read(audioPlayerProvider);
          if (index != playlist.tracks.length - 1) return;

          final track = playlist.tracks.last;
          // Mount-at-end plus the index stream (plus every resubscribe the
          // append below causes) would each fetch radio for this tail.
          if (!_endlessRadioGate.claim(track.id)) return;
          try {
            final tracks = await (await metadataPlugin)?.track.radio(track.id);

            if (tracks == null || tracks.isEmpty) return;

            await playback.addTracks(
              tracks.toList()
                ..removeWhere((e) {
                  final playlist = ref.read(audioPlayerProvider);
                  final isDuplicate = playlist.tracks.any((t) => t.id == e.id);
                  return e.id == track.id || isDuplicate;
                }),
            );
            _endlessRadioGate.serve(track.id);
          } finally {
            // Empty and failed claims stay retryable; served ones do not.
            _endlessRadioGate.release(track.id);
          }
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }

      // Sometimes user can change settings for which the currentIndexChanged
      // might not be called. So we need to check if the current track is the
      // last track and if it is then we need to call the listener manually.
      if (currentIndex == queueTracks.length - 1 &&
          audioPlayer.isPlaying) {
        listener(currentIndex);
      }

      final subscription =
          audioPlayer.currentIndexChangedStream.listen(listener);

      return subscription.cancel;
    },
    [
      metadataPlugin,
      playback,
      queueTracks,
      currentIndex,
      endlessPlayback,
    ],
  );
}
