import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/foreground_coalescer.dart';

void main() {
  group('ForegroundCoalescer', () {
    late int pushes;
    late bool foreground;
    late Completer<void> gate;
    late ForegroundCoalescer coalescer;

    setUp(() {
      pushes = 0;
      foreground = true;
      gate = Completer<void>();
      coalescer = ForegroundCoalescer(
        push: () async {
          pushes++;
          await gate.future;
        },
        isForeground: () => foreground,
      );
    });

    test('collapses a whole foreground playback session into nothing', () async {
      // The 1 Hz position tick is the storm this exists for: sixty requests a
      // minute, none of them visible.
      for (var i = 0; i < 60; i++) {
        await coalescer.request();
      }
      expect(pushes, 0);
    });

    test('pushes the folded state exactly once on the way out of foreground',
        () async {
      for (var i = 0; i < 60; i++) {
        await coalescer.request();
      }
      gate.complete();
      foreground = false;

      await coalescer.onForegroundChanged(false);
      expect(pushes, 1);

      // The pending flag is cleared by the flush, not consumed by the tick that
      // happened to trigger it.
      await coalescer.onForegroundChanged(false);
      expect(pushes, 1);
    });

    test('does nothing on a background transition with nothing pending',
        () async {
      gate.complete();
      foreground = false;
      await coalescer.onForegroundChanged(false);
      expect(pushes, 0);
    });

    test('passes through while already backgrounded', () async {
      gate.complete();
      foreground = false;
      await coalescer.request();
      await coalescer.request();
      expect(pushes, 2);
    });

    test('a request arriving during a flush does not start a second one',
        () async {
      foreground = false;
      final first = coalescer.flush();
      await Future(() {});
      await coalescer.flush();
      expect(pushes, 1);
      gate.complete();
      await first;
    });

    test('a failed push is not remembered as delivered', () async {
      gate.complete();
      var attempts = 0;
      final failing = ForegroundCoalescer(
        push: () async {
          if (attempts++ == 0) throw StateError('widget gone');
        },
        isForeground: () => false,
      );
      await expectLater(failing.request(), throwsStateError);
      // A later signal still reaches the widget instead of being treated as
      // already handled.
      await expectLater(failing.request(), completes);
      expect(attempts, 2);
    });
  });
}
