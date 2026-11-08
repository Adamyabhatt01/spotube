// Search-quality regression for the Android streaming path.
//
// NewPipe queried YouTube's general `videos` page and got the wrong thing in
// two ways the old behaviour cannot fix by reordering: the page for
// "Tum Hi Ho Arijit Singh" put a Hindi-title lyric recap (505M views) ahead of
// the studio recording, and a "Slowed + Reverb" edit with 60M views sat on the
// same page as the song. YouTube's `music_songs` category answers both pages
// with the recording first.
//
// Fixtures below are real rows captured 2026-09-22 from the app's own bundled
// NewPipeCLI for `--search "Tum Hi Ho Arijit Singh"` under each filter.
//
// Locked here: which category gets queried, how many queries a track may cost,
// the tier ordering when a page does not answer the query, the ISRC trap, and
// the degradation rules when a page throws.

import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart'
    as np;
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';

/// A measured row from the `music_songs` page: the recording itself, on a
/// channel NewPipe reports as *unverified*.
np.VideoSearchResultItem _songRow({
  String id = 'BjL7AuPsmEk',
  String name = 'Tum Hi Ho',
  String uploader = 'Arijit Singh',
  int duration = 263,
}) {
  return np.VideoSearchResultItem(
    infoType: np.SearchResultType.video,
    url: 'https://www.youtube.com/watch?v=$id',
    name: name,
    thumbnails: const [],
    streamType: np.StreamInfoType.videoStream,
    uploaderName: uploader,
    uploaderUrl: 'https://www.youtube.com/channel/UCtFOW7jJXChfFNoucRFqRmw',
    uploaderAvatars: const [],
    uploaderVerified: false,
    shortFormContent: false,
    uploadDate: null,
    viewCount: 330272,
    duration: duration,
  );
}

/// A measured row from the `videos` page. [verified] is settable because
/// verification is the signal this change deliberately does *not* trust:
/// T-Series is verified and topped the page with a lyric recap, while the
/// studio channels answering `music_songs` are not verified at all.
np.VideoSearchResultItem _videoRow({
  required String id,
  required String name,
  required String uploader,
  int duration = 263,
  bool verified = false,
  bool shortForm = false,
  np.StreamInfoType streamType = np.StreamInfoType.videoStream,
}) {
  return np.VideoSearchResultItem(
    infoType: np.SearchResultType.video,
    url: 'https://www.youtube.com/watch?v=$id',
    name: name,
    thumbnails: const [],
    streamType: streamType,
    uploaderName: uploader,
    uploaderUrl: 'https://www.youtube.com/channel/UCq-Fj5jknLsUf-MWSy4_brA',
    uploaderAvatars: const [],
    uploaderVerified: verified,
    shortFormContent: shortForm,
    uploadDate: null,
    viewCount: 1000000,
    duration: duration,
  );
}

class _FakeSearch {
  _FakeSearch(this.pages);

  /// Category label -> rows to return, or an `Exception` to throw.
  final Map<String, Object> pages;
  final calls = <String>[];

  Future<List<np.SearchResultItem>> call(
    String query,
    List<np.SearchContentFilters> contentFilters,
  ) async {
    final key = contentFilters.map((filter) => filter.label).join(',');
    calls.add(key);
    final page = pages[key];
    if (page == null) return const [];
    if (page is Exception) throw page;
    return (page as List).cast<np.SearchResultItem>();
  }
}

const songsKey = 'music_songs';
const videosKey = 'videos';

/// The measured `music_songs` page for "Tum Hi Ho Arijit Singh".
final _songsPage = [
  _songRow(),
  _songRow(id: 'Ym4ukuweBOg', duration: 605),
  _songRow(id: 'other-song', name: 'Meri Aashiqui', uploader: 'Palak Muchhal'),
];

/// The measured `videos` page for the same query, in page order.
final _videosPage = [
  _videoRow(
    id: 'Umqb9KENgmk',
    name: 'तुम ही हो आशिकी 2 पूरा गाना बोल के साथ',
    uploader: 'T-Series',
    duration: 268,
    verified: true,
  ),
  _videoRow(
    id: 'BjL7AuPsmEk',
    name: 'Tum Hi Ho',
    uploader: 'Arijit Singh',
    verified: true,
  ),
  _videoRow(
    id: 'HLW8DepLaEg',
    name: 'Tum Hi Ho (Slowed + Reverb)',
    uploader: 'Vansh Lofi',
    duration: 316,
  ),
  _videoRow(
    id: 'CvQl4kgKKAc',
    name: 'TUM HI HO - Arijit Singh | MTV Unplugged Live Performance',
    uploader: 'Rajgoyal',
    duration: 542,
    streamType: np.StreamInfoType.liveStream,
  ),
];

void main() {
  group('NewPipeEngine.searchVideos category choice', () {
    test('queries the songs category and stops there when it answered',
        () async {
      final search =
          _FakeSearch({songsKey: _songsPage, videosKey: _videosPage});

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('Tum Hi Ho Arijit Singh');

      // One query, not two: the songs page matched the query's own words.
      expect(search.calls, [songsKey]);
      expect(results.first.id, 'BjL7AuPsmEk');
      expect(results.first.title, 'Tum Hi Ho');
    });

    test('a two-token query is satisfied by a single shared token', () async {
      // "Wassup Flawed" is `<title> <artist>`, and the artist name appears in
      // no video title, so demanding two matches here would fall back on every
      // short query.
      final search = _FakeSearch({
        songsKey: [
          _songRow(
              id: 'sKHv6S1y_j0',
              name: 'Wassup',
              uploader: 'Flawed',
              duration: 221)
        ],
      });

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('Wassup Flawed');

      expect(search.calls, [songsKey]);
      expect(results.single.id, 'sKHv6S1y_j0');
    });

    test('falls back to the videos category when the songs page is unrelated',
        () async {
      // Measured: an ISRC-shaped query answers 11-20 unrelated songs here.
      final search = _FakeSearch({
        songsKey: [
          _songRow(id: 'rush', name: 'Rush E', uploader: 'Dreaming Piano'),
          _songRow(id: 'aadmi', name: 'Aadmi Chutiya Hai', uploader: 'Rahgir'),
        ],
        videosKey: _videosPage,
      });

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('Tum Hi Ho Arijit Singh');

      expect(search.calls, [songsKey, videosKey]);
      // The unrelated songs page is the weaker tier and is placed as such: its
      // rows land behind everything the videos page actually answered, rather
      // than leading just because of which category they came from.
      final ids = results.map((row) => row.id).toList();
      expect(ids.first, 'BjL7AuPsmEk');
      expect(ids.indexOf('rush'), greaterThan(ids.indexOf('HLW8DepLaEg')));
    });

    test('an empty songs page still gets the videos page', () async {
      final search = _FakeSearch({songsKey: [], videosKey: _videosPage});

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('Tum Hi Ho Arijit Singh');

      expect(search.calls, [songsKey, videosKey]);
      expect(results, isNotEmpty);
    });

    test('an ISRC query never touches the songs category', () async {
      // The plugin searches track.isrc before any text query. YouTube treats
      // an ISRC as prose, so the songs category returns a confident page of
      // junk while the videos category correctly returns nothing - and only a
      // clean empty answer lets the variant ladder reach the text query.
      final search = _FakeSearch({videosKey: []});

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('USR631305109');

      expect(search.calls, [videosKey]);
      expect(results, isEmpty);
    });

    test('a hyphenated code is not treated as an ISRC', () async {
      final search = _FakeSearch({videosKey: []});

      await NewPipeEngine(search: search.call, init: () async {})
          .searchVideos('IN-UMO-13-00720');

      // 12 alphanumeric characters is the shape the plugin sends; punctuation
      // is not an ISRC, so this stays a text query and keeps its songs tier.
      expect(search.calls, [songsKey, videosKey]);
    });
  });

  group('NewPipeEngine.searchVideos degradation', () {
    test('a throwing songs page falls back to the videos page', () async {
      final search = _FakeSearch({
        songsKey: Exception('channel row blew up the page decode'),
        videosKey: _videosPage,
      });

      final results =
          await NewPipeEngine(search: search.call, init: () async {})
              .searchVideos('Tum Hi Ho Arijit Singh');

      expect(search.calls, [songsKey, videosKey]);
      expect(results, isNotEmpty);
    });

    test('a throwing videos page propagates instead of reporting a miss',
        () async {
      // A blocked search must never be cached as "this track does not exist".
      final search = _FakeSearch({
        songsKey: [],
        videosKey: Exception('429 too many requests'),
      });

      await expectLater(
        NewPipeEngine(search: search.call, init: () async {})
            .searchVideos('Tum Hi Ho Arijit Singh'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('NewPipeEngine.orderTiers', () {
    test('a row carried by both tiers appears once, in songs position', () {
      final ordered = NewPipeEngine.orderTiers(
        query: 'Tum Hi Ho Arijit Singh',
        songs:
            _songsPage.map(NewPipeEngine.parseSearchResult).nonNulls.toList(),
        videos:
            _videosPage.map(NewPipeEngine.parseSearchResult).nonNulls.toList(),
      );

      expect(ordered.map((row) => row.id).toSet(), hasLength(ordered.length));
      expect(ordered.first.id, 'BjL7AuPsmEk');
    });

    test('live, short and length-less rows survive but sort last', () {
      final videos = [
        _videoRow(
          id: 'live',
          name: 'Tum Hi Ho Live',
          uploader: 'Arijit Singh',
          streamType: np.StreamInfoType.liveStream,
        ),
        _videoRow(
          id: 'normal',
          name: 'Tum Hi Ho',
          uploader: 'Arijit Singh',
        ),
        _videoRow(
          id: 'short',
          name: 'Tum Hi Ho clip',
          uploader: 'Fan',
          shortForm: true,
        ),
        _videoRow(
          id: 'nodoc',
          name: 'Tum Hi Ho unknown length',
          uploader: 'Arijit Singh',
          duration: -1,
        ),
      ].map(NewPipeEngine.parseSearchResult).nonNulls.toList();

      final ordered = NewPipeEngine.orderTiers(
        query: 'Tum Hi Ho Arijit Singh',
        songs: const [],
        videos: videos,
      );

      expect(
          ordered.map((row) => row.id), ['normal', 'nodoc', 'live', 'short']);
    });

    test('an unparseable row is dropped without costing the page', () {
      final videos = [
        _videoRow(id: 'ok', name: 'Tum Hi Ho', uploader: 'Arijit Singh'),
        np.VideoSearchResultItem(
          infoType: np.SearchResultType.video,
          url: 'https://www.youtube.com/nullplayer',
          name: 'no watch id',
          thumbnails: const [],
          streamType: np.StreamInfoType.videoStream,
          uploaderName: 'Someone',
          uploaderUrl: '',
          uploaderAvatars: const [],
          uploaderVerified: false,
          shortFormContent: false,
          uploadDate: null,
          viewCount: 0,
          duration: 100,
        ),
      ].map(NewPipeEngine.parseSearchResult).nonNulls.toList();

      expect(videos, hasLength(1));
    });
  });

  group('NewPipeEngine.parseSearchResult extras', () {
    test('carries the short-form flag', () {
      final row = NewPipeEngine.parseSearchResult(
        _videoRow(id: 's', name: 'Tum Hi Ho', uploader: 'x', shortForm: true),
      );

      expect(row!.isShortForm, isTrue);
    });

    test('an unknown duration stays unknown, never a negative length', () {
      final row = NewPipeEngine.parseSearchResult(
        _videoRow(id: 'd', name: 'Tum Hi Ho', uploader: 'x', duration: -1),
      );

      expect(row!.duration, isNull);
    });
  });
}
