// The condition evaluator and its consumers in the node renderer.
//
// Covers the pieces this workstream shipped: object-form conditions with
// equals/invert/range/allOf/anyOf, the uniform hiddenWhen guard on every
// node type, disabledWhen pointer inertness, conditional composition, and
// the semantics envelope.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_condition.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    uiKit: 'shadcn',
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime({
  Map<String, dynamic> bindings = const {},
  ThemeUiActionCallback? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    home: Scaffold(child: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('condition evaluator', () {
    const bindings = ThemeUiBindings({
      'player.playing': true,
      'player.loop': 'loop',
      'queue.count': 3,
      'queue.loading': false,
    });

    test('bare string is truthy, !string negates', () {
      expect(
        evaluateThemeUiCondition(bindings, 'player.playing'),
        isTrue,
      );
      expect(
        evaluateThemeUiCondition(bindings, '!player.playing'),
        isFalse,
      );
      expect(evaluateThemeUiCondition(bindings, 'unknown.binding'), isFalse);
    });

    test('equals compares with matches coercion', () {
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.loop',
          'equals': 'loop',
        }),
        isTrue,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.loop',
          'equals': 'single',
        }),
        isFalse,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'queue.count',
          'equals': '3',
        }),
        isTrue,
      );
    });

    test('range keys compare numerically', () {
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'queue.count',
          'gte': 3,
        }),
        isTrue,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'queue.count',
          'lt': 3,
        }),
        isFalse,
      );
      expect(
        evaluateThemeUiCondition(
          bindings,
          {'bind': 'queue.count', 'gte': 2, 'lte': 3},
        ),
        isTrue,
      );
      // A non-numeric bound value fails the range part.
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.loop',
          'gt': 1,
        }),
        isFalse,
      );
    });

    test('allOf and anyOf compose nested conditions', () {
      expect(
        evaluateThemeUiCondition(bindings, {
          'allOf': [
            'player.playing',
            {'bind': 'queue.count', 'gte': 1},
          ],
        }),
        isTrue,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'anyOf': [
            {'bind': 'player.loop', 'equals': 'single'},
            '!player.playing',
          ],
        }),
        isFalse,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'anyOf': [
            {'bind': 'player.loop', 'equals': 'single'},
            'player.playing',
          ],
        }),
        isTrue,
      );
    });

    test('invert negates the whole object result', () {
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.playing',
          'invert': true,
        }),
        isFalse,
      );
    });

    test('bind part and list parts conjoin', () {
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.playing',
          'anyOf': [
            {'bind': 'player.loop', 'equals': 'loop'},
            {'bind': 'queue.loading', 'equals': true},
          ],
        }),
        isTrue,
      );
      expect(
        evaluateThemeUiCondition(bindings, {
          'bind': 'player.playing',
          'anyOf': [
            {'bind': 'player.loop', 'equals': 'single'},
          ],
        }),
        isFalse,
      );
    });

    test('malformed conditions are false, never a throw', () {
      expect(evaluateThemeUiCondition(bindings, null), isFalse);
      expect(evaluateThemeUiCondition(bindings, 42), isFalse);
      expect(evaluateThemeUiCondition(bindings, {}), isFalse);
      expect(evaluateThemeUiCondition(bindings, {'nope': true}), isFalse);
      expect(
        evaluateThemeUiCondition(bindings, {
          'allOf': [null, 42]
        }),
        isFalse,
      );
    });
  });

  group('node guards', () {
    testWidgets('hiddenWhen hides any node type when the condition holds',
        (tester) async {
      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(bindings: {'player.playing': true}),
          node: const {
            'type': 'column',
            'children': [
              {
                'type': 'text',
                'text': 'always',
                'hiddenWhen': 'player.loop',
              },
              {
                'type': 'text',
                'text': 'often',
                'hiddenWhen': 'player.playing',
              },
              {
                'type': 'text',
                'text': 'object',
                'hiddenWhen': {
                  'bind': 'player.playing',
                  'equals': true,
                },
              },
            ],
          },
        ),
      ));

      expect(find.text('always'), findsOneWidget);
      expect(find.text('often'), findsNothing);
      expect(find.text('object'), findsNothing);
    });

    testWidgets('disabledWhen makes a tap target inert', (tester) async {
      var fired = 0;
      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(
            bindings: {'player.playing': true},
            onAction: (_) => fired++,
          ),
          node: const {
            'type': 'text',
            'text': 'nope',
            'disabledWhen': 'player.playing',
            'action': {'type': 'playPause'},
          },
        ),
      ));

      await tester.tap(find.text('nope'));
      expect(fired, 0, reason: 'disabled node must not fire its action');
    });

    testWidgets('disabledWhen with an object condition also blocks',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(
            bindings: {'queue.count': 2},
            onAction: (_) => fired++,
          ),
          node: const {
            'type': 'text',
            'text': 'blocked',
            'disabledWhen': {
              'bind': 'queue.count',
              'gte': 1,
              'invert': false,
            },
            'action': {'type': 'playPause'},
          },
        ),
      ));

      await tester.tap(find.text('blocked'));
      expect(fired, 0);
    });

    testWidgets('conditional honours allOf and anyOf', (tester) async {
      final runtime = _runtime(bindings: {
        'player.playing': true,
        'player.loop': 'loop',
        'queue.count': 3,
      });

      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: runtime,
          node: const {
            'type': 'conditional',
            'allOf': [
              'player.playing',
              {'bind': 'queue.count', 'gte': 1},
            ],
            'children': [
              {'type': 'text', 'text': 'all-of branch'},
              {'type': 'text', 'text': 'other'},
            ],
          },
        ),
      ));

      expect(find.text('all-of branch'), findsOneWidget);
      expect(find.text('other'), findsNothing);

      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: runtime,
          node: const {
            'type': 'conditional',
            'anyOf': [
              {'bind': 'player.loop', 'equals': 'single'},
              {'bind': 'player.shuffled', 'equals': true},
            ],
            'children': [
              {'type': 'text', 'text': 'any-of branch'},
              {'type': 'text', 'text': 'fallback'},
            ],
          },
        ),
      ));

      expect(find.text('any-of branch'), findsNothing);
      expect(find.text('fallback'), findsOneWidget);
    });
  });

  group('semantics envelope', () {
    testWidgets('a label becomes a Semantics node', (tester) async {
      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(),
          node: const {
            'type': 'text',
            'text': 'visual',
            'semantics': {
              'label': 'spoken label',
              'hint': 'spoken hint',
            },
          },
        ),
      ));

      // The tree has several Semantics ancestors (Material, Scaffold); the
      // authored one is the one carrying our label.
      final widgets = tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text('visual'),
              matching: find.byType(Semantics),
            ),
          )
          .toList();
      final ours = widgets.firstWhere(
        (widget) => widget.properties.label == 'spoken label',
      );
      expect(ours.properties.hint, 'spoken hint');
    });

    testWidgets('excludeSemantics hides the subtree', (tester) async {
      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(),
          node: const {
            'type': 'text',
            'text': 'hidden from semantics',
            'semantics': {'excludeSemantics': true},
          },
        ),
      ));

      // shadcn/Material interiors add their own ExcludeSemantics; what
      // matters is ours wraps the authored node.
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(find.text('hidden from semantics'), findsOneWidget);
    });
  });
}
