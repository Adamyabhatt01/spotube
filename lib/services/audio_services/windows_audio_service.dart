import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/audio_player/playback_state.dart';

class WindowsAudioService {
  final SMTCWindows smtc;
  final Future<void> Function() _onStop;
  final AudioPlayerPort _player;

  final subscriptions = <StreamSubscription>[];

  WindowsAudioService(this._onStop, this._player)
      : smtc = SMTCWindows(enabled: false) {
    smtc.setPlaybackStatus(PlaybackStatus.stopped);
    final buttonStream = smtc.buttonPressStream.listen((event) {
      switch (event) {
        case PressedButton.play:
          _player.resume();
          break;
        case PressedButton.pause:
          _player.pause();
          break;
        case PressedButton.next:
          _player.skipToNext();
          break;
        case PressedButton.previous:
          _player.skipToPrevious();
          break;
        case PressedButton.stop:
          _onStop();
          break;
        default:
          break;
      }
    });

    final playerStateStream =
        _player.playerStateStream.listen((state) async {
      switch (state) {
        case AudioPlaybackState.playing:
          await smtc.setPlaybackStatus(PlaybackStatus.playing);
          break;
        case AudioPlaybackState.paused:
          await smtc.setPlaybackStatus(PlaybackStatus.paused);
          break;
        case AudioPlaybackState.stopped:
          await smtc.setPlaybackStatus(PlaybackStatus.stopped);
          break;
        case AudioPlaybackState.completed:
          await smtc.setPlaybackStatus(PlaybackStatus.changing);
          break;
        default:
          break;
      }
    });

    final positionStream = _player.positionTickStream.listen((pos) async {
      // Shared whole-second ticks (see PositionTicker). Playback-status
      // changes bypass this path.
      await smtc.setPosition(pos);
    });

    final durationStream = _player.durationStream.listen((duration) async {
      await smtc.setEndTime(duration);
    });

    subscriptions.addAll([
      buttonStream,
      playerStateStream,
      positionStream,
      durationStream,
    ]);
  }

  Future<void> addTrack(SpotubeTrackObject track) async {
    if (!smtc.enabled) {
      await smtc.enableSmtc();
    }
    await smtc.updateMetadata(
      MusicMetadata(
        title: track.name,
        albumArtist: track.artists.firstOrNull?.name ?? "Unknown",
        artist: track.artists.asString(),
        album: track.album.name,
        thumbnail: (track.album.images).asUrlString(
          placeholder: ImagePlaceholder.albumArt,
        ),
      ),
    );
  }

  void dispose() {
    smtc.disableSmtc();
    smtc.dispose();
    for (var element in subscriptions) {
      element.cancel();
    }
  }
}
