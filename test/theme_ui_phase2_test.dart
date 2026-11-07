import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme({String uiKit = 'shadcn'}) {
  return ThemeDefinition(
    specVersion: 4,
    uiKit: uiKit,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime({
  String uiKit = 'shadcn',
  Map<String, dynamic> bindings = const {},
  ThemeUiActionCallback? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(uiKit: uiKit),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    // The test platform resolves to mobile scaling (1.25); pin it so the
    // logical pixel values in these tests are the values a desktop host sees.
    scaling: const AdaptiveScaling(1),
    home: Scaffold(
      child: SingleChildScrollView(
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

Widget _node(ThemeUiRuntime runtime, Map<String, dynamic> node) {
  return ThemeUiNodeView(runtime: runtime, node: node);
}

Map<String, dynamic> _action(String type, [Map<String, dynamic>? args]) {
  return {
    'type': type,
    if (args != null) 'args': args,
  };
}

void main() {
  setUp(() {
    ThemeUiDiagnostics.enabled = true;
    ThemeUiDiagnostics.reset();
  });

  tearDown(() {
    ThemeUiDiagnostics.reset();
  });

  group('slider', () {
    testWidgets('fires only on release, with the committed value',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'bass': 2}, onAction: fired.add),
        {
          'type': 'slider',
          'bind': 'bass',
          'min': 0,
          'max': 10,
          'step': 1,
          'action': _action('seek', {'position': r'$value'}),
        },
      )));

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart?.call(const SliderValue.single(0.2));
      slider.onChanged?.call(const SliderValue.single(0.5));
      await tester.pump();
      expect(fired, isEmpty, reason: 'a drag does not fire per frame');

      slider.onChangeEnd?.call(const SliderValue.single(0.5));
      await tester.pump();

      expect(fired, hasLength(1));
      expect(fired.single.type, 'seek');
      expect(fired.single.args['position'], 5.0);
    });

    testWidgets('a Material kit renders and commits a Material slider',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(
          uiKit: 'material',
          bindings: {'bass': 2},
          onAction: fired.add,
        ),
        {
          'type': 'slider',
          'bind': 'bass',
          'min': 0,
          'max': 10,
          'step': 1,
          'action': _action('seek', {'position': r'$value'}),
        },
      )));

      expect(find.byType(material.Slider), findsOneWidget);
      final slider =
          tester.widget<material.Slider>(find.byType(material.Slider));
      slider.onChanged?.call(7);
      await tester.pump();
      expect(fired, isEmpty);

      slider.onChangeEnd?.call(7);
      await tester.pump();
      expect(fired.single.args['position'], 7.0);
    });

    testWidgets('a Cupertino kit renders a Cupertino slider', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(uiKit: 'cupertino', bindings: {'bass': 2}),
        const {'type': 'slider', 'bind': 'bass', 'min': 0, 'max': 10},
      )));

      expect(find.byType(cupertino.CupertinoSlider), findsOneWidget);
    });

    testWidgets('label and showValue draw the value', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'bass': 4}),
        const {
          'type': 'slider',
          'bind': 'bass',
          'min': 0,
          'max': 10,
          'step': 1,
          'label': 'Bass',
          'showValue': true,
        },
      )));

      expect(find.text('Bass'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('switch and checkbox', () {
    testWidgets('a switch fires its value', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'muted': false}, onAction: fired.add),
        {
          'type': 'switch',
          'bind': 'muted',
          'label': 'Mute',
          'action': _action('setShuffle', {'value': r'$value'}),
        },
      )));

      expect(find.text('Mute'), findsOneWidget);
      final control = tester.widget<Switch>(find.byType(Switch));
      expect(control.value, isFalse);
      control.onChanged?.call(true);
      await tester.pump();

      expect(fired.single.args['value'], isTrue);
    });

    testWidgets('a checkbox fires its value', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'muted': false}, onAction: fired.add),
        {
          'type': 'checkbox',
          'bind': 'muted',
          'label': 'Mute',
          'action': _action('setShuffle', {'value': r'$value'}),
        },
      )));

      final control = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(control.state, CheckboxState.unchecked);
      control.onChanged?.call(CheckboxState.checked);
      await tester.pump();

      expect(fired.single.args['value'], isTrue);
    });

    testWidgets('disabledWhen disables both controls', (tester) async {
      final runtime = _runtime(bindings: {'player.playing': true});
      await tester.pumpWidget(_app(_node(runtime, const {
        'type': 'column',
        'children': [
          {
            'type': 'switch',
            'bind': 'muted',
            'disabledWhen': 'player.playing',
          },
          {
            'type': 'checkbox',
            'bind': 'muted',
            'disabledWhen': 'player.playing',
          },
        ],
      })));

      expect(tester.widget<Switch>(find.byType(Switch)).enabled, isFalse);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).enabled, isFalse);
    });
  });

  group('radioGroup', () {
    testWidgets('renders options and fires the chosen value', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'quality': 'normal'}, onAction: fired.add),
        {
          'type': 'radioGroup',
          'bind': 'quality',
          'options': [
            {'value': 'normal', 'label': 'Normal'},
            {'value': 'high', 'label': 'High'},
          ],
          'action': _action('plugin', {
            'id': 'quality',
            'value': r'$value',
          }),
        },
      )));

      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);

      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(group.value, 'normal');
      group.onChanged?.call('high');
      await tester.pump();

      expect(fired.single.args['value'], 'high');
    });
  });

  group('text inputs', () {
    testWidgets('debounces typing and fires once with the final text',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'textField',
          'bind': 'query',
          'debounceMs': 150,
          'action': _action('plugin', {
            'id': 'query',
            'value': r'$value',
          }),
        },
      )));

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fired, isEmpty);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fired, isEmpty, reason: 'the trailing edit resets the timer');

      await tester.pump(const Duration(milliseconds: 60));
      expect(fired, hasLength(1));
      expect(fired.single.args['value'], 'hi');
    });

    testWidgets('submit flushes immediately and cancels the debounce',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'textField',
          'bind': 'query',
          'debounceMs': 500,
          'action': _action('plugin', {
            'id': 'query',
            'value': r'$value',
          }),
        },
      )));

      await tester.enterText(find.byType(TextField), 'search');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(fired, hasLength(1));
      expect(fired.single.args['value'], 'search');

      await tester.pump(const Duration(milliseconds: 600));
      expect(fired, hasLength(1));
    });

    testWidgets('clearable clears the field and fires the empty value',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'textField',
          'bind': 'query',
          'debounceMs': 1000,
          'clearable': true,
          'action': _action('plugin', {
            'id': 'query',
            'value': r'$value',
          }),
        },
      )));

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      await tester.tap(find.byIcon(SpotubeIcons.close));
      await tester.pump();

      expect(fired, hasLength(1));
      expect(fired.single.args['value'], '');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );

      await tester.pump(const Duration(milliseconds: 1100));
      expect(fired, hasLength(1));
    });

    testWidgets('textArea honours minLines and maxLines', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'textArea',
          'bind': 'notes',
          'minLines': 3,
          'maxLines': 6,
        },
      )));

      final area = tester.widget<TextArea>(find.byType(TextArea));
      expect(area.minLines, 3);
      expect(area.maxLines, 6);
    });
  });

  group('select', () {
    testWidgets('opens a dropdown and fires the chosen option', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'sort': 'alpha'}, onAction: fired.add),
        {
          'type': 'select',
          'bind': 'sort',
          'placeholder': 'Sort by',
          'options': [
            {'value': 'alpha', 'label': 'Alphabetical'},
            {'value': 'recent', 'label': 'Recently added'},
          ],
          'action': _action('plugin', {
            'id': 'sort',
            'value': r'$value',
          }),
        },
      )));

      expect(find.text('Alphabetical'), findsOneWidget);
      await tester.tap(find.text('Alphabetical'));
      await tester.pumpAndSettle();
      expect(find.text('Recently added'), findsOneWidget);

      await tester.tap(find.text('Recently added'));
      await tester.pumpAndSettle();

      expect(fired.single.args['value'], 'recent');
    });
  });

  group('segmented', () {
    testWidgets('fires the chosen value', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'layout': 'list'}, onAction: fired.add),
        {
          'type': 'segmented',
          'bind': 'layout',
          'options': [
            {'value': 'list', 'label': 'List'},
            {'value': 'grid', 'label': 'Grid'},
          ],
          'action': _action('plugin', {
            'id': 'layout',
            'value': r'$value',
          }),
        },
      )));

      await tester.tap(find.text('Grid'));
      await tester.pump();

      expect(fired.single.args['value'], 'grid');
    });
  });

  group('tabs', () {
    testWidgets('switches panels and fires the item id', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'tab': 'list'}, onAction: fired.add),
        {
          'type': 'tabs',
          'bind': 'tab',
          'items': [
            {'id': 'list', 'label': 'List'},
            {'id': 'grid', 'label': 'Grid'},
          ],
          'panels': [
            [
              {'type': 'text', 'text': 'list panel'},
            ],
            [
              {'type': 'text', 'text': 'grid panel'},
            ],
          ],
          'action': _action('plugin', {
            'id': 'tab',
            'value': r'$value',
          }),
        },
      )));

      expect(find.text('list panel'), findsOneWidget);
      expect(find.text('grid panel'), findsNothing);

      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();

      expect(find.text('grid panel'), findsOneWidget);
      expect(find.text('list panel'), findsNothing);
      expect(fired.single.args['value'], 'grid');
    });

    testWidgets('an index bind picks the initial panel', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'tab': 1}),
        const {
          'type': 'tabs',
          'bind': 'tab',
          'items': [
            {'id': 'list', 'label': 'List'},
            {'id': 'grid', 'label': 'Grid'},
          ],
          'panels': [
            [
              {'type': 'text', 'text': 'list panel'},
            ],
            [
              {'type': 'text', 'text': 'grid panel'},
            ],
          ],
        },
      )));

      expect(find.text('grid panel'), findsOneWidget);
      expect(find.text('list panel'), findsNothing);
    });
  });

  group('menu', () {
    testWidgets('the trigger opens items that dispatch host actions',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'menu',
          'trigger': 'More',
          'items': [
            {
              'label': 'Settings',
              'action': _action('openSettings'),
            },
          ],
        },
      )));

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(fired.single.type, 'openSettings');
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('contextMenu wraps its children and fires on long press',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'contextMenu',
          'items': [
            {
              'label': 'Queue',
              'action': _action('openQueue'),
            },
          ],
          'children': [
            {'type': 'text', 'text': 'target'},
          ],
        },
      )));

      await tester.longPress(find.text('target'));
      await tester.pumpAndSettle();
      expect(find.text('Queue'), findsOneWidget);

      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();

      expect(fired.single.type, 'openQueue');
    });
  });

  group('dialog', () {
    Map<String, dynamic> dialogNode() => {
          'type': 'dialog',
          'title': 'Delete playlist?',
          'description': 'This cannot be undone.',
          'actions': [
            {
              'label': 'Cancel',
              'action': _action('dismiss'),
            },
            {
              'label': 'Delete',
              'action': _action('plugin', {
                'id': 'delete-playlist',
                'payload': {'id': 'p1'},
              }),
            },
          ],
          'children': [
            {'type': 'text', 'text': 'Body'},
          ],
        };

    testWidgets('opens and dismisses locally from a footer button',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(
        _node(_runtime(onAction: fired.add), dialogNode()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Delete playlist?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete playlist?'), findsNothing);
      expect(fired, isEmpty, reason: 'dismiss is local to the overlay');
    });

    testWidgets('a footer action fires before the dialog closes',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(
        _node(_runtime(onAction: fired.add), dialogNode()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(fired.single.type, 'plugin');
      expect(fired.single.args['payload'], {'id': 'p1'});
      expect(find.text('Delete playlist?'), findsNothing);
    });

    testWidgets('Escape closes the dialog', (tester) async {
      await tester.pumpWidget(_app(_node(_runtime(), dialogNode())));
      await tester.pumpAndSettle();
      expect(find.text('Delete playlist?'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Delete playlist?'), findsNothing);
    });

    testWidgets('openBind false keeps it closed', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(bindings: {'dialog.open': false}),
        {
          'type': 'dialog',
          'title': 'Hidden',
          'openBind': 'dialog.open',
          'children': [
            {'type': 'text', 'text': 'Body'},
          ],
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('Hidden'), findsNothing);
    });

    testWidgets('openBind closes on false and reopens on a new true edge',
        (tester) async {
      Widget build(bool open) => _app(_node(
            _runtime(bindings: {'dialog.open': open}),
            {
              'type': 'dialog',
              'title': 'Bound dialog',
              'openBind': 'dialog.open',
              'children': [
                {'type': 'text', 'text': 'Body'},
              ],
            },
          ));

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsOneWidget);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsNothing);

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsOneWidget);
    });

    testWidgets('openBind false before the first frame closes the push',
        (tester) async {
      Widget build(bool open) => _app(_node(
            _runtime(bindings: {'dialog.open': open}),
            {
              'type': 'dialog',
              'title': 'Bound dialog',
              'openBind': 'dialog.open',
              'children': [
                {'type': 'text', 'text': 'Body'},
              ],
            },
          ));

      await tester.pumpWidget(build(true));
      // Flip the binding before the pushed route gets a frame; the dialog
      // must not appear and stay up.
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();

      expect(find.text('Bound dialog'), findsNothing);
    });

    testWidgets('a locally dismissed dialog waits for a new open edge',
        (tester) async {
      Widget build(bool open) => _app(_node(
            _runtime(bindings: {'dialog.open': open}),
            {
              'type': 'dialog',
              'title': 'Bound dialog',
              'openBind': 'dialog.open',
              'actions': [
                {
                  'label': 'Close',
                  'action': _action('dismiss'),
                },
              ],
              'children': [
                {'type': 'text', 'text': 'Body'},
              ],
            },
          ));

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsNothing);

      // The binding is still true; a rebuild must not flap it back open.
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsNothing);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound dialog'), findsOneWidget);
    });
  });

  group('sheet', () {
    testWidgets('opens from the side and a child dismiss closes it',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'sheet',
          'side': 'right',
          'width': 240,
          'children': [
            {'type': 'text', 'text': 'Sheet body'},
            {
              'type': 'button',
              'label': 'Close',
              'action': _action('dismiss'),
            },
          ],
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('Sheet body'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Sheet body'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('openBind shows, hides and reopens the sheet', (tester) async {
      Widget build(bool open) => _app(_node(
            _runtime(bindings: {'sheet.open': open}),
            {
              'type': 'sheet',
              'side': 'right',
              'openBind': 'sheet.open',
              'children': [
                {'type': 'text', 'text': 'Bound sheet'},
              ],
            },
          ));

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.text('Bound sheet'), findsNothing);

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound sheet'), findsOneWidget);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.text('Bound sheet'), findsNothing);

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('Bound sheet'), findsOneWidget);
    });
  });

  group('popover', () {
    testWidgets('content renders in the invoking kit and can dismiss',
        (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        {
          'type': 'popover',
          'trigger': 'Open',
          'kit': 'material',
          'children': [
            {
              'type': 'button',
              'label': 'Inside',
              'action': _action('dismiss'),
            },
          ],
        },
      )));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The popover itself is not a Material surface, but its content is
      // scoped to the kit that opened it.
      expect(find.byType(material.FilledButton), findsOneWidget);
      expect(find.text('Inside'), findsOneWidget);

      await tester.tap(find.text('Inside'));
      await tester.pumpAndSettle();

      expect(find.text('Inside'), findsNothing);
    });
  });

  group('tooltip', () {
    testWidgets('shows its text after hovering', (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'tooltip',
          'text': 'Helpful hint',
          'children': [
            {'type': 'text', 'text': 'tip'},
          ],
        },
      )));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('tip')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Helpful hint'), findsOneWidget);
    });
  });

  group('dismiss outside an overlay', () {
    testWidgets('falls through to the host dispatcher', (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(_app(_node(
        _runtime(onAction: fired.add),
        {
          'type': 'button',
          'label': 'Dismiss',
          'action': _action('dismiss'),
        },
      )));

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(fired.single.type, 'dismiss');
    });
  });

  group('focus traversal', () {
    testWidgets('Tab moves focus from one text field to the next',
        (tester) async {
      await tester.pumpWidget(_app(_node(
        _runtime(),
        const {
          'type': 'column',
          'children': [
            {
              'type': 'textField',
              'bind': 'first',
              'placeholder': 'First',
            },
            {
              'type': 'textField',
              'bind': 'second',
              'placeholder': 'Second',
            },
          ],
        },
      )));

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      final before = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, isNot(same(before)));
    });
  });
}
