import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/lyrics/better_lyrics_provider.dart';
import 'package:spotube/services/lyrics/lrclib_provider.dart';
import 'package:spotube/services/lyrics/lyrics_provider.dart';

/// Built-in lyric sources, in priority order.
///
/// A provider (rather than a mutable services-side registry) so the chain is
/// scoped to the container: tests override it instead of clearing and
/// repopulating process-wide state, and app startup no longer has to register
/// anything.
final lyricsProvidersProvider = Provider<List<LyricsProvider>>(
  (ref) => [
    LRCLibLyricsProvider(),
    BetterLyricsLyricsProvider(),
  ],
);

/// Resolutions currently running, keyed by track id.
///
/// Two family instances for the same track (different track objects, same id)
/// share one fetch instead of doubling the provider chain. Entries remove
/// themselves on completion, so the map holds only live work.
final Map<String, Future<SubtitleSimple>> _lyricsInFlight = {};

/// Tracks whose providers all missed recently, mapped to when the miss was
/// recorded. A miss is stable ("no lyrics" rarely becomes lyrics), so a
/// revisit within [_lyricsMissTtl] skips the whole provider chain — the way
/// HTTP clients cache 404s. Bounded; the oldest entry goes first.
final Map<String, DateTime> _lyricsMisses = {};

/// How long a recorded miss suppresses refetching.
const _lyricsMissTtl = Duration(hours: 24);

/// Cap on remembered misses, so pathological browsing cannot grow the map
/// without bound.
const _maxLyricsMisses = 200;

@visibleForTesting
bool isFreshLyricsMiss(String trackId) {
  final recordedAt = _lyricsMisses[trackId];
  if (recordedAt == null) return false;
  if (DateTime.now().difference(recordedAt) > _lyricsMissTtl) {
    _lyricsMisses.remove(trackId);
    return false;
  }
  return true;
}

void _recordLyricsMiss(String trackId) {
  _lyricsMisses[trackId] = DateTime.now();
  while (_lyricsMisses.length > _maxLyricsMisses) {
    _lyricsMisses.remove(_lyricsMisses.keys.first);
  }
}

/// Clears the miss and in-flight maps. Test-only: static lyric state would
/// otherwise leak between cases.
@visibleForTesting
void clearLyricsFetchState() {
  _lyricsMisses.clear();
  _lyricsInFlight.clear();
}

/// Wall-clock ceiling for the whole provider cascade (all providers
/// combined). Each provider already bounds its own HTTP (LRCLib 10 s receive,
/// Better Lyrics 8 s, both on globalDio 15 s connect): two sequential misses
/// on a degraded network could otherwise block the lyrics build for ~60 s.
/// 30 s never fires on a healthy network (each provider answers in ~1 s) and
/// on timeout the held plain fallback still wins over a miss.
const lyricsCascadeBudget = Duration(seconds: 30);

/// Expected "this track has no lyrics" outcome, as opposed to a provider
/// failure. The UI renders both as the no-lyrics state, but only a real
/// failure deserves a stack trace in the on-device log: instrumentals and
/// local files are the common case, not an error.
class LyricsUnavailableException implements Exception {
  final String message;

  const LyricsUnavailableException([this.message = "Unable to find lyrics"]);

  @override
  String toString() => message;
}

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  @override
  FutureOr<SubtitleSimple> build(track) {
    if (track == null) return _load(null);
    final running = _lyricsInFlight[track.id];
    if (running != null) return running;
    final future = _load(track);
    _lyricsInFlight[track.id] = future;
    _releaseWhenDone(track.id, future);
    return future;
  }

  /// Removes a finished resolution from [_lyricsInFlight].
  ///
  /// Both handlers swallow (the entry removal is the whole result), so this
  /// telemetric future always completes cleanly: a `whenComplete` here would
  /// rethrow a failed resolution into an unobserved future and surface it as
  /// an unhandled zone error.
  void _releaseWhenDone(String trackId, Future<SubtitleSimple> future) {
    future.then(
      (_) {
        if (identical(_lyricsInFlight[trackId], future)) {
          _lyricsInFlight.remove(trackId);
        }
      },
      onError: (_) {
        if (identical(_lyricsInFlight[trackId], future)) {
          _lyricsInFlight.remove(trackId);
        }
      },
    );
  }

  Future<SubtitleSimple> _load(SpotubeTrackObject? track) async {
    try {
      final database = ref.watch(databaseProvider);

      if (track == null) {
        throw const LyricsUnavailableException("No track currently");
      }

      // `trackId` has no unique index (the primary key is an autoincrement
      // id), so a track can legitimately have several rows. Read them all and
      // keep the best: getSingleOrNull() throws on the second row, which used
      // to break that track's lyrics permanently.
      final rows = await (database.select(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(track.id)))
          .get();
      final cached = _bestCachedRow(rows);

      // A cached row only counts if it says something. Blank answers used to
      // be stored and then treated as a hit forever.
      final fromCache = cached != null && cached.hasContent ? cached : null;
      var lyrics = fromCache;

      // A recent miss short-circuits the whole chain: no provider, no HTTP.
      if (lyrics == null &&
          track is SpotubeFullTrackObject &&
          isFreshLyricsMiss(track.id)) {
        throw const LyricsUnavailableException();
      }

      if (lyrics == null && track is SpotubeFullTrackObject) {
        // Only online tracks have provider-backed lyrics; local files have
        // none to fetch. Try each provider in priority order, isolating
        // failures so one broken source cannot prevent later providers.
        // The whole cascade races a single budget so two sequential stalls
        // cannot block the build for a minute.
        SubtitleSimple? plainFallback;
        SubtitleSimple? syncedWinner;
        final providers = ref.read(lyricsProvidersProvider);
        try {
          syncedWinner = await (() async {
            for (final provider in providers) {
              try {
                final candidate = await provider.fetchLyrics(track);
                if (!candidate.hasContent) continue;
                if (candidate.isSynced) return candidate;
                // Timestamps beat no timestamps, so an unsynced answer is
                // held while the remaining providers get a chance to beat it.
                plainFallback ??= candidate;
              } catch (e, stackTrace) {
                AppLogger.reportError(
                  e,
                  stackTrace,
                  'lyrics provider ${provider.id}',
                );
              }
            }
            return null;
          })().timeout(lyricsCascadeBudget);
        } on TimeoutException catch (e, stackTrace) {
          AppLogger.reportError(
            e,
            stackTrace,
            'lyrics cascade budget $lyricsCascadeBudget',
          );
        }
        lyrics = syncedWinner ?? plainFallback;
      }

      if (lyrics == null || !lyrics.hasContent) {
        // Reachable only for a real track (a null track throws above), so
        // the miss is always attributable to this id.
        _recordLyricsMiss(track.id);
        throw const LyricsUnavailableException();
      }

      final shouldWrite =
          fromCache == null || (lyrics.hasContent && lyrics.isSynced);
      if (shouldWrite) {
        // Replace rather than append, so a track never accumulates rows that
        // the read above then has to arbitrate between. One transaction, so a
        // kill between the two statements can never leave the track with no
        // cached lyrics at all (the blob is re-fetched instead of lost).
        final toCache = lyrics;
        await database.transaction(() async {
          await (database.delete(database.lyricsTable)
                ..where((tbl) => tbl.trackId.equals(track.id)))
              .go();
          await database.into(database.lyricsTable).insert(
                LyricsTableCompanion.insert(
                  trackId: track.id,
                  data: toCache,
                ),
              );
        });
      }

      return lyrics;
    } catch (e, stackTrace) {
      // A miss is an expected answer. Reporting it writes a full stack trace
      // to the Android log file for every instrumental/local track; the UI
      // already renders the dedicated no-lyrics state from the AsyncError.
      if (e is! LyricsUnavailableException) {
        AppLogger.reportError(e, stackTrace);
      }
      rethrow;
    }
  }

  /// Newest row that has readable text, preferring one with real timestamps;
  /// falling back to the newest row at all so an empty cache still reads as
  /// empty rather than missing.
  SubtitleSimple? _bestCachedRow(List<LyricsTableData> rows) {
    if (rows.isEmpty) return null;

    final sorted = [...rows]..sort((a, b) => b.id.compareTo(a.id));
    SubtitleSimple? best;
    int bestScore(SubtitleSimple? s) {
      if (s == null) return -1;
      return (s.hasContent ? 2 : 0) + (s.isSynced ? 1 : 0);
    }

    for (final row in sorted) {
      if (bestScore(row.data) > bestScore(best)) best = row.data;
    }
    return best;
  }
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(
  () => SyncedLyricsNotifier(),
);
