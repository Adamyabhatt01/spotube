import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_suggestions.dart';

SpotubeSimplePlaylistObject _playlist(String id, String name) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: name,
    description: 'A playlist under test',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

SpotubeSimpleAlbumObject _album(String id, String name,
    [List<String> artists = const ['Artist']]) {
  return SpotubeSimpleAlbumObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/album/$id',
    artists: [
      for (final artist in artists)
        SpotubeSimpleArtistObject(
          id: 'artist-$artist',
          name: artist,
          externalUri: 'https://example.test/artist/$artist',
        ),
    ],
    albumType: SpotubeAlbumType.album,
  );
}

SpotubeFullArtistObject _artist(String id, String name) {
  return SpotubeFullArtistObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/artist/$id',
  );
}

SpotubeFullTrackObject _track(String id, String name,
    [String artist = 'Test Artist']) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-1',
        name: artist,
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST000000$id',
    explicit: false,
  );
}

void main() {
  group('filterRecentSearches', () {
    test('empty text returns all recents', () {
      expect(
        filterRecentSearches(['a', 'b'], ''),
        ['a', 'b'],
      );
      expect(filterRecentSearches(['a', 'b'], '   '), ['a', 'b']);
    });

    test('applies the fuzzy cutoff', () {
      expect(
        filterRecentSearches(['Daft Punk', 'Metallica'], 'daft'),
        ['Daft Punk'],
      );
    });

    test('does not mutate the input', () {
      final recents = ['a', 'b'];
      filterRecentSearches(recents, 'a');
      expect(recents, ['a', 'b']);
    });
  });

  group('topMatches', () {
    test('blank query matches nothing', () {
      expect(
        topMatches([_playlist('a', 'Daft Punk')], '  ', (p) => [p.name]),
        isEmpty,
      );
    });

    test('ranks best score first', () {
      final items = [
        _playlist('a', 'Punk Rock Classics'),
        _playlist('b', 'Daft Punk'),
      ];
      final matched = topMatches(items, 'daft punk', (p) => [p.name]);
      expect(matched.map((p) => p.id), ['b', 'a']);
    });

    test('below-cutoff items are dropped', () {
      expect(
        topMatches([_playlist('a', 'Metallica')], 'daft', (p) => [p.name]),
        isEmpty,
      );
    });

    test('caps rows per group', () {
      final items = [
        for (var i = 0; i < 10; i++) _playlist('p$i', 'Daft Punk $i'),
      ];
      expect(
        topMatches(items, 'daft punk', (p) => [p.name]).length,
        searchSuggestionGroupCap,
      );
    });

    test('matches across secondary fields', () {
      final items = [
        _album('a', 'Random Access Memories', ['Daft Punk']),
        _album('b', 'Metallica', ['Metallica']),
      ];
      final matched = topMatches(
        items,
        'daft punk',
        (a) => [a.name, a.artists.asString()],
      );
      expect(matched.map((a) => a.id), ['a']);
    });
  });

  group('buildSearchSuggestions', () {
    test('empty text yields recents only, no library rows', () {
      final options = buildSearchSuggestions(
        text: '',
        libraryQueryText: '',
        recents: ['daft punk'],
        tracks: [_track('t', 'One More Time')],
        playlists: [_playlist('a', 'Daft Punk')],
        albums: [_album('b', 'Discovery')],
        artists: [_artist('c', 'Daft Punk')],
      );
      expect(options.recents, hasLength(1));
      expect(options.recents.single, isA<RecentSearchSuggestion>());
      expect(options.live, isEmpty);
      expect(options.library, isEmpty);
    });

    test('non-empty text groups recents before library rows', () {
      final options = buildSearchSuggestions(
        text: 'daft',
        libraryQueryText: 'daft',
        recents: ['daft punk mix'],
        tracks: const [],
        playlists: [_playlist('a', 'Daft Punk')],
        albums: const [],
        artists: [_artist('c', 'Daft Punk')],
      );
      expect(options.recents.first, isA<RecentSearchSuggestion>());
      expect(
        options.library.whereType<PlaylistSearchSuggestion>().map((s) => s.playlist.id),
        ['a'],
      );
      expect(
        options.library.whereType<ArtistSearchSuggestion>().map((s) => s.artist.id),
        ['c'],
      );
    });

    test('empty library reads as empty, never an error', () {
      final options = buildSearchSuggestions(
        text: 'daft',
        libraryQueryText: 'daft',
        recents: const [],
        tracks: const [],
        playlists: const [],
        albums: const [],
        artists: const [],
      );
      expect(options.recents, isEmpty);
      expect(options.live, isEmpty);
      expect(options.library, isEmpty);
    });

    test('songs lead the library rows with artist match', () {
      final options = buildSearchSuggestions(
        text: 'daft',
        libraryQueryText: 'daft',
        recents: const [],
        tracks: [_track('t', 'Get Lucky', 'Daft Punk')],
        playlists: [_playlist('a', 'Daft Punk')],
        albums: const [],
        artists: const [],
      );
      expect(options.library.first, isA<TrackSearchSuggestion>());
      expect(
        (options.library.first as TrackSearchSuggestion).track.id,
        't',
      );
    });

    test('live songs land in live, library rows in library', () {
      final options = buildSearchSuggestions(
        text: 'daft punk',
        libraryQueryText: 'daft punk',
        recents: ['old search'],
        liveTracks: [_track('live', 'Get Lucky', 'Daft Punk')],
        tracks: [_track('t', 'One More Time', 'Daft Punk')],
        playlists: const [],
        albums: const [],
        artists: const [],
      );
      expect(options.live, hasLength(1));
      expect(options.live.single, isA<LiveTrackSearchSuggestion>());
      expect(
        options.library.whereType<TrackSearchSuggestion>().map((s) => s.track.id),
        ['t'],
      );
    });

    test('live tracks never leak into library despite the subtype relation', () {
      // LiveTrackSearchSuggestion extends TrackSearchSuggestion, so a
      // post-hoc `is Track` split would misfile them; the grouped record is
      // built per loop site instead. This pins that contract.
      final options = buildSearchSuggestions(
        text: 'daft punk',
        libraryQueryText: 'daft punk',
        recents: const [],
        liveTracks: [_track('live', 'Get Lucky', 'Daft Punk')],
        tracks: const [],
        playlists: const [],
        albums: const [],
        artists: const [],
      );
      expect(options.live, hasLength(1));
      expect(options.library, isEmpty);
    });

    test('cleared text force-clears library and live despite stale debounce', () {
      // After a fast clear the debounced term still holds the old query for
      // a beat; rows must not linger.
      final options = buildSearchSuggestions(
        text: '',
        libraryQueryText: 'daft punk',
        recents: ['daft punk'],
        liveTracks: [_track('live', 'Get Lucky', 'Daft Punk')],
        tracks: [_track('t', 'One More Time', 'Daft Punk')],
        playlists: [_playlist('a', 'Daft Punk')],
        albums: const [],
        artists: const [],
      );
      expect(options.recents, hasLength(1));
      expect(options.live, isEmpty);
      expect(options.library, isEmpty);
    });

    test('library follows the debounced term, not the raw field', () {
      // Mid-typing: raw field already at 'daft punk x' but the debounce has
      // not fired yet — library still answers the previous pause.
      final options = buildSearchSuggestions(
        text: 'daft punk x',
        libraryQueryText: 'daft punk',
        recents: const [],
        tracks: [_track('t', 'One More Time', 'Daft Punk')],
        playlists: const [],
        albums: const [],
        artists: const [],
      );
      expect(
        options.library.whereType<TrackSearchSuggestion>().map((s) => s.track.id),
        ['t'],
      );
    });

    test('live songs are capped', () {
      final options = buildSearchSuggestions(
        text: 'daft punk',
        libraryQueryText: 'daft punk',
        recents: const [],
        liveTracks: [
          for (var i = 0; i < 10; i++)
            _track('live$i', 'Daft Punk $i', 'Daft Punk'),
        ],
      );
      expect(
        options.live.length,
        searchSuggestionLiveCap,
      );
    });

    test('no live tracks still shows library rows', () {
      final options = buildSearchSuggestions(
        text: 'daft',
        libraryQueryText: 'daft',
        recents: const [],
        tracks: [_track('t', 'Get Lucky', 'Daft Punk')],
        playlists: const [],
        albums: const [],
        artists: const [],
      );
      expect(options.live, isEmpty);
      expect(
        options.library.whereType<TrackSearchSuggestion>().map((s) => s.track.id),
        ['t'],
      );
    });
  });
}
