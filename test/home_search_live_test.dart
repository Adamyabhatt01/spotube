// Live songs in the Browse search dropdown: after a debounce pause, one
// gated search call per term feeds the panel's Songs group; short queries
// never fire; failures stay silent in the panel.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/home/home_search_results.dart';
import 'package:spotube/modules/home/home_search_suggestions.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

// 1x1 transparent PNG, served for every image request so cover rows decode
// without touching the network.
final _kPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _FakeImageResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _kPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_kPng).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class _FakeImageRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeImageResponse();
}

class _FakeImageHeaders extends Fake implements HttpHeaders {}

class _FakeImageClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeImageRequest();
}

class _FakeImageOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeImageClient();
}

SpotubeFullTrackObject _liveTrack() {
  return SpotubeFullTrackObject(
    id: 'live-1',
    // Deliberately overlapping nothing the user typed: live rows pass
    // through unfiltered (the server already filtered them).
    name: 'Neon Skyline',
    externalUri: 'https://example.test/track/live-1',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-9',
        name: 'Midnight Circuit',
        externalUri: 'https://example.test/artist/9',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-9',
      name: 'Afterglow',
      externalUri: 'https://example.test/album/9',
      artists: const [],
      albumType: SpotubeAlbumType.album,
      images: [
        SpotubeImageObject(
          url: 'https://example.test/cover.jpg',
          width: 300,
          height: 300,
        ),
      ],
    ),
    durationMs: 210000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

SpotubeSearchResponseObject _searchResponse(
    List<SpotubeFullTrackObject> tracks) {
  return SpotubeSearchResponseObject(
    albums: const [],
    artists: const [],
    playlists: const [],
    tracks: tracks,
  );
}

/// Empty saved-library notifiers, so the bar never reaches the auth gate
/// the real builds await.
class _EmptyPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: 0,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: [],
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyAlbums extends MetadataPluginSavedAlbumNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: 0,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: [],
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyArtists extends MetadataPluginSavedArtistNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: 0,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: [],
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyTracks extends MetadataPluginSavedTracksNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: 0,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: [],
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
          int offset, int limit) =>
      build();
}

class _LiveHarness extends StatelessWidget {
  const _LiveHarness();

  @override
  Widget build(BuildContext context) {
    return const ShadcnApp(
      localizationsDelegates: [AppLocalizations.delegate],
      home: Scaffold(
        child: SingleChildScrollView(child: HomeSearchBar()),
      ),
    );
  }
}

/// Production mounting: the bar lives in a sliver (`HomePage` puts it in a
/// `SliverToBoxAdapter` inside a `CustomScrollView`), not in a
/// `SingleChildScrollView` like the harnesses above.
class _SliverHarness extends StatelessWidget {
  const _SliverHarness();

  @override
  Widget build(BuildContext context) {
    return const ShadcnApp(
      localizationsDelegates: [AppLocalizations.delegate],
      home: Scaffold(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: HomeSearchBar()),
          ],
        ),
      ),
    );
  }
}

class _BackHarness extends ConsumerWidget {
  const _BackHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirrors HomePage's swap: a non-blank term replaces the field with
    // the results view. The results get a bounded height like the
    // SliverFillRemaining host gives them in production.
    final searching =
        ref.watch(searchTermStateProvider.select((s) => s.trim().isNotEmpty));
    return ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        child: searching
            ? const SizedBox(height: 600, child: HomeSearchResults())
            : const SingleChildScrollView(child: HomeSearchBar()),
      ),
    );
  }
}

void main() {
  // Result rows read the global player (active highlight); same wart as
  // home_search_chips_test.dart — host libmpv exists, revisit if CI lacks it.
  setUpAll(() => MediaKit.ensureInitialized());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    HttpOverrides.global = _FakeImageOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<ProviderContainer> pumpBar(
    WidgetTester tester, {
    required List<String> queries,
    List<SpotubeFullTrackObject>? liveTracks,
  }) async {
    final container = ProviderContainer(
      overrides: [
        themeDefinitionProvider.overrideWith((ref) async => null),
        themeUiProvider.overrideWith((ref) async => null),
        metadataPluginSavedPlaylistsProvider
            .overrideWith(() => _EmptyPlaylists()),
        metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
        metadataPluginSavedArtistsProvider.overrideWith(() => _EmptyArtists()),
        metadataPluginSavedTracksProvider.overrideWith(() => _EmptyTracks()),
        metadataPluginSearchAllProvider.overrideWith((ref, query) async {
          queries.add(query);
          return _searchResponse(liveTracks ?? [_liveTrack()]);
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _LiveHarness(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    return container;
  }

  Finder findField() => find.byType(TextField);

  group('live songs in the search dropdown', () {
    testWidgets('debounced term fetches one call and shows the song',
        (tester) async {
      final queries = <String>[];
      await pumpBar(tester, queries: queries);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'daf');
      // Let the keystroke build first (arming the 500ms debounce timer),
      // then advance past it: pump(duration) elapses before building, so
      // advancing without a prior build would strand the timer in the future.
      await tester.pump();
      // Debounce (500ms) + provider resolution + portal show.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(queries, ['daf']);
      expect(find.text('Neon Skyline'), findsOneWidget);
      // The subtitle is artist and album as separate texts now, so the album
      // half can open its own page.
      expect(find.text('Midnight Circuit'), findsOneWidget);
      expect(find.text('Afterglow'), findsOneWidget);
    });

    testWidgets('focus loss with the panel open hides without crashing',
        (tester) async {
      // Regression: dismissing an actually-visible panel via a state
      // change (focus leaves the field while the portal is showing)
      // used to call OverlayPortalController.hide() synchronously
      // inside build, tripping the persistentCallbacks assertion in
      // _OverlayPortalState.hide. Tap dismissal never trips it —
      // gestures hide the portal before the rebuild — so only a
      // tapless focus change (e.g. Tab out) reproduces it.
      final queries = <String>[];
      await pumpBar(tester, queries: queries);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'daf');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Neon Skyline'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(find.text('Neon Skyline'), findsNothing);
    });

    testWidgets('rapid typing fires once, for the final term', (tester) async {
      final queries = <String>[];
      await pumpBar(tester, queries: queries);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'd');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(findField(), 'da');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(findField(), 'daf');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(queries, ['daf']);
      expect(find.text('Neon Skyline'), findsOneWidget);
    });

    testWidgets('single character never fires', (tester) async {
      final queries = <String>[];
      await pumpBar(tester, queries: queries);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'd');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(queries, isEmpty);
      expect(find.text('Neon Skyline'), findsNothing);
    });

    testWidgets('tapping a recent submits it without navigating',
        (tester) async {
      await KVStoreService.setRecentSearches(['old mix']);
      final container =
          await pumpBar(tester, queries: <String>[], liveTracks: const []);

      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('old mix'), findsOneWidget);

      await tester.tap(find.text('old mix'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Submitted exactly like pressing Enter: provider state set, history
      // kept, no route pushed (this harness has no router to push to).
      expect(container.read(searchTermStateProvider), 'old mix');
      expect(KVStoreService.recentSearches.first, 'old mix');
    });

    testWidgets('real mouse timing: focus loss between down and up still taps',
        (tester) async {
      // Production repro of the dead dropdown, two parts the plain
      // `tester.tap` cannot express: (a) down and up land on different
      // frames (a mouse holds the button across frames), and (b) pressing
      // a row moves primary focus off the field at pointer-down in
      // production (observed live: showPanel flipped to false mid-click,
      // no row tap ever printed). Without the panelPointerDown pin the
      // focus loss detaches the overlay entry before pointer-up arrives,
      // the row's tap never completes, and every click does nothing.
      await KVStoreService.setRecentSearches(['old mix']);
      final container =
          await pumpBar(tester, queries: <String>[], liveTracks: const []);

      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('old mix'), findsOneWidget);

      final center = tester.getCenter(find.text('old mix'));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('old mix'),
        findsOneWidget,
        reason: 'panel detached mid-gesture: the tap can no longer land',
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(
        container.read(searchTermStateProvider),
        'old mix',
        reason: 'row tap was swallowed: panel vanished mid-gesture',
      );
    });

    testWidgets('outside tap closes the panel without firing background taps',
        (tester) async {
      // The panel is modal: the opaque barrier must absorb the tap so the
      // widget behind it never sees the event (no pass-through playback).
      var backgroundFired = false;
      await KVStoreService.setRecentSearches(['old mix']);
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider.overrideWith((ref) async => null),
          themeUiProvider.overrideWith((ref) async => null),
          metadataPluginSavedPlaylistsProvider
              .overrideWith(() => _EmptyPlaylists()),
          metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
          metadataPluginSavedArtistsProvider
              .overrideWith(() => _EmptyArtists()),
          metadataPluginSavedTracksProvider.overrideWith(() => _EmptyTracks()),
          metadataPluginSearchAllProvider.overrideWith((ref, query) async {
            return _searchResponse(const []);
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: Scaffold(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const HomeSearchBar(),
                    // Well below the 360px-max panel, so this target is
                    // genuinely outside it (a tap absorbed by the panel
                    // itself would prove nothing about the barrier).
                    const SizedBox(height: 400),
                    OutlineButton(
                      onPressed: () => backgroundFired = true,
                      child: const Text('tap target'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('old mix'), findsOneWidget);

      // warnIfMissed: the tap is *supposed* to miss the button — the opaque
      // barrier must intercept it. backgroundFired + panel-closed below are
      // the real assertions.
      await tester.tap(find.text('tap target'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(backgroundFired, isFalse);
      expect(find.text('old mix'), findsNothing);
    });
  });

  group('back to Browse', () {
    testWidgets('back button clears the term and restores the field',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider.overrideWith((ref) async => null),
          themeUiProvider.overrideWith((ref) async => null),
          metadataPluginSavedPlaylistsProvider
              .overrideWith(() => _EmptyPlaylists()),
          metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
          metadataPluginSavedArtistsProvider
              .overrideWith(() => _EmptyArtists()),
          metadataPluginSavedTracksProvider.overrideWith(() => _EmptyTracks()),
          metadataPluginSearchChipsProvider
              .overrideWith((ref) async => ['all']),
          metadataPluginSearchAllProvider.overrideWith((ref, query) async {
            return _searchResponse(const []);
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _BackHarness(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(findField(), findsOneWidget);

      // Submit a term: the results view replaces the field.
      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'daf');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(container.read(searchTermStateProvider), 'daf');
      expect(findField(), findsNothing);

      // Back clears the term: the field is back.
      await tester.tap(find.byIcon(SpotubeIcons.angleLeft));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(container.read(searchTermStateProvider), '');
      expect(findField(), findsOneWidget);
    });
  });

  group('production mounting', () {
    testWidgets('row tap works with the bar in a sliver', (tester) async {
      // Discriminant for dead clicks in production: if the sliver +
      // LayerLink + overlay combination breaks hit testing, tapping a
      // recent row submits nothing here either.
      await KVStoreService.setRecentSearches(['old mix']);
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider.overrideWith((ref) async => null),
          themeUiProvider.overrideWith((ref) async => null),
          metadataPluginSavedPlaylistsProvider
              .overrideWith(() => _EmptyPlaylists()),
          metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
          metadataPluginSavedArtistsProvider
              .overrideWith(() => _EmptyArtists()),
          metadataPluginSavedTracksProvider.overrideWith(() => _EmptyTracks()),
          metadataPluginSearchAllProvider.overrideWith((ref, query) async {
            return _searchResponse(const []);
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _SliverHarness(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('old mix'), findsOneWidget);

      await tester.tap(find.text('old mix'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      expect(container.read(searchTermStateProvider), 'old mix');
    });
  });

  group('field width', () {
    Future<void> sizeViewport(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('the field is exactly as wide as the panel under it',
        (tester) async {
      // The pairing the user asked for: the field pill ends where the
      // dropdown ends, so the panel reads as the field's own shadow. Measured
      // against the real panel rather than a repeated constant, so the two
      // cannot drift apart silently.
      //
      // Also a regression pin for `Align`: `ConstrainedBox` alone is a no-op
      // under `Expanded`, which hands down a tight width, so dropping the
      // Align restores a full-width field with nothing failing but this.
      await sizeViewport(tester, 1200);
      await pumpBar(tester, queries: <String>[]);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'daf');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final panel = find.byType(HomeSearchSuggestionsPanel);
      expect(panel, findsOneWidget);
      final fieldWidth = tester.getSize(findField()).width;
      expect(fieldWidth, 520);
      expect(tester.getSize(panel).width, fieldWidth);
    });

    testWidgets('a narrow window shrinks the field instead of overflowing',
        (tester) async {
      // A phone gets a single full-width column: the desktop Radio shortcut
      // is hidden (the bottom bar / Search scope chips already expose radio)
      // and the field takes the viewport minus its 16px gutters.
      await sizeViewport(tester, 400);
      await pumpBar(tester, queries: <String>[]);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Button, 'Radio'), findsNothing);
      expect(
        tester.getSize(findField()).width,
        moreOrLessEquals(400 - 32, epsilon: 1.0),
      );
    });
  });

  group('dropdown height', () {
    // The complaint this pins: a long suggestion list used to be clipped at a
    // fixed 360px, so whichever song landed on the fold was cut in half. The
    // panel now takes the room actually left under the field and only scrolls
    // for what genuinely does not fit.
    Future<void> sizeViewport(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // One more frame for the row-snap measurement.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeSearchSuggestionsPanel), findsOneWidget);
    }

    Rect rowRect(Element element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    testWidgets('a short list stays short instead of padding to the cap',
        (tester) async {
      await sizeViewport(tester, const Size(1200, 900));
      await KVStoreService.setRecentSearches(['daf punk']);
      await pumpBar(tester, queries: <String>[]);
      await openPanel(tester);

      final height =
          tester.getSize(find.byType(HomeSearchSuggestionsPanel)).height;
      // One header + one row, nowhere near the old fixed 360.
      expect(height, greaterThan(40));
      expect(height, lessThan(searchSuggestionPanelMaxHeight));
    });

    testWidgets('a long list grows with the window, not to a fixed height',
        (tester) async {
      await sizeViewport(tester, const Size(1200, 900));
      await KVStoreService.setRecentSearches(
        List.generate(24, (i) => 'term $i'),
      );
      await pumpBar(tester, queries: <String>[]);
      await openPanel(tester);

      expect(
        tester.getSize(find.byType(HomeSearchSuggestionsPanel)).height,
        greaterThan(searchSuggestionPanelMaxHeight),
      );
    });

    testWidgets('the fold lands between rows, never across one',
        (tester) async {
      // Short enough that the 20-recent list cannot fit: without the row snap
      // the fold bisects whichever row lands on it.
      await sizeViewport(tester, const Size(1200, 500));
      await KVStoreService.setRecentSearches(
        List.generate(24, (i) => 'term $i'),
      );
      await pumpBar(tester, queries: <String>[]);
      await openPanel(tester);

      // The fold is the scroll viewport's bottom edge, not the card's outer
      // edge: the card keeps a gutter below it.
      final fold = tester
          .getRect(
            find.descendant(
              of: find.byType(HomeSearchSuggestionsPanel),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .bottom;
      final rows = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SuggestionRow',
      );
      expect(rows, findsWidgets);
      for (final element in rows.evaluate()) {
        final rect = rowRect(element);
        // A row straddling the fold is exactly the "song cut in half" the
        // user reported.
        expect(
          rect.top < fold - 0.5 && rect.bottom > fold + 0.5,
          isFalse,
          reason: 'row at $rect is sliced by the fold at $fold',
        );
      }
    });

    testWidgets('a tall window shows more rows than a short one',
        (tester) async {
      Future<double> panelHeightAt(WidgetTester tester, double viewport) async {
        await KVStoreService.setRecentSearches(
          List.generate(24, (i) => 'term $i'),
        );
        await pumpBar(tester, queries: <String>[]);
        await openPanel(tester);
        return tester.getSize(find.byType(HomeSearchSuggestionsPanel)).height;
      }

      await sizeViewport(tester, const Size(1200, 500));
      final short = await panelHeightAt(tester, 500);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      tester.view.physicalSize = const Size(1200, 900);
      final tall = await panelHeightAt(tester, 900);

      expect(tall, greaterThan(short));
    });
  });
}
