// The player sheet writes navigationPanelHeight on every animation frame of a
// drag (PlayerOverlay.onPanelSlide). The bar has two states, so watching the raw
// value meant rebuilding the whole navigation subtree — Divider, NavigationBar,
// five buttons, badges, theme lookups — roughly once per frame while the sheet
// moved, which is the stutter when opening the player. It watches the threshold
// instead; the drag is what this drives, frame by frame, against both providers.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';

/// Pumps the event loop so Riverpod's scheduled flush runs, the way a frame
/// boundary does in the app: one drag tick, then the notifications it earned.
Future<void> drain([int yields = 2]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The values one 30-frame open produces, then the same values reversed.
List<double> get _openDrag => [
      for (var i = 0; i <= 30; i++) 50 * (1 - i / 30),
    ];

Future<({int raw, int covers})> _driveDrag(
  ProviderContainer container,
  List<double> heights,
) async {
  var raw = 0;
  var covers = 0;

  // Priming both reads before listening is what makes the counts "notifications
  // delivered during the drag" rather than "the first value each saw".
  container.read(navigationPanelHeight);
  container.read(navigationPanelCoversBar);

  final rawSub = container.listen(navigationPanelHeight, (_, __) => raw++);
  final coversSub =
      container.listen(navigationPanelCoversBar, (_, __) => covers++);

  for (final height in heights) {
    container.read(navigationPanelHeight.notifier).state = height;
    await drain();
  }

  rawSub.close();
  coversSub.close();
  return (raw: raw, covers: covers);
}

void main() {
  group('navigationPanelCoversBar', () {
    test('a full sheet drag moves the bar once, not once per frame', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final (:raw, :covers) = await _driveDrag(container, _openDrag);

      // Negative control: the value the old watch used really did change on
      // nearly every frame, so `covers` being small is the fix and not a
      // consequence of the drag being too short to see.
      expect(raw, 30);
      expect(covers, 1);
    });

    test('closing the sheet brings the bar back exactly once', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final opening = await _driveDrag(container, _openDrag);
      final closing = await _driveDrag(container, _openDrag.reversed.toList());

      expect(opening.covers, 1);
      expect(closing.covers, 1);
    });

    test('the bar covers exactly where the old inline check did', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The threshold was `panelHeight < 10` written inline in the widget.
      for (final (height, expected) in [
        (50.0, false),
        (10.0, false),
        (9.99, true),
        (0.0, true),
      ]) {
        container.read(navigationPanelHeight.notifier).state = height;
        expect(
          container.read(navigationPanelCoversBar),
          expected,
          reason: 'panelHeight $height',
        );
      }
    });
  });
}
