// The `resizable` node is the one piece of layout a theme hands back to the
// user: a drag handle between two panes, with the first pane's size persisted
// per `storageKey`. The tests below pin the size the user sees under the
// theme's bounds and the store the host writes on release.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime() {
  return ThemeUiRuntime(
    theme: _theme(),
    bindings: const ThemeUiBindings({}),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: (_) {},
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    scaling: const AdaptiveScaling(1),
    home: Scaffold(
      child: SingleChildScrollView(
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

Map<String, dynamic> _node({
  String? direction,
  double initial = 240,
  double min = 120,
  double max = 480,
  String? storageKey,
}) {
  return {
    'type': 'resizable',
    if (direction != null) 'direction': direction,
    'initial': initial,
    'min': min,
    'max': max,
    if (storageKey != null) 'storageKey': storageKey,
    'children': [
      {'type': 'text', 'text': 'LEFT'},
      {'type': 'text', 'text': 'RIGHT'},
    ],
  };
}

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> node, {
  Size window = const Size(800, 600),
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _app(ThemeUiNodeView(node: node, runtime: _runtime())),
  );
  await tester.pump();
}

double _secondPaneStart(WidgetTester tester, {bool horizontal = true}) {
  final rect = tester.getRect(find.text('RIGHT'));
  return horizontal ? rect.left : rect.top;
}

Future<void> _dragHandle(
  WidgetTester tester,
  double delta, {
  bool horizontal = true,
  double start = 246,
}) async {
  final gesture = await tester.startGesture(
    horizontal ? Offset(start - 3, 8) : Offset(8, start - 3),
    kind: PointerDeviceKind.mouse,
  );
  // Two moves keep the distance clear of the drag slop either way.
  await gesture.moveBy(
    horizontal ? Offset(delta / 2, 0) : Offset(0, delta / 2),
  );
  await gesture.moveBy(
    horizontal ? Offset(delta / 2, 0) : Offset(0, delta / 2),
  );
  await gesture.up();
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  group('horizontal split', () {
    testWidgets('starts at the theme initial and keeps two panes',
        (tester) async {
      await _pump(tester, _node(storageKey: 'shelf'));

      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);
      // First pane 240 + the 6px handle.
      expect(_secondPaneStart(tester), 246);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dragging moves the split and persists on release',
        (tester) async {
      await _pump(tester, _node(storageKey: 'shelf'));

      await _dragHandle(tester, 100);

      expect(_secondPaneStart(tester), greaterThan(246));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('resizable.shelf'), greaterThan(240));
    });

    testWidgets('clamps to the theme bounds', (tester) async {
      await _pump(tester, _node(storageKey: 'shelf'));

      await _dragHandle(tester, -1000);
      expect(_secondPaneStart(tester), 126, reason: 'min 120 + handle');

      await _dragHandle(tester, 2000, start: 126);
      expect(_secondPaneStart(tester), 486, reason: 'max 480 + handle');
    });

    testWidgets('a stored size wins over the initial', (tester) async {
      SharedPreferences.setMockInitialValues({'resizable.shelf': 300.0});
      await KVStoreService.initialize();

      await _pump(tester, _node(storageKey: 'shelf'));

      expect(_secondPaneStart(tester), 306);
    });

    testWidgets('a non-finite stored size reads as absent', (tester) async {
      SharedPreferences.setMockInitialValues({
        'resizable.shelf': double.infinity,
      });
      await KVStoreService.initialize();

      await _pump(tester, _node(storageKey: 'shelf'));

      expect(_secondPaneStart(tester), 246);
    });

    testWidgets('no storageKey keeps the size session-only', (tester) async {
      await _pump(tester, _node());

      await _dragHandle(tester, 100);

      expect(_secondPaneStart(tester), greaterThan(246));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('resizable.')),
        isEmpty,
      );
    });
  });

  group('vertical split', () {
    testWidgets('direction vertical fixes the height', (tester) async {
      await _pump(
        tester,
        _node(direction: 'vertical', storageKey: 'stack'),
        window: const Size(600, 700),
      );

      expect(_secondPaneStart(tester, horizontal: false), 246);

      await _dragHandle(tester, 80, horizontal: false);

      expect(_secondPaneStart(tester, horizontal: false), greaterThan(246));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('resizable.stack'), greaterThan(240));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a node with fewer than two panes renders what it has',
      (tester) async {
    await _pump(tester, {
      'type': 'resizable',
      'storageKey': 'broken',
      'children': [
        {'type': 'text', 'text': 'ONLY'},
      ],
    });

    expect(find.text('ONLY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
