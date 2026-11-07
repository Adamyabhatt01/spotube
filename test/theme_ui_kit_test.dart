import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme({
  String uiKit = 'shadcn',
  Map<String, dynamic> components = const {},
}) {
  return ThemeDefinition(
    specVersion: 4,
    uiKit: uiKit,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
    components: components,
  );
}

ThemeUiRuntime _runtime({
  String uiKit = 'shadcn',
  Map<String, dynamic> components = const {},
  Map<String, dynamic> bindings = const {},
  ThemeUiActionCallback? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(uiKit: uiKit, components: components),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(
  Widget child, {
  material.ThemeData? materialTheme,
  cupertino.CupertinoThemeData? cupertinoTheme,
}) {
  return ShadcnApp(
    // The test platform resolves to mobile scaling (1.25); pin it so the
    // logical pixel values in these tests are the values a desktop host sees.
    scaling: const AdaptiveScaling(1),
    materialTheme: materialTheme,
    cupertinoTheme: cupertinoTheme,
    home: Scaffold(
      child: SingleChildScrollView(
        // A vertical scroll view hands its child the viewport's tight width;
        // Align loosens it so a node's own width/height (grid, aspectRatio,
        // box) is the constraint its subtree sees.
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

Widget _node(ThemeUiRuntime runtime, Map<String, dynamic> node) {
  return ThemeUiNodeView(runtime: runtime, node: node);
}

BoxDecoration _decorationWhere(
  WidgetTester tester,
  bool Function(BoxDecoration decoration) test,
) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .firstWhere(test);
}

void main() {
  group('kit resolution', () {
    testWidgets('the theme uiKit is the default kit for semantic nodes',
        (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'material'),
        const {'type': 'button', 'label': 'ok'},
      )));

      expect(find.byType(material.FilledButton), findsOneWidget);
      expect(find.byType(cupertino.CupertinoButton), findsNothing);
    });

    testWidgets('a kitScope overrides the theme kit for its subtree',
        (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'shadcn'),
        const {
          'type': 'kitScope',
          'kit': 'cupertino',
          'children': [
            {'type': 'button', 'label': 'ok'},
          ],
        },
      )));

      expect(find.byType(cupertino.CupertinoButton), findsOneWidget);
      expect(find.byType(material.FilledButton), findsNothing);
    });

    testWidgets('the nearest kitScope wins over an outer one', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'shadcn'),
        const {
          'type': 'kitScope',
          'kit': 'cupertino',
          'children': [
            {
              'type': 'kitScope',
              'kit': 'material',
              'children': [
                {'type': 'button', 'label': 'ok'},
              ],
            },
          ],
        },
      )));

      expect(find.byType(material.FilledButton), findsOneWidget);
      expect(find.byType(cupertino.CupertinoButton), findsNothing);
    });

    testWidgets('a node kit wins over the enclosing kitScope', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'shadcn'),
        const {
          'type': 'kitScope',
          'kit': 'cupertino',
          'children': [
            {'type': 'button', 'label': 'ok', 'kit': 'material'},
          ],
        },
      )));

      expect(find.byType(material.FilledButton), findsOneWidget);
      expect(find.byType(cupertino.CupertinoButton), findsNothing);
    });

    testWidgets('an unknown node kit falls through to the enclosing scope',
        (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'shadcn'),
        const {
          'type': 'kitScope',
          'kit': 'cupertino',
          'children': [
            {'type': 'button', 'label': 'ok', 'kit': 'watchos'},
          ],
        },
      )));

      expect(find.byType(cupertino.CupertinoButton), findsOneWidget);
    });

    testWidgets('an unknown theme uiKit falls back to shadcn', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'watchos'),
        const {'type': 'button', 'label': 'ok'},
      )));

      expect(find.byType(material.FilledButton), findsNothing);
      expect(find.byType(cupertino.CupertinoButton), findsNothing);
      expect(find.text('ok'), findsOneWidget);
    });
  });

  group('kit fallback and diagnostics', () {
    setUp(() {
      ThemeUiDiagnostics.enabled = true;
      ThemeUiDiagnostics.reset();
    });

    tearDown(() {
      ThemeUiDiagnostics.reset();
      ThemeUiDiagnostics.enabled = kDebugMode;
    });

    testWidgets('a component the requested kit lacks falls back to the theme',
        (tester) async {
      late ThemeUiKit resolved;
      await tester.pumpWidget(ShadcnApp(
        home: ThemeUiKitScope(
          kit: ThemeUiKit.material,
          child: Builder(
            builder: (context) {
              resolved = const ThemeUiKitResolver(themeKit: ThemeUiKit.shadcn)
                  .resolveForComponent(
                context,
                component: 'card',
                nodeType: 'card',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ));

      expect(resolved, ThemeUiKit.shadcn);
      expect(ThemeUiDiagnostics.entries, hasLength(1));
      final entry = ThemeUiDiagnostics.entries.single;
      expect(entry.requested, ThemeUiKit.material);
      expect(entry.used, ThemeUiKit.shadcn);
      expect(entry.missing, isFalse);
    });

    testWidgets('a component no kit implements is reported as missing',
        (tester) async {
      late ThemeUiKit resolved;
      await tester.pumpWidget(ShadcnApp(
        home: ThemeUiKitScope(
          kit: ThemeUiKit.material,
          child: Builder(
            builder: (context) {
              resolved = const ThemeUiKitResolver(themeKit: ThemeUiKit.material)
                  .resolveForComponent(
                context,
                component: 'mystery',
                nodeType: 'mystery',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ));

      expect(resolved, ThemeUiKit.shadcn);
      final entry = ThemeUiDiagnostics.entries.single;
      expect(entry.requested, ThemeUiKit.material);
      expect(entry.used, ThemeUiKit.shadcn);
      expect(entry.missing, isTrue);
    });

    testWidgets('one fallback is recorded once per node/variant/kit',
        (tester) async {
      await tester.pumpWidget(ShadcnApp(
        home: ThemeUiKitScope(
          kit: ThemeUiKit.material,
          child: Builder(
            builder: (context) {
              const resolver = ThemeUiKitResolver(themeKit: ThemeUiKit.shadcn);
              for (var i = 0; i < 3; i++) {
                resolver.resolveForComponent(
                  context,
                  component: 'card',
                  nodeType: 'card',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ));

      expect(ThemeUiDiagnostics.entries, hasLength(1));
    });
  });

  group('component styles', () {
    test('a kit override layers over the base group and variant', () {
      final theme = _theme(components: {
        'buttons': {
          'radius': 4,
          'primary': {'background': '#111111'},
        },
        'material': {
          'buttons': {
            'radius': 8,
            'primary': {'background': '#222222'},
          },
        },
      });

      final materialStyle = themeUiComponentStyle(
        theme,
        ThemeUiKit.material,
        'buttons',
        variant: 'primary',
      );
      expect(materialStyle['radius'], 8);
      expect(materialStyle['background'], '#222222');

      final shadcnStyle = themeUiComponentStyle(
        theme,
        ThemeUiKit.shadcn,
        'buttons',
        variant: 'primary',
      );
      expect(shadcnStyle['radius'], 4);
      expect(shadcnStyle['background'], '#111111');
    });
  });

  group('material buttons', () {
    testWidgets('variants map to Material button types', (tester) async {
      final runtime = _runtime(uiKit: 'material');
      Future<void> pump(String variant) async {
        await tester.pumpWidget(_app(_node(
          runtime,
          {'type': 'button', 'label': 'go', 'variant': variant},
        )));
      }

      await pump('ghost');
      expect(find.byType(material.TextButton), findsOneWidget);

      await pump('outline');
      expect(find.byType(material.OutlinedButton), findsOneWidget);

      await pump('secondary');
      expect(find.byType(material.FilledButton), findsOneWidget);

      await pump('destructive');
      final destructive = tester
          .widget<material.FilledButton>(find.byType(material.FilledButton));
      expect(destructive.style?.backgroundColor, isNotNull);

      await pump('primary');
      final primary = tester
          .widget<material.FilledButton>(find.byType(material.FilledButton));
      expect(primary.style?.backgroundColor, isNull);
    });

    testWidgets('a Material button fires its actions', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'material', onAction: fired.add),
        const {
          'type': 'button',
          'label': 'play',
          'action': {'type': 'playPause'},
        },
      )));

      await tester.tap(find.text('play'));
      await tester.pump();

      expect(fired.single.type, 'playPause');
    });

    testWidgets('disabledWhen disables a Material button', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(
          uiKit: 'material',
          bindings: {'player.playing': true},
          onAction: fired.add,
        ),
        const {
          'type': 'button',
          'label': 'next',
          'action': {'type': 'next'},
          'disabledWhen': 'player.playing',
        },
      )));

      await tester.tap(find.text('next'), warnIfMissed: false);
      await tester.pump();

      expect(fired, isEmpty);
    });
  });

  group('cupertino buttons', () {
    testWidgets('a Cupertino button fires its actions', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'cupertino', onAction: fired.add),
        const {
          'type': 'button',
          'label': 'play',
          'action': {'type': 'playPause'},
        },
      )));

      await tester.tap(find.text('play'));
      await tester.pump();

      expect(fired.single.type, 'playPause');
    });

    testWidgets('disabledWhen disables a Cupertino button', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(
          uiKit: 'cupertino',
          bindings: {'player.playing': true},
          onAction: fired.add,
        ),
        const {
          'type': 'button',
          'label': 'next',
          'action': {'type': 'next'},
          'disabledWhen': 'player.playing',
        },
      )));

      await tester.tap(find.text('next'), warnIfMissed: false);
      await tester.pump();

      expect(fired, isEmpty);
    });
  });

  group('kit progress', () {
    testWidgets(
        'a Material theme renders a Material slider and seeks on release',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(
          uiKit: 'material',
          bindings: {
            'player.position': const Duration(seconds: 30),
            'player.duration': const Duration(seconds: 120),
          },
          onAction: fired.add,
        ),
        const {'type': 'progress', 'width': 300, 'height': 8},
      )));

      expect(find.byType(material.Slider), findsOneWidget);

      await tester.drag(find.byType(material.Slider), const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(fired, isNotEmpty);
      expect(fired.last.type, 'seek');
      expect(fired.last.args['fraction'], greaterThan(0.4));
    });

    testWidgets(
        'a Cupertino theme renders a Cupertino slider and seeks on release',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(
          uiKit: 'cupertino',
          bindings: {
            'player.position': const Duration(seconds: 30),
            'player.duration': const Duration(seconds: 120),
          },
          onAction: fired.add,
        ),
        const {'type': 'progress', 'width': 300, 'height': 8},
      )));

      expect(find.byType(cupertino.CupertinoSlider), findsOneWidget);

      // CupertinoSlider only hit-tests around its thumb, so start the drag at
      // the current fraction instead of the widget centre.
      final rect = tester.getRect(find.byType(cupertino.CupertinoSlider));
      await tester.dragFrom(
        Offset(
          rect.left + 8 + (rect.width - 16) * 0.25,
          rect.center.dy,
        ),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();

      expect(fired, isNotEmpty);
      expect(fired.last.type, 'seek');
      expect(fired.last.args['fraction'], greaterThan(0.4));
    });
  });

  group('box', () {
    testWidgets('paints a background, radius and fixed size', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'box',
          'background': '#ff0000',
          'width': 120,
          'height': 60,
          'radius': 12,
          'children': [
            {'type': 'text', 'text': 'hero'},
          ],
        },
      )));

      final decoration = _decorationWhere(
        tester,
        (decoration) => decoration.color == const Color(0xFFFF0000),
      );
      expect(decoration.borderRadius, BorderRadius.circular(12));

      final box = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                const Color(0xFFFF0000),
      );
      expect(tester.getSize(box).width, closeTo(120, 0.01));
      expect(tester.getSize(box).height, closeTo(60, 0.01));
    });

    testWidgets('a bare colour border gets a one-pixel rule', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'box',
          'border': '#00ff00',
          'children': [
            {'type': 'text', 'text': 'framed'},
          ],
        },
      )));

      final decoration = _decorationWhere(
        tester,
        (decoration) => decoration.border != null,
      );
      final border = decoration.border! as Border;
      expect(border.top.color, const Color(0xFF00FF00));
      expect(border.top.width, 1);
    });

    testWidgets('a border object carries its own width', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'box',
          'border': {'color': '#0000ff', 'width': 3},
          'children': [
            {'type': 'text', 'text': 'thick'},
          ],
        },
      )));

      final decoration = _decorationWhere(
        tester,
        (decoration) => decoration.border != null,
      );
      final border = decoration.border! as Border;
      expect(border.top.color, const Color(0xFF0000FF));
      expect(border.top.width, 3);
    });

    testWidgets('paints a gradient and clips its children', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'box',
          'radius': 12,
          'clip': true,
          'gradient': {
            'colors': ['#111111', '#222222'],
            'begin': 'topCenter',
            'end': 'bottomCenter',
            'stops': [0.0, 0.9],
          },
          'children': [
            {'type': 'text', 'text': 'inside'},
          ],
        },
      )));

      final decoration = _decorationWhere(
        tester,
        (decoration) => decoration.gradient is LinearGradient,
      );
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, const [Color(0xFF111111), Color(0xFF222222)]);
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.stops, const [0.0, 0.9]);

      final clip = tester.widget<ClipRRect>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.borderRadius == BorderRadius.circular(12),
        ),
      );
      expect(clip.clipBehavior, Clip.antiAlias);
      expect(find.text('inside'), findsOneWidget);
    });
  });

  group('grid', () {
    testWidgets('lays children out in fixed-width columns', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          width: 320,
          child: _node(
            _runtime(),
            const {
              'type': 'grid',
              'columns': 2,
              'gap': 10,
              'children': [
                {'type': 'text', 'text': 'a'},
                {'type': 'text', 'text': 'b'},
                {'type': 'text', 'text': 'c'},
              ],
            },
          ),
        ),
      ));

      final a = tester.getTopLeft(find.text('a'));
      final b = tester.getTopLeft(find.text('b'));
      final c = tester.getTopLeft(find.text('c'));

      // Two 155 px cells with a 10 px gutter.
      expect(b.dy, a.dy);
      expect(b.dx - a.dx, closeTo(165, 0.01));
      expect(c.dx, a.dx);
      expect(c.dy, greaterThan(a.dy));
    });

    testWidgets('an empty grid renders nothing', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {'type': 'grid', 'children': []},
      )));

      expect(find.byType(Wrap), findsNothing);
    });
  });

  group('safeArea', () {
    testWidgets('insets every edge when edges is omitted', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'safeArea',
          'children': [
            {'type': 'text', 'text': 'safe'},
          ],
        },
      )));

      final safeArea = tester.widget<SafeArea>(
        find
            .descendant(
              of: find.byType(ThemeUiNodeView),
              matching: find.byType(SafeArea),
            )
            .first,
      );
      expect(safeArea.top, isTrue);
      expect(safeArea.right, isTrue);
      expect(safeArea.bottom, isTrue);
      expect(safeArea.left, isTrue);
    });

    testWidgets('only the listed edges are inset', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'safeArea',
          'edges': ['top', 'right'],
          'children': [
            {'type': 'text', 'text': 'safe'},
          ],
        },
      )));

      final safeArea = tester.widget<SafeArea>(
        find
            .descendant(
              of: find.byType(ThemeUiNodeView),
              matching: find.byType(SafeArea),
            )
            .first,
      );
      expect(safeArea.top, isTrue);
      expect(safeArea.right, isTrue);
      expect(safeArea.bottom, isFalse);
      expect(safeArea.left, isFalse);
    });
  });

  group('aspectRatio', () {
    testWidgets('sizes the subtree from its width and ratio', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          width: 200,
          child: _node(
            _runtime(),
            const {
              'type': 'aspectRatio',
              'ratio': 2,
              'children': [
                {'type': 'text', 'text': 'ratio'},
              ],
            },
          ),
        ),
      ));

      final aspect = find
          .descendant(
            of: find.byType(ThemeUiNodeView),
            matching: find.byType(AspectRatio),
          )
          .first;
      expect(tester.widget<AspectRatio>(aspect).aspectRatio, 2);
      expect(tester.getSize(aspect).width, closeTo(200, 0.01));
      expect(tester.getSize(aspect).height, closeTo(100, 0.01));
    });
  });

  group('theme bridges', () {
    test('the Material bridge inherits the plugin palette and type ladder', () {
      final scheme = LegacyColorSchemes.darkSlate().copyWith(
        primary: () => const Color(0xFF00FF00),
        background: () => const Color(0xFF101010),
      );
      final theme = buildMaterialKitTheme(
        scheme: scheme,
        typography: const Typography.geist(
          base: TextStyle(fontSize: 17),
          p: TextStyle(fontSize: 15),
        ),
        brightness: Brightness.dark,
      );

      expect(theme.colorScheme.primary, const Color(0xFF00FF00));
      expect(theme.colorScheme.surface, const Color(0xFF101010));
      expect(theme.textTheme.bodyLarge?.fontSize, 17);
      expect(theme.textTheme.bodyMedium?.fontSize, 15);
    });

    test('the Cupertino bridge inherits the plugin palette and type ladder',
        () {
      final scheme = LegacyColorSchemes.darkSlate().copyWith(
        primary: () => const Color(0xFF00FF00),
        background: () => const Color(0xFF101010),
      );
      final theme = buildCupertinoKitTheme(
        scheme: scheme,
        typography: const Typography.geist(base: TextStyle(fontSize: 17)),
        brightness: Brightness.dark,
      );

      expect(theme.primaryColor, const Color(0xFF00FF00));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF101010));
      expect(theme.textTheme.textStyle.fontSize, 17);
    });

    testWidgets('a Material button reads the bridged palette', (tester) async {
      final scheme = LegacyColorSchemes.darkSlate().copyWith(
        primary: () => const Color(0xFF00FF00),
      );
      final materialTheme = buildMaterialKitTheme(
        scheme: scheme,
        typography: const Typography.geist(),
        brightness: Brightness.dark,
      );

      await tester.pumpWidget(_app(
        _node(
          _runtime(uiKit: 'material'),
          const {'type': 'button', 'label': 'go'},
        ),
        materialTheme: materialTheme,
      ));

      final context = tester.element(find.byType(material.FilledButton));
      expect(
        material.Theme.of(context).colorScheme.primary,
        const Color(0xFF00FF00),
      );
    });
  });

  group('slider width safety', () {
    testWidgets('a horizontal slider survives an unbounded-width parent',
        (tester) async {
      // The host player's trailing slot lays its row out in a shrink-wrapped
      // column that reaches the slider with infinite main-axis width. A bare
      // shadcn Slider asserts a finite width and its internal Stack trips
      // size.isFinite — the crash Neon Maximalist hit live. A horizontal scroll
      // view gives exactly that unbounded width.
      await tester.pumpWidget(
        ShadcnApp(
          scaling: const AdaptiveScaling(1),
          home: Scaffold(
            child: SizedBox(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _node(
                  _runtime(uiKit: 'shadcn', bindings: {'player.volume': 0.5}),
                  const {
                    'type': 'slider',
                    'bind': 'player.volume',
                    'min': 0,
                    'max': 1,
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('a bounded slider still fills its parent', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          scaling: const AdaptiveScaling(1),
          home: Scaffold(
            child: SizedBox(
              width: 400,
              child: _node(
                _runtime(uiKit: 'shadcn', bindings: {'player.volume': 0.5}),
                const {
                  'type': 'slider',
                  'bind': 'player.volume',
                  'min': 0,
                  'max': 1,
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Bounded host: the slider fills the row rather than the 160 fallback.
      expect(tester.getSize(find.byType(Slider)).width, greaterThan(300));
    });
  });
}
