import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/services/audio_player/custom_player.dart';

/// Playback surface a radio station needs from an audio backend.
///
/// An interface so the [RadioPlaybackNotifier](package:spotube/provider/radio/radio_playback.dart)
/// can be driven by a fake in unit tests without a native mpv, and so a
/// future platform (web) can supply a different implementation without
/// touching the notifier.
abstract interface class RadioPlayerBackend {
  /// Starts (or replaces) playback of a raw stream URL. No queue, no
  /// `SpotubeTrackObject` — the backend plays the URL exactly as given. The
  /// URL must already be scheme-validated by the caller.
  Future<void> open(String url, {bool play = true});

  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  /// Output level as a 0.0–1.0 fraction. A fresh backend starts at full volume,
  /// so the caller re-applies the user's level after [open].
  Future<void> setVolume(double volume);

  /// Current live metadata title (ICY/`media-title`), or empty when the source
  /// reports none. May update many times per station as tracks change.
  Stream<String> get titleStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;

  Future<void> dispose();
}

/// [RadioPlayerBackend] over a *dedicated* `media_kit` player instance.
///
/// Deliberately a second [CustomPlayer] rather than reusing the global
/// [audioPlayer]: the music notifier rebuilds its queue from every backend
/// playlist event via `SpotubeMedia.media`, which requires each media to
/// carry a `SpotubeTrackObject`. Routing a live station through that path
/// would force a station into the Track model — the bad abstraction the radio
/// design rejects. A separate instance reuses the same engine (no backend
/// replacement), leaves the music queue and its persistence untouched, and is
/// created on first play and disposed on stop so the extra context costs
/// nothing when radio is idle.
///
/// Not available on web (no native mpv); the caller must not construct it
/// there — see [kRadioPlaybackSupported].
class MediaKitRadioPlayerBackend implements RadioPlayerBackend {
  MediaKitRadioPlayerBackend() : _player = CustomPlayer() {
    _subs.addAll([
      _player.stream.playing.listen((v) => _playing.add(v)),
      _player.stream.buffering.listen((v) => _buffering.add(v)),
      _player.stream.error.listen((v) => _errors.add(v)),
    ]);
  }

  final CustomPlayer _player;
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _title = StreamController<String>.broadcast();
  final List<StreamSubscription> _subs = [];

  // mpv's `media-title` reflects the live ICY StreamTitle on http streams.
  // Observing it must happen once per native player and only after the engine
  // is initialized; observing the same property twice throws, so track it.
  bool _titleObserved = false;

  @override
  Future<void> open(String url, {bool play = true}) async {
    if (!_titleObserved) {
      _titleObserved = true;
      try {
        await _player.nativePlayer
            .observeProperty('media-title', (value) async {
          if (!_title.isClosed) _title.add(value);
        });
      } catch (e) {
        // Live title is best-effort; a player without the property observer
        // just keeps showing the station name from the directory.
        _titleObserved = false;
      }
    }
    await _player.open(Media(url), play: play);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  // media_kit volume is 0–100; the notifier speaks 0.0–1.0.
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);

  /// Live ICY/`media-title` updates for the open stream; empty until the
  /// observer fires its first value. May update many times per station as
  /// tracks change, so the notifier treats the latest value as now-playing.
  @override
  Stream<String> get titleStream => _title.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    if (_titleObserved) {
      try {
        await _player.nativePlayer.unobserveProperty('media-title');
      } catch (_) {
        // Best-effort: the player is about to be disposed anyway.
      }
    }
    await _playing.close();
    await _buffering.close();
    await _errors.close();
    await _title.close();
    return _player.dispose();
  }
}

/// Radio uses the native mpv path, so it is unavailable on web just like the
/// main player's native features.
const bool kRadioPlaybackSupported = !kIsWeb;
