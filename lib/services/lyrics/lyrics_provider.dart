import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

/// Reads the app version for lyric-provider User-Agent headers.
///
/// A process-wide memo: the version is a constant, but every provider used to
/// pay its own `PackageInfo.fromPlatform()` platform-channel round trip per
/// track (two per uncached track once LRCLib missed into Better Lyrics).
/// Browsers cache their UA string for the same reason; so do we.
Future<String> Function() _userAgentReader = _readUserAgent;
Future<String>? _memoizedUserAgent;

/// Descriptive User-Agent shared by all lyric providers, read once per
/// process. Test seam: [debugOverrideLyricsUserAgent] swaps the reader.
Future<String> lyricsUserAgent() => _memoizedUserAgent ??= _userAgentReader();

Future<String> _readUserAgent() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return "Spotube v${packageInfo.version} "
      "(https://github.com/KRTirtho/spotube)";
}

@visibleForTesting
void debugOverrideLyricsUserAgent(Future<String> Function()? reader) {
  _userAgentReader = reader ?? _readUserAgent;
  _memoizedUserAgent = null;
}