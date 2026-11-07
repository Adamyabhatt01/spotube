// PR 8 (A7): the six history aggregates used to be six watched queries, so one
// play-history write re-scanned the table six times and emitted six separate
// states. This pins the single-statement replacement against a hand-built
// history: the values must match what the six branches computed, and one write
// must produce one emission.
//
// Run with: fvm flutter test test/history_summary_test.dart -r expanded

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/summary.dart';

HistoryTableCompanion _track({
  required String id,
  required List<String> artistIds,
  required int durationMs,
  required DateTime createdAt,
}) {
  return HistoryTableCompanion.insert(
    createdAt: Value(createdAt),
    type: HistoryEntryType.track,
    itemId: id,
    data: {
      'id': id,
      'durationMs': durationMs,
      'artists': [
        for (final artistId in artistIds)
          {'id': artistId, 'name': 'Artist $artistId'},
      ],
    },
  );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  // The month branch is a calendar window, so the fixtures hang off the real
  // clock: any day of any month has a "this month" and a "last month".
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month);
  final lastMonth = startOfMonth.subtract(const Duration(days: 1));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    await db.batch((batch) {
      batch.insertAll(db.historyTable, [
        _track(
          id: 'A',
          artistIds: const ['ar1', 'ar2'],
          durationMs: 1000,
          createdAt: startOfMonth.add(const Duration(hours: 3)),
        ),
        _track(
          id: 'A',
          artistIds: const ['ar1'],
          durationMs: 2000,
          createdAt: now,
        ),
        _track(
          id: 'B',
          artistIds: const ['ar3'],
          durationMs: 3000,
          createdAt: lastMonth,
        ),
        HistoryTableCompanion.insert(
          createdAt: Value(now),
          type: HistoryEntryType.album,
          itemId: 'alb1',
          data: const {'id': 'alb1'},
        ),
        HistoryTableCompanion.insert(
          createdAt: Value(now),
          type: HistoryEntryType.playlist,
          itemId: 'pl1',
          data: const {'id': 'pl1'},
        ),
      ]);
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  PlaybackHistorySummary read() =>
      container.read(playbackHistorySummaryProvider).requireValue;

  test('counts, durations and the month window all survive the rewrite',
      () async {
    await container.read(playbackHistorySummaryProvider.future);

    expect(read().tracks, 2, reason: 'distinct track ids');
    expect(read().duration, const Duration(milliseconds: 6000));
    expect(read().artists, 3, reason: 'distinct artist ids across all rows');
    expect(read().albums, 1);
    expect(read().playlists, 1);
    // Only the two rows inside the calendar month feed the royalty estimate.
    expect(read().fees, closeTo(2 * 0.005, 1e-12));
  });

  test('one history write emits one state', () async {
    final emissions = <PlaybackHistorySummary>[];
    // The provider is auto-disposed, so the listener is what keeps the watch
    // alive across the write.
    final subscription = container.listen(
      playbackHistorySummaryProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.requireValue);
      },
    );
    await container.read(playbackHistorySummaryProvider.future);
    emissions.clear();

    await db.into(db.historyTable).insert(
          _track(
            id: 'C',
            artistIds: const ['ar4'],
            durationMs: 4000,
            createdAt: now,
          ),
        );
    await pumpEventQueue();

    expect(
      emissions,
      hasLength(1),
      reason: 'the six watched queries used to emit six times per write',
    );
    expect(emissions.first.tracks, 3);
    expect(emissions.first.artists, 4);
    expect(emissions.first.duration, const Duration(milliseconds: 10000));
    expect(emissions.first.fees, closeTo(3 * 0.005, 1e-12));

    subscription.close();
  });

  test('a write that moves no number does not notify', () async {
    var notifications = 0;
    final subscription = container.listen(
      playbackHistorySummaryProvider,
      (_, __) => notifications++,
    );
    await container.read(playbackHistorySummaryProvider.future);
    notifications = 0;

    // An album entry already counted changes nothing the summary reports.
    await db.into(db.historyTable).insert(
          HistoryTableCompanion.insert(
            createdAt: Value(now),
            type: HistoryEntryType.album,
            itemId: 'alb1',
            data: const {'id': 'alb1'},
          ),
        );
    await pumpEventQueue();

    expect(notifications, 0, reason: 'the summary compares by value');
    subscription.close();
  });
}
