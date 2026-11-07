import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

/// The Spotify home slot mounts the real search bar, which reads recents from
/// the KV store. That store is hydrated during app startup, not in this test.
class _EmptyRecents extends RecentSearchesNotifier {
  @override
  List<String> build() => const [];
}

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

Widget _app(Widget child, {bool scroll = false}) {
  return ShadcnApp(
    home: Scaffold(
      child: scroll ? SingleChildScrollView(child: child) : child,
    ),
  );
}

ProviderContainer _container({
  required ThemeDefinition theme,
  required ThemeUiDocument ui,
}) {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => theme),
      themeUiProvider.overrideWith((ref) async => ui),
      cachedThemeDefinitionProvider.overrideWith((ref) async => null),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      recentSearchesProvider.overrideWith(_EmptyRecents.new),
    ],
  );
}

void main() {
  const bindings = ThemeUiBindings({
    'player.title': 'Nightfall',
    'player.artist': 'Ada',
    'player.artwork': 'assets/images/album-placeholder.png',
    'player.playing': false,
    'player.loop': 'loop',
    'player.volume': 0.72,
    'app.version': '4.6.0',
  });

  testWidgets('a slot falls back when the theme did not fill it',
      (tester) async {
    final container = _container(theme: _theme(), ui: const ThemeUiDocument());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemeSlot(
            'sidebar.header',
            fallback: Text('HOST HEADER'),
            bindings: bindings,
          ),
          scroll: true,
        ),
      ),
    );

    expect(find.text('HOST HEADER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slot replaces the fallback with theme content',
      (tester) async {
    const ui = ThemeUiDocument(slots: {
      'sidebar.header': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'THEME HEADER'},
      ]),
    });
    final container = _container(theme: _theme(), ui: ui);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemeSlot(
            'sidebar.header',
            fallback: Text('HOST HEADER'),
            bindings: bindings,
          ),
          scroll: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('THEME HEADER'), findsOneWidget);
    expect(find.text('HOST HEADER'), findsNothing);
  });

  testWidgets('page content replaces the host body and publishes page bindings',
      (tester) async {
    const ui = ThemeUiDocument(slots: {
      'collection.content': ThemeUiSlot(children: [
        {'type': 'text', 'bind': 'collection.title'},
        {
          'type': 'list',
          'bind': 'collection.tracks',
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ]
        },
      ]),
    });
    final container = _container(theme: _theme(), ui: ui);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          ThemePageContent(
            slot: 'collection.content',
            liveBindings: bindings,
            bindings: {
              'collection.title': 'THEME COLLECTION',
              'collection.tracks': [
                SpotubeFullTrackObject(
                  id: 't1',
                  name: 'THEME TRACK',
                  externalUri: 'https://example.test/track/t1',
                  artists: const [],
                  album: SpotubeSimpleAlbumObject(
                    id: 'a1',
                    name: 'Album',
                    externalUri: 'https://example.test/album/a1',
                    artists: const [],
                    albumType: SpotubeAlbumType.album,
                  ),
                  durationMs: 1000,
                  isrc: 'TEST00000001',
                  explicit: false,
                ),
              ],
            },
            fallback: const Text('HOST BODY'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('THEME COLLECTION'), findsOneWidget);
    expect(find.text('THEME TRACK'), findsOneWidget);
    expect(find.text('HOST BODY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page content keeps the host body when the slot is absent',
      (tester) async {
    final container = _container(theme: _theme(), ui: const ThemeUiDocument());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemePageContent(
            slot: 'collection.content',
            bindings: {'collection.title': 'THEME COLLECTION'},
            fallback: Text('HOST BODY'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HOST BODY'), findsOneWidget);
    expect(find.text('THEME COLLECTION'), findsNothing);
  });

  testWidgets('the stage mounts the theme\'s center and below slots',
      (tester) async {
    const ui = ThemeUiDocument(slots: {
      'stage.center': ThemeUiSlot(children: [
        {
          'type': 'animate',
          'kind': 'rotate',
          'duration': 24000,
          'curve': 'linear',
          'bind': 'player.playing',
          'children': [
            {
              'type': 'text',
              'bind': 'player.title',
              'size': 'lg',
              'weight': 'bold',
            },
          ],
        },
      ]),
      'stage.below': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'NOW SPINNING', 'align': 'center'},
        {'type': 'text', 'bind': 'player.artist', 'size': 'md'},
      ]),
    });
    final container = _container(theme: _theme(), ui: ui);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const ThemeUiStage(bindings: bindings), scroll: true),
      ),
    );
    await tester.pump();

    expect(find.text('Nightfall'), findsWidgets);
    expect(find.text('NOW SPINNING'), findsWidgets);
    expect(find.text('Ada'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the spotify home slot renders the real theme payload',
      (tester) async {
    final payload = jsonDecode(
      File('themes/conformance/spotify-shell-v4.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final theme = ThemeDefinition.fromJson(payload);
    final ui = theme.ui!;
    final container = _container(theme: theme, ui: ui);
    addTearDown(container.dispose);

    final recent = SpotubeSimpleAlbumObject(
      id: 'a1',
      name: 'THEME ALBUM',
      externalUri: 'https://example.test/album/a1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    );
    final live = ThemeUiBindings({
      ...bindings.values,
      'app.greeting': 'Good evening',
      'user.name': 'Ada',
      'user.avatar': '',
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          ThemePageContent(
            slot: 'home.content',
            liveBindings: live,
            bindings: {
              'home.greeting': 'Good evening',
              'home.recent': [recent],
              'home.hasRecent': true,
              'home.newReleases': const [],
              'home.hasNewReleases': false,
              'home.browse': const [],
              'home.hasBrowse': false,
            },
            fallback: const Text('HOST BODY'),
          ),
          scroll: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('What do you want to play?'), findsOneWidget);
    expect(find.text('Good evening'), findsOneWidget);
    // The reference home is Spotify's pattern: the bound recent feed draws
    // once, as the shortcut matrix — there is no "Recents" shelf anymore.
    expect(find.text('Recents'), findsNothing);
    expect(find.text('Recently played'), findsNothing);
    expect(find.text('THEME ALBUM'), findsOneWidget);
    expect(find.text('HOST BODY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a theme screen covers the shell and the host back pops it',
      (tester) async {
    const ui = ThemeUiDocument(screens: {
      'now-playing': ThemeUiScreen(
        title: 'Now playing',
        showBack: true,
        children: [
          {'type': 'text', 'text': 'SCREEN BODY'},
        ],
      ),
    });
    final container = _container(theme: _theme(), ui: ui);
    addTearDown(container.dispose);
    container.read(themeUiScreenStackProvider.notifier).state = ['now-playing'];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const ThemeUiScreenHost(
          bindings: bindings,
          child: Text('SHELL'),
        )),
      ),
    );
    await tester.pump();

    expect(find.text('SHELL'), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('SCREEN BODY'), findsOneWidget);

    await tester.tap(find.byIcon(SpotubeIcons.angleLeft));
    await tester.pump();

    expect(container.read(themeUiScreenStackProvider), isEmpty);
    expect(find.text('SCREEN BODY'), findsNothing);
    expect(find.text('SHELL'), findsOneWidget);
  });

  testWidgets('a page-level list builds only the visible rows', (tester) async {
    const ui = ThemeUiDocument(slots: {
      'collection.content': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'COLLECTION HEADER'},
        {
          'type': 'padding',
          'all': 0,
          'children': [
            {
              'type': 'list',
              'bind': 'collection.tracks',
              'limit': 300,
              'children': [
                {'type': 'text', 'bind': 'item.title'},
              ],
            },
          ],
        },
      ]),
    });
    final container = _container(theme: _theme(), ui: ui);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          ThemePageContent(
            slot: 'collection.content',
            liveBindings: const ThemeUiBindings({}),
            bindings: {
              'collection.tracks': [
                for (var i = 0; i < 300; i++)
                  {'id': 't$i', 'title': 'Track $i'},
              ],
            },
            fallback: const Text('HOST BODY'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COLLECTION HEADER'), findsOneWidget);
    expect(find.text('Track 0'), findsOneWidget);
    // The point of the lazy path: the last row is not built until the
    // viewport reaches it. 300 eager rows would make this fail.
    expect(find.text('Track 299'), findsNothing);
    expect(
      tester.widgetList(find.byType(ThemeUiNodeView)).length,
      lessThan(50),
      reason: 'only the viewport and its cache should be built',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('effective providers prefer live over cached', (tester) async {
    const cachedUi = ThemeUiDocument(slots: {
      'sidebar.header': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'CACHED HEADER'},
      ]),
    });
    const liveUi = ThemeUiDocument(slots: {
      'sidebar.header': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'LIVE HEADER'},
      ]),
    });
    final cachedTheme = ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
      ui: cachedUi,
    );
    final liveTheme = ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
      ui: liveUi,
    );
    final container = ProviderContainer(
      overrides: [
        themeDefinitionProvider.overrideWith((ref) async => liveTheme),
        themeUiProvider.overrideWith((ref) async => liveUi),
        cachedThemeDefinitionProvider.overrideWith((ref) async => cachedTheme),
        themeUiAssetsProvider
            .overrideWith((ref) async => const ThemeUiAssets()),
        themeUiFontsProvider.overrideWith((ref) async {}),
        recentSearchesProvider.overrideWith(_EmptyRecents.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemeSlot(
            'sidebar.header',
            fallback: Text('HOST HEADER'),
            bindings: bindings,
          ),
          scroll: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('LIVE HEADER'), findsOneWidget);
    expect(find.text('CACHED HEADER'), findsNothing);
    expect(container.read(effectiveThemeDefinitionProvider), liveTheme);
    expect(container.read(effectiveThemeUiProvider), liveUi);
  });

  testWidgets('slots paint the cached tree while live is still loading',
      (tester) async {
    const cachedUi = ThemeUiDocument(slots: {
      'sidebar.header': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'CACHED HEADER'},
        {'type': 'text', 'bind': 'player.title'},
      ]),
    });
    final cachedTheme = ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
      ui: cachedUi,
    );
    final liveDefCompleter = Completer<ThemeDefinition?>();
    final liveUiCompleter = Completer<ThemeUiDocument?>();
    final container = ProviderContainer(
      overrides: [
        themeDefinitionProvider.overrideWith((ref) => liveDefCompleter.future),
        themeUiProvider.overrideWith((ref) => liveUiCompleter.future),
        cachedThemeDefinitionProvider.overrideWith((ref) async => cachedTheme),
        themeUiAssetsProvider
            .overrideWith((ref) async => const ThemeUiAssets()),
        themeUiFontsProvider.overrideWith((ref) async {}),
        recentSearchesProvider.overrideWith(_EmptyRecents.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemeSlot(
            'sidebar.header',
            fallback: Text('HOST HEADER'),
            bindings: bindings,
          ),
          scroll: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CACHED HEADER'), findsOneWidget);
    expect(find.text('HOST HEADER'), findsNothing);
    expect(tester.takeException(), isNull);

    // The demand scan follows the cached document too: a cached binding
    // is subscribed before live lands.
    final demand = container.read(themeUiBindingDemandProvider);
    expect(demand.names, contains('player.title'));
    expect(demand.sources, contains('audioPlayer'));
  });

  testWidgets('cached slot does not leak into the next theme identity',
      (tester) async {
    const cachedUi = ThemeUiDocument(slots: {
      'sidebar.header': ThemeUiSlot(children: [
        {'type': 'text', 'text': 'CACHED HEADER'},
      ]),
    });
    final cachedTheme = ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
      ui: cachedUi,
    );
    final container = ProviderContainer(
      overrides: [
        // Live settled to null (no theme / removed theme) and the cache
        // miss matches the new identity — nothing should paint.
        themeDefinitionProvider.overrideWith((ref) async => null),
        themeUiProvider.overrideWith((ref) async => null),
        cachedThemeDefinitionProvider.overrideWith((ref) async => null),
        themeUiAssetsProvider
            .overrideWith((ref) async => const ThemeUiAssets()),
        themeUiFontsProvider.overrideWith((ref) async {}),
        recentSearchesProvider.overrideWith(_EmptyRecents.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const ThemeSlot(
            'sidebar.header',
            fallback: Text('HOST HEADER'),
            bindings: bindings,
          ),
          scroll: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HOST HEADER'), findsOneWidget);
    expect(find.text('CACHED HEADER'), findsNothing);
    expect(tester.takeException(), isNull);
    // Avoid an unused-variable lint for the seeded theme shape used above.
    expect(cachedTheme.ui?.slots.length, 1);
  });
}
