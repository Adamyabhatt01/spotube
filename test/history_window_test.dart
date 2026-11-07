import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/albums.dart';
import 'package:spotube/provider/history/top/playlists.dart';

import 'support/perf_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('history window', () {
    test('uses calendar boundaries shared by every stats family', () {
      final now = DateTime.now();

      expect(
          historyWindowStart(HistoryDuration.days7).weekday, DateTime.monday);
      expect(historyWindowStart(HistoryDuration.days7).hour, 0);
      expect(
        historyWindowStart(HistoryDuration.days30),
        DateTime(now.year, now.month),
      );
      expect(
        historyWindowStart(HistoryDuration.months6),
        DateTime(now.year, now.month - 5),
      );
      expect(historyWindowStart(HistoryDuration.year), DateTime(now.year));
      expect(
        historyWindowStart(HistoryDuration.years2),
        DateTime(now.year - 1),
      );
    });

    test('top playlists uses the canonical week', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final provider = historyTopPlaylistsProvider(HistoryDuration.days7);
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);
      await container.read(provider.future);

      expect(
        container.read(provider.notifier).windowStart,
        historyWindowStart(HistoryDuration.days7),
      );
    });

    test('top playlists drops legacy rows instead of throwing', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final playlist = PerfFixtures.playlist('legacy-playlist');
      await db.into(db.historyTable).insert(
            HistoryTableCompanion.insert(
              type: HistoryEntryType.playlist,
              itemId: playlist.id,
              data: {
                ...playlist.toJson(),
                'external_urls': {'spotify': playlist.externalUri},
              },
            ),
          );

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final provider = historyTopPlaylistsProvider(HistoryDuration.allTime);
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);

      await expectLater(container.read(provider.future), completes);
      expect(container.read(provider).asData!.value.items, isEmpty);
    });

    test('top albums drops legacy rows and respects the week window', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final currentTrack = PerfFixtures.track('current-track');
      final legacyTrack = PerfFixtures.track('legacy-track');
      final albumRow = PerfFixtures.track('current-album').album;
      final legacyAlbum = PerfFixtures.track('legacy-album').album;
      final oldTrack = PerfFixtures.track('old-track');
      final now = DateTime.now();

      await db.batch((batch) {
        batch.insertAll(db.historyTable, [
          HistoryTableCompanion.insert(
            createdAt: Value(now),
            type: HistoryEntryType.track,
            itemId: currentTrack.id,
            data: currentTrack.toJson(),
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(now),
            type: HistoryEntryType.track,
            itemId: legacyTrack.id,
            data: {
              ...legacyTrack.toJson(),
              'external_urls': {'spotify': legacyTrack.externalUri},
            },
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(now),
            type: HistoryEntryType.album,
            itemId: albumRow.id,
            data: albumRow.toJson(),
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(now),
            type: HistoryEntryType.album,
            itemId: legacyAlbum.id,
            data: {
              ...legacyAlbum.toJson(),
              'external_urls': {'spotify': legacyAlbum.externalUri},
            },
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(
              historyWindowStart(HistoryDuration.days7)
                  .subtract(const Duration(minutes: 1)),
            ),
            type: HistoryEntryType.track,
            itemId: oldTrack.id,
            data: oldTrack.toJson(),
          ),
        ]);
      });

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final provider = historyTopAlbumsProvider(HistoryDuration.days7);
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);

      await container.read(provider.future);
      final ids = container
          .read(provider)
          .asData!
          .value
          .items
          .map((item) => item.album.id)
          .toSet();

      expect(ids, {currentTrack.album.id, albumRow.id});
    });
  });
}
