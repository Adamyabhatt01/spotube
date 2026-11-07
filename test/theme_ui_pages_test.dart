// Phase 6: theme pages.
//
// A theme declares `ui.pages` entries and a `page.<id>` slot; the host routes
// them through one generated `ThemeRoute`, injects them into the nav section
// named by `parent`, and drops any page whose parent is not a host section.
// These tests pin the contract on both sides: pure resolution plus a mounted
// page proving the slot actually renders inside the shell.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/pages/theme_page/theme_page.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

import 'support/common_fakes.dart';

class _EmptyRecents extends RecentSearchesNotifier {
  @override
  List<String> build() => const [];
}

const _audio = ThemeUiPage(
  id: 'audio',
  title: 'Audio',
  icon: 'equalizer',
  parent: 'library.local',
  showBack: true,
);
const _mixer = ThemeUiPage(
  id: 'mixer',
  parent: 'settings',
);
const _ghost = ThemeUiPage(
  id: 'ghost',
  parent: 'nowhere',
);
const _hidden = ThemeUiPage(
  id: 'hidden',
  parent: 'library.local',
  visible: false,
);

const _doc = ThemeUiDocument(
  pages: [_audio, _mixer, _ghost, _hidden],
  slots: {
    'page.audio': ThemeUiSlot(children: [
      {'type': 'text', 'text': 'AUDIO BODY'},
    ]),
  },
);

ProviderContainer _container({
  ThemeUiDocument? ui,
  bool viaDefinition = true,
}) {
  final definition = ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
    ui: viaDefinition ? (ui ?? _doc) : null,
  );
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => definition),
      if (!viaDefinition)
        themeUiProvider.overrideWith((ref) async => ui ?? _doc),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      recentSearchesProvider.overrideWith(_EmptyRecents.new),
      userPreferencesProvider.overrideWith(
        () => StubPrefsNotifier(PreferencesTable.defaults()),
      ),
    ],
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: AppLayout(
      tokens: const ThemeTokens(),
      radii: const ThemeRadius(),
      layout: const ThemeLayout(),
      child: child,
    ),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  String pageId,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _app(ThemePage(pageId: pageId)),
    ),
  );
  await tester.pump();
}

void main() {
  group('parsing', () {
    test('pages parse from the ui document json', () {
      final ui = ThemeUiDocument.fromJson(const {
        'specVersion': 4,
        'pages': [
          {
            'id': 'audio',
            'title': 'Audio',
            'icon': 'equalizer',
            'parent': 'library.local',
            'showBack': true,
          },
          {'id': 'hidden', 'parent': 'library.local', 'visible': false},
        ],
        'slots': {
          'page.audio': {
            'children': [
              {'type': 'text', 'text': 'x'},
            ],
          },
        },
      });
      expect(ui.pages, hasLength(2));
      expect(ui.pages.first.id, 'audio');
      expect(ui.pages.first.title, 'Audio');
      expect(ui.pages.first.icon, 'equalizer');
      expect(ui.pages.first.parent, 'library.local');
      expect(ui.pages.first.showBack, isTrue);
      expect(ui.pages.first.visible, isTrue);
      expect(ui.pages.last.visible, isFalse);
    });
  });

  group('routableThemePage', () {
    test('accepts a visible page under a host section', () {
      expect(routableThemePage(_doc, 'audio'), _audio);
      expect(routableThemePage(_doc, 'mixer'), _mixer);
    });
    test('rejects an unknown parent, invisible pages and unknown ids', () {
      expect(routableThemePage(_doc, 'ghost'), isNull);
      expect(routableThemePage(_doc, 'hidden'), isNull);
      expect(routableThemePage(_doc, 'zzz'), isNull);
      expect(routableThemePage(null, 'audio'), isNull);
    });
  });

  group('themePageTiles', () {
    test('builds routed tiles for one parent, in declaration order', () {
      final tiles = themePageTiles(_doc, parent: 'library.local');
      expect(tiles.map((t) => t.id), ['page:audio']);
      final tile = tiles.single;
      expect(tile.title, 'Audio');
      expect(tile.route, isA<ThemeRoute>());
      expect(tile.pathPrefix, '/theme-page/audio');
      expect(tile.icon, SpotubeIcons.equalizer);
      expect(tile.screenId, isNull);
    });
    test('untitled pages fall back to the id; unknown icons go to magic', () {
      final tiles = themePageTiles(_doc, parent: 'settings');
      expect(tiles.single.title, 'mixer');
      expect(tiles.single.icon, SpotubeIcons.magic);
    });
    test('an unknown parent section gets nothing', () {
      expect(themePageTiles(_doc, parent: 'nowhere'), isEmpty);
    });
    test('no document, no tiles', () {
      expect(themePageTiles(null, parent: 'library'), isEmpty);
    });
  });

  group('navigation resolution', () {
    test('page: references resolve against bare page ids', () {
      final ids = resolveThemeItems(
        hostIds: const ['home', 'search'],
        themeIds: const ['home', 'page:audio', 'page:zzz'],
        screens: const {'audio'},
      );
      expect(ids, ['home', 'page:audio']);
    });

    test('themeEntriesFor places a page tile pulled from the merged map', () {
      final host = [
        SideBarTiles(
          icon: SpotubeIcons.home,
          title: 'Home',
          id: 'home',
          pathPrefix: '/',
        ),
      ];
      final screens = {
        'page:audio': themePageTiles(_doc, parent: 'library.local').single,
      };
      final result = themeEntriesFor(
        host: host,
        themeIds: const ['home', 'page:audio'],
        screens: screens,
      );
      expect(result.map((t) => t.id), ['home', 'page:audio']);
    });
  });

  group('ThemePage widget', () {
    testWidgets('renders the theme slot with the page title', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpPage(tester, container, 'audio');

      expect(find.text('AUDIO BODY'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.byIcon(SpotubeIcons.angleLeft), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a titleless page shows its id and no back button',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpPage(tester, container, 'mixer');
      await tester.pumpAndSettle();

      expect(find.text('mixer'), findsOneWidget);
      expect(find.byIcon(SpotubeIcons.angleLeft), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unroutable page renders nothing and does not throw',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpPage(tester, container, 'ghost');
      await tester.pumpAndSettle();

      expect(find.text('AUDIO BODY'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a theme switch takes its pages down with it',
        (tester) async {
      // Resolved through the real provider path (definition.ui + override)
      // so the override swap re-emits themeUiProvider like in the app.
      final container = _container(viaDefinition: true);
      addTearDown(container.dispose);

      await _pumpPage(tester, container, 'audio');
      expect(find.text('AUDIO BODY'), findsOneWidget);

      container.read(themeUiOverrideProvider.notifier).state =
          const ThemeUiDocument();
      await tester.pump();
      await tester.pump();

      expect(find.text('AUDIO BODY'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
