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

/// Registers built-in lyric providers. Called at app startup (idempotent).
void registerLyricsProviders() {
  if (lyricsProviders.isNotEmpty) return;
  lyricsProviders.add(LRCLibLyricsProvider());
  lyricsProviders.add(BetterLyricsLyricsProvider());
}

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
/// otherwise leak between cases the way the provider registry already guards
/// against with `lyricsProviders.clear()`.
@visibleForTesting
void clearLyricsFetchState() {
  _lyricsMisses.clear();
  _lyricsInFlight.clear();
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
        throw "No track currently";
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
        throw Exception("Unable to find lyrics");
      }

      if (lyrics == null && track is SpotubeFullTrackObject) {
        // Only online tracks have provider-backed lyrics; local files have
        // none to fetch. Try each provider in priority order, isolating
        // failures so one broken source cannot prevent later providers.
        SubtitleSimple? plainFallback;
        for (final provider in lyricsProviders) {
          try {
            final candidate = await provider.fetchLyrics(track);
            if (!candidate.hasContent) continue;
            if (candidate.isSynced) {
              lyrics = candidate;
              break;
            }
            // Timestamps beat no timestamps, so an unsynced answer is held
            // while the remaining providers get a chance to beat it.
            plainFallback ??= candidate;
          } catch (e, stackTrace) {
            AppLogger.reportError(
              e,
              stackTrace,
              'lyrics provider ${provider.id}',
            );
          }
        }
        lyrics ??= plainFallback;
      }

      if (lyrics == null || !lyrics.hasContent) {
        // Reachable only for a real track (a null track throws above), so
        // the miss is always attributable to this id.
        _recordLyricsMiss(track.id);
        throw Exception("Unable to find lyrics");
      }

      if (fromCache == null) {
        // Replace rather than append, so a track never accumulates rows that
        // the read above then has to arbitrate between.
        await (database.delete(database.lyricsTable)
              ..where((tbl) => tbl.trackId.equals(track.id)))
            .go();
        await database.into(database.lyricsTable).insert(
              LyricsTableCompanion.insert(
                trackId: track.id,
                data: lyrics,
              ),
            );
      }

      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
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
