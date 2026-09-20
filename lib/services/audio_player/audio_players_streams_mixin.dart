part of 'audio_player.dart';

mixin SpotubeAudioPlayersStreams on AudioPlayerInterface {
  // stream getters
  Stream<Duration> get durationStream {
    return _mkPlayer.stream.duration;
  }

  Stream<Duration>? _countedPositionStream;
  PositionTicker? _positionTicker;

  /// Wrapped in a counting `map` only outside release builds; media_kit's
  /// `position` is a broadcast stream and `map` preserves that, so every
  /// consumer keeps receiving the same events from the same source.
  Stream<Duration> get positionStream {
    if (!kPerfCountersEnabled) return _mkPlayer.stream.position;
    return _countedPositionStream ??= _mkPlayer.stream.position.map((position) {
      PerfCounters.note('position.rawDispatch');
      return position;
    });
  }

  /// Shared whole-second ticks for consumers that never need finer position
  /// resolution than a second. Lazy: the upstream subscription exists only
  /// once someone asks, which in practice is the first player UI mounting.
  /// See [PositionTicker] for the emission contract.
  Stream<Duration> get positionTickStream {
    return (_positionTicker ??= PositionTicker(positionStream)).stream;
  }

  /// Drops the current second so the next position event passes the gate —
  /// called on seek, where the position jumps without crossing seconds in
  /// order.
  void _invalidatePositionTick() => _positionTicker?.invalidate();

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
