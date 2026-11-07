// Settings → Appearance → Context menu contracts: the preview is the same
// builder the live menus use, every edit persists immediately, and reset
// clears one target or all of them without touching the other surface.
import 'package:flutter/material.dart'
    show ListTile, ReorderableListView;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/pages/settings/context_menu.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

class _StubConfigNotifier extends ContextMenuConfigNotifier {
  _StubConfigNotifier(this.initial);

  final ContextMenuConfig initial;

  @override
  ContextMenuConfig build() => initial;
}

ProviderContainer _container({
  ContextMenuConfig config = ContextMenuConfig.defaults,
  List<ThemePinTarget> pinTargets = const [],
}) {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith(
        (ref) async => ThemeDefinition(
          specVersion: 4,
          light: builtInLightThemeColors(),
          dark: builtInDarkThemeColors(),
        ),
      ),
      themeUiProvider.overrideWith((ref) async => null),
      contextMenuConfigProvider.overrideWith(() => _StubConfigNotifier(config)),
    ],
  );
}

Widget _harness(
  ProviderContainer container, {
  List<ThemePinTarget> pinTargets = const [],
}) {
  return UncontrolledProviderScope(
    container: container,
    child: ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        child: AppLayout(
          tokens: const ThemeTokens(),
          radii: const ThemeRadius(),
          layout: ThemeLayout(pinTargets: pinTargets),
          child: const ContextMenuSettingsDialog(),
        ),
      ),
    ),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ContextMenuConfig config = ContextMenuConfig.defaults,
  List<ThemePinTarget> pinTargets = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = _container(config: config, pinTargets: pinTargets);
  addTearDown(container.dispose);
  await tester.pumpWidget(_harness(container, pinTargets: pinTargets));
  await tester.pumpAndSettle();
  return container;
}

Finder _actionSwitch(String label) => find.descendant(
      of: find.widgetWithText(ListTile, label),
      matching: find.byType(Switch),
    );

Finder _tileSwitch(String label) => find.descendant(
      of: find.widgetWithText(ListTile, label),
      matching: find.byType(Switch),
    );

Finder _pinSwitch(String label) => find.descendant(
      of: find.widgetWithText(Row, label),
      matching: find.byType(Switch),
    );

Future<void> _reveal(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    120,
    scrollable: find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the playlist preview lists every configurable host row',
      (tester) async {
    await _pump(tester);

    expect(find.text('Context menu'), findsOneWidget);
    expect(
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .itemCount,
      8,
    );
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Pin to Sidebar'), findsOneWidget);

    await _reveal(tester, 'Copy Link');
    expect(find.text('Delete Playlist'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
  });

  testWidgets('hiding an action persists for the selected target',
      (tester) async {
    final container = await _pump(tester);

    await _reveal(tester, 'Copy Link');
    await tester.tap(_actionSwitch('Copy Link'));
    await tester.pumpAndSettle();

    final config = container
        .read(contextMenuConfigProvider)
        .forTarget(ContextMenuTarget.playlist);
    expect(config.hidden, contains('copyLink'));
    expect(tester.widget<Switch>(_actionSwitch('Copy Link')).value, isFalse);
  });

  testWidgets('switching targets edits that target only', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.widgetWithText(Button, 'Track'));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Delete Playlist'), findsNothing);

    await _reveal(tester, 'Share');
    await tester.tap(_actionSwitch('Share'));
    await tester.pumpAndSettle();

    final state = container.read(contextMenuConfigProvider);
    expect(
      state.forTarget(ContextMenuTarget.track).hidden,
      contains('share'),
    );
    expect(state.forTarget(ContextMenuTarget.playlist).hidden, isEmpty);
  });

  testWidgets('reordering persists the explicit action order', (tester) async {
    final container = await _pump(tester);

    final list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorder(0, 3);
    await tester.pumpAndSettle();

    final config = container
        .read(contextMenuConfigProvider)
        .forTarget(ContextMenuTarget.playlist);
    expect(config.order.take(3), ['open', 'pin:sidebar', 'play']);
  });

  testWidgets('the display toggles persist for the selected target',
      (tester) async {
    final container = await _pump(tester);

    await tester.tap(_tileSwitch('Show icons'));
    await tester.pumpAndSettle();
    await tester.tap(_tileSwitch('Confirm destructive actions'));
    await tester.pumpAndSettle();

    final config = container
        .read(contextMenuConfigProvider)
        .forTarget(ContextMenuTarget.playlist);
    expect(config.showIcons, isFalse);
    expect(config.confirmDestructive, isFalse);
  });

  testWidgets('the fallback sidebar pin target can be hidden', (tester) async {
    final container = await _pump(tester);

    expect(find.text('Sidebar'), findsOneWidget);
    await tester.tap(_pinSwitch('Sidebar'));
    await tester.pumpAndSettle();

    final config = container
        .read(contextMenuConfigProvider)
        .forTarget(ContextMenuTarget.playlist);
    expect(config.hiddenPinTargets, contains('sidebar'));
  });

  testWidgets('declared pin targets replace the sidebar fallback',
      (tester) async {
    await _pump(
      tester,
      pinTargets: const [
        ThemePinTarget(id: 'bar', label: 'Top bar'),
        ThemePinTarget(id: 'rail', label: 'Right rail'),
      ],
    );

    expect(find.text('Top bar'), findsOneWidget);
    expect(find.text('Right rail'), findsOneWidget);
    expect(find.text('Sidebar'), findsNothing);
  });

  testWidgets('reset this target keeps the other targets', (tester) async {
    final container = await _pump(
      tester,
      config: const ContextMenuConfig(targets: {
        'playlist': ContextMenuTargetConfig(hidden: {'copyLink'}),
        'track': ContextMenuTargetConfig(hidden: {'share'}),
      }),
    );

    await tester.tap(find.widgetWithText(Button, 'Reset this target'));
    await tester.pumpAndSettle();

    final state = container.read(contextMenuConfigProvider);
    expect(state.forTarget(ContextMenuTarget.playlist).hidden, isEmpty);
    expect(
      state.forTarget(ContextMenuTarget.track).hidden,
      contains('share'),
    );
  });

  testWidgets('reset all clears every target', (tester) async {
    final container = await _pump(
      tester,
      config: const ContextMenuConfig(targets: {
        'playlist': ContextMenuTargetConfig(hidden: {'copyLink'}),
        'track': ContextMenuTargetConfig(hidden: {'share'}),
      }),
    );

    await tester.tap(find.widgetWithText(Button, 'Reset all'));
    await tester.pumpAndSettle();

    expect(container.read(contextMenuConfigProvider).targets, isEmpty);
  });
}
