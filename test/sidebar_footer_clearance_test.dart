// The sidebar pins its footer to the bottom of the window and reserves space
// there so the floating bottom player cannot cover the settings button in it.
// That reservation has to track the player, and the player is built from
// paddings, icons and text that all follow `theme.scaling` — the old
// `Gap(130)` / `Gap(65)` literals did not, so a scaled-up theme slid the
// profile row underneath the player. The scaling-1.5 case is the one that used
// to fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/sidebar/sidebar.dart';

const probeKey = ValueKey('pinned');

/// Pumps the shell at [width] with a footer of [footerHeight] and reports what
/// the sidebar derives: the reservation itself, and where a row pinned above it
/// ends up, as a distance from the window's bottom edge.
Future<({double clearance, double fromBottom})> _measureShell(
  WidgetTester tester, {
  required double width,
  required double footerHeight,
  double scaling = 1,
  bool playerVisible = true,
  PlayerDock dock = PlayerDock.fullWidth,
  ThemeLayout layout = const ThemeLayout(),
}) async {
  const windowHeight = 1000.0;
  tester.view.physicalSize = Size(width, windowHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  var clearance = 0.0;
  await tester.pumpWidget(
    ShadcnApp(
      scaling: AdaptiveScaling(scaling),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        floatingFooter: true,
        footers: [
          SizedBox(height: footerHeight, width: double.infinity),
        ],
        child: AppLayout(
          layout: layout,
          child: Builder(
            builder: (context) {
              clearance = sidebarBottomClearanceOf(context,
                  playerVisible: playerVisible, dock: dock);
              return Column(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  const SizedBox(key: probeKey, width: 1, height: 1),
                  Gap(clearance),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  // The app theme is animated, so the scaled theme is only in place once the
  // transition has run; reading earlier sees scaling 1.
  await tester.pump(const Duration(seconds: 1));

  return (
    clearance: clearance,
    fromBottom: windowHeight - tester.getRect(find.byKey(probeKey)).bottom,
  );
}

void main() {
  group('sidebarBottomClearanceOf', () {
    testWidgets('is what the player measures at scaling 1', (tester) async {
      final above = await _measureShell(
        tester,
        width: 1800,
        footerHeight: 130,
      );
      final narrow = await _measureShell(tester, width: 700, footerHeight: 65);

      expect(above.clearance, 130);
      expect(narrow.clearance, 65);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grows with the player, instead of falling behind it',
        (tester) async {
      // The case `Gap(130)` lost: a player that grew by half still has the
      // settings row cleared above it.
      final scaled = await _measureShell(
        tester,
        width: 1800,
        footerHeight: 195,
        scaling: 1.5,
      );

      expect(scaled.clearance, 195);
      expect(scaled.fromBottom, greaterThanOrEqualTo(195));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scales the narrow layout too', (tester) async {
      for (final (scaling, expected) in [
        (1.0, 65.0),
        (1.5, 97.5),
        (2.0, 130.0)
      ]) {
        final seen = await _measureShell(
          tester,
          width: 700,
          footerHeight: 0,
          scaling: scaling,
        );

        expect(seen.clearance, expected, reason: 'scaling $scaling');
        expect(seen.fromBottom, greaterThanOrEqualTo(expected),
            reason: 'scaling $scaling');
        expect(tester.takeException(), isNull, reason: 'scaling $scaling');
      }
    });

    testWidgets('flips on the same breakpoint the player appears on',
        (tester) async {
      // `lgAndUp` is `width > 820` and BottomPlayer hides itself on `mdAndDown`,
      // which is `width <= 820` — the same boundary, so the two cannot disagree
      // about whether a player is on screen.
      final below = await _measureShell(tester, width: 820, footerHeight: 0);
      final above = await _measureShell(tester, width: 821, footerHeight: 0);

      expect(below.clearance, 65);
      expect(above.clearance, 130);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is the same for a labelled nav and an icon-only rail',
        (tester) async {
      // The settings row has to stay reachable in a rail-width sidebar exactly
      // as much as in a wide one. Tying the reservation to the nav shape is how
      // the button ended up under the player once already.
      for (final width in [908.0, 1400.0]) {
        for (final scaling in [1.0, 1.5]) {
          final labels = await _measureShell(
            tester,
            width: width,
            footerHeight: 130,
            scaling: scaling,
          );
          final rail = await _measureShell(
            tester,
            width: width,
            footerHeight: 130,
            scaling: scaling,
            layout: const ThemeLayout(nav: ThemeNav.rail),
          );

          expect(rail.clearance, labels.clearance,
              reason: '$width at $scaling');
          expect(tester.takeException(), isNull, reason: '$width at $scaling');
        }
      }
    });

    testWidgets('makes room for a seek line the player grew underneath',
        (tester) async {
      const below = ThemeLayout(progress: ThemeProgress.below);

      final flat = await _measureShell(
        tester,
        width: 1400,
        footerHeight: 130,
        scaling: 1.5,
      );
      final withSeekLine = await _measureShell(
        tester,
        width: 1400,
        footerHeight: 130,
        scaling: 1.5,
        layout: below,
      );
      // `progress: below` only adds a line when there is a bar to hang it on;
      // the narrow layouts get a floating overlay that takes no space at all.
      final overlayLayout = await _measureShell(
        tester,
        width: 1400,
        footerHeight: 130,
        scaling: 1.5,
        layout: below,
        playerVisible: false,
      );

      expect(withSeekLine.clearance, flat.clearance + 12 * 1.5);
      expect(overlayLayout.clearance, flat.clearance);
      expect(
        withSeekLine.fromBottom,
        greaterThanOrEqualTo(withSeekLine.clearance),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses when the player docks under the content',
        (tester) async {
      // A docked player never overlaps the sidebar, so the reservation is
      // a small pad regardless of width, visibility or seek-line layout.
      for (final width in [700.0, 1400.0]) {
        for (final scaling in [1.0, 1.5]) {
          final docked = await _measureShell(
            tester,
            width: width,
            footerHeight: 0,
            scaling: scaling,
            dock: PlayerDock.docked,
          );
          expect(docked.clearance, 12 * scaling,
              reason: '$width at $scaling');
          expect(tester.takeException(), isNull,
              reason: '$width at $scaling');
        }
      }
      final withSeekLine = await _measureShell(
        tester,
        width: 1400,
        footerHeight: 0,
        scaling: 1.5,
        dock: PlayerDock.docked,
        layout: const ThemeLayout(progress: ThemeProgress.below),
      );
      expect(withSeekLine.clearance, 12 * 1.5);
      expect(tester.takeException(), isNull);
    });
  });

  group('sidebarClearance', () {
    test('full-width matrix matches the historic literals', () {
      // lgAndUp desktop bar.
      expect(
        sidebarClearance(
          lgAndUp: true,
          playerVisible: true,
          progressBelow: false,
          dock: PlayerDock.fullWidth,
          scaling: 1,
        ),
        130,
      );
      // Seek line adds its own row.
      expect(
        sidebarClearance(
          lgAndUp: true,
          playerVisible: true,
          progressBelow: true,
          dock: PlayerDock.fullWidth,
          scaling: 2,
        ),
        (130 + 12) * 2,
      );
      // Narrow/overlay: no bar growth.
      expect(
        sidebarClearance(
          lgAndUp: false,
          playerVisible: false,
          progressBelow: true,
          dock: PlayerDock.fullWidth,
          scaling: 1,
        ),
        65,
      );
    });

    test('reserves the measured player height when a theme grows the bar', () {
      // A theme's player slots can add rows (the kitchen sink's progress
      // slot does), so the measurement wins over the historic estimate.
      expect(
        sidebarClearance(
          lgAndUp: true,
          playerVisible: true,
          progressBelow: false,
          dock: PlayerDock.fullWidth,
          scaling: 1,
          playerHeight: 157,
        ),
        169,
      );
      // A hidden bar, or one docked under the content, ignores it.
      expect(
        sidebarClearance(
          lgAndUp: true,
          playerVisible: false,
          progressBelow: false,
          dock: PlayerDock.fullWidth,
          scaling: 1,
          playerHeight: 157,
        ),
        130,
      );
      expect(
        sidebarClearance(
          lgAndUp: true,
          playerVisible: true,
          progressBelow: false,
          dock: PlayerDock.docked,
          scaling: 1,
          playerHeight: 157,
        ),
        12,
      );
    });

    test('docked ignores everything but scaling', () {
      for (final lgAndUp in [true, false]) {
        for (final playerVisible in [true, false]) {
          for (final progressBelow in [true, false]) {
            expect(
              sidebarClearance(
                lgAndUp: lgAndUp,
                playerVisible: playerVisible,
                progressBelow: progressBelow,
                dock: PlayerDock.docked,
                scaling: 1.5,
              ),
              18,
            );
          }
        }
      }
    });
  });
}
