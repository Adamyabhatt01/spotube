// PR 7 (D-04): the SQL-side playlist aggregation must produce exactly what the
// legacy Dart grouping produced - same groups, same counts, same representative
// playlist, same window - while no longer parsing every row of the history.
//
// The legacy implementation is duplicated here on purpose: it is the reference,
// and the watch path in `lib/` no longer uses it.

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/playlists.dart';

import 'support/perf_fixtures.dart';

/// Verbatim copy of `HistoryTopPlaylistsNotifier.getPlaylistsWithCount` from
/// before the SQL aggregation, except that rows the old `playlist!` would have
/// crashed on (legacy `external_urls` shape) are dropped - the same decision
/// the tracks aggregation made for its unresolvable rows.
List<PlaybackHistoryPlaylist> legacyGroupPlaylists(
  List<HistoryTableData> playlists,
) {
  final resolvable = [
    for (final row in playlists)
      if (row.playlist != null) row,
  ];

  return groupBy(resolvable, (playlist) => playlist.playlist!.id)
      .entries
      .map((entry) {
        return (
          count: entry.value.length,
          playlist: entry.value.first.playlist!,
        );
      })
      .sorted((a, b) => b.count.compareTo(a.count))
      .toList();
}

/// A playlist history built so that every branch of the grouping rules is
/// exercised: duplicates, a legacy row that must be dropped, a row whose
/// `item_id` column disagrees with the JSON id, and rows outside the window.
class _Dataset {
  _Dataset(this.rows);

  final List<HistoryTableCompanion> rows;

  static const expectedCounts = {'a': 4, 'b': 2, 'c': 1, 'd': 2, 'e': 1};

  static Future<_Dataset> spanning(DateTime windowStart) async {
    final rows = <HistoryTableCompanion>[];

    void play(
      String id,
      DateTime at, {
      int? play,
      bool legacyUnresolved = false,
      String? itemId,
    }) {
      var playlist = PerfFixtures.playlist('playlist-$id');
      if (play != null) {
        // Make the rows of one group distinguishable, so "which row was picked
        // as the representative" is observable in the parsed playlist.
        playlist = playlist.copyWith(name: '${playlist.name} #$play');
      }
      final data = legacyUnresolved
          ? {
              ...playlist.toJson(),
              'external_urls': {'spotify': playlist.externalUri}
            }
          : playlist.toJson();
      rows.add(
        HistoryTableCompanion.insert(
          createdAt: Value(at),
          type: HistoryEntryType.playlist,
          itemId: itemId ?? playlist.id,
          data: data,
        ),
      );
    }

    void plays(String id, int count) {
      for (var i = 0; i < count; i++) {
        play(id, windowStart.add(Duration(minutes: i + 1)), play: i);
      }
    }

    plays('a', 4);
    plays('b', 2);
    plays('c', 1);
    // A playable group plus a legacy row: the legacy row must not change the
    // group's count or representative.
    play('d', windowStart.add(const Duration(minutes: 5)));
    play('d', windowStart.add(const Duration(minutes: 6)), play: 1);
    play('d', windowStart.add(const Duration(minutes: 7)),
        legacyUnresolved: true);
    // Plays that are outside the window for every duration, including
    // [HistoryDuration.allTime].
    for (var i = 0; i < 2; i++) {
      play('f', windowStart.subtract(const Duration(days: 1)), play: i);
    }
    // A row whose `item_id` column disagrees with the id inside its JSON: the
    // grouping key must be the JSON one, like it always was.
    play(
      'e',
      windowStart.add(const Duration(minutes: 30)),
      itemId: 'stale-column-value',
    );

    // 'd' is a group of two resolvable rows.
    return _Dataset(rows);
  }

  Future<void> insertInto(AppDatabase db) =>
      db.batch((batch) => batch.insertAll(db.historyTable, rows));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final duration in HistoryDuration.values) {
    test('top playlists aggregation equals the legacy grouping ($duration)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // The notifier's window, reproduced here so the test does not depend on
      // `arg` being wired through a provider container.
      final windowStart = historyWindowStart(duration);
      final dataset = await _Dataset.spanning(windowStart);
      await dataset.insertInto(db);
      expect(dataset.rows, isNotEmpty);

      final legacy = legacyGroupPlaylists(
        await (db.select(db.historyTable)
              ..where(
                (t) =>
                    t.type.equalsValue(HistoryEntryType.playlist) &
                    t.createdAt.isBiggerOrEqualValue(windowStart),
              ))
            .get(),
      );
      final actual = await historyPlaylistGroups(
        db,
        windowStart: windowStart,
      ).get();

      expect(legacy, isNotEmpty, reason: 'the dataset must produce groups');
      expect(
        {for (final e in actual) e.playlist.id: e.count},
        {
          for (final entry in _Dataset.expectedCounts.entries)
            'playlist-${entry.key}': entry.value,
        },
        reason: '$duration: unexpected groups',
      );
      expect(
        actual.map((e) => (e.playlist.id, e.count)).toSet(),
        legacy.map((e) => (e.playlist.id, e.count)).toSet(),
        reason: '$duration: groups/counts differ from the legacy grouping',
      );
      expect(
        actual.map((e) => e.playlist).toList()..sort(_byPlaylistId),
        legacy.map((e) => e.playlist).toList()..sort(_byPlaylistId),
        reason: '$duration: representative playlists differ',
      );
      // Spelled out, so the representative rule cannot silently move: the
      // first row of the group (lowest row id), like `groupBy(...).first`.
      expect(
        actual.firstWhere((e) => e.playlist.id == 'playlist-a').playlist.name,
        endsWith('#0'),
        reason: '$duration: representative should be the first play',
      );

      final counts = actual.map((e) => e.count).toList();
      expect(
        counts,
        orderedEquals([...counts]..sort((a, b) => b.compareTo(a))),
        reason: '$duration: items must be sorted by descending play count',
      );
    });
  }
}

int _byPlaylistId(
        SpotubeSimplePlaylistObject a, SpotubeSimplePlaylistObject b) =>
    a.id.compareTo(b.id);
