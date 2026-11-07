// A theme-owned `contextMenu` opts into the user's host-menu configuration
// only when it names a host `target`: hidden rows disappear and the stored
// order applies, while a menu without a target stays purely theme-owned.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

class _StubConfigNotifier extends ContextMenuConfigNotifier {
  _StubConfigNotifier(this.initial);

  final ContextMenuConfig initial;

  @override
  ContextMenuConfig build() => initial;
}

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

Map<String, dynamic> _action(String type) => {'type': type};

Map<String, dynamic> _menu({String? target}) {
  return {
    'type': 'contextMenu',
    if (target != null) 'target': target,
    'items': [
      {
        'id': 'theme.first',
        'label': 'First',
        'action': _action('openQueue'),
      },
      {
        'id': 'theme.hidden',
        'label': 'Hidden',
        'action': _action('openQueue'),
      },
      {
        'id': 'theme.second',
        'label': 'Second',
        'action': _action('openQueue'),
      },
    ],
    'children': [
      {'type': 'text', 'text': 'target'},
    ],
  };
}

Widget _app({required ContextMenuConfig config, required Widget child}) {
  return ProviderScope(
    overrides: [
      contextMenuConfigProvider.overrideWith(() => _StubConfigNotifier(config)),
    ],
    child: ShadcnApp(
      scaling: const AdaptiveScaling(1),
      home: Scaffold(child: child),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.longPress(find.text('target'));
  await tester.pumpAndSettle();
}

void main() {
  const config = ContextMenuConfig(targets: {
    'playlist': ContextMenuTargetConfig(
      hidden: {'theme.hidden'},
      order: ['theme.second'],
    ),
  });

  testWidgets('a target applies hidden rows and stored order', (tester) async {
    await tester.pumpWidget(
      _app(
        config: config,
        child: ThemeUiNodeView(
            runtime: _runtime(), node: _menu(target: 'playlist')),
      ),
    );
    await _openMenu(tester);

    expect(find.text('Hidden'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Second')).dy,
      lessThan(tester.getTopLeft(find.text('First')).dy),
    );
  });

  testWidgets('no target leaves the menu theme-owned', (tester) async {
    await tester.pumpWidget(
      _app(
        config: config,
        child: ThemeUiNodeView(runtime: _runtime(), node: _menu()),
      ),
    );
    await _openMenu(tester);

    expect(find.text('Hidden'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First')).dy,
      lessThan(tester.getTopLeft(find.text('Second')).dy),
    );
  });

  // Both of these rebuild the runtime, and a dropped `item` is invisible: the
  // only reader is the `hostItem: true` menu, which simply stops appearing in
  // templated list rows. That is the shape a library list actually has.
  group('the row item across a rebuild', () {
    ThemeUiRuntime rowRuntime(Object item) => ThemeUiRuntime(
          theme: _runtime().theme,
          bindings: const ThemeUiBindings({}),
          assets: const ThemeUiAssets(),
          templates: const {
            'row': ThemeUiTemplate(
              children: [
                {'type': 'text', 'text': 'hello'},
              ],
            ),
          },
          specVersion: 4,
          onAction: (_) {},
          item: item,
        );

    test('survives a template expansion', () {
      expect(rowRuntime('a track').descendTemplate('row').item, 'a track');
    });

    test('survives a binding rebind', () {
      expect(
        rowRuntime('a track')
            .withBindings(const ThemeUiBindings({'item.title': 'x'}))
            .item,
        'a track',
      );
    });
  });
}
