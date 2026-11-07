// The sidebar was the last hardcoded shell width: 200 logical px for the
// labelled column, 180 for the footer row, and everything else deriving from
// that literal. `layout.sidebarWidth` replaces it, so the width a theme asks
// for has to reach the column, the footer and the content (and the docked
// seek bar that tracks it) consistently.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/sidebar/sidebar_footer.dart';

Future<
    ({
      double sidebar,
      double footer,
      double content,
    })> _measure(
  WidgetTester tester, {
  ThemeLayout layout = const ThemeLayout(),
  double scaling = 1,
  double windowWidth = 1000,
}) async {
  tester.view.physicalSize = Size(windowWidth, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late final ({double sidebar, double footer, double content}) metrics;
  await tester.pumpWidget(
    ShadcnApp(
      scaling: AdaptiveScaling(scaling),
      home: Scaffold(
        child: AppLayout(
          layout: layout,
          child: Builder(
            builder: (context) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: context.sidebarWidth),
                  const VerticalDivider(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        metrics = (
                          sidebar: context.sidebarWidth,
                          footer: sidebarFooterWidth(context),
                          content: constraints.maxWidth,
                        );
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  // The app theme animates to the requested scaling.
  await tester.pump(const Duration(seconds: 1));
  return metrics;
}

void main() {
  testWidgets('the host literal reaches the column, footer and content',
      (tester) async {
    final metrics = await _measure(tester);
    final divider = tester.getSize(find.byType(VerticalDivider).first).width;

    expect(metrics.sidebar, 200);
    expect(metrics.footer, 180);
    expect(metrics.content, 1000 - 200 - divider);
  });

  testWidgets('a theme width narrows the content by the same amount',
      (tester) async {
    final base = await _measure(tester);
    final wide = await _measure(
      tester,
      layout: const ThemeLayout(sidebarWidth: 260),
    );

    expect(wide.sidebar, 260);
    expect(wide.footer, 240);
    expect(wide.content, base.content - 60);
  });

  testWidgets('the width and the footer ride the active scaling',
      (tester) async {
    final metrics = await _measure(tester, scaling: 2);

    expect(metrics.sidebar, 400);
    expect(metrics.footer, 360);
  });

  testWidgets('the footer never narrows past the labels', (tester) async {
    final metrics = await _measure(
      tester,
      layout: const ThemeLayout(sidebarWidth: 100),
    );

    expect(metrics.footer, 120);
  });
}
