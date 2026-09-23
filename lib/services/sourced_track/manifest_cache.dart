import 'package:flutter/foundation.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// An extracted manifest (stream URLs) plus the instant it stops being
/// servable: the earliest `expire` across its URLs (see
/// [manifestMinExpireSeconds]). Entries with unknown expiry are never
/// stored — see below.
class CachedManifest {
  const CachedManifest({
    required this.sources,
    required this.minExpireSeconds,
  });

  final List<SpotubeAudioSourceStreamObject> sources;

  /// Always a known-positive unix timestamp. Servable while
  /// `minExpireSeconds > nowSeconds` (strict, mirroring
  /// [isStreamUrlExpired]); at or past it the entry is a miss.
  final int minExpireSeconds;
}

/// In-memory LRU of extracted manifests, keyed
/// `$trackId|$sourceSlug|$matchId`.
///
/// Why this is safe: extraction is deterministic per (match, engine) — the
/// same inputs produce the same signed URLs — and an entry is servable only
/// while every URL in it is unexpired. What it does NOT do:
/// - it never serves past expiry (strict `>` check on every lookup);
/// - it never stores manifests with unknown expiry (those engines' URLs
///   cannot be reasoned about, so they keep today's re-extract behavior);
/// - it never stores failed extractions (only callers with a successful
///   result store);
/// - it never replaces validation: the refresh path (`refreshStream`,
///   expiry/failure reactive handling) is untouched and still the only
///   thing that can bless a dead URL back to life.
///
/// Eviction only costs a re-extraction, never correctness, so the cap is a
/// memory bound, not a correctness parameter.
class ManifestCache {
  ManifestCache({this.maxEntries = 32});

  final int maxEntries;

  final Map<String, CachedManifest> _entries = {};

  @visibleForTesting
  int get length => _entries.length;

  static String cacheKey({
    required String trackId,
    required String sourceSlug,
    required String matchId,
  }) =>
      '$trackId|$sourceSlug|$matchId';

  /// The cached manifest, or null on any miss: unknown key, expired horizon,
  /// or (defensively) an empty source list. A hit refreshes LRU position.
  List<SpotubeAudioSourceStreamObject>? lookup({
    required String trackId,
    required String sourceSlug,
    required String matchId,
    required DateTime now,
  }) {
    final key = cacheKey(
      trackId: trackId,
      sourceSlug: sourceSlug,
      matchId: matchId,
    );
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.sources.isEmpty) return null;
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    if (entry.minExpireSeconds <= nowSeconds) return null;
    _entries[key] = entry;
    return entry.sources;
  }

  /// Records a successful extraction. Callers must have computed
  /// [minExpireSeconds] via [manifestMinExpireSeconds] and must not call
  /// this when it is null (unknown expiry → keep re-extracting).
  void store({
    required String trackId,
    required String sourceSlug,
    required String matchId,
    required List<SpotubeAudioSourceStreamObject> sources,
    required int minExpireSeconds,
  }) {
    if (sources.isEmpty) return;
    final key = cacheKey(
      trackId: trackId,
      sourceSlug: sourceSlug,
      matchId: matchId,
    );
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = CachedManifest(
      sources: sources,
      minExpireSeconds: minExpireSeconds,
    );
  }

  @visibleForTesting
  void clear() => _entries.clear();
}

/// The process-wide manifest cache. Keyed per track+source+match with
/// strict expiry, so entries cannot leak across tracks, engines or plugin
/// switches; bounded so a long session cannot accumulate manifests.
final manifestCache = ManifestCache();
