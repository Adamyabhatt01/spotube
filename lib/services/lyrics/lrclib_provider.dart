import 'package:dio/dio.dart';
import 'package:lrc/lrc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/dio/dio.dart';

import 'lyrics_provider.dart';

bool _hasText(String? raw) => raw != null && raw.trim().isNotEmpty;

List<LyricSlice>? _parseSynced(String raw) {
  try {
    final lines = Lrc.parse(raw).lyrics.map(LyricSlice.fromLrcLine).toList();
    return lines.isEmpty ? null : lines;
  } on FormatException {
    // A malformed timestamp in an otherwise usable document should not cost
    // the whole answer; the plain text of the same entry is still readable.
    return null;
  }
}

/// Picks the best LRCLib entry among [entries] for one track.
///
/// `/api/get` is an exact-match lookup and LRCLib's own artist strings do not
/// agree with Spotify's ("Hardbone boy,SINASH" against "Hardbone boy, SINASH"),
/// so the fuzzy `/api/search` list is ranked here instead: timed lyrics beat
/// plain ones, an album-name agreement breaks ties, and an entry whose length
/// is nowhere near the track's is dropped.
Map<String, dynamic>? selectLrclibEntry(
  List<dynamic> entries, {
  required String albumName,
  required int durationMs,
}) {
  Map<String, dynamic>? best;
  var bestScore = 0;

  for (final entry in entries) {
    if (entry is! Map) continue;
    final candidate = Map<String, dynamic>.from(entry);

    var score = _hasText(candidate['syncedLyrics'] as String?)
        ? 8
        : _hasText(candidate['plainLyrics'] as String?)
            ? 4
            : 0;
    if (score == 0) continue;

    if (albumName.trim().isNotEmpty &&
        (candidate['albumName'] as String? ?? '')
            .trim()
            .toLowerCase()
            .contains(albumName.trim().toLowerCase())) {
      score += 2;
    }

    final entrySeconds = candidate['duration'];
    if (durationMs > 0 && entrySeconds is num) {
      final drift = (entrySeconds - durationMs / 1000).abs();
      if (drift <= 3) {
        score += 2;
      } else if (drift > 30) {
        continue;
      } else if (drift <= 10) {
        score += 1;
      }
    }

    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }

  return best;
}

/// LRCLib lyrics source.
///
/// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors.
class LRCLibLyricsProvider implements LyricsProvider {
  @override
  String get id => "LRCLib";

  Uri _endpoint(String path, Map<String, String> query) {
    return Uri(
      scheme: "https",
      host: "lrclib.net",
      path: "/$path",
      queryParameters: query,
    );
  }

  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    final packageInfo = await PackageInfo.fromPlatform();

    // A miss is an answer, not a crash: lrclib 404s everything its exact
    // match does not recognise and 503s when it is loaded, and both are
    // reasons to try its search endpoint rather than to give up.
    final options = Options(
      headers: {
        "User-Agent":
            "Spotube v${packageInfo.version} (https://github.com/KRTirtho/spotube)"
      },
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    );

    final firstArtist =
        track.artists.isNotEmpty ? track.artists.first.name : "";

    final getRes = await globalDio.getUri(
      _endpoint("api/get", {
        "artist_name": firstArtist,
        "track_name": track.name,
        // Sent only when known: an empty value is a literal filter, and an
        // unknown album name would then have to match "" upstream.
        if (track.album.name.trim().isNotEmpty) "album_name": track.album.name,
        if (track.durationMs > 0)
          "duration": (track.durationMs / 1000).toInt().toString(),
      }),
      options: options,
    );

    var entry = getRes.statusCode == 200 && getRes.data is Map
        ? Map<String, dynamic>.from(getRes.data as Map)
        : null;
    var uri = getRes.realUri;

    if (entry == null ||
        (!_hasText(entry['syncedLyrics'] as String?) &&
            !_hasText(entry['plainLyrics'] as String?))) {
      final searchRes = await globalDio.getUri(
        _endpoint("api/search", {
          "artist_name": firstArtist,
          "track_name": track.name,
        }),
        options: options,
      );

      final data = searchRes.data;
      final found = data is List
          ? selectLrclibEntry(
              data,
              albumName: track.album.name,
              durationMs: track.durationMs,
            )
          : null;
      if (found != null) {
        entry = found;
        uri = searchRes.realUri;
      }
    }

    if (entry == null) {
      return _empty(track, uri);
    }

    final synced = _parseSynced(entry['syncedLyrics'] as String? ?? "");
    if (synced != null) {
      return SubtitleSimple(
        lyrics: synced,
        name: track.name,
        uri: uri,
        rating: 100,
        provider: id,
      );
    }

    final plain = (entry['plainLyrics'] as String? ?? "")
        .split("\n")
        .map((line) => LyricSlice(text: line, time: Duration.zero))
        .toList();

    return SubtitleSimple(
      lyrics: plain,
      name: track.name,
      uri: uri,
      rating: 0,
      provider: id,
    );
  }

  SubtitleSimple _empty(SpotubeFullTrackObject track, Uri uri) {
    return SubtitleSimple(
      lyrics: [],
      name: track.name,
      uri: uri,
      rating: 0,
      provider: id,
    );
  }
}
