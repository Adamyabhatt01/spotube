import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/radio/playback_handoff.dart';
import 'package:spotube/provider/radio/radio_playback.dart';

class _Music implements MusicPlaybackDelegate {
  int pauses = 0;
  Completer<void>? gate;

  @override
  Future<void> pauseMusic() async {
    pauses++;
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Stream<bool> get musicPlayingStream => const Stream.empty();
}

void main() {
  test('toRadio resolves only after music paused', () async {
    final music = _Music()..gate = Completer<void>();
    final handoff = PlaybackHandoff(music);
    var done = false;
    final future = handoff.toRadio().then((_) => done = true);

    await Future<void>.delayed(Duration.zero);
    expect(music.pauses, 1);
    expect(done, isFalse);

    music.gate!.complete();
    await future;
    expect(done, isTrue);
  });

  test('toMusic resolves only after teardown completes', () async {
    final handoff = PlaybackHandoff(_Music());
    final gate = Completer<void>();
    var tornDown = false;
    final future = handoff.toMusic(() async {
      await gate.future;
      tornDown = true;
    });
    var resolved = false;
    unawaited(future.then((_) => resolved = true));

    await Future<void>.delayed(Duration.zero);
    expect(tornDown, isFalse);
    expect(resolved, isFalse);

    gate.complete();
    await future;
    expect(tornDown, isTrue);
    expect(resolved, isTrue);
  });

  test('concurrent handoffs share one teardown', () async {
    final handoff = PlaybackHandoff(_Music());
    var calls = 0;
    var gate = Completer<void>();

    Future<void> teardown() async {
      calls++;
      await gate.future;
    }

    final a = handoff.toMusic(teardown);
    final b = handoff.toMusic(teardown);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    gate.complete();
    await Future.wait([a, b]);

    gate = Completer<void>();
    final c = handoff.toMusic(teardown);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2, reason: 'a later handoff tears down again');
    gate.complete();
    await c;
  });
}
