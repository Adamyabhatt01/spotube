// In-sidebar drag reorder for library tiles and pinned playlists: the whole
// row grabs on hover (desktop, immediate) or long-press (touch); a short tap
// keeps the row action. Drops are directional (top half = before, bottom half
// = after) inside the same group; cross-group drops are rejected.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/root/sidebar/sidebar_reorderable_item.dart';

SidebarReorderableItem reorderRow({
  required String id,
  required SidebarReorderGroup group,
  void Function(String draggedId, String targetId, {required bool after})?
      onAccept,
  VoidCallback? onPressed,
}) {
  return SidebarReorderableItem(
    key: ValueKey('${group.name}:$id'),
    group: group,
    id: id,
    onAcceptInGroup: onAccept ?? (_, __, {required bool after}) {},
    feedback: Text('$id-ghost'),
    row: NavigationButton(
      label: Text('$id-label'),
      onPressed: onPressed ?? () {},
      child: Text('$id-icon'),
    ),
  );
}

Future<void> pumpRows(
  WidgetTester tester,
  List<NavigationBarItem> rows,
) async {
  await tester.pumpWidget(
    ShadcnApp(
      home: Scaffold(
        child: NavigationSidebar(children: rows),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

/// Shared mouse pointer per test: adding a second pointer with the same id
/// trips the framework mouse tracker, and a touch-kind `tester.drag` does not
/// faithfully drive the desktop drag layer. Hover with no buttons pressed,
/// then [mouseDragFrom] presses, moves and releases with the same pointer.
TestGesture? _mouse;
bool _mouseAdded = false;

Future<TestGesture> mousePointer(WidgetTester tester) async {
  if (_mouse == null) {
    _mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(() async {
      await _mouse?.removePointer();
      _mouse = null;
      _mouseAdded = false;
    });
  }
  final gesture = _mouse!;
  if (!_mouseAdded) {
    await gesture.addPointer(location: Offset.zero);
    _mouseAdded = true;
  }
  return gesture;
}

/// Moves the shared mouse pointer onto [finder] so `MouseRegion` hover state
/// applies (no buttons pressed).
Future<void> hoverOn(WidgetTester tester, Finder finder) async {
  final gesture = await mousePointer(tester);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// Presses the shared mouse pointer at [from], drags to [to] and releases —
/// a faithful desktop drag (same pointer that was hovering).
Future<void> mouseDragFrom(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await mousePointer(tester);
  await gesture.moveTo(from);
  await tester.pump(); // let hover arm the whole-row overlay
  await gesture.down(from);
  await gesture.moveTo(to);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('handle hidden until hovered, tap still presses the row',
      (tester) async {
    var pressed = 0;
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.library, onPressed: () {
        pressed++;
      }),
    ]);

    // No visible handle anywhere and no drag layer before hover.
    expect(find.byType(Draggable<String>), findsNothing);

    await tester.tap(find.text('a-label'));
    await tester.pump();
    expect(pressed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover arms the whole-row drag layer', (tester) async {
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.library),
    ]);
    expect(find.byType(Draggable<String>), findsNothing);

    await hoverOn(tester, find.text('a-label'));
    expect(find.byType(Draggable<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drop on the bottom half inserts after the row', (tester) async {
    final moves = <String>[];
    String move(String from, String to, {required bool after}) =>
        '$from->$to${after ? '+' : '-'}';
    Future<void> pumpThree() => pumpRows(tester, [
          for (final id in ['a', 'b', 'c'])
            reorderRow(
              id: id,
              group: SidebarReorderGroup.library,
              onAccept: (from, to, {required bool after}) =>
                  moves.add(move(from, to, after: after)),
            ),
        ]);

    // a dropped on b's bottom half lands after b.
    await pumpThree();
    final start = tester.getCenter(find.text('a-label'));
    final target = tester.getCenter(find.text('b-label'));
    await mouseDragFrom(
      tester,
      start,
      target + const Offset(0, 9),
    );
    expect(moves, ['a->b+']);
  });

  testWidgets('drop on the top half inserts before the row', (tester) async {
    final moves = <String>[];
    await pumpRows(tester, [
      for (final id in ['a', 'b', 'c'])
        reorderRow(
          id: id,
          group: SidebarReorderGroup.library,
          onAccept: (from, to, {required bool after}) =>
              moves.add('$from->$to${after ? '+' : '-'}'),
        ),
    ]);

    // c dropped on a's top half lands before a.
    await hoverOn(tester, find.text('c-label'));
    final start = tester.getCenter(find.text('c-label'));
    final target = tester.getCenter(find.text('a-label'));
    await mouseDragFrom(
      tester,
      start,
      target - const Offset(0, 9),
    );
    expect(moves, ['c->a-']);
  });

  testWidgets('bottom half of the last row reaches the very end',
      (tester) async {
    final moves = <String>[];
    await pumpRows(tester, [
      for (final id in ['a', 'b', 'c'])
        reorderRow(
          id: id,
          group: SidebarReorderGroup.library,
          onAccept: (from, to, {required bool after}) =>
              moves.add('$from->$to${after ? '+' : '-'}'),
        ),
    ]);

    // a dropped on c's bottom half lands after c (the end).
    await hoverOn(tester, find.text('a-label'));
    final start = tester.getCenter(find.text('a-label'));
    final target = tester.getCenter(find.text('c-label'));
    await mouseDragFrom(
      tester,
      start,
      target + const Offset(0, 9),
    );
    expect(moves, ['a->c+']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross-group drops are rejected', (tester) async {
    var libraryCalls = 0;
    var pinCalls = 0;
    await pumpRows(tester, [
      reorderRow(
        id: 'a',
        group: SidebarReorderGroup.library,
        onAccept: (_, __, {required bool after}) => libraryCalls++,
      ),
      reorderRow(
        id: 'p',
        group: SidebarReorderGroup.pins,
        onAccept: (_, __, {required bool after}) => pinCalls++,
      ),
    ]);

    await hoverOn(tester, find.text('p-label'));
    final startCenter = tester.getCenter(find.text('p-label'));
    final targetCenter = tester.getCenter(find.text('a-label'));
    await tester.drag(
      find.text('p-label'),
      targetCenter - startCenter,
    );
    await tester.pumpAndSettle();

    expect(libraryCalls, 0);
    expect(pinCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch path carries the row id on a long-press draggable',
      (tester) async {
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.library),
    ]);

    final draggable = tester.widget<LongPressDraggable<String>>(
      find.byType(LongPressDraggable<String>),
    );
    expect(draggable.data, 'library|a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('trailing zone moves a row to the very bottom', (tester) async {
    final accepted = <String>[];
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.pins),
      reorderRow(id: 'b', group: SidebarReorderGroup.pins),
      SidebarTrailingDropZone(
        key: const ValueKey('pins-end'),
        group: SidebarReorderGroup.pins,
        visibleIds: const ['a', 'b'],
        onAccept: accepted.add,
      ),
    ]);

    await hoverOn(tester, find.text('a-label'));
    final startCenter = tester.getCenter(find.text('a-label'));
    final zoneCenter = tester.getCenter(
      find.descendant(
        of: find.byType(SidebarTrailingDropZone),
        matching: find.byType(SizedBox),
      ),
    );
    await tester.drag(
      find.text('a-label'),
      zoneCenter - startCenter,
    );
    await tester.pumpAndSettle();

    expect(accepted, ['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trailing zone rejects cross-group and already-last drops',
      (tester) async {
    var calls = 0;
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.library),
      reorderRow(id: 'p', group: SidebarReorderGroup.pins),
      SidebarTrailingDropZone(
        key: const ValueKey('lib-end'),
        group: SidebarReorderGroup.library,
        visibleIds: const ['a'],
        onAccept: (_) => calls++,
      ),
    ]);

    // Cross-group: pin dropped on the library zone.
    Finder zoneBox() => find.descendant(
          of: find.byType(SidebarTrailingDropZone),
          matching: find.byType(SizedBox),
        );
    await hoverOn(tester, find.text('p-label'));
    var startCenter = tester.getCenter(find.text('p-label'));
    var zoneCenter = tester.getCenter(zoneBox());
    await tester.drag(find.text('p-label'), zoneCenter - startCenter);
    await tester.pumpAndSettle();
    expect(calls, 0);

    // Already last: the only library row dropped on its own end zone.
    await hoverOn(tester, find.text('a-label'));
    startCenter = tester.getCenter(find.text('a-label'));
    zoneCenter = tester.getCenter(zoneBox());
    await tester.drag(find.text('a-label'), zoneCenter - startCenter);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row renders as a sliver inside the sidebar', (tester) async {
    // NavigationSidebar lays out every child as a sliver (each wrapped in a
    // SliverPadding in a CustomScrollView); a bare box child fails sliver
    // protocol at mount time, like NavigationButton avoids via
    // SliverToBoxAdapter.
    await pumpRows(tester, [
      reorderRow(id: 'a', group: SidebarReorderGroup.pins),
    ]);

    expect(
      find.ancestor(
        of: find.byType(DragTarget<String>),
        matching: find.byType(SliverToBoxAdapter),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row renders as a plain box inside the rail', (tester) async {
    // NavigationRail lays out boxes (its buttons take the box path), so the
    // wrapper must not add a SliverToBoxAdapter there — and the inner button
    // keeps the real rail container data, rendering exactly as before.
    var pressed = 0;
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: NavigationRail(children: [
            reorderRow(
              id: 'a',
              group: SidebarReorderGroup.pins,
              onPressed: () => pressed++,
            ),
          ]),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    expect(find.byType(SliverToBoxAdapter), findsNothing);

    // The rail hides the label (labelType selected, nothing selected), so
    // tap the icon slot like a user would.
    await tester.tap(find.text('a-icon'));
    await tester.pump();
    expect(pressed, 1);
    expect(tester.takeException(), isNull);
  });
}
