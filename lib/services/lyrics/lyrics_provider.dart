import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/lyrics.dart';

/// A source that can produce synced or plain lyrics for a track.
///
/// Providers are tried in registry order; the first non-empty result wins.
/// This is an in-app extension point (kept inside Spotube rather than the
/// pinned external hetu plugin package) so new lyric sources can be added
/// without touching external code.
abstract interface class LyricsProvider {
  /// Stable identifier for logging and diagnostics.
  String get id;

  /// Attempts to fetch lyrics for [track]. Should throw when the provider
  /// cannot serve this track; the caller isolates failures between
  /// providers so one broken source cannot block the rest.
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track);
}

/// Ordered set of lyric providers. Registration order determines priority:
/// the first registered provider with non-empty results wins. Providers may
/// be added at runtime by inserting into this list (typically at [init]).
final List<LyricsProvider> lyricsProviders = [];