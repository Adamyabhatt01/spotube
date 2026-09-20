import 'dart:async';

import 'package:drift/drift.dart';
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

      final cachedLyrics = await (database.select(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(track.id)))
          .map((row) => row.data)
          .getSingleOrNull();

      SubtitleSimple? lyrics = cachedLyrics;

      if (lyrics == null ||
          lyrics.lyrics.isEmpty) {
        // Only online tracks have provider-backed lyrics; local files have
        // none to fetch. Try each provider in priority order, isolating
        // failures so one broken source cannot prevent later providers.
        if (track is SpotubeFullTrackObject) {
          for (final provider in lyricsProviders) {
            try {
              final candidate = await provider.fetchLyrics(track);
              if (candidate.lyrics.isNotEmpty) {
                lyrics = candidate;
                break;
              }
            } catch (e, stackTrace) {
              AppLogger.reportError(
                e,
                stackTrace,
                'lyrics provider ${provider.id}',
              );
            }
          }
        }
      }

      if (lyrics == null || lyrics.lyrics.isEmpty) {
        throw Exception("Unable to find lyrics");
      }

      if (cachedLyrics == null || cachedLyrics.lyrics.isEmpty) {
        await database.into(database.lyricsTable).insert(
              LyricsTableCompanion.insert(
                trackId: track.id,
                data: lyrics,
              ),
              mode: InsertMode.replace,
            );
      }

      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      rethrow;
    }
  }
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(
  () => SyncedLyricsNotifier(),
);
