import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/dio/dio.dart';

import 'lyrics_provider.dart';

/// Parses an Apple Music (Better Lyrics) TTML timestamp into a [Duration].
///
/// Accepts both `ss.mmm` and `m:ss.mmm` forms. Returns `null` for anything
/// else so callers can skip unparseable lines.
Duration? parseTtmlTimestamp(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return null;

  final parts = normalized.split(":");
  double totalSeconds;
  if (parts.length == 1) {
    final seconds = double.tryParse(parts[0]);
    if (seconds == null) return null;
    totalSeconds = seconds;
  } else if (parts.length == 2) {
    final minutes = int.tryParse(parts[0]);
    final seconds = double.tryParse(parts[1]);
    if (minutes == null || seconds == null) return null;
    totalSeconds = minutes * 60 + seconds;
  } else {
    return null;
  }

  if (totalSeconds < 0) return null;
  return Duration(milliseconds: (totalSeconds * 1000).round());
}

final _ttmlLinePattern = RegExp(
  r'<p\b[^>]*begin="([^"]+)"[^>]*>(.*?)</p>',
  dotAll: true,
);

final _tagPattern = RegExp(r'<[^>]+>');
final _whitespacePattern = RegExp(r'\s+');

/// Parses a Better Lyrics TTML document into timed lyric lines.
///
/// Each `<p begin="...">text</p>` becomes one [LyricSlice] whose time is the
/// line's `begin` timestamp. For word-timed documents the inner `<span>`
/// elements are collapsed into the visible line text (one highlight per line,
/// consistent with the rest of the app). Lines without a parseable timestamp
/// or visible text are skipped.
List<LyricSlice> parseBetterLyricsTtml(String ttml) {
  final slices = <LyricSlice>[];

  for (final match in _ttmlLinePattern.allMatches(ttml)) {
    final time = parseTtmlTimestamp(match.group(1)!);
    if (time == null) continue;

    final rawText = match.group(2)!;
    final text = rawText
        .replaceAll(_tagPattern, '')
        .replaceAll(_whitespacePattern, ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .trim();

    if (text.isEmpty) continue;

    slices.add(LyricSlice(time: time, text: text));
  }

  return slices;
}

/// Same threshold rule as the LRCLib side: small documents parse inline,
/// large ones go through [compute] so a pathological document cannot jank
/// the UI thread.
const _isolateParseThresholdBytes = 16384;

/// Parses a Better Lyrics TTML document, off the calling isolate when it is
/// large enough for the parse to matter. Small documents parse inline.
Future<List<LyricSlice>> parseTtmlDocument(String ttml) {
  if (ttml.length < _isolateParseThresholdBytes) {
    return Future.value(parseBetterLyricsTtml(ttml));
  }
  return compute(parseBetterLyricsTtml, ttml);
}

/// Better Lyrics lyrics source.
///
/// Hits the public Better Lyrics API
/// ([lyrics-api.boidu.dev](https://lyrics-api.boidu.dev)) which returns Apple
/// Music synchronized lyrics as TTML. Positioned as a fallback after LRCLib
/// because the maintainer deliberately limits the public endpoints; this
/// provider is only consulted when earlier providers miss, and sends a
/// descriptive User-Agent rather than hammering the service.
///
/// Lyrics credits: [Better Lyrics](https://better-lyrics.boidu.dev) and their
/// contributors.
class BetterLyricsLyricsProvider implements LyricsProvider {
  @override
  String get id => "Better Lyrics";

  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    final userAgent = await lyricsUserAgent();

    final res = await globalDio.getUri(
      Uri(
        scheme: "https",
        host: "lyrics-api.boidu.dev",
        path: "/getLyrics",
        queryParameters: {
          "a": track.artists.isNotEmpty ? track.artists.first.name : "",
          "s": track.name,
        },
      ),
      options: Options(
        headers: {"User-Agent": userAgent},
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 8),
        // The public endpoint answers 401 ("uncached queries require a valid
        // API key") for anything it has not already served. That is a miss to
        // report, not an exception to log with a stack trace.
        validateStatus: (_) => true,
      ),
    );

    if (res.statusCode != 200) {
      return _empty(track, res.realUri);
    }

    final json = res.data;
    final ttml = json is Map<String, dynamic> ? json["ttml"] as String? : null;
    if (ttml == null || ttml.trim().isEmpty) return _empty(track, res.realUri);

    final lyrics = await parseTtmlDocument(ttml);
    if (lyrics.isEmpty) return _empty(track, res.realUri);

    return SubtitleSimple(
      lyrics: lyrics,
      name: track.name,
      uri: res.realUri,
      rating: 100,
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