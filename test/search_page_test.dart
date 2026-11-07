import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/pages/search/search.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/recent.dart';
import 'package:spotube/provider/metadata_plugin/album/releases.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/radio_audio_player.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

import 'support/common_fakes.dart';

RadioStation _station(String id) => RadioStation(
      id: id,
      provider: 'fake',
      name: 'Station $id',
      streamUrl: 'https://stream/$id',
      tags: const ['jazz'],
    );

class _InMemoryDirectory implements RadioDirectoryProvider {
  @override
  final String id = 'fake';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    final items = [_station('1'), _station('2')];
    return SpotubePaginationResponseObject(
      limit: limit,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Empty history/releases: landing sections render fake shimmer cards while
/// their providers load, and those cards watch the native player.
class _EmptyHistory extends RecentlyPlayedItemNotifier {
  @override
  Future<List<HistoryTableData>> build() async => [];
}

class _EmptyReleases extends MetadataPluginAlbumReleasesNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build() async => SpotubePaginationResponseObject(
            limit: 20,
            nextOffset: null,
            total: 0,
            hasMore: false,
            items: const [],
          );
}

/// Personalized Browse sections: proves Search's landing uses recommendation
/// rails instead of the home page's Recently Played history.
class _FakeBrowseSections extends MetadataPluginBrowseSectionsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: 1,
      nextOffset: null,
      total: 1,
      hasMore: false,
      items: [
        SpotubeBrowseSectionObject<Object>(
          id: 'taste',
          title: 'New artists based on your taste',
          externalUri: 'https://example.test/taste',
          browseMore: false,
          items: [
            SpotubeFullArtistObject(
              id: 'taste-artist',
              name: 'Taste Artist',
              externalUri: 'https://example.test/artist/taste',
            ),
          ],
        ),
      ],
    );
  }
}

/// Fake radio backend: station tiles build playback actions that would
/// otherwise construct the native player. Same seam `radio_ui_test` uses.
class _NoopMusicDelegate implements MusicPlaybackDelegate {
  @override
  Future<void> pauseMusic() async {}
  @override
  Stream<bool> get musicPlayingStream => const Stream<bool>.empty();
}

class _FakeRadioBackend implements RadioPlayerBackend {
  final _playing = StreamController<bool>.broadcast();

  @override
  Future<void> open(String url, {bool play = true}) async {
    _playing.add(true);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setAudioFilterChain(String chain) async {}
  @override
  Stream<String> get titleStream => const Stream<String>.empty();
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();
  @override
  Stream<String> get errorStream => const Stream<String>.empty();
  @override
  @override
  Future<void> dispose() async => _playing.close();
}

/// Hermetic player: shimmer cards watch `audioPlayerProvider`, whose real
/// build touches media_kit.
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

/// The unified Search page: music scope (field + recents landing) and radio
/// scope (station search) behind one switcher, with no network and no plugin
/// VMs — empty metadata plugins, seeded recents, in-memory radio directory.
void main() {
  late AppDatabase db;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'recentSearches': ['lofi beats'],
    });
    await KVStoreService.initialize();
    AppLogger.initialize(false);
    PathProviderPlatform.instance = FakePathProvider('/tmp');
    db = newMemoryDatabase();
    radioProviders.add(_InMemoryDirectory());
  });

  tearDown(() async {
    radioProviders.clear();
    await db.close();
  });

  Future<ProviderContainer> buildContainer() async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioPlayerProvider.overrideWith(() => _FakeAudioPlayerNotifier()),
        recentlyPlayedItems.overrideWith(() => _EmptyHistory()),
        metadataPluginAlbumReleasesProvider
            .overrideWith(() => _EmptyReleases()),
        metadataPluginBrowseSectionsProvider
            .overrideWith(() => _FakeBrowseSections()),
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(PreferencesTable.defaults()),
        ),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        radioBackendFactoryProvider
            .overrideWithValue(() => _FakeRadioBackend()),
        musicPlaybackDelegateProvider.overrideWithValue(_NoopMusicDelegate()),
      ],
    );
    // Resolve the landing sections' providers before the first frame: while
    // loading they render fake shimmer cards, and those cards watch the
    // native player (unavailable in unit tests).
    await container.read(recentlyPlayedItems.future);
    await container.read(metadataPluginAlbumReleasesProvider.future);
    return container;
  }

  Future<ProviderContainer> pumpSearch(WidgetTester tester) async {
    final container = await buildContainer();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShadcnApp(
          localizationsDelegates: [AppLocalizations.delegate],
          home: Scaffold(child: SearchPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('music landing shows seeded recents; radio scope searches',
      (tester) async {
    // Seed radio history so a leaked Recent rail would be visible in Search.
    final historyStation = _station('history');
    await db.into(db.historyTable).insert(
          HistoryTableCompanion.insert(
            type: HistoryEntryType.radio,
            itemId: historyStation.favoriteKey,
            data: historyStation.toJson(),
          ),
        );

    final container = await pumpSearch(tester);

    // Music scope: scope chips + seeded recent chip, no results yet.
    // (The chip text also appears in the autofocused suggestion panel.)
    expect(find.byKey(const ValueKey('searchScopeMusic')), findsOneWidget);
    expect(find.byKey(const ValueKey('searchScopeRadio')), findsOneWidget);
    expect(find.text('lofi beats'), findsWidgets);

    // Search recommends; it does not replay history. The personalized Browse
    // section is used only here, not on the actual Browse page.
    expect(find.text('Recently Played'), findsNothing);
    expect(find.text('New artists based on your taste'), findsOneWidget);

    // Switch to radio scope: station field appears without the Radio page's
    // Music shortcut or its Recent station rail.
    await tester.tap(find.byKey(const ValueKey('searchScopeRadio')));
    await tester.pumpAndSettle();
    expect(find.text('Search stations'), findsOneWidget);
    expect(find.byKey(const ValueKey('radioMusicShortcut')), findsNothing);
    expect(find.text('Recent'), findsNothing);

    // Typing filters the in-memory directory (200ms debounce).
    await tester.enterText(find.byType(TextField), 'jazz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Station 1'), findsWidgets);

    // Back to music: term still blank, landing intact.
    await tester.tap(find.byKey(const ValueKey('searchScopeMusic')));
    await tester.pumpAndSettle();
    expect(find.text('lofi beats'), findsWidgets);

    // Unmount before disposing the container: drift retires its query
    // streams on a zero-duration timer during disposal, and the framework
    // fails a test with any timer still pending afterwards.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    container.dispose();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
