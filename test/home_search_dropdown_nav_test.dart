// Clicking a song row in the Browse search dropdown must open *that* song.
// The panel rows bind their tap callback to the same track object they
// render; this pins display == navigation for the live (Songs) group and the
// library group, with a real auto_route stack behind the bar.
import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

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

SpotubeFullTrackObject _track(String id, String name) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-$id',
        name: 'Midnight Circuit',
        externalUri: 'https://example.test/artist/$id',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-$id',
      name: 'Afterglow',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
      images: [
        SpotubeImageObject(
          url: 'https://example.test/cover-$id.jpg',
          width: 300,
          height: 300,
        ),
      ],
    ),
    durationMs: 210000,
    isrc: 'TEST$id',
    explicit: false,
  );
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Scaffold(child: SingleChildScrollView(child: child));
}

String? capturedTrackId;
_RootTestRouter? _rootRouter;
ProviderContainer? lastContainer;

class _TrackProbePage extends StatelessWidget {
  const _TrackProbePage(this.trackId);
  final String trackId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(child: Center(child: Text('page:$trackId')));
}

class _RootTestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: _EmptyRoute.page,
          initial: true,
          children: [
            AutoRoute(
              page: PageInfo(
                'TrackRoute',
                builder: (data) {
                  capturedTrackId = (data.args as dynamic).trackId as String;
                  return _TrackProbePage(capturedTrackId!);
                },
              ),
              path: 'track/:id',
            ),
          ],
        ),
      ];
}

class _EmptyRoute extends PageRouteInfo<void> {
  const _EmptyRoute({List<PageRouteInfo>? children})
      : super(_EmptyRoute.name, initialChildren: children);

  static const String name = '_EmptyRoute';
  static PageInfo page = PageInfo(
    name,
    builder: (data) => const Stack(
      children: [
        _EmptyPage(child: HomeSearchBar()),
        Positioned.fill(child: IgnorePointer(child: AutoRouter())),
      ],
    ),
  );
}

class _EmptyPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _empty(null);
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyAlbums extends MetadataPluginSavedAlbumNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build() async => _empty(null);
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyArtists extends MetadataPluginSavedArtistNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      build() async => _empty(null);
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _SavedTracks extends MetadataPluginSavedTracksNotifier {
  _SavedTracks(this.items);
  final List<SpotubeFullTrackObject> items;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build() async {
    // Production's notifier calls cacheFor(): a ref.read() with no listener
    // would otherwise dispose the element before the fetch lands.
    ref.cacheFor();
    return _empty(items);
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
          int offset, int limit) =>
      build();
}

SpotubePaginationResponseObject<T> _empty<T>(List<T>? items) =>
    SpotubePaginationResponseObject(
      limit: items?.length ?? 0,
      nextOffset: null,
      total: items?.length ?? 0,
      hasMore: false,
      items: items ?? [],
    );

class _RouterHarness extends StatelessWidget {
  const _RouterHarness();

  @override
  Widget build(BuildContext context) {
    final router = _RootTestRouter();
    _rootRouter = router;
    final RouterConfig config = router.config();
    return ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Router(
        routerDelegate: config.routerDelegate,
        routeInformationParser: config.routeInformationParser,
        routeInformationProvider: config.routeInformationProvider,
      ),
    );
  }
}

void main() {
  setUpAll(() => MediaKit.ensureInitialized());

  setUp(() async {
    capturedTrackId = null;
    lastContainer = null;
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    HttpOverrides.global = _FakeImageOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Widget? harness;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 6));
    expect(tester.takeException(), isNull);
  }

  Future<void> pumpHarness(
    WidgetTester tester, {
    List<SpotubeFullTrackObject> liveTracks = const [],
    List<SpotubeFullTrackObject> savedTracks = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        metadataPluginSavedPlaylistsProvider
            .overrideWith(() => _EmptyPlaylists()),
        metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
        metadataPluginSavedArtistsProvider.overrideWith(() => _EmptyArtists()),
        metadataPluginSavedTracksProvider
            .overrideWith(() => _SavedTracks(savedTracks)),
        metadataPluginSearchAllProvider.overrideWith(
          (ref, query) async => SpotubeSearchResponseObject(
            albums: const [],
            artists: const [],
            playlists: const [],
            tracks: liveTracks,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    lastContainer = container;
    harness = UncontrolledProviderScope(
      container: container,
      child: const _RouterHarness(),
    );
    await tester.pumpWidget(harness!);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> focusAndType(WidgetTester tester, String text) async {
    await tester.tap(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'TextField'));
    await tester.pump();
    await tester.enterText(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'TextField'),
        text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  // shadcn's TextField is an EditableText: onSubmitted is driven by the
  // text-input action, which a headless test does not get from a physical
  // Enter key.
  Future<void> pressEnter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  }

  String? submittedTerm() => lastContainer?.read(searchTermStateProvider);

  testWidgets('tapping the second live row opens the second song',
      (tester) async {
    final live = [
      _track('live-1', 'Alpha Song'),
      _track('live-2', 'Beta Song'),
      _track('live-3', 'Gamma Song'),
    ];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');

    expect(find.text('Alpha Song'), findsOneWidget);
    expect(find.text('Beta Song'), findsOneWidget);
    expect(find.text('Gamma Song'), findsOneWidget);

    await tester.tap(find.text('Beta Song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    tester.takeException();

    await unmount(tester);
    expect(capturedTrackId, 'live-2',
        reason: 'dropdown tap opened the wrong song');
  });

  testWidgets('tapping the last live row opens the last song', (tester) async {
    final live = [
      _track('live-1', 'Alpha Song'),
      _track('live-2', 'Beta Song'),
      _track('live-3', 'Gamma Song'),
    ];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');

    await tester.tap(find.text('Gamma Song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    tester.takeException();

    await unmount(tester);
    expect(capturedTrackId, 'live-3',
        reason: 'dropdown tap opened the wrong song');
  });

  testWidgets('a second dropdown song tap replaces the open track page',
      (tester) async {
    final live = [
      _track('live-1', 'Alpha Song'),
      _track('live-2', 'Beta Song'),
      _track('live-3', 'Gamma Song'),
    ];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');

    await tester.tap(find.text('Beta Song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();
    expect(find.text('page:live-2'), findsOneWidget);

    // Tap a second suggestion after the first track page is replaced, which
    // is what happens when the panel is still open and gets used twice.
    await _rootRouter!.navigate(const _EmptyRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await focusAndType(tester, 'daf');
    await tester.tap(find.text('Gamma Song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();

    expect(find.text('page:live-3'), findsOneWidget,
        reason: 'dropdown tap re-opened the previously visited song');
    expect(find.text('page:live-2'), findsNothing);
    await unmount(tester);
  });

  // A real mouse press spans frames and moves primary focus off the field at
  // pointer-down (tester.tap does neither). The live group is gated on focus,
  // so an unfocus mid-press deleted the rows the user was clicking and the
  // library rows slid into the pressed element — pointer-up then opened an
  // already-saved song instead of the live one.
  testWidgets('a two-frame press on a live row still opens the live song',
      (tester) async {
    final live = [
      _track('live-1', 'Hello Live One'),
      _track('live-2', 'Hello Live Two'),
    ];
    final saved = [
      _track('lib-1', 'Hello Library One'),
      _track('lib-2', 'Hello Library Two'),
    ];
    await pumpHarness(tester, liveTracks: live, savedTracks: saved);
    await focusAndType(tester, 'Hello');

    // Titles that contain the query render as RichText (highlight), so rows
    // are addressed by index: 0 and 1 are the live songs, 2 and 3 the saved
    // ones already in the library, 4 the see-all footer.
    expect(find.byType(GhostButton), findsNWidgets(5));

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(GhostButton).at(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // What the press itself does on a desktop: focus leaves the field.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();

    await unmount(tester);
    expect(capturedTrackId, 'live-2',
        reason: 'a press that lost focus mid-way opened another song');
  });

  testWidgets('tapping a library song row opens that song', (tester) async {
    final saved = [
      _track('lib-1', 'Library One'),
      _track('lib-2', 'Library Two'),
    ];
    await pumpHarness(tester, savedTracks: saved);
    await focusAndType(tester, 'Library');
    await tester.pump(const Duration(milliseconds: 200));

    // Titles render as RichText (query highlight), so address rows by index:
    // row 0 = Library One, row 1 = Library Two.
    await tester.tap(find.byType(GhostButton).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    await unmount(tester);
    expect(capturedTrackId, 'lib-2',
        reason: 'dropdown tap opened the wrong song');
  });

  testWidgets('arrow down highlights a row and enter opens that song',
      (tester) async {
    final live = [
      _track('live-1', 'Alpha Song'),
      _track('live-2', 'Beta Song'),
      _track('live-3', 'Gamma Song'),
    ];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');

    // Row order: the three live songs, then the see-all footer. Two presses
    // land on Beta Song — the second live row, which is not the first row.
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressEnter(tester);

    await unmount(tester);
    expect(capturedTrackId, 'live-2',
        reason: 'enter did not open the highlighted row');
    expect(submittedTerm(), isNot('daf'));
  });

  testWidgets('escape dismisses the panel without opening or submitting',
      (tester) async {
    final live = [_track('live-1', 'Alpha Song')];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');
    expect(find.byType(GhostButton), findsWidgets);

    await pressKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(GhostButton), findsNothing);
    await unmount(tester);
    expect(capturedTrackId, isNull);
    expect(submittedTerm(), isEmpty);
  });

  testWidgets('arrow up wraps onto the footer and enter submits the term',
      (tester) async {
    final live = [
      _track('live-1', 'Alpha Song'),
      _track('live-2', 'Beta Song'),
      _track('live-3', 'Gamma Song'),
    ];
    await pumpHarness(tester, liveTracks: live);
    await focusAndType(tester, 'daf');

    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    await pressEnter(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Nothing highlighted on entry means the last row — the footer — so this
    // is a term submission, not a song.
    expect(find.byType(GhostButton), findsNothing);
    await unmount(tester);
    expect(capturedTrackId, isNull);
    expect(submittedTerm(), 'daf');
  });

  testWidgets('a query that matches nothing still submits from the footer',
      (tester) async {
    await pumpHarness(tester);
    await focusAndType(tester, 'zzz');

    expect(find.byType(GhostButton), findsOneWidget);

    await pressEnter(tester);
    await unmount(tester);
    expect(capturedTrackId, isNull);
    expect(submittedTerm(), 'zzz');
  });
}
