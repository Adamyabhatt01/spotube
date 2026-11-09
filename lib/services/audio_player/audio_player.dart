import 'dart:io';

import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:spotube/services/audio_player/custom_player.dart';
import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/position_tick.dart';

part 'audio_players_streams_mixin.dart';
part 'audio_player_impl.dart';

class SpotubeMedia {
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
        );

  /// The uri the backend holds [track] under. Also what a bare `Media` — the
  /// kind media_kit rebuilds the playlist from after `setShuffle` — can be
  /// matched back to a queue entry by, so the rule lives in one place.
  static String uriFor(SpotubeTrackObject track) =>
      track is SpotubeLocalTrackObject
          ? track.path
          : "http://$_host:$serverPort/stream/${track.id}";

  /// The queue URI. Matches [toMedia]'s `Media.uri` (media_kit normalises the
  /// same string, and the normalisation is idempotent for http/file URIs).
  String get uri => uriFor(track);

  // media_kit 1.2.6 made `Media` a factory with a private generative ctor
  // (`fix: memory leaks (#1446)`), so it can no longer be extended. This
  // wrapper instead materialises a real `Media` — which registers in
  // media_kit's cache and attaches its finalizer — on demand.
  mk.Media get toMedia => mk.Media(uri, extras: track.toJson());

  factory SpotubeMedia.media(Media media) {
    // The backend holds real `Media` instances whose `extras` carry the track
    // json; recovery is `SpotubeTrackObject.fromJson(media.extras!)`.
    assert(media.extras != null, "[Media] must have extra metadata set");
    return SpotubeMedia(SpotubeTrackObject.fromJson(media.extras!));
  }

  /// The track carried by a backend [Media] (its `extras` json).
  static SpotubeTrackObject trackOf(Media media) =>
      SpotubeMedia.media(media).track;
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

  double get speed {
    return _mkPlayer.state.rate;
  }

  bool get isBuffering {
    return _mkPlayer.state.buffering;
  }
}
