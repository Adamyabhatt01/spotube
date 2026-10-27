import 'package:spotube/provider/radio/radio_playback.dart';

/// Serializes the two audio-focus directions between music and radio.
///
/// Radio owns a second native player, so a transition must either silence
/// music *before* the station opens or dispose the station player *before*
/// music resumes. Making that ordering an awaited API keeps callers from
/// relying on the stream ordering of the two players.
class PlaybackHandoff {
  final MusicPlaybackDelegate music;

  Future<void>? _radioTeardown;

  PlaybackHandoff(this.music);

  /// Music → radio: silence music and await the pause before radio opens.
  Future<void> toRadio() => music.pauseMusic();

  /// Radio → music: run [teardown] (which includes the native dispose) and
  /// return only when it finished. Concurrent callers share one teardown, so
  /// a stop racing a station switch cannot dispose the same backend twice.
  Future<void> toMusic(Future<void> Function() teardown) {
    return _radioTeardown ??= teardown().whenComplete(() {
      _radioTeardown = null;
    });
  }
}
