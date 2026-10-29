import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/audio_player/audio_effects.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/radio/playback_handoff.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/audio_player/radio_audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

/// Seam over the global music player so the radio controller can hand audio
/// focus back cleanly (pause music when radio starts), watch for music taking
/// focus back (resume → stop radio), and so tests can observe the transitions
/// without a native mpv.
abstract interface class MusicPlaybackDelegate {
  Future<void> pauseMusic();

  /// Emits the music player's playing state. Used for the reverse handoff.
  Stream<bool> get musicPlayingStream;
}

class AudioPlayerMusicDelegate implements MusicPlaybackDelegate {
  final AudioPlayerPort player;

  AudioPlayerMusicDelegate(this.player);

  @override
  Future<void> pauseMusic() => player.pause();

  @override
  Stream<bool> get musicPlayingStream => player.playingStream;
}

final musicPlaybackDelegateProvider = Provider<MusicPlaybackDelegate>(
  (ref) => AudioPlayerMusicDelegate(ref.read(audioPlayerPortProvider)),
);

/// Creates a fresh radio backend per listening session. A factory (not a
/// cached [Provider]) so the controller can build one on play and fully
/// dispose it on stop, keeping the extra player's cost bounded to active radio
/// use. Tests override with a fake.
typedef RadioBackendFactory = RadioPlayerBackend Function();

final radioBackendFactoryProvider =
    Provider<RadioBackendFactory>((_) => MediaKitRadioPlayerBackend.new);

/// Owns internet-radio playback: which station is live, its transport state,
/// and the handoff of audio focus with the music player.
///
/// Kept as a non-autoDispose [Notifier] (like the music player) because it
/// must outlive the screen that started playback — a station should keep
/// playing while the user browses. A global, app-lifetime singleton backed by
/// a lazily-created, eagerly-disposed [RadioPlayerBackend].
class RadioPlaybackNotifier extends Notifier<RadioPlaybackState> {
  RadioPlayerBackend? _backend;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  late final PlaybackHandoff _handoff =
      PlaybackHandoff(ref.read(musicPlaybackDelegateProvider));

  /// Monotonic token identifying the newest [play]/[stop] intent.
  ///
  /// [play] is async from its first `await`, and two station taps interleave
  /// freely — nothing else serialises them. Without this, the loser of a race
  /// keeps going: it installs a second player the winner never tears down (an
  /// orphaned mpv context, which media_kit only terminates 5s after `dispose`),
  /// records a "recently played" row for a station that never went on air, and
  /// writes its failure into the state of whichever station *is* live. Every
  /// post-await step re-checks it, and a superseded play disposes whatever it
  /// managed to build.
  int _generation = 0;

  @override
  RadioPlaybackState build() {
    // Reverse handoff: if the user starts music while a station is live, stop
    // radio so the two separate mpv players never emit at once. Only music
    // *playing* events trigger this — play() emits a pause before the source
    // flips, so it can never self-cancel.
    final musicPlaying = ref
        .read(musicPlaybackDelegateProvider)
        .musicPlayingStream
        .listen((playing) {
      if (playing && state.isRadio) {
        unawaited(stop());
      }
    });
    ref.onDispose(() {
      musicPlaying.cancel();
      _teardown();
    });
    // The equalizer/normalization chain is app-wide; mirror changes onto a
    // live station backend so settings take effect without a restart.
    ref.listen<String>(audioFilterChainProvider, (previous, next) {
      if (previous == next) return;
      final backend = _backend;
      if (backend != null) unawaited(_applyFilters(backend, next));
    });
    return const RadioPlaybackState();
  }

  /// Value equality rather than Riverpod's `!identical(previous, next)`
  /// default, so an assignment that changes nothing (a repeated `playing ==
  /// true`, an unchanged ICY title) does not fan out to every station control.
  /// Requires [RadioPlaybackState.==].
  @override
  bool updateShouldNotify(
          RadioPlaybackState previous, RadioPlaybackState next) =>
      previous != next;

  Future<void> play(RadioStation station) async {
    final token = ++_generation;

    // Only guard against non-http on this boundary too: the model is data and
    // the directory already filtered, but a favorite re-resolve or a future
    // provider must not be able to hand the native player an arbitrary scheme.
    if (!_isHttp(station.streamUrl)) {
      if (token != _generation) return;
      state = state.copyWith(
        source: PlaybackSource.radio,
        activeStation: station,
        // Never leave `buffering` set on a path that opened nothing — it drives
        // isLoading, which pins the tile's play button disabled.
        buffering: false,
        playing: false,
        error: ArgumentError('Refusing non-http radio URL'),
      );
      return;
    }

    // Hand over audio focus: silence music before the station opens so the two
    // players never emit at once, but leave the music queue intact.
    if (state.source == PlaybackSource.music) {
      await _handoff.toRadio();
      if (token != _generation) return;
    }

    await _handoff.toMusic(_teardown);
    // A newer intent took over during the teardown and now owns `_backend`;
    // installing a second player here is the leak this guard exists for.
    if (token != _generation) return;

    final backend = ref.read(radioBackendFactoryProvider)();
    _backend = backend;
    _watch(backend);

    state = state.copyWith(
      source: PlaybackSource.radio,
      activeStation: station,
      buffering: true,
      playing: false,
      clearTitle: true,
      clearError: true,
    );

    try {
      // Same chain as the music player, applied before the stream opens so the
      // first seconds are not unfiltered. Best-effort: a bad filter must never
      // stop the station.
      await _applyFilters(backend, ref.read(audioFilterChainProvider));
      if (token != _generation) return;
      await backend.open(station.streamUrl, play: true);
      // Superseded mid-open: this backend is already torn down, so it is not a
      // listen and its outcome belongs to nobody.
      if (token != _generation) return;
      // A fresh backend starts at full volume; restore the user's level.
      await backend.setVolume(state.volume);
      if (token != _generation) return;
      unawaited(_recordListen(station));
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio play ${station.id}');
      if (token != _generation) return;
      state = state.copyWith(
        // The connection attempt is over, whatever its verdict. Leaving
        // `buffering` true here is what used to pin the tile to a dead spinner.
        buffering: false,
        playing: false,
        error: e,
      );
    }
  }

  /// Best-effort "recently played" entry. Reuses [HistoryTable] with a new
  /// `radio` type value, so no migration; a write failure never breaks
  /// playback. [itemId] is namespaced by provider like the favorite key.
  ///
  /// Supersedes any earlier row for the same station rather than appending,
  /// because [RadioHistoryNotifier] only ever reads the newest row per
  /// `item_id` (`ROW_NUMBER() ... WHERE rn = 1`) — older ones are invisible to
  /// every reader while still costing a row per play, so an append-only write
  /// grows history_table without bound for the life of the install. Same
  /// transaction, so a crash cannot leave a station with no row at all.
  Future<void> _recordListen(RadioStation station) async {
    try {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        // `type` is a textEnum column, so it matches on the enum's name — the
        // same literal RadioHistoryNotifier's SQL filters on.
        final superseded = db.delete(db.historyTable)
          ..where((t) =>
              t.type.equals(HistoryEntryType.radio.name) &
              t.itemId.equals(station.favoriteKey));
        await superseded.go();
        await db.into(db.historyTable).insert(
              HistoryTableCompanion.insert(
                type: HistoryEntryType.radio,
                itemId: station.favoriteKey,
                data: station.toJson(),
              ),
            );
      });
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio history');
    }
  }

  Future<void> pause() async {
    await _backend?.pause();
  }

  Future<void> _applyFilters(RadioPlayerBackend backend, String chain) async {
    try {
      await backend.setAudioFilterChain(chain);
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio audio filters');
    }
  }

  Future<void> resume() async {
    await _backend?.play();
  }

  /// Set the radio output level (0.0–1.0). Kept in state so it survives a
  /// station change (each play builds a fresh backend) and pushed live to the
  /// current one. Independent of the music player's [volumeProvider].
  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    await _backend?.setVolume(clamped);
  }

  /// Stop radio and return focus to the (still-paused) music player. The user
  /// resumes music themselves — auto-resuming would be surprising.
  Future<void> stop() async {
    // A play() in flight must not resurrect a station the user just stopped.
    ++_generation;
    await _handoff.toMusic(_teardown);
    state = state.copyWith(
      source: PlaybackSource.music,
      clearStation: true,
      playing: false,
      buffering: false,
      clearTitle: true,
      clearError: true,
      // The output level is a user setting, not session state: it outlives a
      // station change (each play builds a fresh backend) and so outlives a
      // stop. Re-applied on the next play().
      volume: state.volume,
    );
  }

  void _watch(RadioPlayerBackend backend) {
    _subscriptions.addAll([
      backend.playingStream.listen((playing) {
        if (!identical(backend, _backend)) return;
        // Only a confirmed resume ends the spinner. A pause or an idle event
        // says nothing about whether the stream is still stalling, so it must
        // not clear `buffering` — `bufferingStream` owns that flag.
        state = state.copyWith(
          playing: playing,
          buffering: playing ? false : state.buffering,
        );
      }),
      backend.bufferingStream.listen((buffering) {
        if (!identical(backend, _backend)) return;
        state = state.copyWith(buffering: buffering);
      }),
      backend.titleStream.listen((title) {
        if (!identical(backend, _backend)) return;
        if (title.isEmpty) return;
        state = state.copyWith(liveTitle: title);
      }),
      backend.errorStream.listen((message) {
        if (!identical(backend, _backend)) return;
        AppLogger.reportError(
            message, StackTrace.current, 'radio stream error');
        state = state.copyWith(error: message, playing: false);
      }),
    ]);
  }

  Future<void> _teardown() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      try {
        await backend.dispose();
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'radio backend dispose');
      }
    }
  }

  static bool _isHttp(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

final radioPlaybackControllerProvider =
    NotifierProvider<RadioPlaybackNotifier, RadioPlaybackState>(
  RadioPlaybackNotifier.new,
);

@visibleForTesting
bool radioUrlIsHttp(String url) => RadioPlaybackNotifier._isHttp(url);
