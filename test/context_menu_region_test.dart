// ContextMenuRegion contracts: long press opens the compact sheet on touch,
// a disabled region never opens, and selection reports the resolved action id
// through the same callback the desktop menu uses.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';

Widget _app({
  required bool enabled,
  required List<String> selected,
}) {
  return ProviderScope(
    child: ShadcnApp(
      home: Scaffold(
        child: Center(
          child: ContextMenuRegion(
            enabled: enabled,
            longPressEnabled: true,
            item: const ContextMenuItemContext(
              target: ContextMenuTarget.playlist,
              flags: {'owner': true},
            ),
            builderFor: (context) => ContextMenuBuilder(
              label: (key, [args]) => key,
              availableActions: const {'play', 'copyLink'},
            ),
            onSelected: (context, container, action) async {
              selected.add(action.id);
            },
            child: const SizedBox(
              key: Key('menu-target'),
              width: 120,
              height: 80,
              child: ColoredBox(color: Color(0xFF888888)),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('long press opens the compact sheet and selects an action',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_app(enabled: true, selected: selected));

    await tester.longPress(find.byKey(const Key('menu-target')));
    await tester.pumpAndSettle();
    expect(find.text('play'), findsOneWidget);

    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    expect(selected, ['play']);
  });

  testWidgets('a disabled region stays closed', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_app(enabled: false, selected: selected));

    await tester.longPress(find.byKey(const Key('menu-target')));
    await tester.pumpAndSettle();
    expect(find.text('play'), findsNothing);
    expect(selected, isEmpty);
  });
}
