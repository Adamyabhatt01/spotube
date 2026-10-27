import 'package:media_kit/media_kit.dart' as mk;

import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/services/audio_player/player_backend.dart';

/// Playback surface the app depends on.
///
/// Deliberately narrow and free of private members so it can be implemented
/// from another library: tests (and, later, a non-mpv backend) supply their own
/// implementation instead of reaching for the process-wide player. The
/// concrete media_kit implementation stays in `audio_player.dart`.
abstract interface class AudioPlayerPort implements PlayerBackend {
  // Transport
  @override
  Future<void> pause();

  /// Starts/resumes the queue. [play] is the shared backend-contract name.
  Future<void> resume();
  @override
  Future<void> play();
  @override
  Future<void> stop();
  Future<void> seek(Duration position);

  /// Output level as a 0.0–1.0 fraction.
  @override
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setAudioDevice(mk.AudioDevice device);
  @override
  Future<void> dispose();

  // Queue
  Future<void> openPlaylist(
    List<mk.Media> tracks, {
    bool autoPlay = true,
    int initialIndex = 0,
  });
  Future<void> addTrack(mk.Media media);
  Future<void> addTrackAt(mk.Media media, int index);
  Future<void> removeTrack(int index);
  Future<void> moveTrack(int from, int to);
  Future<void> clearPlaylist();
  Future<void> jumpTo(int index);
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  List<String> get sources;
  String? get currentSource;
  String? get nextSource;
  String? get previousSource;
  int get currentIndex;

  // Modes and effects
  Future<void> setShuffle(bool shuffle);
  Future<void> setLoopMode(mk.PlaylistMode loop);
  Future<void> setAudioNormalization(bool normalize);
  Future<void> setDemuxerBufferSize(int sizeInBytes);

  // Snapshot state
  Duration get duration;
  Duration get position;
  Duration get bufferedPosition;
  mk.Playlist get playlist;
  Future<mk.AudioDevice> get selectedDevice;
  Future<List<mk.AudioDevice>> get devices;
  bool get isPlaying;
  bool get isPaused;
  Future<bool> get isCompleted;
  bool get isShuffled;
  mk.PlaylistMode get loopMode;
  double get volume;
  bool get isBuffering;

  // Streams
  Stream<Duration> get durationStream;
  Stream<Duration> get positionStream;

  /// Whole-second position ticks shared by consumers that need no finer
  /// resolution (see `PositionTicker`).
  Stream<Duration> get positionTickStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<void> get completedStream;
  @override
  Stream<bool> get playingStream;
  Stream<bool> get shuffledStream;
  Stream<mk.PlaylistMode> get loopModeStream;
  Stream<double> get volumeStream;
  @override
  Stream<bool> get bufferingStream;
  Stream<AudioPlaybackState> get playerStateStream;
  Stream<int> get currentIndexChangedStream;
  Stream<String> get activeSourceChangedStream;
  Stream<List<mk.AudioDevice>> get devicesStream;
  Stream<mk.AudioDevice> get selectedDeviceStream;
  @override
  Stream<String> get errorStream;
  Stream<mk.Playlist> get playlistStream;
}
