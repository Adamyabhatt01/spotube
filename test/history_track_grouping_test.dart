// PR 2 (C1): the SQL-side track aggregation must produce exactly what the
// legacy Dart grouping produced - same groups, same counts, same representative
// track, same window - while no longer parsing every row of the history.
//
// The legacy implementation is duplicated here on purpose: it is the reference,
// and it no longer exists in `lib/`.

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/tracks.dart';

import 'support/perf_fixtures.dart';

typedef _Parsed = ({HistoryTableData row, SpotubeTrackObject track});

/// Verbatim copy of `HistoryTopTracksNotifier.getTracksWithCount` from before
/// the SQL aggregation, minus the artist-image repair (which
/// `history_image_repair_test.dart` covers separately).
List<PlaybackHistoryTrack> legacyGroupTracks(List<HistoryTableData> tracks) {
  final parsed = <_Parsed>[
    for (final row in tracks)
      if (row.track case final track?) (row: row, track: track),
  ];

  return groupBy(parsed, (entry) => entry.track.id)
      .entries
      .map((entry) {
        return (
          count: entry.value.length,
          track: entry.value
                  .firstWhereOrNull(
                    (t) => t.track.artists.every((a) => a.images != null),
                  )
                  ?.track ??
              entry.value.first.track,
        );
      })
      .sorted((a, b) => b.count.compareTo(a.count))
      .toList();
}

SpotubeTrackObject _withoutArtistImages(SpotubeTrackObject track) =>
    track.copyWith(
      artists: track.artists
          .map((a) => a.copyWith(images: null))
          .toList(growable: false),
    );

/// A history of listens built so that every branch of the grouping rules is
/// exercised: duplicates, a group whose only imaged row is not the first, a
/// group with no imaged row at all, a legacy row that must be dropped, and rows
/// outside the window.
class _Dataset {
  _Dataset(this.rows);

  final List<HistoryTableCompanion> rows;

  static const expectedCounts = {
    'a': 5,
    'b': 3,
    'c': 3,
    'd': 2,
    'e': 1,
    'g': 1,
  };

  static Future<_Dataset> spanning(DateTime windowStart) async {
    final rows = <HistoryTableCompanion>[];

    Future<void> play(
      String id,
      DateTime at, {
      bool imaged = true,
      bool legacyUnresolved = false,
      int? play,
    }) async {
      SpotubeTrackObject track = PerfFixtures.track('track-$id');
      if (play != null) {
        // Make the rows of one group distinguishable, so "which row was picked
        // as the representative" is observable in the parsed track.
        track = track.copyWith(name: '${track.name} #$play');
      }
      if (!imaged) track = _withoutArtistImages(track);
      final data = legacyUnresolved
          ? {
              ...track.toJson(),
              'external_urls': {'spotify': track.externalUri}
            }
          : track.toJson();
      rows.add(
        HistoryTableCompanion.insert(
          createdAt: Value(at),
          type: HistoryEntryType.track,
          itemId: track.id,
          data: data,
        ),
      );
    }

    Future<void> plays(
      String id,
      int count, {
      bool Function(int play)? imagedFor,
    }) async {
      for (var i = 0; i < count; i++) {
        await play(
          id,
          windowStart.add(Duration(minutes: i + 1)),
          imaged: imagedFor?.call(i) ?? true,
          play: i,
        );
      }
    }

    await plays('a', 5);
    // Only the last play has artist images: the representative must be that one.
    await plays('b', 3, imagedFor: (i) => i == 2);
    // No play has artist images: fall back to the first row.
    await plays('c', 3, imagedFor: (i) => false);
    await plays('d', 2);
    await play(
      'd',
      windowStart.add(const Duration(minutes: 9)),
      legacyUnresolved: true,
    );
    await plays('e', 1);
    // Plays that are outside the window for every duration, including
    // [HistoryDuration.allTime] (whose window starts in 1970).
    for (var i = 0; i < 2; i++) {
      await play('f', windowStart.subtract(const Duration(days: 1)), play: i);
    }
    // A row whose `item_id` column disagrees with the id inside its JSON: the
    // grouping key must be the JSON one, like it always was.
    final mismatch = PerfFixtures.track('track-g');
    rows.add(
      HistoryTableCompanion.insert(
        createdAt: Value(windowStart.add(const Duration(minutes: 30))),
        type: HistoryEntryType.track,
        itemId: 'stale-column-value',
        data: mismatch.toJson(),
      ),
    );

    return _Dataset(rows);
  }

  Future<void> insertInto(AppDatabase db) =>
      db.batch((batch) => batch.insertAll(db.historyTable, rows));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test opens its own in-memory database; drift's warning is about two
  // AppDatabase instances sharing one executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final duration in HistoryDuration.values) {
    test('top tracks aggregation equals the legacy grouping ($duration)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final windowStart = historyWindowStart(duration);
      final dataset = await _Dataset.spanning(windowStart);
      await dataset.insertInto(db);
      expect(dataset.rows, isNotEmpty);

      final legacy = legacyGroupTracks(
        await (db.select(db.historyTable)
              ..where(
                (t) =>
                    t.type.equalsValue(HistoryEntryType.track) &
                    t.createdAt.isBiggerOrEqualValue(windowStart),
              ))
            .get(),
      );
      final grouped = await historyTrackGroups(
        db,
        windowStart: windowStart,
      ).get();
      final actual = grouped.map((e) => e.item).toList();

      expect(legacy, isNotEmpty, reason: 'the dataset must produce groups');
      // The dataset itself is the contract: if the legacy grouping and the
      // aggregation both went wrong in the same way, this still fails.
      expect(
        {for (final e in actual) e.track.id: e.count},
        {
          for (final entry in _Dataset.expectedCounts.entries)
            'track-${entry.key}': entry.value,
        },
        reason: '$duration: unexpected groups',
      );
      expect(
        actual.map((e) => (e.track.id, e.count)).toSet(),
        legacy.map((e) => (e.track.id, e.count)).toSet(),
        reason: '$duration: groups/counts differ from the legacy grouping',
      );
      expect(
        actual.map((e) => e.track).toList()..sort(_byTrackId),
        legacy.map((e) => e.track).toList()..sort(_byTrackId),
        reason: '$duration: representative tracks differ',
      );
      // Spelled out, so the representative rule cannot silently move:
      // 'b' has one imaged play (the last), 'c' has none.
      expect(
        actual.firstWhere((e) => e.track.id == 'track-b').track.name,
        endsWith('#2'),
        reason: '$duration: representative should be the imaged play',
      );
      expect(
        actual.firstWhere((e) => e.track.id == 'track-c').track.name,
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

int _byTrackId(SpotubeTrackObject a, SpotubeTrackObject b) =>
    a.id.compareTo(b.id);
