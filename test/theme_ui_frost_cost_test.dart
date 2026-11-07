// What a theme tree of frosted panels costs, measured rather than asserted.
//
// `blur` puts a real `BackdropFilter` behind the node that asks for it, so the
// filter count is a property a theme controls and the host can be checked on.
// The raster half — the shader work that is the whole reason the prop is
// expensive — is invisible from a widget test on this host, exactly as
// `.ai/PERFORMANCE.md` records for the lyrics page and the title bar. What this
// file can see, and pins:
//
//   * one filter per frosted node, and one clip, at rest;
//   * no filter at all while a scroll is in flight — the freeze removes the
//     widget rather than leaving a zero-sigma filter mounted, because a filter
//     that blurs nothing still runs a backdrop pass every frame;
//   * the host-side build and layout cost of the tree, which is what the freeze
//     has to be worth.
//
// The printed timings are host-side JIT numbers, comparable only with each
// other on this machine; no budget is asserted on them.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeUiRuntime _runtime() {
  return ThemeUiRuntime(
    theme: ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
    ),
    bindings: const ThemeUiBindings({}),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: (_) {},
  );
}

/// `n` panels of the same shape, frosted or not.
Map<String, dynamic> _shelf(int n, {required bool frosted}) {
  return {
    'type': 'column',
    'gap': 8,
    'children': [
      for (var i = 0; i < n; i++)
        {
          'type': 'box',
          'height': 60,
          'radius': 16,
          'background': '@card',
          if (frosted) ...{
            'blur': 12,
            'blurTint': '#0ea5e9',
          },
          'children': [
            {'type': 'text', 'text': 'panel $i'},
          ],
        },
    ],
  };
}

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> node, {
  required bool frozen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chromeBlurFrozen.overrideWith((ref) => frozen),
      ],
      child: ShadcnApp(
        home: Scaffold(
          child: SingleChildScrollView(
            child: ThemeUiNodeView(node: node, runtime: _runtime()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a frosted shelf mounts one filter per panel', (tester) async {
    await _pump(tester, _shelf(40, frosted: true), frozen: false);

    expect(find.text('panel 39'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNWidgets(40));
  });

  testWidgets('the scroll freeze takes every filter off', (tester) async {
    await _pump(tester, _shelf(40, frosted: true), frozen: true);

    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: 'a mounted zero-sigma filter still costs a backdrop pass',
    );
    expect(find.text('panel 39'), findsOneWidget, reason: 'the panels stay');
    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color)
          .where((color) => color == const Color(0xFF0EA5E9))
          .length,
      40,
      reason: 'and each keeps its tint, so the surface does not blink',
    );
  });

  testWidgets('host-side cost of the frost, printed not asserted',
      (tester) async {
    for (final n in const [10, 40, 120]) {
      final frosted = <int>[];
      final plain = <int>[];
      final frozen = <int>[];
      for (var round = 0; round < 3; round++) {
        frosted.add(await _time(tester, _shelf(n, frosted: true), frozen: false));
        plain.add(await _time(tester, _shelf(n, frosted: false), frozen: false));
        frozen.add(await _time(tester, _shelf(n, frosted: true), frozen: true));
      }

      // ignore: avoid_print
      print(
        '[theme-frost] n=$n '
        'frosted=${_median(frosted)}ms '
        'plain=${_median(plain)}ms '
        'frozen=${_median(frozen)}ms '
        '(rounds: ${frosted.join('/')} ${plain.join('/')} ${frozen.join('/')})',
      );
    }
  });
}

Future<int> _time(
  WidgetTester tester,
  Map<String, dynamic> node, {
  required bool frozen,
}) async {
  final sw = Stopwatch()..start();
  await _pump(tester, node, frozen: frozen);
  sw.stop();
  return sw.elapsedMilliseconds;
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
