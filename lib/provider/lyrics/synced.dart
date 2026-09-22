import 'dart:async';

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

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  @override
  FutureOr<SubtitleSimple> build(track) async {
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
