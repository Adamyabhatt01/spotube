import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/ui/button_tile.dart';

/// The track menu rows used to all render with the accent fill, so the cursor
/// had nothing left to highlight. `Clickable` unions the widget states it
/// resolves with those provided by its ancestors, which means a row inside a
/// hovered track row inherits `hovered`. `AdaptivePopSheetList` — the menu next
/// to the search box, which behaves correctly — cuts that off with
/// [WidgetStatesProvider.boundary]; the track menu now does the same.
void main() {
  Future<Color?> rowFill(WidgetTester tester, Widget row) async {
    await tester.pumpWidget(
      Theme(
        data: const ThemeData.dark(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 220, child: row),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(ButtonTile),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = container.decoration;
    return decoration is BoxDecoration ? decoration.color : null;
  }

  Widget menuRow() => ButtonTile(
        style: ButtonVariance.menu,
        onPressed: () {},
        title: const Text('Add to queue'),
      );

  testWidgets('a leaked hovered state fills every row', (tester) async {
    final color = await rowFill(
      tester,
      WidgetStatesProvider(
        states: const {WidgetState.hovered},
        child: menuRow(),
      ),
    );

    // The negative control: without this the boundary test below would pass
    // for a row that never fills at all.
    expect(color, isNotNull, reason: 'ancestor states must reach the row');
  });

  testWidgets('a states boundary leaves the row plain', (tester) async {
    final color = await rowFill(
      tester,
      WidgetStatesProvider(
        states: const {WidgetState.hovered},
        child: WidgetStatesProvider.boundary(child: menuRow()),
      ),
    );

    expect(color, isNull, reason: 'boundary must block the leak');
  });
}
