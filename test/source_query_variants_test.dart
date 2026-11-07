// Recall regression: a track whose streaming-service credits carry trademark
// glyphs and accented letters ("Wassup" credited to "Flawed, Slay™, SÎM")
// used to get exactly one search — with the plugin's own query string — and a
// 6-hour source_match tombstone when that single query came back empty.
//
// Measured against the app's own NewPipe backend, the verbatim query returns
// 0 results while "Wassup Flawed" returns 20 with the correct video first.
// So the failure was recall, not availability, and the tombstone made it stick.
//
// Locked here: the variant ladder that gives the search a second and third
// try before a miss is recorded, and the artist/channel comparison in
// [SourcedTrack.rankResults] that decides *which* of the returned videos wins.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

SpotubeSimpleArtistObject _artist(String name) =>
    SpotubeSimpleArtistObject(id: 'a-$name', name: name, externalUri: '');

SpotubeFullTrackObject _track({
  String name = 'Wassup',
  List<SpotubeSimpleArtistObject> artists = const [],
  String isrc = '',
  int durationMs = 274000,
}) {
  return SpotubeFullTrackObject(
    id: 'track-1',
    name: name,
    externalUri: 'https://open.spotify.com/track/track-1',
    artists: artists.isEmpty ? [_artist('Flawed'), _artist('Slay™')] : artists,
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Sounds Like Home',
      externalUri: '',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: durationMs,
    isrc: isrc,
    explicit: false,
  );
}

SpotubeAudioSourceMatchObject _match({
  required String id,
  required String title,
  required List<String> artists,
  int seconds = 274,
}) {
  return SpotubeAudioSourceMatchObject(
    id: id,
    title: title,
    artists: artists,
    duration: Duration(seconds: seconds),
    externalUri: 'https://youtube.com/watch?v=$id',
  );
}

void main() {
  group('searchRetryVariants', () {
    test(
        'simplifies an ISRC + credited-artist query down to something findable',
        () {
      final track = _track(isrc: 'INR123456789');

      final variants = searchRetryVariants(track);

      expect(variants, hasLength(2));
      // ISRC never appears in a video title, and a junk ISRC page is what
      // stops the plugin's own "empty result -> text query" fallback.
      expect(variants[0].isrc, isEmpty);
      expect(variants[0].name, 'Wassup');
      expect(
        variants[0].artists.map((a) => a.name),
        ['Flawed', 'Slay'],
      );
      // Featured credits carry the noise that collapses result pages, so the
      // last variant keeps only the primary artist.
      expect(
        variants[1].artists.map((a) => a.name),
        ['Flawed'],
      );
    });

    test('costs nothing extra for an already simple query', () {
      final track = _track(
        artists: [_artist('Flawed')],
      );

      expect(searchRetryVariants(track), isEmpty);
    });

    test('keeps non-Latin credits intact', () {
      final track = _track(
        name: 'ग ऱहान',
        artists: [_artist('अनुराग')],
        isrc: 'INR123456789',
      );

      final variants = searchRetryVariants(track);

      expect(variants, hasLength(1));
      expect(variants.single.name, 'ग ऱहान');
      expect(
        variants.single.artists.single.name,
        'अनुराग',
      );
    });

    test('drops a track name made only of credit symbols', () {
      final track = _track(name: '™', artists: [_artist('Flawed')]);

      expect(searchRetryVariants(track), isEmpty);
    });
  });

  group('matchWithQueryVariants', () {
    test('stops at the first query that answers', () async {
      final calls = <String>[];
      final track = _track(isrc: 'INR123456789');

      final results = await SourcedTrack.matchWithQueryVariants(
        track: track,
        search: (query) async {
          calls.add(query.isrc.isNotEmpty ? query.isrc : query.name);
          return [
            _match(id: 'first', title: 'Wassup', artists: ['Flawed'])
          ];
        },
      );

      expect(results, hasLength(1));
      expect(calls, hasLength(1));
    });

    test('escalates through the variants in order until one answers', () async {
      final queries = <SpotubeFullTrackObject>[];
      final track = _track(isrc: 'INR123456789');

      final results = await SourcedTrack.matchWithQueryVariants(
        track: track,
        search: (query) async {
          queries.add(query);
          if (query.artists.length == 1) {
            return [
              _match(
                id: 'KENf509XTjI',
                title: 'Wassup ft. Slay, SIM || Sounds Like Home',
                artists: ['Flawed and 2 more'],
              ),
            ];
          }
          return [];
        },
      );

      expect(queries, hasLength(3));
      expect(queries[0].isrc, 'INR123456789');
      expect(queries[1].isrc, isEmpty);
      expect(queries[2].artists.single.name, 'Flawed');
      expect(results.single.id, 'KENf509XTjI');
    });

    test('a blocked search is never retried or reported as empty', () async {
      final track = _track(isrc: 'INR123456789');
      var calls = 0;

      await expectLater(
        SourcedTrack.matchWithQueryVariants(
          track: track,
          search: (query) async {
            calls++;
            throw Exception('429 too many requests');
          },
        ),
        throwsA(isA<Exception>()),
      );

      // The caller must see the error, not an empty list that would be
      // cached as "this track does not exist" for the TTL.
      expect(calls, 1);
    });

    test('a real miss costs one search per variant, then stays empty',
        () async {
      final track = _track(isrc: 'INR123456789');
      var calls = 0;

      final results = await SourcedTrack.matchWithQueryVariants(
        track: track,
        search: (query) async {
          calls++;
          return [];
        },
      );

      expect(results, isEmpty);
      expect(calls, 1 + searchRetryVariants(track).length);
    });
  });

  group('rankResults', () {
    test('credits the right artist over a title that merely names them', () {
      final track = _track();
      final uploaded = _match(
        id: 'KENf509XTjI',
        title: 'Wassup ft. Slay, SIM || Sounds Like Home',
        artists: ['Flawed and 2 more'],
      );
      final imposter = _match(
        id: 'other',
        title: 'Wassup Flawed Style (Beat Switch)',
        artists: ['Beat Bedouin'],
      );

      final ranked = SourcedTrack.rankResults(
        [imposter, uploaded],
        track,
      );

      // uploaded wins on: exact track name, the "Slay™" needle matched after
      // symbol-stripping, and a channel credit matched case-insensitively
      // through NewPipe's "… and N more" suffix.
      expect(ranked.first.id, 'KENf509XTjI');
    });

    // Candidates below are measured rows from the "Tum Hi Ho Arijit Singh"
    // result page, which is where each of these rules earns its place.
    group('picks the recording over the edits that share its title', () {
      final track = _track(
        name: 'Tum Hi Ho',
        artists: [_artist('Arijit Singh')],
        durationMs: 263000,
      );
      final studio = _match(
        id: 'studio',
        title: 'Tum Hi Ho',
        artists: ['Arijit Singh'],
        seconds: 263,
      );

      test('a slowed + reverb edit with 60M views', () {
        final slowed = _match(
          id: 'slowed',
          title: 'Tum Hi Ho (Slowed + Reverb)',
          artists: ['Vansh Lofi'],
          seconds: 316,
        );

        final ranked = SourcedTrack.rankResults([slowed, studio], track);

        expect(ranked.first.id, 'studio');
      });

      test('an official lyric video, which the old pattern rewarded', () {
        // "(Official Lyric Video)" used to satisfy officialMusicRegex and pick
        // up +1, then +2 more for naming the track: 7 to the recording's 4.
        final lyric = _match(
          id: 'lyric',
          title: 'Tum Hi Ho (Official Lyric Video)',
          artists: ['Arijit Singh'],
          seconds: 262,
        );

        final ranked = SourcedTrack.rankResults([lyric, studio], track);

        expect(ranked.first.id, 'studio');
      });

      test('a live boot that credits the artist correctly', () {
        // This one matches on channel *and* names the artist in the title, so
        // it outscores the recording on text alone: 5 to 4. Only the known
        // length separates them.
        final live = _match(
          id: 'live',
          title: 'TUM HI HO - Arijit Singh | MTV Unplugged Live Performance',
          artists: ['Arijit Singh'],
          seconds: 542,
        );

        final ranked = SourcedTrack.rankResults([live, studio], track);

        expect(ranked.first.id, 'studio');
      });

      test('leaves a near-enough length alone', () {
        // Re-encodes and trailing silence routinely move a few seconds.
        final slight = _match(
          id: 'slight',
          title: 'Tum Hi Ho',
          artists: ['Arijit Singh'],
          seconds: 270,
        );

        final ranked = SourcedTrack.rankResults([slight, studio], track);

        expect(ranked.map((match) => match.id), contains('slight'));
      });
    });
  });
}
