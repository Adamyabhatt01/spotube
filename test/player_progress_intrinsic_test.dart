// The desktop player is a `Scaffold` footer, and shadcn positions that footer
// from exactly one number: `footer.getMaxIntrinsicHeight(double.infinity)`
// (shadcn_flutter-0.0.47/lib/src/components/layout/scaffold.dart:944). Asking a
// subtree for its intrinsic dimensions is *not* the same as laying it out —
// `RenderLayoutBuilder` refuses the question and throws "LayoutBuilder does not
// support returning intrinsic dimensions", which aborts `performLayout` and
// leaves the whole window unpainted. That is what an earlier `progress: below`
// attempt did with `Row([Text, Expanded(Slider), Text])`: a flex child in a Row
// gets asked for its intrinsic *width* (flutter/lib/src/rendering/flex.dart:753),
// and shadcn's `Slider` is built on a `LayoutBuilder`.
//
// So a seek row that lives in the player has to answer this query, which means
// every width in it is computed rather than claimed. These tests put the real
// `PlayerSeekLine` inside the real `SurfaceCard` inside a real floating footer —
// the same path the app builds — and ask it the question shadcn will ask. The
// control case proves the probe catches the version that black-screened the app.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/modules/player/player_progress.dart';

const _windowHeight = 900.0;

/// The bar at the shape the player will hand it, wrapped the way the player
/// wraps it.
Widget playerSeekLine({required Key key, required bool inline}) {
  return SurfaceCard(
    borderRadius: BorderRadius.zero,
    child: PlayerSeekLine(
      key: key,
      inline: inline,
      value: 0.4,
      buffered: 0.6,
      elapsed: '0:42',
      total: '3:11',
      duration: const Duration(minutes: 3, seconds: 11),
      enabled: true,
      onSeek: (_) {},
    ),
  );
}

/// The shape that broke: the bar takes the leftover width with `Expanded`.
Widget expandedSeekRow(Key key) {
  return Builder(
    key: key,
    builder: (context) {
      final style = Theme.of(context).typography.xSmall;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: kProgressRowGutter),
        child: Row(
          children: [
            Text('0:42', style: style),
            const Expanded(child: Slider(value: SliderValue.single(0.4))),
            Text('3:11', style: style),
          ],
        ),
      );
    },
  );
}

Future<void> pumpInFooter(
  WidgetTester tester,
  Widget footer, {
  required double windowWidth,
  double scaling = 1,
}) async {
  tester.view.physicalSize = Size(windowWidth, _windowHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShadcnApp(
      scaling: AdaptiveScaling(scaling),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        floatingFooter: true,
        footers: [footer],
        child: const SizedBox.shrink(),
      ),
    ),
  );
  // The theme arrives animated, so scaling is only readable after the settle.
  await tester.pump(const Duration(seconds: 1));
}

/// The exact call shadcn makes, taken out of the layout pass so a failure is a
/// value under test rather than a blank window.
double intrinsicFooterHeight(WidgetTester tester, Key key) {
  final box = tester.renderObject<RenderBox>(find.byKey(key));
  final intrinsic = box.getMaxIntrinsicHeight(double.infinity);
  expect(
    intrinsic,
    box.size.height,
    reason: 'a footer that measures one height and lays out another detaches '
        'from the bottom edge',
  );
  return intrinsic;
}

void main() {
  const sizes = [
    (900.0, 1.0),
    (1400.0, 1.0),
    (1808.0, 1.0),
    (1400.0, 0.7),
    (1400.0, 1.5),
    (1400.0, 2.0),
  ];

  testWidgets('the below-player seek line answers the intrinsic query',
      (tester) async {
    for (final (width, scaling) in sizes) {
      final key = GlobalKey();
      await pumpInFooter(
        tester,
        playerSeekLine(key: key, inline: false),
        windowWidth: width,
        scaling: scaling,
      );

      expect(
        intrinsicFooterHeight(tester, key),
        greaterThan(0),
        reason: '$width at $scaling',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$width at $scaling overflowed or failed to lay out',
      );
    }
  });

  testWidgets('the seek line spans the player, inset by the card padding',
      (tester) async {
    final key = GlobalKey();
    await pumpInFooter(
      tester,
      playerSeekLine(key: key, inline: false),
      windowWidth: 1400,
    );

    final line = tester.getRect(find.byKey(key));
    final bar = tester.getRect(find.byType(Slider));
    // The bar keeps a sane share of the row instead of being squeezed out...
    expect(bar.width, greaterThan(line.width * 0.6));
    // ...and the times stay at the two ends of it.
    expect(bar.left, greaterThan(line.left));
    expect(bar.right, lessThan(line.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the inline shape Spotube already ships is measurable too',
      (tester) async {
    // The probe has to pass on the existing bar before it can be trusted to
    // judge the new one.
    for (final (width, scaling) in sizes) {
      final key = GlobalKey();
      await pumpInFooter(
        tester,
        playerSeekLine(key: key, inline: true),
        windowWidth: width,
        scaling: scaling,
      );

      expect(
        intrinsicFooterHeight(tester, key),
        greaterThan(0),
        reason: '$width at $scaling',
      );
      expect(tester.takeException(), isNull, reason: '$width at $scaling');
    }
  });

  test('the bar width is floored and capped by the window, never negative', () {
    expect(progressSeekBarWidth(1400, 1), 1184);
    // Below the allowance the floor takes over rather than going negative.
    expect(progressSeekBarWidth(200, 1), 140);
    // A window narrower than the floor cannot hold one, so it gets the window.
    expect(progressSeekBarWidth(100, 1), 100);
    // Scaling eats the width: 216 * 2 off a 1400px window.
    expect(progressSeekBarWidth(1400, 2), 968);
  });

  testWidgets(
      'control: the Expanded version is what this probe exists to catch',
      (tester) async {
    final key = GlobalKey();
    // The footer's own performLayout dies on this shape, which is the black
    // screen; drain those reports so the assertion below is the only thing that
    // can fail this test.
    await pumpInFooter(tester, expandedSeekRow(key), windowWidth: 1400);
    while (tester.takeException() != null) {}

    final box = tester.renderObject<RenderBox>(find.byKey(key));
    expect(
      () => box.getMaxIntrinsicHeight(double.infinity),
      throwsA(isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('intrinsic dimensions'),
      )),
      reason: 'if this stops throwing, the probe no longer guards the footer',
    );
  });
}
