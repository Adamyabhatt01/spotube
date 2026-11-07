// Frosted chrome keeps its look and stops paying for it mid-motion: while
// anything is scrolling, or while the player sheet is in flight, the pinned
// surfaces draw with surfaceBlur 0, which shadcn's SurfaceBlur turns into no
// BackdropFilter at all instead of a blur pass over every frame of moving
// content. Two things have to hold for that to be worth shipping:
//   - the freeze has to be a state change, not a per-frame one. A surface that
//     rebuilt every scroll frame to save a blur pass would trade one cost for
//     another, so the counts below are the point of the test.
//   - it has to come back. Nothing is counted, so a scrollable destroyed
//     mid-fling cannot leave the app permanently unblurred.
// GPU frame times are not measurable here; this proves the mechanism, not the
// milliseconds it saves.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/scroll_motion_scope.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/provider/scroll_motion.dart';

/// The frames a drag spends in flight, matching what `SlidingUpPanel` reports per
/// animation frame while a sheet is moved.
const dragFrames = 30;

Future<void> drain([int yields = 50]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Widget _list() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      height: 300,
      child: ListView(
        children: [
          for (var i = 0; i < 60; i++)
            SizedBox(height: 60, child: Text('row $i')),
        ],
      ),
    ),
  );
}

void main() {
  group('ScrollInFlight', () {
    test('a frame of scrolling is one state change, not one per frame',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var changes = 0;
      container.listen(scrollInFlightProvider, (_, __) => changes++);
      final motion = container.read(scrollInFlightProvider.notifier);

      for (var frame = 0; frame < dragFrames; frame++) {
        motion.markActive();
      }
      expect(container.read(scrollInFlightProvider), isTrue);
      expect(changes, 1, reason: 'the surfaces rebuild once at the start');

      await Future<void>.delayed(ScrollInFlight.settle + const Duration(milliseconds: 5));
      expect(container.read(scrollInFlightProvider), isFalse);
      expect(changes, 2, reason: '...and once when the content settles');
    });

    test('a destroyed scrollable cannot leave the chrome frozen forever',
        () async {
      // The leak a counter would have: the last notification never arrives, so
      // there is nothing to decrement - only the countdown, which still runs.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(scrollInFlightProvider.notifier).markActive();
      expect(container.read(scrollInFlightProvider), isTrue);

      await Future<void>.delayed(ScrollInFlight.settle + const Duration(milliseconds: 5));
      expect(container.read(scrollInFlightProvider), isFalse);
    });

    test('the frost returns after one settle, not after every gap', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final motion = container.read(scrollInFlightProvider.notifier);

      motion.markActive();
      await Future<void>.delayed(ScrollInFlight.settle ~/ 2);
      // Still moving: the countdown restarted with the frame that just arrived.
      motion.markActive();
      await Future<void>.delayed(
        ScrollInFlight.settle - const Duration(milliseconds: 20),
      );
      expect(container.read(scrollInFlightProvider), isTrue);

      await Future<void>.delayed(ScrollInFlight.settle + const Duration(milliseconds: 5));
      expect(container.read(scrollInFlightProvider), isFalse);
    });
  });

  group('ScrollMotionScope', () {
    Future<ProviderContainer> pumpList(
      WidgetTester tester, {
      required bool enabled,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScrollMotionScope(
            enabled: enabled,
            child: _list(),
          ),
        ),
      );
      return container;
    }

    /// A finger down, thirty frames of movement, then release: the shape of the
    /// scroll that costs a blur pass per frame. [onFrame] runs between frames,
    /// where an expectation failure reports against this test rather than the
    /// pump that triggered it.
    Future<void> dragOneFinger(
      WidgetTester tester, {
      void Function(int frame)? onFrame,
      bool untilRelease = true,
    }) async {
      final gesture = await tester.startGesture(const Offset(150, 200));
      await gesture.moveBy(const Offset(0, -20));
      for (var frame = 0; frame < dragFrames; frame++) {
        await gesture.moveBy(const Offset(0, -4));
        await tester.pump(const Duration(milliseconds: 16));
        onFrame?.call(frame);
      }
      if (!untilRelease) return;
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// The list's first layout reports its own metrics, so nothing counts as
    /// moving until that countdown has run out.
    Future<void> comeToRest(WidgetTester tester) async {
      await tester.pump(
        ScrollInFlight.settle + const Duration(milliseconds: 5),
      );
    }

    testWidgets('a scroll anywhere under the scope reports itself',
        (tester) async {
      final container = await pumpList(tester, enabled: true);
      await comeToRest(tester);

      await dragOneFinger(
        tester,
        onFrame: (frame) => expect(
          container.read(scrollInFlightProvider),
          isTrue,
          reason: 'frozen from the first frame of movement (frame $frame)',
        ),
      );

      // pumpAndSettle has drained the fling, so the only thing left is the
      // countdown that returns the frost.
      await tester.pump(
        ScrollInFlight.settle + const Duration(milliseconds: 5),
      );
      expect(container.read(scrollInFlightProvider), isFalse);
    });

    testWidgets('motion freezes the chrome once and holds it through a fling',
        (tester) async {
      final container = await pumpList(tester, enabled: true);
      await comeToRest(tester);

      var changes = 0;
      container.listen(scrollInFlightProvider, (_, __) => changes++);

      await dragOneFinger(
        tester,
        untilRelease: false,
        onFrame: (frame) {
          if (frame == 0) {
            expect(
              changes,
              1,
              reason: 'the first frame of a scroll flips the chrome once',
            );
          }
        },
      );

      expect(container.read(scrollInFlightProvider), isTrue);
      expect(
        changes,
        1,
        reason: 'thirty frames of movement, one rebuild of the surfaces',
      );

      // The fling is still moving content, so the frost stays off.
      await tester.pump(const Duration(milliseconds: 16));
      expect(container.read(scrollInFlightProvider), isTrue);
      expect(changes, 1);

      await tester.pumpAndSettle();
      await tester.pump(
        ScrollInFlight.settle + const Duration(milliseconds: 5),
      );
      expect(container.read(scrollInFlightProvider), isFalse);
      expect(changes, 2, reason: 'and one more when everything has stopped');
    });

    testWidgets('a host that is not a phone reports nothing', (tester) async {
      final container = await pumpList(tester, enabled: false);

      await dragOneFinger(tester);

      expect(container.read(scrollInFlightProvider), isFalse);
    });
  });

  group('chromeBlurFrozen', () {
    test('a sheet in flight freezes the chrome once, not per frame', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var frozen = false;
      var raw = 0;
      container.listen(navigationPanelHeight, (_, __) => raw++);
      container.listen(chromeBlurFrozen, (_, next) => frozen = next);

      final panel = container.read(navigationPanelHeight.notifier);
      for (var frame = 0; frame < dragFrames; frame++) {
        // The exact values PlayerOverlay.onPanelSlide writes on the way up.
        panel.state = 50 * (1 - (frame + 1) / dragFrames);
        await drain(1);
      }
      expect(raw, dragFrames, reason: 'the sheet really did write every frame');
      expect(frozen, isTrue);
      expect(
        container.read(chromeBlurFrozen),
        isTrue,
        reason: 'the panel is off its resting height',
      );

      panel.state = 50;
      await drain(1);
      expect(container.read(chromeBlurFrozen), isFalse);
    });

    test('at rest with the sheet down, the blur is the theme\'s', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(chromeBlurFrozen), isFalse);
    });
  });
}
