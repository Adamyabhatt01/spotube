// Chips: re-emitting the same list must not bounce the user off their tab;
// losing the selected chip resets to first; unknown plugin chips fall back
// to All and never read as selected.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_results.dart';
import 'package:spotube/pages/search/tabs/albums.dart';
import 'package:spotube/pages/search/tabs/all.dart';
import 'package:spotube/pages/search/tabs/artists.dart';
import 'package:spotube/pages/search/tabs/playlists.dart';
import 'package:spotube/pages/search/tabs/tracks.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/search/albums.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/provider/metadata_plugin/search/artists.dart';
import 'package:spotube/provider/metadata_plugin/search/playlists.dart';
import 'package:spotube/provider/metadata_plugin/search/tracks.dart';

/// Hermetic player: the All tab's sections/cards watch `audioPlayerProvider`,
/// whose real build touches media_kit.
class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        currentIndex: 0,
        tracks: const [],
      );
}

final _chipsStateProvider =
    StateProvider<List<String>>((ref) => ['all', 'tracks']);

SpotubePaginationResponseObject<T> _emptyPage<T>() {
  return SpotubePaginationResponseObject<T>(
    limit: 0,
    nextOffset: null,
    total: 0,
    hasMore: false,
    items: [],
  );
}

class _EmptySearchTracks extends MetadataPluginSearchTracksNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build(String arg) async => _emptyPage();
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
          int offset, int limit) =>
      build(arg);
}

class _EmptySearchAlbums extends MetadataPluginSearchAlbumsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build(String arg) async => _emptyPage();
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
          int offset, int limit) =>
      build(arg);
}

class _EmptySearchArtists extends MetadataPluginSearchArtistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      build(String arg) async => _emptyPage();
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
          int offset, int limit) =>
      build(arg);
}

class _EmptySearchPlaylists extends MetadataPluginSearchPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build(String arg) async => _emptyPage();
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
          int offset, int limit) =>
      build(arg);
}

Future<ProviderContainer> _pumpResults(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      audioPlayerProvider.overrideWith(() => _FakeAudioPlayerNotifier()),
      themeDefinitionProvider.overrideWith((ref) async => null),
      themeUiProvider.overrideWith((ref) async => null),
      metadataPluginSearchChipsProvider.overrideWith(
        (ref) async => ref.watch(_chipsStateProvider),
      ),
      metadataPluginSearchAllProvider.overrideWith((ref, query) async {
        return SpotubeSearchResponseObject(
          albums: const [],
          artists: const [],
          playlists: const [],
          tracks: const [],
        );
      }),
      metadataPluginSearchTracksProvider
          .overrideWith(() => _EmptySearchTracks()),
      metadataPluginSearchAlbumsProvider
          .overrideWith(() => _EmptySearchAlbums()),
      metadataPluginSearchArtistsProvider
          .overrideWith(() => _EmptySearchArtists()),
      metadataPluginSearchPlaylistsProvider
          .overrideWith(() => _EmptySearchPlaylists()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: Scaffold(child: HomeSearchResults()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  return container;
}

void main() {
  // Empty search sections render skeleton AlbumCards, which read the global
  // player service in build (pre-existing wart, not something this test
  // owns). The host provides libmpv, so a real init works here.
  setUpAll(() => MediaKit.ensureInitialized());

  testWidgets('re-emitting identical chips keeps the selected tab',
      (tester) async {
    final container = await _pumpResults(tester);
    container.read(_chipsStateProvider.notifier).state = [
      'all',
      'tracks',
      'albums',
      'artists',
      'playlists',
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Artists'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SearchPageArtistsTab), findsOneWidget);

    // Same contents, new list instance: the provider re-emits, selection
    // must survive.
    container.read(_chipsStateProvider.notifier).state = [
      'all',
      'tracks',
      'albums',
      'artists',
      'playlists',
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchPageArtistsTab), findsOneWidget);
  });

  testWidgets('losing the selected chip resets to the first tab',
      (tester) async {
    final container = await _pumpResults(tester);
    container.read(_chipsStateProvider.notifier).state = [
      'all',
      'tracks',
      'albums',
      'artists',
      'playlists',
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Artists'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SearchPageArtistsTab), findsOneWidget);

    container.read(_chipsStateProvider.notifier).state = [
      'all',
      'tracks',
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchPageAllTab), findsOneWidget);
  });

  testWidgets('unknown plugin chip falls back to All, never selected',
      (tester) async {
    final container = await _pumpResults(tester);
    container.read(_chipsStateProvider.notifier).state = [
      'all',
      'tracks',
      'grooves',
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Grooves'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchPageAllTab), findsOneWidget);
    expect(find.byType(SearchPageTracksTab), findsNothing);
    expect(find.byType(SearchPageAlbumsTab), findsNothing);
    expect(find.byType(SearchPageArtistsTab), findsNothing);
    expect(find.byType(SearchPagePlaylistsTab), findsNothing);
  });
}
