import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/lyrics.dart';

/// A source that can produce synced or plain lyrics for a track.
///
/// Providers are tried in registry order; the first result with readable text
/// wins, and an unsynced answer is only kept if no later provider can put
/// timestamps on it. This is an in-app extension point (kept inside Spotube
/// rather than the pinned external hetu plugin package) so new lyric sources
/// can be added without touching external code.
abstract interface class LyricsProvider {
  /// Stable identifier for logging and diagnostics.
  String get id;

  /// Attempts to fetch lyrics for [track]. Returning an answer with no
  /// readable text is how a provider reports a miss; throwing is reserved for
  /// a source that cannot serve the track at all. The caller isolates both so
  /// one broken source cannot block the rest.
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track);
}

/// Ordered set of lyric providers. Registration order determines priority
/// within the rules above. Providers may be added at runtime by inserting into
/// this list (typically at [init]).
final List<LyricsProvider> lyricsProviders = [];