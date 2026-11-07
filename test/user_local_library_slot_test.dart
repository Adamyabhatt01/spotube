// The local-library page hands its body to `library.local.content` and
// publishes the folders the page resolves (download dir, cache dir, and the
// user's own locations). A theme can draw the grid from those bindings; when
// it fills nothing the host grid — and the add/delete controls that live with
// it — must come back unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
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

ProviderContainer _container({required ThemeUiDocument ui}) {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => _theme()),
      themeUiProvider.overrideWith((ref) async => ui),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      userPreferencesProvider.overrideWith(
        () => StubPrefsNotifier(PreferencesTable.defaults()),
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

const _themeUi = ThemeUiDocument(slots: {
  'library.local.content': ThemeUiSlot(children: [
    {
      'type': 'list',
      'bind': 'library.folders',
      'children': [
        {'type': 'text', 'bind': 'item.name'},
      ],
    },
  ]),
});

void main() {
  test('folders are published with the contract shape', () {
    final folders = themeLibraryFolders([
      '/home/me/Music',
      '/home/me/Downloads/Spotube',
      '/media/library',
    ]);

    expect(folders, hasLength(3));
    expect(folders.first, {
      'path': '/home/me/Music',
      'name': 'Music',
      'type': 'folder',
    });
    expect(folders.map((folder) => folder['name']), [
      'Music',
      'Spotube',
      'library',
    ]);
  });

  testWidgets('the slot replaces the host grid with the folder list',
      (tester) async {
    final container = _container(ui: _themeUi);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(ThemePageContent(
          slot: 'library.local.content',
          scroll: false,
          liveBindings: const ThemeUiBindings({}),
          bindings: {
            'library.folders':
                themeLibraryFolders(['/home/me/Music', '/media/library']),
            'library.counts': const {'folders': 2},
          },
          fallback: const Text('HOST GRID'),
        )),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('library'), findsOneWidget);
    expect(find.text('HOST GRID'), findsNothing);
  });

  testWidgets('an unfilled slot keeps the host grid', (tester) async {
    final container = _container(ui: const ThemeUiDocument());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const ThemePageContent(
          slot: 'library.local.content',
          scroll: false,
          bindings: {
            'library.folders': <Map<String, Object?>>[],
            'library.counts': {'folders': 0},
          },
          fallback: Text('HOST GRID'),
        )),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOST GRID'), findsOneWidget);
    expect(find.text('Music'), findsNothing);
  });
}
