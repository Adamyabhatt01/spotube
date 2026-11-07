// PR 1 / R-06: the offline retry probe must not fire while the app is
// backgrounded. The old skip covered only `paused`; `hidden` (occluded on
// desktop, stopped-but-cached Android task) kept issuing DNS lookups every
// 30 s. The predicate is the seam — the timer itself can't be exercised
// here without driving real DNS through the singleton.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/connectivity_adapter.dart';

void main() {
  group('ConnectionCheckerService.probeSkipsState', () {
    test('backgrounded states skip the probe', () {
      expect(
        ConnectionCheckerService.probeSkipsState(AppLifecycleState.paused),
        isTrue,
      );
      expect(
        ConnectionCheckerService.probeSkipsState(AppLifecycleState.hidden),
        isTrue,
        reason: 'the added case: hidden was probing every 30 s',
      );
    });

    test('foreground-ish states still probe (unchanged behavior)', () {
      for (final state in [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.detached,
        null,
      ]) {
        expect(
          ConnectionCheckerService.probeSkipsState(state),
          isFalse,
          reason: '$state must keep the old probe behavior',
        );
      }
    });
  });
}
