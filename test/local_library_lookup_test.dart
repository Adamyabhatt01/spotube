// Tests for the local-library lookup.
//
// A track that is already in the folder Spotube was pointed at needs no
// YouTube lookup, no manifest extraction and no upstream stream. The
// lookup is what decides that, so it has to be right in both directions:
// the right file for the track, and no file at all for a track the
// library does not hold.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/local_library_lookup.dart';

SpotubeFullTrackObject _track({
  String name = 'One More Time',
  List<String> artists = const ['Daft Punk'],
  String id = 'track-1',
}) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/1',
    artists: [
      for (final artist in artists)
        SpotubeSimpleArtistObject(
          id: artist.toLowerCase().replaceAll(' ', '-'),
          name: artist,
          externalUri: 'https://example.test/artist/1',
        ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Discovery',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 322000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

SpotubeLocalTrackObject _local({
  required String name,
  String path = '/music/one more time.m4a',
  List<String> artists = const ['Daft Punk'],
  String id = 'local-1',
}) {
  return SpotubeLocalTrackObject(
    id: id,
    name: name,
    externalUri: 'file://$path',
    artists: [
      for (final artist in artists)
        SpotubeSimpleArtistObject(
          id: artist.toLowerCase().replaceAll(' ', '-'),
          name: artist,
          externalUri: 'https://example.test/artist/1',
        ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Discovery',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 322000,
    path: path,
  );
}

void main() {
  group('LocalLibraryLookup.find', () {
    test('an exact title matches', () {
      final match = LocalLibraryLookup.find(
        _track(),
        [_local(name: 'One More Time')],
      );

      expect(match, isNotNull);
      expect(match!.track.name, 'One More Time');
    });

    test('a filename with a different case still matches', () {
      final match = LocalLibraryLookup.find(
        _track(),
        [_local(name: 'ONE MORE TIME')],
      );

      expect(match, isNotNull);
    });

    test('a filename with different punctuation still matches', () {
      final match = LocalLibraryLookup.find(
        _track(),
        [_local(name: 'One More Time (Remastered)')],
      );

      expect(match, isNotNull);
    });

    test('a differently-named file does not match', () {
      final match = LocalLibraryLookup.find(
        _track(),
        [_local(name: 'Get Lucky')],
      );

      expect(match, isNull);
    });

    test('the same artist with a different title does not match', () {
      // The library holds many files by one artist; the artist alone is
      // not the track.
      final match = LocalLibraryLookup.find(
        _track(),
        [_local(name: 'Get Lucky')],
      );

      expect(match, isNull);
    });

    test('the best match wins when several files are close', () {
      final match = LocalLibraryLookup.find(
        _track(name: 'One More Time'),
        [
          _local(name: 'One More Time (Live)', id: 'a', path: '/music/live.m4a'),
          _local(name: 'One More Time', id: 'b', path: '/music/studio.m4a'),
        ],
      );

      expect(match, isNotNull);
      expect(match!.track.id, 'b');
    });

    test('an empty library matches nothing', () {
      expect(LocalLibraryLookup.find(_track(), const []), isNull);
    });

    test('a track with no name matches nothing', () {
      expect(
        LocalLibraryLookup.find(_track(name: ''), [_local(name: 'Anything')]),
        isNull,
      );
    });

    test('the artists are part of the match, not a separate gate', () {
      // The same title by a different artist is a different recording.
      final match = LocalLibraryLookup.find(
        _track(artists: const ['Daft Punk']),
        [_local(name: 'One More Time', artists: const ['Kanye West'])],
      );

      // The title still matches, so the file is found — but it scores
      // lower than a same-artist match, which is what the ordering below
      // relies on.
      expect(match, isNotNull);
    });

    test('a same-artist match outranks a different-artist one', () {
      final match = LocalLibraryLookup.find(
        _track(artists: const ['Daft Punk']),
        [
          _local(
            name: 'One More Time',
            id: 'other',
            path: '/music/other.m4a',
            artists: const ['Kanye West'],
          ),
          _local(
            name: 'One More Time',
            id: 'same',
            path: '/music/same.m4a',
            artists: const ['Daft Punk'],
          ),
        ],
      );

      expect(match!.track.id, 'same');
    });
  });

  group('LocalLibraryLookup.fileExists', () {
    test('a file that is not there is reported as missing', () {
      final track = _local(
        name: 'One More Time',
        path: '/definitely/not/here.m4a',
      );
      expect(LocalLibraryLookup.fileExists(track), isFalse);
    });
  });
}
