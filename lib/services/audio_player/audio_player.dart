import 'dart:io';

import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:spotube/services/audio_player/custom_player.dart';
import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/position_tick.dart';

part 'audio_players_streams_mixin.dart';
part 'audio_player_impl.dart';

class SpotubeMedia extends mk.Media {
  static int serverPort = 0;

  // Windows proxy bypass lists conventionally name "localhost", not 127.0.0.1,
  // and libmpv honors http_proxy — so the loopback literal can get local
  // playback routed through a proxy that then rejects it.
  static String get _host =>
      kIsWindows ? "localhost" : InternetAddress.loopbackIPv4.address;

  final SpotubeTrackObject track;
  SpotubeMedia(this.track)
      : assert(
          track is SpotubeLocalTrackObject || track is SpotubeFullTrackObject,
          "Track must be a either a local track or a full track object with ISRC",
        ),
        super(uriFor(track), extras: track.toJson());

  /// The uri the backend holds [track] under. Also what a bare `Media` — the
  /// kind media_kit rebuilds the playlist from after `setShuffle` — can be
  /// matched back to a queue entry by, so the rule lives in one place.
  static String uriFor(SpotubeTrackObject track) =>
      track is SpotubeLocalTrackObject
          ? track.path
          : "http://$_host:$serverPort/stream/${track.id}";

  factory SpotubeMedia.media(Media media) {
    // The backend keeps the [SpotubeMedia] instances it was given, so on an
    // index-only playlist event `media` is already one and `track` is already
    // parsed. Re-running `fromJson` over `extras` cost one track parse per
    // queue slot per event.
    if (media is SpotubeMedia) return media;

    assert(media.extras != null, "[Media] must have extra metadata set");
    return SpotubeMedia(SpotubeTrackObject.fromJson(media.extras!));
  }
}

abstract class AudioPlayerInterface {
  final CustomPlayer _mkPlayer;

  AudioPlayerInterface()
      : _mkPlayer = CustomPlayer(
          configuration: const mk.PlayerConfiguration(
            title: "Spotube",
            logLevel: kDebugMode ? mk.MPVLogLevel.info : mk.MPVLogLevel.error,
            async: true,
          ),
        ) {
    _mkPlayer.stream.error.listen((event) {
      AppLogger.reportError(event, StackTrace.current);
    });
  }

  Duration get duration {
    return _mkPlayer.state.duration;
  }

  Playlist get playlist {
    return _mkPlayer.state.playlist;
  }

  Duration get position {
    return _mkPlayer.state.position;
  }

  Duration get bufferedPosition {
    return _mkPlayer.state.buffer;
  }

  Future<mk.AudioDevice> get selectedDevice async {
    return _mkPlayer.state.audioDevice;
  }

  Future<List<mk.AudioDevice>> get devices async {
    return _mkPlayer.state.audioDevices;
  }

  bool get isPlaying {
    return _mkPlayer.state.playing;
  }

  bool get isPaused {
    return !_mkPlayer.state.playing;
  }

  Future<bool> get isCompleted async {
    return _mkPlayer.state.completed;
  }

  bool get isShuffled {
    return _mkPlayer.shuffled;
  }

  PlaylistMode get loopMode {
    return _mkPlayer.state.playlistMode;
  }

  double get volume {
    return _mkPlayer.state.volume / 100;
  }

  bool get isBuffering {
    return _mkPlayer.state.buffering;
  }
}
