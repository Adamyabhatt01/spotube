// PR 1 baseline measurements. These tests exist to make the optimization
// roadmap's claims measurable rather than asserted from source reading.
//
// They print a before/after table on every run (visible in `flutter test`
// output) and assert only the structural assumptions the instrumentation
// relies on. The scaling *guards* (cost must stop growing with dataset size)
// land with the PR that fixes each cost, in that PR's own test file.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/utils/perf_counters.dart';

import 'support/perf_fixtures.dart';

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queue serialization', () {
    const converter = SpotubeTrackObjectListConverter();

    for (final count in [50, 600, 2000]) {
      test('encode + decode of a $count-track queue', () {
        final tracks = PerfFixtures.tracks(count);
        PerfCounters.reset();

        final encodeSw = Stopwatch()..start();
        final sql = converter.toSql(tracks);
        encodeSw.stop();

        final decodeSw = Stopwatch()..start();
        final restored = converter.fromSql(sql);
        decodeSw.stop();

        // ignore: avoid_print
        print(
          '[queue] n=$count bytes=${sql.length} (${_mb(sql.length)}MB) '
          'encode=${encodeSw.elapsedMilliseconds}ms '
          'decode=${decodeSw.elapsedMilliseconds}ms',
        );

        expect(restored, hasLength(count));
        expect(restored.first.id, tracks.first.id);
        expect(restored.last.album.id, tracks.last.album.id);
        expect(PerfCounters.countOf('queue.encode'), 1);
        expect(PerfCounters.countOf('queue.decode'), 1);
        expect(PerfCounters.countOf('queue.encodeBytes'), sql.length);
      });
    }

    test('counters are cumulative across writes', () {
      const converter = SpotubeTrackObjectListConverter();
      final tracks = PerfFixtures.tracks(50);
      PerfCounters.reset();
      converter.toSql(tracks);
      converter.toSql(tracks);
      expect(PerfCounters.countOf('queue.encode'), 2);
      expect(PerfCounters.countOf('queue.encodeRows'), 100);
    });
  });

  group('history re-parse', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    for (final count in [50, 5000, 25000]) {
      test('one scrobble over a $count-row history', () async {
        await PerfFixtures.insertHistory(db, count);

        // The exact query `historyTopTracksProvider(allTime)` watches: unbounded,
        // type-filtered, and every returned row is parsed through `HistoryTableData.track`.
        final query = (db.select(db.historyTable)
              ..where((t) =>
                  t.type.equalsValue(HistoryEntryType.track) &
                  t.createdAt.isBiggerOrEqualValue(DateTime(1970))));

        final fetchSw = Stopwatch()..start();
        final rows = await query.get();
        fetchSw.stop();

        PerfCounters.reset();
        final parseSw = Stopwatch()..start();
        final parsed = rows.map((e) => e.track).nonNulls.toList();
        parseSw.stop();

        // ignore: avoid_print
        print(
          '[history] rows=$count trackRows=${rows.length} '
          'sqlFetch=${fetchSw.elapsedMilliseconds}ms '
          'parse=${parseSw.elapsedMilliseconds}ms '
          'parses=${PerfCounters.countOf('history.rowParse')} '
          'parsedOk=${parsed.length}',
        );

        expect(parsed, hasLength(rows.length));
        // The pathological shape this measurement exists to prove: a single
        // history write costs a parse of every row in the window.
        expect(PerfCounters.countOf('history.rowParse'), rows.length);
      });
    }
  });

  group('instrumentation assumptions', () {
    test('counting map over a broadcast stream keeps it broadcast', () async {
      // The counted position stream relies on this: media_kit's position stream
      // is broadcast and has many simultaneous subscribers.
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);
      var seen = 0;
      final tapped = controller.stream.map((e) {
        seen++;
        return e;
      });

      expect(tapped.isBroadcast, isTrue);
      final a = tapped.listen((_) {});
      final b = tapped.listen((_) {});
      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(seen, 2);
      await a.cancel();
      await b.cancel();
    });

    test('counters are compiled out only in release', () {
      // Debug/test runs must observe; the flag is a compile-time constant so a
      // release build folds every call site away.
      expect(kReleaseMode, isFalse);
      expect(kPerfCountersEnabled, isTrue);
      PerfCounters.note('probe');
      expect(PerfCounters.countOf('probe'), 1);
      expect(PerfCounters.snapshot(), contains('probe=1'));
    });

    test('dump timer is opt-in and cancelable', () async {
      var dumps = 0;
      PerfCounters.startDumpTimer(
        interval: const Duration(milliseconds: 20),
        log: (_) => dumps++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      PerfCounters.stopDumpTimerForTest();
      expect(dumps, greaterThan(0));
    });
  });
}
