// Phase 5 hands three new surfaces to a theme — the sidebar body, the library
// group and a right-hand aside — plus the persisted state that decides whether
// the user is looking at them. This suite pins the host's half of that
// contract: a slot replaces the host widget only when the theme filled it,
// the aside appears only when the theme asked and the user left it open, and
// the toggle actions write the same preferences the shortcuts write.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/aside/aside_region.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_registry.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

import 'support/common_fakes.dart';

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

SpotubeSimplePlaylistObject _playlist(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'spotify:playlist:$id',
      owner: SpotubeUserObject(id: 'owner', name: 'Owner', externalUri: ''),
    );

/// A preferences notifier that records toggles instead of touching drift.
class _RecordingPrefs extends UserPreferencesNotifier {
  _RecordingPrefs(this.stub);

  PreferencesTableData stub;
  final sidebarCalls = <bool>[];
  final asideCalls = <bool>[];
  final pinCalls = <String>[];

  @override
  PreferencesTableData build() => stub;

  @override
  void setSidebarCollapsed(bool collapsed) {
    sidebarCalls.add(collapsed);
    stub = stub.copyWith(sidebarCollapsed: collapsed);
    state = stub;
  }

  @override
  void setAsideOpen(bool open) {
    asideCalls.add(open);
    stub = stub.copyWith(asideOpen: open);
    state = stub;
  }

  @override
  void togglePinnedPlaylist(String id) {
    pinCalls.add(id);
    final ids = List<String>.of(stub.pinnedPlaylistIds);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.insert(0, id);
    }
    stub = stub.copyWith(pinnedPlaylistIds: ids);
    state = stub;
  }
}

ProviderContainer _container({
  required ThemeUiDocument ui,
  _RecordingPrefs? prefs,
}) {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => _theme()),
      themeUiProvider.overrideWith((ref) async => ui),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      userPreferencesProvider.overrideWith(
        () => prefs ?? StubPrefsNotifier(PreferencesTable.defaults()),
      ),
    ],
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    home: Scaffold(
      child: SingleChildScrollView(
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

void main() {
  group('region slots', () {
    testWidgets('sidebar.content replaces the host body and falls back',
        (tester) async {
      const filled = ThemeUiDocument(slots: {
        'sidebar.content': ThemeUiSlot(children: [
          {'type': 'text', 'text': 'THEME SIDEBAR'},
        ]),
      });
      final container = _container(ui: filled);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(const ThemeSlot(
            'sidebar.content',
            fallback: Text('HOST SIDEBAR'),
            bindings: ThemeUiBindings({}),
          )),
        ),
      );
      await tester.pump();

      expect(find.text('THEME SIDEBAR'), findsOneWidget);
      expect(find.text('HOST SIDEBAR'), findsNothing);

      final empty = _container(ui: const ThemeUiDocument());
      addTearDown(empty.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: empty,
          child: _app(const ThemeSlot(
            'sidebar.content',
            fallback: Text('HOST SIDEBAR'),
            bindings: ThemeUiBindings({}),
          )),
        ),
      );
      await tester.pump();

      expect(find.text('THEME SIDEBAR'), findsNothing);
      expect(find.text('HOST SIDEBAR'), findsOneWidget);
    });

    testWidgets('sidebar.library replaces the host group', (tester) async {
      const ui = ThemeUiDocument(slots: {
        'sidebar.library': ThemeUiSlot(children: [
          {'type': 'text', 'text': 'THEME LIBRARY'},
        ]),
      });
      final container = _container(ui: ui);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(const ThemeSlot(
            'sidebar.library',
            fallback: Text('HOST LIBRARY'),
            bindings: ThemeUiBindings({}),
          )),
        ),
      );
      await tester.pump();

      expect(find.text('THEME LIBRARY'), findsOneWidget);
      expect(find.text('HOST LIBRARY'), findsNothing);
    });

    testWidgets('the aside draws its slot and the host close persists',
        (tester) async {
      const ui = ThemeUiDocument(slots: {
        'aside.content': ThemeUiSlot(children: [
          {'type': 'text', 'text': 'NOW PLAYING'},
        ]),
      });
      final prefs = _RecordingPrefs(PreferencesTable.defaults());
      final container = _container(ui: ui, prefs: prefs);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
              const SizedBox(width: 320, height: 600, child: AsideRegion())),
        ),
      );
      await tester.pump();

      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.byIcon(SpotubeIcons.close), findsOneWidget);

      await tester.tap(find.byIcon(SpotubeIcons.close));
      await tester.pump();

      expect(prefs.asideCalls, [false]);
    });
  });

  group('aside visibility', () {
    test('needs a theme, an open preference and room past compact', () {
      expect(
        themeAsideVisible(themeAsks: true, userOpen: true, windowWidth: 1400),
        isTrue,
      );
      expect(
        themeAsideVisible(themeAsks: false, userOpen: true, windowWidth: 1400),
        isFalse,
      );
      expect(
        themeAsideVisible(themeAsks: true, userOpen: false, windowWidth: 1400),
        isFalse,
      );
      expect(
        themeAsideVisible(themeAsks: true, userOpen: true, windowWidth: 820),
        isFalse,
      );
      expect(
        themeAsideVisible(themeAsks: true, userOpen: true, windowWidth: 821),
        isTrue,
      );
    });
  });

  group('toggle actions', () {
    Future<
        ({
          ProviderContainer container,
          _RecordingPrefs prefs,
          BuildContext context,
          WidgetRef ref,
        })> pump(
      WidgetTester tester, {
      ThemeLayout layout = const ThemeLayout(),
    }) async {
      final prefs = _RecordingPrefs(PreferencesTable.defaults());
      final container = ProviderContainer(
        overrides: [userPreferencesProvider.overrideWith(() => prefs)],
      );
      addTearDown(container.dispose);

      late BuildContext capturedContext;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppLayout(
            layout: layout,
            child: Consumer(
              builder: (context, ref, _) {
                capturedContext = context;
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      return (
        container: container,
        prefs: prefs,
        context: capturedContext,
        ref: capturedRef,
      );
    }

    testWidgets('toggleSidebar flips the stored collapse', (tester) async {
      final setup = await pump(tester);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleSidebar'),
      );
      expect(setup.prefs.sidebarCalls, [true]);
      expect(setup.prefs.stub.sidebarCollapsed, isTrue);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleSidebar'),
      );
      expect(setup.prefs.sidebarCalls, [true, false]);
    });

    testWidgets('toggleAside flips the stored open state', (tester) async {
      final setup = await pump(tester);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleAside'),
      );
      expect(setup.prefs.asideCalls, [false]);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleAside'),
      );
      expect(setup.prefs.asideCalls, [false, true]);
    });

    testWidgets('toggleRegion routes by id and ignores anything else',
        (tester) async {
      final setup = await pump(tester);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleRegion', {'id': 'sidebar'}),
      );
      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleRegion', {'id': 'aside'}),
      );
      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleRegion', {'id': 'player'}),
      );
      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        const ThemeUiAction('toggleRegion'),
      );

      expect(setup.prefs.sidebarCalls, [true]);
      expect(setup.prefs.asideCalls, [false]);
    });

    testWidgets('pinItem defaults to the sidebar and unpinItem removes it',
        (tester) async {
      final setup = await pump(tester);
      final playlist = _playlist('p1');

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('pinItem', {'item': playlist}),
      );
      expect(setup.prefs.pinCalls, ['p1']);
      expect(setup.prefs.stub.pinnedPlaylistIds, contains('p1'));

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('unpinItem', {'item': playlist}),
      );
      expect(setup.prefs.pinCalls, ['p1', 'p1']);
      expect(setup.prefs.stub.pinnedPlaylistIds, isNot(contains('p1')));
    });

    testWidgets('pinItem stores a declared custom target separately',
        (tester) async {
      final setup = await pump(
        tester,
        layout: const ThemeLayout(
          pinTargets: [
            ThemePinTarget(id: 'bar.bottom', label: 'Bottom bar'),
          ],
        ),
      );
      final playlist = _playlist('p2');

      // The sidebar is not declared, so an omitted target is rejected rather
      // than silently pinning somewhere the theme no longer draws.
      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('pinItem', {'item': playlist}),
      );
      expect(setup.prefs.pinCalls, isEmpty);
      expect(setup.container.read(themePinsProvider), isEmpty);

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('pinItem', {
          'item': playlist,
          'target': 'bar.bottom',
        }),
      );
      expect(
        setup.container.read(themePinsProvider)['bar.bottom'],
        ['p2'],
      );

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('unpinItem', {
          'item': playlist,
          'target': 'bar.bottom',
        }),
      );
      expect(
        setup.container.read(themePinsProvider).containsKey('bar.bottom'),
        isFalse,
      );
    });

    testWidgets('pinItem ignores a target the theme did not declare',
        (tester) async {
      final setup = await pump(tester);
      final playlist = _playlist('p3');

      await dispatchThemeUiAction(
        setup.context,
        setup.container,
        ThemeUiAction('pinItem', {
          'item': playlist,
          'target': 'bar.unknown',
        }),
      );

      expect(setup.prefs.pinCalls, isEmpty);
      expect(setup.container.read(themePinsProvider), isEmpty);
    });

    test('the parser accepts the new verbs', () {
      for (final verb in [
        'toggleSidebar',
        'toggleAside',
        'toggleRegion',
        'pinItem',
        'unpinItem',
      ]) {
        expect(ThemeUiAction.tryParse({'type': verb}), isNotNull, reason: verb);
      }
    });
  });

  group('shell bindings', () {
    test('the registry names the layout preference source', () {
      final collapsed = ThemeUiBindingRegistry.lookup('app.sidebarCollapsed');
      final aside = ThemeUiBindingRegistry.lookup('app.asideOpen');

      expect(collapsed?.kind, ThemeUiBindingKind.boolean);
      expect(collapsed?.source, 'layoutPrefs');
      expect(aside?.kind, ThemeUiBindingKind.boolean);
      expect(aside?.source, 'layoutPrefs');
    });

    testWidgets('published only for the names the theme demanded',
        (tester) async {
      final prefs = _RecordingPrefs(
        PreferencesTable.defaults().copyWith(
          sidebarCollapsed: true,
          asideOpen: false,
        ),
      );
      final container = ProviderContainer(
        overrides: [userPreferencesProvider.overrideWith(() => prefs)],
      );
      addTearDown(container.dispose);

      ThemeUiBindings? demanded;
      ThemeUiBindings? undemanded;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              demanded = buildThemeUiBindings(
                ref,
                brightness: Brightness.dark,
                themeMode: 'system',
                demand: ThemeUiBindingDemand(
                  const ['app.sidebarCollapsed', 'app.asideOpen'],
                ),
              );
              undemanded = buildThemeUiBindings(
                ref,
                brightness: Brightness.dark,
                themeMode: 'system',
                demand: ThemeUiBindingDemand(const ['app.greeting']),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(demanded!.raw('app.sidebarCollapsed'), isTrue);
      expect(demanded!.raw('app.asideOpen'), isFalse);
      expect(undemanded!.values.containsKey('app.sidebarCollapsed'), isFalse);
      expect(undemanded!.values.containsKey('app.asideOpen'), isFalse);
    });
  });
}
