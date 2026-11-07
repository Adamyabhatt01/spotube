// The dropdown's per-row affordances: every library row carries its own play
// button, its cover reveals a badge on hover and plays without navigating, and
// the names inside a subtitle are routes. These are the pieces a screenshot
// cannot distinguish — a play button wired to the wrong row, or an artist name
// that looks like a link but is not — so each is asserted here.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_suggestions.dart';

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
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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

SpotubeSimpleArtistObject _artist(String id, String name) =>
    SpotubeSimpleArtistObject(
      id: id,
      name: name,
      externalUri: 'https://example.test/artist/$id',
    );

SpotubeSimpleAlbumObject _album(String id, String name, String artistName) =>
    SpotubeSimpleAlbumObject(
      id: id,
      name: name,
      externalUri: 'https://example.test/album/$id',
      artists: [_artist('$id-artist', artistName)],
      albumType: SpotubeAlbumType.album,
      images: [
        SpotubeImageObject(
          url: 'https://example.test/cover-$id.jpg',
          width: 300,
          height: 300,
        ),
      ],
    );

SpotubeFullTrackObject _track(
  String id,
  String name, {
  required String artistId,
  required String artistName,
  required String albumName,
}) =>
    SpotubeFullTrackObject(
      id: id,
      name: name,
      externalUri: 'https://example.test/track/$id',
      artists: [_artist(artistId, artistName)],
      album: _album('$id-album', albumName, artistName),
      durationMs: 210000,
      isrc: 'TEST$id',
      explicit: false,
    );

SpotubeSimplePlaylistObject _playlist(String id, String name) =>
    SpotubeSimplePlaylistObject(
      id: id,
      name: name,
      description: '',
      externalUri: 'https://example.test/playlist/$id',
      owner: SpotubeUserObject(
        id: 'owner-$id',
        name: 'Owner',
        externalUri: 'https://example.test/user/$id',
      ),
    );

SpotubeFullArtistObject _fullArtist(String id, String name) =>
    SpotubeFullArtistObject(
      id: id,
      name: name,
      externalUri: 'https://example.test/artist/$id',
    );

class _Recorded {
  final played = <LibrarySearchSuggestion>[];
  final playedOnly = <LibrarySearchSuggestion>[];
  final activated = <HomeSearchSuggestion>[];
  final openedAlbums = <SpotubeSimpleAlbumObject>[];
  final openedArtists = <SpotubeSimpleArtistObject>[];
}

/// A row's trailing play button. The cover's badge is drawn with the same
/// glyph, so the button's ancestry is what tells the two targets apart.
Finder trailingPlay() => find.descendant(
      of: find.byType(IconButton),
      matching: find.byIcon(SpotubeIcons.play),
    );

/// The play hit area on the cover of the [row]th suggestion, found by the
/// semantics the cover puts on it rather than by its badge — the badge only
/// exists while the pointer is over that cover.
Finder coverPlay(int row) => find
    .byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Play',
    )
    .at(row);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required _Recorded recorded,
  List<LibrarySearchSuggestion> library = const [],
  bool withPlay = true,
  bool withLinks = true,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          child: Center(
            child: HomeSearchSuggestionsPanel(
              recents: const [],
              live: const [],
              library: library,
              query: 'hello',
              onActivate: (suggestion) => recorded.activated.add(suggestion),
              onPlay: withPlay
                  ? (suggestion) => recorded.played.add(suggestion)
                  : null,
              onPlayOnly: withPlay
                  ? (suggestion) => recorded.playedOnly.add(suggestion)
                  : null,
              onOpenAlbum: withLinks
                  ? (album) => recorded.openedAlbums.add(album)
                  : null,
              onOpenArtist: withLinks
                  ? (artist) => recorded.openedArtists.add(artist)
                  : null,
              onRemoveRecent: (_) {},
              onClearRecents: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// One suggestion per library row type, in the order the panel paints them.
List<LibrarySearchSuggestion> _fourRows() => [
      TrackSearchSuggestion(
        _track(
          't1',
          'Hello Track',
          artistId: 'a1',
          artistName: 'Circuit Voices',
          albumName: 'Track Album',
        ),
      ),
      PlaylistSearchSuggestion(_playlist('p1', 'Hello Mix')),
      AlbumSearchSuggestion(_album('al1', 'Hello Record', 'Album Owner')),
      ArtistSearchSuggestion(_fullArtist('fa1', 'Hello Person')),
    ];

void main() {
  setUp(() {
    HttpOverrides.global = _FakeImageOverrides();
  });
  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('each library row type carries its own play button',
      (tester) async {
    final library = _fourRows();
    final recorded = _Recorded();
    await _pumpPanel(tester, recorded: recorded, library: library);

    // Paint order is the library order, so the nth button belongs to the nth
    // suggestion.
    expect(trailingPlay(), findsNWidgets(4));
    await tester.tap(trailingPlay().at(2));
    await tester.pump();

    expect(recorded.played, [library[2]]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cover reveals its badge on hover and plays without opening',
      (tester) async {
    final library = _fourRows();
    final recorded = _Recorded();
    await _pumpPanel(tester, recorded: recorded, library: library);

    // Nothing but the rows' own buttons until the pointer arrives.
    expect(find.byIcon(SpotubeIcons.play), findsNWidgets(4));

    final cover = tester.getCenter(coverPlay(2));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(cover);
    await tester.pump();

    // Exactly one badge, on the cover under the pointer.
    expect(find.byIcon(SpotubeIcons.play), findsNWidgets(5));

    await pointer.down(cover);
    await pointer.up();
    await tester.pump();

    // The cover plays and stops there — no activation, so no page opens, and
    // the row's own play-and-open button never fires either.
    expect(recorded.playedOnly, [library[2]]);
    expect(recorded.played, isEmpty);
    expect(recorded.activated, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a song row opens the credited artist and the album apart',
      (tester) async {
    final recorded = _Recorded();
    await _pumpPanel(
      tester,
      recorded: recorded,
      library: [
        TrackSearchSuggestion(
          _track(
            't1',
            'Hello Track',
            artistId: 'a1',
            artistName: 'Circuit Voices',
            albumName: 'Track Album',
          ),
        ),
      ],
    );

    await tester.tap(find.text('Circuit Voices'));
    await tester.pump();
    expect(recorded.openedArtists.map((a) => a.id), ['a1']);
    expect(recorded.openedAlbums, isEmpty);

    await tester.tap(find.text('Track Album'));
    await tester.pump();
    expect(recorded.openedAlbums.map((a) => a.id), ['t1-album']);

    // Tapping either half of a subtitle must not also fire the row's own
    // activation, which would open the song on top of the artist or album.
    expect(recorded.played, isEmpty);
  });

  testWidgets("an album row's artist subtitle opens that artist",
      (tester) async {
    final recorded = _Recorded();
    await _pumpPanel(
      tester,
      recorded: recorded,
      library: [
        AlbumSearchSuggestion(_album('al1', 'Hello Record', 'Album Owner')),
      ],
    );

    await tester.tap(find.text('Album Owner'));
    await tester.pump();
    expect(recorded.openedArtists.map((a) => a.id), ['al1-artist']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without callbacks the rows fall back to plain text',
      (tester) async {
    final recorded = _Recorded();
    await _pumpPanel(
      tester,
      recorded: recorded,
      library: [
        TrackSearchSuggestion(
          _track(
            't1',
            'Hello Track',
            artistId: 'a1',
            artistName: 'Circuit Voices',
            albumName: 'Track Album',
          ),
        ),
      ],
      withPlay: false,
      withLinks: false,
    );

    expect(find.byIcon(SpotubeIcons.play), findsNothing);
    // The names still render — they simply are not routes.
    expect(find.text('Circuit Voices'), findsOneWidget);
    expect(find.text('Track Album'), findsOneWidget);

    await tester.tap(find.text('Track Album'));
    await tester.pump();
    expect(recorded.openedAlbums, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
