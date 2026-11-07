// Drives RadioPlaybackNotifier against a fake backend + fake music delegate:
// audio-focus handoff, station switching, state surfaced from the backend
// streams, teardown on stop/switch, and the non-http guard. No native mpv.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/services/audio_player/radio_audio_player.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

class _FakeBackend implements RadioPlayerBackend {
  final opened = <String>[];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool throwOnOpen = false;

  /// When set, [open] parks on this until it completes — the seam for driving
  /// two overlapping `play()` calls deterministically.
  Completer<void>? openGate;

  final playing = StreamController<bool>.broadcast();
  final buffering = StreamController<bool>.broadcast();
  final title = StreamController<String>.broadcast();
  final errors = StreamController<String>.broadcast();

  @override
  Future<void> open(String url, {bool play = true}) async {
    final gate = openGate;
    if (gate != null) await gate.future;
    if (throwOnOpen) throw StateError('open failed');
    opened.add(url);
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing.add(false);
  }

  @override
  Future<void> stop() async => stopCalls++;

  double? lastVolume;
  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;

  final appliedFilters = <String>[];
  @override
  Future<void> setAudioFilterChain(String chain) async =>
      appliedFilters.add(chain);

  @override
  Stream<String> get titleStream => title.stream;
  @override
  Stream<bool> get playingStream => playing.stream;
  @override
  Stream<bool> get bufferingStream => buffering.stream;
  @override
  Stream<String> get errorStream => errors.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await playing.close();
    await buffering.close();
    await title.close();
    await errors.close();
  }
}

class _RecordingMusicDelegate implements MusicPlaybackDelegate {
  int pauseCalls = 0;
  final playing = StreamController<bool>.broadcast();
  @override
  Future<void> pauseMusic() async => pauseCalls++;
  @override
  Stream<bool> get musicPlayingStream => playing.stream;
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  AppLogger.initialize(false);

  late List<_FakeBackend> created;
  late _RecordingMusicDelegate music;
  late ProviderContainer container;
  late RadioPlaybackNotifier notifier;
  late bool nextBackendThrows;
  late Completer<void>? nextBackendGate;
  late AppDatabase database;

  RadioStation station(String id, {String url = 'https://stream/live'}) =>
      RadioStation(id: id, provider: 'p', name: id, streamUrl: url);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    created = [];
    music = _RecordingMusicDelegate();
    nextBackendThrows = false;
    nextBackendGate = null;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      radioBackendFactoryProvider.overrideWithValue(() {
        final b = _FakeBackend();
        if (nextBackendThrows) {
          b.throwOnOpen = true;
          nextBackendThrows = false;
        }
        if (nextBackendGate != null) {
          b.openGate = nextBackendGate;
          nextBackendGate = null;
        }
        created.add(b);
        return b;
      }),
      musicPlaybackDelegateProvider.overrideWithValue(music),
      databaseProvider.overrideWithValue(database),
    ]);
    addTearDown(container.dispose);
    addTearDown(database.close);
    notifier = container.read(radioPlaybackControllerProvider.notifier);
  });

  RadioPlaybackState st() =>
      container.read(radioPlaybackControllerProvider);

  test('play pauses music, opens the URL and enters radio mode', () async {
    await notifier.play(station('A'));
    await _flush();

    expect(music.pauseCalls, 1);
    expect(created.single.opened, ['https://stream/live']);
    expect(st().source, PlaybackSource.radio);
    expect(st().activeStation?.id, 'A');
  });

  test('playing state is surfaced from the backend stream', () async {
    await notifier.play(station('A'));
    await _flush();

    created.single.playing.add(true);
    await _flush();

    expect(st().playing, isTrue);
    expect(st().buffering, isFalse,
        reason: 'first playing event clears the buffering spinner');
  });

  test('switching stations disposes the old backend without re-pausing music',
      () async {
    await notifier.play(station('A'));
    await _flush();
    await notifier.play(station('B', url: 'https://other/live'));
    await _flush();

    expect(created, hasLength(2));
    expect(created.first.disposeCalls, 1, reason: 'A torn down for B');
    expect(created.last.opened, ['https://other/live']);
    expect(music.pauseCalls, 1, reason: 'music already yielded focus once');
    expect(st().activeStation?.id, 'B');
  });

  test('stop returns to music mode and disposes the backend', () async {
    await notifier.play(station('A'));
    await _flush();
    await notifier.stop();
    await _flush();

    expect(st().source, PlaybackSource.music);
    expect(st().activeStation, isNull);
    expect(created.single.disposeCalls, 1);
  });

  test('after a switch, the current backend drives state', () async {
    await notifier.play(station('A'));
    await _flush();
    await notifier.play(station('B'));
    await _flush();

    // The replaced backend is disposed (its controllers closed), so only the
    // live one can move the state.
    created.last.playing.add(true);
    await _flush();

    expect(st().activeStation?.id, 'B');
    expect(st().playing, isTrue);
  });

  test('a non-http URL is refused before a backend is built', () async {
    await notifier.play(station('bad', url: 'file:///etc/passwd'));
    await _flush();

    expect(created, isEmpty);
    expect(st().error, isNotNull);
    expect(st().source, PlaybackSource.radio);
    expect(st().activeStation?.id, 'bad');
  });

  test('an open() failure is surfaced, not thrown', () async {
    nextBackendThrows = true;
    await notifier.play(station('A'));
    await _flush();

    expect(st().error, isNotNull);
    expect(st().source, PlaybackSource.radio);
  });

  test('error stream marks the station unavailable', () async {
    await notifier.play(station('A'));
    await _flush();

    created.single.errors.add('connection lost');
    await _flush();

    expect(st().error, 'connection lost');
    expect(st().playing, isFalse);
  });

  test('live title from the backend stream becomes the now-playing title',
      () async {
    await notifier.play(station('A'));
    await _flush();

    created.single.title.add('Artist - Track');
    await _flush();

    expect(st().liveTitle, 'Artist - Track');
  });

  test('an empty live title is ignored, keeping the last real one', () async {
    await notifier.play(station('A'));
    await _flush();

    created.single.title.add('Artist - Track');
    await _flush();
    created.single.title.add('');
    await _flush();

    expect(st().liveTitle, 'Artist - Track');
  });

  test('resume/pause route to the active backend', () async {
    await notifier.play(station('A'));
    await _flush();

    await notifier.pause();
    await _flush();
    await notifier.resume();
    await _flush();

    expect(created.single.pauseCalls, 1);
    expect(created.single.playCalls, 1);
  });

  test('a successful play records a radio history row', () async {
    await notifier.play(station('A', url: 'https://live/a'));
    await _flush();
    // Give the unawaited best-effort insert a chance to land.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rows = await database.select(database.historyTable).get();
    final radio = rows.where((r) => r.type == HistoryEntryType.radio).toList();

    expect(radio, hasLength(1));
    expect(radio.single.itemId, 'p:A');
    expect(radio.single.radio?.name, 'A');
  });

  test('a failed play does not write history', () async {
    nextBackendThrows = true;
    await notifier.play(station('bad'));
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final radio =
        (await database.select(database.historyTable).get()).where((r) => r.type == HistoryEntryType.radio);
    expect(radio, isEmpty);
  });

  test('replaying a station supersedes its row instead of stacking', () async {
    // The reader is `ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY
    // created_at DESC) ... WHERE rn = 1`, so only the newest row per station is
    // ever visible. Older rows are invisible *and* unbounded — history_table
    // grows by one row every single play, forever.
    await notifier.play(station('A', url: 'https://live/a'));
    await _flush();
    await notifier.stop();
    await notifier.play(station('A', url: 'https://live/a'));
    await _flush();
    await notifier.stop();
    await notifier.play(station('A', url: 'https://live/a-rotated'));
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final radio = (await database.select(database.historyTable).get())
        .where((r) => r.type == HistoryEntryType.radio)
        .toList();

    expect(radio, hasLength(1), reason: 'one row per station, not one per play');
    expect(radio.single.data['streamUrl'], 'https://live/a-rotated',
        reason: 'the surviving row must be the latest listen');
  });

  test('distinct stations each keep their own row', () async {
    await notifier.play(station('A'));
    await _flush();
    await notifier.stop();
    await notifier.play(station('B'));
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final radio = (await database.select(database.historyTable).get())
        .where((r) => r.type == HistoryEntryType.radio)
        .toList();

    expect(radio.map((r) => r.itemId).toSet(), {'p:A', 'p:B'});
  });

  test('starting music while a station is live stops radio (reverse handoff)',
      () async {
    await notifier.play(station('A'));
    await _flush();
    expect(st().source, PlaybackSource.radio);

    music.playing.add(true);
    await _flush();

    expect(st().source, PlaybackSource.music,
        reason: 'music taking focus must not leave radio playing');
    expect(st().activeStation, isNull);
    expect(created.single.disposeCalls, 1);
  });

  test('a music pause event does not stop radio', () async {
    await notifier.play(station('A'));
    await _flush();

    music.playing.add(false);
    await _flush();

    expect(st().source, PlaybackSource.radio,
        reason: 'play() emits a music pause before the source flips');
  });

  test('setVolume updates state and pushes to the live backend', () async {
    await notifier.play(station('A'));
    await _flush();

    await notifier.setVolume(0.5);
    await _flush();

    expect(st().volume, 0.5);
    expect(created.single.lastVolume, 0.5);
  });

  test('setVolume is clamped to 0.0-1.0', () async {
    await notifier.setVolume(1.8);
    expect(st().volume, 1.0);
    await notifier.setVolume(-0.4);
    expect(st().volume, 0.0);
  });

  test('play re-applies the persisted volume to a fresh backend', () async {
    await notifier.setVolume(0.3);
    await notifier.play(station('A'));
    await _flush();

    expect(created.single.lastVolume, 0.3,
        reason: 'a new backend starts at full volume and must be reset');
  });

  test('an open() failure clears buffering so the tile is usable again',
      () async {
    nextBackendThrows = true;
    await notifier.play(station('A'));
    await _flush();

    expect(st().error, isNotNull);
    expect(st().buffering, isFalse,
        reason:
            'buffering drives isLoading, which disables the station play '
            'button; leaving it true pins the user to a disabled spinner');
    expect(st().playing, isFalse);
  });

  test('a refused non-http URL also clears buffering', () async {
    await notifier.play(station('bad', url: 'file:///etc/passwd'));
    await _flush();

    expect(st().error, isNotNull);
    expect(st().buffering, isFalse);
  });

  test('an idle event does not dismiss a genuine buffering spinner', () async {
    await notifier.play(station('A'));
    await _flush();

    // The stream stalls again (a reconnect), then the backend reports idle.
    // An idle event says nothing about whether the stream is still stalling, so
    // it must not clear the spinner — that is what `bufferingStream` is for.
    created.single.playing.add(true);
    created.single.buffering.add(true);
    await _flush();
    expect(st().buffering, isTrue);

    created.single.playing.add(false);
    await _flush();

    expect(st().playing, isFalse);
    expect(st().buffering, isTrue,
        reason: 'the backend still reports buffering; only a resume or a '
            'buffering event may clear it');

    created.single.buffering.add(false);
    await _flush();
    expect(st().buffering, isFalse);
  });

  test('stop preserves the radio volume', () async {
    await notifier.setVolume(0.4);
    await notifier.play(station('A'));
    await _flush();
    await notifier.stop();
    await _flush();

    expect(st().volume, 0.4,
        reason: 'setVolume survives a station change, so it survives a stop');
  });

  test('overlapping plays leave one live backend and record only the winner',
      () async {
    final gate = Completer<void>();
    nextBackendGate = gate;

    // A parks inside open(), so B's play() runs while A is still mid-flight.
    final a = notifier.play(station('A', url: 'https://a/live'));
    await _flush();
    expect(created, hasLength(1));

    final b = notifier.play(station('B', url: 'https://b/live'));
    await _flush();
    expect(created, hasLength(2));
    expect(created.first.disposeCalls, 1,
        reason: "B's teardown must dispose the backend A already built");

    gate.complete();
    await Future.wait([a, b]);
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(st().activeStation?.id, 'B');
    expect(created.first.disposeCalls, 1,
        reason: 'the superseded backend is disposed, never orphaned (an orphan '
            'is a whole mpv context that only terminates 5s after dispose)');

    await notifier.stop();
    await _flush();
    expect(created.last.disposeCalls, 1,
        reason: 'stopping releases the one that was live');

    final radio = (await database.select(database.historyTable).get())
        .where((r) => r.type == HistoryEntryType.radio)
        .toList();
    expect(radio.map((r) => r.itemId), ['p:B'],
        reason: 'A was superseded before it ever played; it is not a listen');
  });

  test('a superseded play does not stamp its error on the winner', () async {
    final gate = Completer<void>();
    nextBackendGate = gate;

    final a = notifier.play(station('A', url: 'https://a/live'));
    await _flush();
    // Make A's backend throw once the gate releases.
    created.first.throwOnOpen = true;

    final b = notifier.play(station('B', url: 'https://b/live'));
    await _flush();

    gate.complete();
    await Future.wait([a, b]);
    await _flush();

    expect(st().activeStation?.id, 'B');
    expect(st().error, isNull,
        reason: "A's late failure belongs to A, not to the station now live");
  });
}
