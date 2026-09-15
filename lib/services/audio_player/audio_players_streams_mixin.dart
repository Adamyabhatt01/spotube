part of 'audio_player.dart';

mixin SpotubeAudioPlayersStreams on AudioPlayerInterface {
  // stream getters
  Stream<Duration> get durationStream {
    return _mkPlayer.stream.duration;
  }

  Stream<Duration> get positionStream {
    return _mkPlayer.stream.position;
  }

  Stream<Duration> get bufferedPositionStream {
    return _mkPlayer.stream.buffer;
  }

  Stream<void> get completedStream {
    return _mkPlayer.stream.completed;
  }

  Stream<int> percentCompletedStream(double percent) {
    return positionStream
        .asyncMap(
          (position) async => duration == Duration.zero
              ? 0
              : (position.inSeconds / duration.inSeconds * 100).toInt(),
        )
        .where((event) => event >= percent);
  }

  Stream<bool> get playingStream {
    return _mkPlayer.stream.playing;
  }

  Stream<bool> get shuffledStream {
    return _mkPlayer.shuffleStream;
  }

  Stream<PlaylistMode> get loopModeStream {
    return _mkPlayer.stream.playlistMode;
  }

  Stream<double> get volumeStream {
    return _mkPlayer.stream.volume.map((event) => event / 100);
  }

  Stream<bool> get bufferingStream {
    return Stream.value(false);
  }

  Stream<AudioPlaybackState> get playerStateStream {
    return _mkPlayer.playerStateStream;
  }

  Stream<int> get currentIndexChangedStream {
    return _mkPlayer.indexChangeStream;
  }

  Stream<String> get activeSourceChangedStream {
    return _mkPlayer.indexChangeStream
        .map((event) {
          return _mkPlayer.state.playlist.medias.elementAtOrNull(event)?.uri;
        })
        .where((event) => event != null)
        .cast<String>();
  }

  Stream<List<mk.AudioDevice>> get devicesStream =>
      _mkPlayer.stream.audioDevices.asBroadcastStream();

  Stream<mk.AudioDevice> get selectedDeviceStream =>
      _mkPlayer.stream.audioDevice.asBroadcastStream();

  Stream<String> get errorStream => _mkPlayer.stream.error;

  Stream<mk.Playlist> get playlistStream => _mkPlayer.stream.playlist;
}
