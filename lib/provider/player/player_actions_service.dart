import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/volume_provider.dart';

/// The transport verbs, with no idea who asked for them.
///
/// A theme widget and a spoken command want the same thing out of these six:
/// the same empty-queue guard, the same clamping, the same persisted volume.
/// Both dispatch here instead of each keeping its own copy, so a rule about
/// "seek" can only ever be written once.
///
/// Every method reads through [ref] rather than taking a player as an argument
/// — the port is a provider so tests can replace it, and callers must not be
/// able to hand in a player that bypasses the guards.
class PlayerActionsService {
  const PlayerActionsService(this.ref);

  final Ref ref;

  bool get _hasActiveTrack => ref.read(audioPlayerProvider).activeTrack != null;

  Future<void> playPause() async {
    if (!_hasActiveTrack) return;
    final player = ref.read(audioPlayerPortProvider);
    if (player.isPlaying) {
      await player.pause();
    } else {
      await player.resume();
    }
  }

  Future<void> next() async {
    if (!_hasActiveTrack) return;
    await ref.read(audioPlayerPortProvider).skipToNext();
  }

  Future<void> previous() async {
    if (!_hasActiveTrack) return;
    await ref.read(audioPlayerPortProvider).skipToPrevious();
  }

  /// Starts or keeps playback, and never restarts a track that is already
  /// playing.
  ///
  /// "play" and "toggle playback" are different spoken commands: a theme's
  /// button is allowed to pause what the user just asked to hear.
  Future<void> resume() async {
    if (!_hasActiveTrack) return;
    final player = ref.read(audioPlayerPortProvider);
    if (!player.isPlaying) await player.resume();
  }

  Future<void> pause() async {
    final player = ref.read(audioPlayerPortProvider);
    if (player.isPlaying) await player.pause();
  }

  /// Moves the playhead by [step] from where it is, clamped inside the track.
  ///
  /// A relative command cannot be expressed as a `seek` argument because the
  /// caller would have to read the position itself — and a voice command hears
  /// "ten seconds" as a number long before anything knows where the playhead
  /// is. The clamp lives here so "forward" at the end of a song stays at the
  /// end instead of seeking past it.
  Future<void> seekBy(Duration step) async {
    if (!_hasActiveTrack) return;
    final player = ref.read(audioPlayerPortProvider);
    final duration = player.duration;
    var target = player.position + step;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  /// Seeks to `position` seconds, or to `fraction` of the current duration.
  ///
  /// A theme slider and "rewind ten seconds" both arrive as loose JSON, so the
  /// clamping is the whole point: nothing upstream can put the playhead past
  /// the end of the track.
  Future<void> seek(Map<String, dynamic> args) async {
    final player = ref.read(audioPlayerPortProvider);
    final duration = player.duration;
    final seconds = args['position'];
    final fraction = args['fraction'];
    final target = switch ((seconds, fraction)) {
      (final num value, _) => Duration(milliseconds: (value * 1000).round()),
      (_, final num value) => Duration(
          milliseconds: (duration.inMilliseconds * value.clamp(0, 1)).round(),
        ),
      _ => null,
    };
    if (target == null) return;
    final max = duration > Duration.zero ? duration : target;
    await player.seek(
      Duration(
        milliseconds:
            target.inMilliseconds.clamp(0, max.inMilliseconds).toInt(),
      ),
    );
  }

  /// Sets the level, or moves it by `delta` from where it is now.
  ///
  /// The clamped value lands on [volumeProvider], which owns the persisted
  /// level — this must not write the player's runtime volume directly, or the
  /// next track would restart at the unclamped number.
  Future<void> setVolume(Map<String, dynamic> args) async {
    final current = ref.read(volumeProvider);
    final raw = args['volume'] ?? args['value'];
    final target = switch (raw) {
      final num value => value.toDouble(),
      _ => args['delta'] is num
          ? current + (args['delta'] as num).toDouble()
          : null,
    };
    if (target == null || !target.isFinite) return;
    await ref.read(volumeProvider.notifier).setVolume(target.clamp(0, 1));
  }

  Future<void> like() async {
    final track = ref.read(audioPlayerProvider).activeTrack;
    if (track == null) return;
    await ref
        .read(metadataPluginSavedTracksProvider.notifier)
        .toggleFavorite(track);
  }
}

final playerActionsServiceProvider = Provider<PlayerActionsService>(
  (ref) => PlayerActionsService(ref),
);
