import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_registry.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/services/theme_ui/artwork_palette.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

class _FakeSavedPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> build() {
    final items = [_playlist('a'), _playlist('b')];
    return Future.value(
      SpotubePaginationResponseObject(
        limit: items.length,
        nextOffset: null,
        total: items.length,
        hasMore: false,
        items: items,
      ),
    );
  }
}

class _StubPlayer extends AudioPlayerNotifier {
  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
      );
}

class _AddedProviders extends ProviderObserver {
  final Set<ProviderBase<Object?>> added = {};

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    added.add(provider);
  }
}

SpotubeSimplePlaylistObject _playlist(String id) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: 'Playlist $id',
    description: 'A saved playlist',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner',
    ),
    images: [
      SpotubeImageObject(
        url: 'https://example.test/p/$id.jpg',
        height: 300,
        width: 300,
      ),
    ],
  );
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    durationMs: 213000,
    isrc: 'ISRC$id',
    explicit: false,
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist',
        name: 'Artist',
        externalUri: 'https://example.test/artist/a',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album',
      name: 'Album',
      externalUri: 'https://example.test/album/b',
      artists: [],
      albumType: SpotubeAlbumType.album,
    ),
  );
}

ThemeUiDocument _document(Map<String, dynamic> ui) {
  return ThemeUiDocument.fromJson(ui);
}

ArtworkPalette _palette(int seed) {
  final color = Color(0xFF000000 | seed);
  return ArtworkPalette(
    dominant: color,
    vibrant: color,
    muted: color,
    darkMuted: color,
    lightMuted: color,
    onDominant: const Color(0xFFFFFFFF),
  );
}

void main() {
  group('demand detection', () {
    test('walks slots, screens, templates and nested props', () {
      final demand = ThemeUiBindingDemand.scan(_document({
        'specVersion': 4,
        'slots': {
          'sidebar': {
            'children': [
              {'type': 'text', 'bind': 'library.playlists'},
              {
                'type': 'column',
                'children': [
                  {
                    'type': 'button',
                    'disabledWhen': 'player.playing',
                    'openBind': 'app.sidebarOpen',
                  },
                ],
              },
            ],
          },
          'player': {
            'children': [
              {'type': 'box', 'color': '@palette.dominant'},
            ],
          },
        },
        'screens': {
          'now': {
            'children': [
              {'type': 'list', 'bind': 'queue.tracks'},
            ],
          },
        },
        'templates': {
          'row': {
            'children': [
              {
                'type': 'table',
                'bind': 'search.results',
                'columns': [
                  {'key': 'title', 'bind': 'item.title'},
                ],
              },
            ],
          },
        },
      }));

      expect(
        demand.names,
        containsAll([
          'library.playlists',
          'player.playing',
          'app.sidebarOpen',
          'palette.dominant',
          'queue.tracks',
          'search.results',
          'item.title',
          // Implicit: a row's active state compares against the player.
          'player.trackId',
        ]),
      );
      expect(demand.wants('library.albums'), isFalse);
      expect(demand.wantsNamespace('library'), isTrue);
      expect(demand.wantsNamespace('player'), isTrue);
      expect(demand.sources, containsAll(['savedPlaylists', 'audioPlayer']));
    });

    test('ignores document text and URLs that only look binding-shaped', () {
      final demand = ThemeUiBindingDemand.scan(_document({
        'slots': {
          'main': {
            'children': [
              {'type': 'text', 'text': 'Hello world'},
              {'type': 'text', 'text': 'https://example.test/a.b'},
            ],
          },
        },
      }));
      expect(demand.names, isEmpty);
    });

    test('a missing document costs nothing', () {
      expect(ThemeUiBindingDemand.scan(null).names, isEmpty);
    });
  });

  group('provider subscriptions', () {
    testWidgets('a document that never draws the library does not watch it',
        (tester) async {
      final observer = _AddedProviders();

      await tester.pumpWidget(
        ProviderScope(
          observers: [observer],
          child: Consumer(
            builder: (context, ref, child) {
              buildThemeUiBindings(
                ref,
                brightness: Brightness.light,
                themeMode: 'system',
                demand: ThemeUiBindingDemand(const ['app.greeting']),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(observer.added,
          isNot(contains(metadataPluginSavedPlaylistsProvider)));
      expect(observer.added, isNot(contains(audioPlayerProvider)));
      expect(observer.added, isNot(contains(themeAppVersionProvider)));
    });

    testWidgets('requesting library.playlists watches the saved list',
        (tester) async {
      final observer = _AddedProviders();
      Object? snapshots;

      await tester.pumpWidget(
        ProviderScope(
          observers: [observer],
          overrides: [
            metadataPluginSavedPlaylistsProvider.overrideWith(
              _FakeSavedPlaylists.new,
            ),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              final bindings = buildThemeUiBindings(
                ref,
                brightness: Brightness.light,
                themeMode: 'system',
                demand: ThemeUiBindingDemand(const ['library.playlists']),
              );
              snapshots = bindings.raw('library.playlists');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(observer.added, contains(metadataPluginSavedPlaylistsProvider));
      expect(snapshots, isA<List<Object?>>());
    });
  });

  group('binding values', () {
    test('playlists carry identity, pinned state and the contract shape', () {
      final playlists = [_playlist('a'), _playlist('b')];
      final maps = themeLibraryPlaylists(
        playlists,
        {'a'},
      );

      expect(maps.first['id'], 'a');
      expect(maps.first['name'], 'Playlist a');
      expect(maps.first['pinned'], isTrue);
      expect(maps.first['artwork'], contains('example.test'));
      expect(maps.first['palette'], isA<Map>());
      expect(maps.first['object'], same(playlists.first));
      expect(maps.last['pinned'], isFalse);
      expect(maps.last['object'], same(playlists.last));
    });

    test('a count the host does not have is null, not an invented zero', () {
      final album = SpotubeSimpleAlbumObject(
        id: 'album',
        name: 'Album',
        externalUri: 'https://example.test/album/a',
        artists: const [],
        albumType: SpotubeAlbumType.album,
      );

      for (final row in [
        themeLibraryPlaylists([_playlist('a')], const {'a'}).single,
        themeLibraryAlbums([album]).single,
        themeLibraryPins([_playlist('a')], const {'a'}).single,
      ]) {
        expect(row.containsKey('trackCount'), isTrue,
            reason: 'the key stays part of the published shape');
        expect(row['trackCount'], isNull);
      }

      expect(
        const ThemeUiBindings({'library.count': null}).display('library.count'),
        '',
        reason: 'an unknown count renders as nothing, never as "0"',
      );
    });

    test('queue rows expose a duration and artwork', () {
      final rows = themeQueueTracks([_track('one')]);
      expect(rows.single['id'], 'one');
      expect(rows.single['duration'], const Duration(milliseconds: 213000));
      expect(rows.single['artist'], 'Artist');
      expect(rows.single['type'], 'track');
    });

    test('folders are named from their path', () {
      expect(
        themeLibraryFolders(['/home/me/Music']).single,
        containsPair('name', 'Music'),
      );
    });

    test('pins merge playlist and station pins in declared order', () {
      final station = RadioStation(
        id: 's1',
        provider: 'radio-browser',
        name: 'Station One',
        streamUrl: 'https://example.test/stream',
      );
      final pins = themeLibraryPins(
        [_playlist('a')],
        {'a'},
        stationPins: const ['radio-browser:s1'],
        favorites: [station],
      );

      expect(pins.map((pin) => pin['type']), ['playlist', 'station']);
      expect(pins.last['name'], 'Station One');
    });

    test('pin targets default to the sidebar and keep declared labels', () {
      expect(themePinTargets(null), [
        {'id': 'sidebar', 'label': 'Sidebar'},
      ]);
      expect(
        themePinTargets(
          const ThemeLayout(
            pinTargets: [
              ThemePinTarget(id: 'bar.bottom', label: 'Bottom bar'),
            ],
          ),
        ),
        [
          {'id': 'bar.bottom', 'label': 'Bottom bar'},
        ],
      );
    });

    test('target pins carry their target and leave the sidebar default', () {
      final pins = themeLibraryPins(
        [_playlist('a'), _playlist('b')],
        {'a'},
        targetPins: const {
          'bar.bottom': ['b'],
        },
      );

      expect(
        pins.map((pin) => (pin['id'], pin['target'])),
        [('a', 'sidebar'), ('b', 'bar.bottom')],
      );
    });
  });

  group('palette precedence', () {
    test('page artwork overrides the player palette, explicit maps win', () {
      const base = ThemeUiBindings({
        'player.artwork': 'https://example.test/player.jpg',
        'palette.dominant': '#111111',
        'palette.vibrant': '#222222',
        'collection.artwork': 'https://example.test/collection.jpg',
        'collection.palette': {'dominant': '#000000'},
      });

      final merged = withArtworkPalette(
        base,
        paletteFor: (url) =>
            url.endsWith('collection.jpg') ? _palette(0xABCDEF) : null,
      );

      expect(merged.raw('palette.dominant'), '#000000',
          reason: 'an explicit scope palette is nearest');
      expect(merged.raw('palette.vibrant'), '#abcdef',
          reason: 'the scope artwork fills keys the map does not override');
    });

    test('a cache miss leaves the player palette as the fallback', () {
      const base = ThemeUiBindings({
        'player.artwork': 'https://example.test/player.jpg',
        'palette.dominant': '#111111',
      });
      String? requested;
      final merged = withArtworkPalette(
        base,
        paletteFor: (url) => null,
        request: (url) => requested = url,
      );

      expect(merged.raw('palette.dominant'), '#111111');
      expect(requested, 'https://example.test/player.jpg');
    });
  });

  test('the registry names the source of a known binding', () {
    final palette = ThemeUiBindingRegistry.lookup('palette.darkMuted');
    expect(palette?.kind, ThemeUiBindingKind.color);
    expect(palette?.source, 'palette');

    final setting = ThemeUiBindingRegistry.lookup('setting.accent');
    expect(setting?.source, 'settings');

    expect(
      ThemeUiBindingRegistry.globalNames,
      containsAll(['library.playlists', 'queue.tracks', 'theme.id']),
    );
  });

  testWidgets('a sidebar slot draws the saved playlists', (tester) async {
    final document = _document({
      'specVersion': 4,
      'slots': {
        'sidebar.library.before': {
          'children': [
            {
              'type': 'list',
              'bind': 'library.playlists',
              'limit': 8,
              'children': [
                {'type': 'text', 'bind': 'item.name'},
              ],
            },
          ],
        },
      },
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeDefinitionProvider.overrideWith(
            (ref) async => ThemeDefinition(
              specVersion: 3,
              light: builtInLightThemeColors(),
              dark: builtInDarkThemeColors(),
            ),
          ),
          themeUiProvider.overrideWith((ref) async => document),
          cachedThemeDefinitionProvider.overrideWith((ref) async => null),
          themeUiAssetsProvider.overrideWith(
            (ref) async => const ThemeUiAssets(),
          ),
          themeUiFontsProvider.overrideWith((ref) async {}),
          metadataPluginSavedPlaylistsProvider.overrideWith(
            _FakeSavedPlaylists.new,
          ),
          audioPlayerProvider.overrideWith(_StubPlayer.new),
        ],
        child: const ShadcnApp(
          home: Scaffold(child: ThemeSlot('sidebar.library.before')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Playlist a'), findsOneWidget);
    expect(find.text('Playlist b'), findsOneWidget);
  });

  group('route bindings', () {
    test('currentRoute is the first path segment', () {
      expect(themeCurrentRoute('/home'), 'home');
      expect(themeCurrentRoute('/library/artists'), 'library');
      expect(themeCurrentRoute('/search'), 'search');
      expect(themeCurrentRoute(null), '');
      expect(themeCurrentRoute(''), '');
      expect(themeCurrentRoute('/'), '');
    });

    test('library section names the tab, and only inside the library', () {
      expect(themeLibrarySection('/library/playlists'), 'playlists');
      expect(themeLibrarySection('/library/artists'), 'artists');
      expect(themeLibrarySection('/library/albums'), 'albums');
      expect(themeLibrarySection('/library/stations'), 'stations');
      expect(themeLibrarySection('/library'), '');
      expect(themeLibrarySection('/home'), '');
      expect(themeLibrarySection('/radio'), '');
      expect(themeLibrarySection(null), '');
    });
  });

  group('radio stations', () {
    final station = RadioStation(
      id: 'a',
      provider: 'dir',
      name: 'Wave',
      streamUrl: 'https://example.com/stream',
      tags: ['jazz'],
      country: 'NL',
    );

    test('rows carry identity, favorite and live state', () {
      final rows = themeRadioStations(
        [station],
        favoriteKeys: {'dir:a'},
        activeFavoriteKey: 'dir:a',
      );
      expect(rows, hasLength(1));
      expect(rows.first['id'], 'a');
      expect(rows.first['favoriteKey'], 'dir:a');
      expect(rows.first['isFavorite'], isTrue);
      expect(rows.first['isPlaying'], isTrue);
      expect(rows.first['subtitle'], contains('jazz'));
      expect(rows.first['country'], 'NL');
    });

    test('a non-live station reads as not playing', () {
      final rows = themeRadioStations(
        [station],
        favoriteKeys: const {},
        activeFavoriteKey: 'dir:other',
      );
      expect(rows.first['isFavorite'], isFalse);
      expect(rows.first['isPlaying'], isFalse);
    });
  });
}
