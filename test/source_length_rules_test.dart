// Tests for the source-resolution length rules.
//
// A clip of a track carries the track's exact title, so the title score
// alone cannot tell a 33-second "Edit" from the five-minute recording it
// was cut from. The length can, and the rules below are what make the
// original recording win.
//
// These are the real yt-dlp rows for "daft punk one more time" against a
// 322-second track.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

SpotubeFullTrackObject _track({
  int durationMs = 322000,
  String name = 'One More Time',
  List<String> artists = const ['Daft Punk'],
}) {
  return SpotubeFullTrackObject(
    id: 'track-1',
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
    durationMs: durationMs,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

SpotubeAudioSourceMatchObject _match({
  required String title,
  required int durationSeconds,
  String channel = 'Daft Punk',
}) {
  return SpotubeAudioSourceMatchObject(
    id: 'match-$title',
    title: title,
    artists: [channel],
    duration: Duration(seconds: durationSeconds),
    externalUri: 'https://example.test/source/1',
  );
}

void main() {
  group('isWrongLengthForTrack', () {
    test('a 33-second clip of a 322-second track is the wrong length', () {
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 33),
          _track(),
        ),
        isTrue,
      );
    });

    test('a 126-second short version is not the wrong length', () {
      // 126s is 39% of 322s — above the 25% floor, so it is not ruled out
      // as a clip. It is still ranked below the recording by the mismatch
      // penalty (196s of drift against a 15s tolerance); the floor is for
      // the clips the penalty cannot catch on its own.
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 126),
          _track(),
        ),
        isFalse,
      );
    });

    test('a candidate under a quarter of the track is the wrong length', () {
      // 80s against 322s is 25% — the line itself.
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 80),
          _track(),
        ),
        isTrue,
      );
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 81),
          _track(),
        ),
        isFalse,
      );
    });

    test('the recording itself is the right length', () {
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 322),
          _track(),
        ),
        isFalse,
      );
    });

    test('a live take a little longer is still the same recording', () {
      // 260s against 322s: inside the 15s tolerance, and inside the
      // length band too.
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 260),
          _track(),
        ),
        isFalse,
      );
    });

    test('an hour-long mix is the wrong length', () {
      expect(
        isWrongLengthForTrack(
          const Duration(hours: 1),
          _track(),
        ),
        isTrue,
      );
    });

    test('a candidate with no known duration is never ruled out', () {
      // The plugin boundary does not always carry one: a yt-dlp flat
      // search row often omits it, and "unknown" is not evidence.
      expect(
        isWrongLengthForTrack(Duration.zero, _track()),
        isFalse,
      );
    });

    test('a track with no known duration rules nothing out', () {
      expect(
        isWrongLengthForTrack(
          const Duration(seconds: 3),
          _track(durationMs: 0),
        ),
        isFalse,
      );
    });

    test('a genuinely short track is not ruled out', () {
      // A 30-second song against a 30-second track: the floor is
      // relative to the track's own length, so a short recording of a
      // short track is fine.
      final short = _track(durationMs: 30000, name: 'Interlude');
      expect(
        isWrongLengthForTrack(const Duration(seconds: 30), short),
        isFalse,
      );
    });

    test('a 5-second clip of a 30-second track is still the wrong length', () {
      final short = _track(durationMs: 30000, name: 'Interlude');
      expect(
        isWrongLengthForTrack(const Duration(seconds: 5), short),
        isTrue,
      );
    });
  });

  group('rankResults', () {
    test('the recording wins over a clip of the same title', () {
      // The real rows, without an "(Official …)" marker on the recording —
      // which is most of the catalogue.
      final ranked = SourcedTrack.rankResults(
        [
          _match(title: 'One More Time - Daft Punk Edit', durationSeconds: 33),
          _match(title: 'Daft Punk - One More Time', durationSeconds: 322),
        ],
        _track(),
      );

      expect(ranked.first.title, 'Daft Punk - One More Time');
    });

    test('a clip with an exact title still loses to a right-length match', () {
      final ranked = SourcedTrack.rankResults(
        [
          _match(title: 'One More Time - Daft Punk Edit', durationSeconds: 33),
          _match(title: 'One More Time', durationSeconds: 321),
        ],
        _track(),
      );

      expect(ranked.first.duration, const Duration(seconds: 321));
    });

    test('a duration mismatch outweighs a title match', () {
      // The clip carries the track's exact title, so the title scores it
      // the same points as the recording. The mismatched length has to
      // cost more than the title earns, or the clip wins.
      final ranked = SourcedTrack.rankResults(
        [
          _match(title: 'One More Time', durationSeconds: 30),
          _match(title: 'One More Time', durationSeconds: 322),
        ],
        _track(),
      );

      expect(
        ranked.first.duration,
        const Duration(seconds: 322),
        reason: 'the same title at the right length must rank first',
      );
    });

    test('an unknown duration does not penalise a candidate', () {
      final ranked = SourcedTrack.rankResults(
        [
          _match(title: 'One More Time', durationSeconds: 0),
          _match(title: 'One More Time (Live)', durationSeconds: 260),
        ],
        _track(),
      );

      expect(ranked.first.duration, Duration.zero);
    });
  });

  group('dropWrongLengthCandidates', () {
    test('the clip is dropped when the recording survives', () {
      final kept = SourcedTrack.dropWrongLengthCandidates(
        [
          _match(title: 'One More Time - Daft Punk Edit', durationSeconds: 33),
          _match(title: 'Daft Punk - One More Time', durationSeconds: 322),
        ],
        _track(),
      );

      expect(kept, hasLength(1));
      expect(kept.single.duration, const Duration(seconds: 322));
    });

    test('nothing is dropped when every candidate is the wrong length', () {
      // A track with no full-length match on the backend must still play
      // something: a clip beats nothing.
      final candidates = [
        _match(title: 'One More Time - Edit', durationSeconds: 33),
        _match(title: 'One More Time - Short', durationSeconds: 60),
      ];

      final kept = SourcedTrack.dropWrongLengthCandidates(candidates, _track());

      expect(kept, hasLength(2));
    });

    test('a candidate with no known duration is kept', () {
      final kept = SourcedTrack.dropWrongLengthCandidates(
        [
          _match(title: 'One More Time', durationSeconds: 0),
        ],
        _track(),
      );

      expect(kept, hasLength(1));
    });

    test('an empty list stays empty', () {
      expect(
        SourcedTrack.dropWrongLengthCandidates(const [], _track()),
        isEmpty,
      );
    });
  });
}
