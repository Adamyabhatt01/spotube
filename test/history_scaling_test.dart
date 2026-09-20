// PR 2 (C1): a playback-history write must not cost a re-parse of the whole
// history window. This file is the benchmark (printed table) and the scaling
// guard. The equivalence proof (legacy Dart grouping vs the SQL aggregation)
// lives in history_track_grouping_test.dart, the image-repair coverage in
// history_image_repair_test.dart.
//
// Run with: fvm flutter test test/history_scaling_test.dart -r expanded

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/albums.dart';
import 'package:spotube/provider/history/top/playlists.dart';
import 'package:spotube/provider/history/top/tracks.dart';
import 'package:spotube/utils/perf_counters.dart';

import 'support/perf_fixtures.dart';

class _Cost {
  const _Cost({
    required this.provider,
    required this.rows,
    required this.settleMs,
    required this.items,
    required this.parses,
    required this.events,
    required this.parseMs,
  });

  final String provider;
  final int rows;
  final int settleMs;
  final int items;
  final int parses;
  final int? events;
  final int parseMs;

  @override
  String toString() =>
      '[$provider] historyRows=$rows writeToSettle=${settleMs}ms '
      'itemsAfter=$items rowParses=$parses watchEvents=${events ?? '-'} '
      'ofWhichParse=${parseMs}ms';
}

/// One probe gets its own database and container. Sharing them across probes
/// made the numbers meaningless: every earlier watcher stayed alive and
/// recomputed on the same write, so parses came out a multiple of the groups.
class _Env {
  _Env() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  }

  late final AppDatabase db;
  late final ProviderContainer container;

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }

  Future<void> insert(HistoryTableCompanion row) =>
      db.into(db.historyTable).insert(row);

  Future<int> rowCount() async {
    final rows =
        await db.customSelect('SELECT COUNT(*) AS c FROM history_table').get();
    return rows.first.read<int>('c');
  }
}

/// Polls until [done] or a timeout; drift delivers watch events asynchronously,
/// so the only way to time one is to wait for its visible effect.
Future<void> _awaitSettled(bool Function() done, String what) async {
  for (var attempt = 0; attempt < 4000; attempt++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('$what did not settle within 4s');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Seeds a [rows]-row history, installs the watcher the way the Stats page
  /// does, performs exactly one history write and times how long the provider
  /// takes to produce its next value.
  ///
  /// Settlement is detected by *object identity* of the state value, not by
  /// item count: the initial page only groups the first 20 rows, so on a small
  /// or heavily-duplicated fixture the number of groups can be unchanged even
  /// though the watcher recomputed everything.
  Future<_Cost> probe({
    required String name,
    required String? eventCounter,
    required int rows,
    required Future<void> Function(_Env) load,
    required SpotubePaginationResponseObject<Object?>? Function(_Env) snapshot,
    required Future<void> Function(_Env) write,
  }) async {
    final env = _Env();
    addTearDown(env.dispose);

    await PerfFixtures.insertMixedHistory(env.db, rows);
    await load(env);

    var before = snapshot(env);
    expect(before, isNotNull);
    expect(before!.items.length, greaterThan(0),
        reason: '$name probe seeded nothing');

    // Warm-up: the very first write also pays the stream-query's one-off setup
    // (statement prep, first full materialization), which would otherwise
    // dominate the smallest dataset and make the scaling look sub-linear.
    await write(env);
    await _awaitSettled(
      () => !identical(snapshot(env), before),
      '$name warm-up',
    );
    before = snapshot(env);

    PerfCounters.reset();
    final sw = Stopwatch()..start();
    await write(env);
    await _awaitSettled(
      () => !identical(snapshot(env), before),
      '$name watcher',
    );
    sw.stop();

    return _Cost(
      provider: name,
      rows: await env.rowCount(),
      settleMs: sw.elapsedMilliseconds,
      items: snapshot(env)!.items.length,
      parses: PerfCounters.countOf('history.rowParse'),
      parseMs: PerfCounters.totalOf('history.rowParseTime').inMilliseconds,
      events: eventCounter == null ? null : PerfCounters.countOf(eventCounter),
    );
  }

  Future<_Cost> probeTracks(int rows) {
    final newTrack = PerfFixtures.track('scrobble-target');
    final provider = historyTopTracksProvider(HistoryDuration.allTime);
    return probe(
      name: 'topTracks',
      eventCounter: 'history.tracks.watchEvents',
      rows: rows,
      load: (env) async {
        env.container.listen(provider, (_, __) {});
        await env.container.read(provider.future);
      },
      snapshot: (env) => env.container.read(provider).asData?.value,
      write: (env) => env.insert(
        HistoryTableCompanion.insert(
          createdAt: Value(DateTime.utc(2026, 2, 1)),
          type: HistoryEntryType.track,
          itemId: newTrack.id,
          data: newTrack.toJson(),
        ),
      ),
    );
  }

  Future<_Cost> probeAlbums(int rows) {
    // A track whose album id appears nowhere else: exactly one new album group.
    final newTrack = PerfFixtures.track('album-scrobble-target');
    final album = newTrack.album.copyWith(id: 'scrobble-album');
    final provider = historyTopAlbumsProvider(HistoryDuration.allTime);
    return probe(
      name: 'topAlbums',
      eventCounter: null,
      rows: rows,
      load: (env) async {
        env.container.listen(provider, (_, __) {});
        await env.container.read(provider.future);
      },
      snapshot: (env) => env.container.read(provider).asData?.value,
      write: (env) => env.insert(
        HistoryTableCompanion.insert(
          createdAt: Value(DateTime.utc(2026, 2, 1)),
          type: HistoryEntryType.track,
          itemId: newTrack.id,
          data: newTrack.copyWith(album: album).toJson(),
        ),
      ),
    );
  }

  Future<_Cost> probePlaylists(int rows) {
    final playlist = PerfFixtures.playlist('scrobble-playlist');
    final provider = historyTopPlaylistsProvider(HistoryDuration.allTime);
    return probe(
      name: 'topPlaylists',
      eventCounter: null,
      rows: rows,
      load: (env) async {
        env.container.listen(provider, (_, __) {});
        await env.container.read(provider.future);
      },
      snapshot: (env) => env.container.read(provider).asData?.value,
      write: (env) => env.insert(
        HistoryTableCompanion.insert(
          createdAt: Value(DateTime.utc(2026, 2, 1)),
          type: HistoryEntryType.playlist,
          itemId: playlist.id,
          data: playlist.toJson(),
        ),
      ),
    );
  }

  test('one history write is not proportional to history size', () async {
    final costs = <_Cost>[];
    for (final rows in [50, 5000, 25000]) {
      costs.add(await probeTracks(rows));
    }
    // ignore: avoid_print
    costs.forEach(print);

    // Loose on purpose (JIT warm-up, shared machine): it fails while the cost
    // is linear in history size, and passes once it is flat.
    expect(
      costs.last.settleMs,
      lessThan(costs.first.settleMs + 400),
      reason: 'per-write cost grew with history size:\n$costs',
    );
    // One write must recompute (at most) twice, and a recompute costs one
    // parse per group - not one per row.
    for (final cost in costs) {
      expect(cost.events, lessThanOrEqualTo(2), reason: '$cost');
      expect(cost.parses, lessThanOrEqualTo(cost.items * 3), reason: '$cost');
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('albums and playlists are no larger a cost than tracks', () async {
    const rows = 5000;
    final tracks = await probeTracks(rows);
    final albums = await probeAlbums(rows);
    final playlists = await probePlaylists(rows);
    // ignore: avoid_print
    [tracks, albums, playlists].forEach(print);

    // Reference numbers, guarding the scope decision: all three stayed within
    // the same order of magnitude once tracks stopped parsing every row.
    expect(albums.settleMs, lessThan(1000), reason: '$albums');
    expect(playlists.settleMs, lessThan(1000), reason: '$playlists');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a write with no Stats page open recomputes nothing', () async {
    final env = _Env();
    addTearDown(env.dispose);
    await PerfFixtures.insertMixedHistory(env.db, 5000);

    // Open the page, let the first aggregation settle, then close it. The three
    // top families are autoDispose, so the watcher must be gone afterwards.
    final provider = historyTopTracksProvider(HistoryDuration.allTime);
    PerfCounters.reset();
    final subscription = env.container.listen(provider, (_, __) {});
    await env.container.read(provider.future);
    await _awaitSettled(
      () => PerfCounters.countOf('history.tracks.watchEvents') > 0,
      'the initial aggregation',
    );
    subscription.close();
    // Disposal of an autoDispose provider is not synchronous with the last
    // listener going away; give it a chance to happen, and any event that was
    // already in flight to land, before measuring.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    PerfCounters.reset();

    PerfCounters.reset();
    final newTrack = PerfFixtures.track('scrobble-while-closed');
    await env.insert(
      HistoryTableCompanion.insert(
        createdAt: Value(DateTime.utc(2026, 2, 1)),
        type: HistoryEntryType.track,
        itemId: newTrack.id,
        data: newTrack.toJson(),
      ),
    );
    // Give any leaked watcher time to fire.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      PerfCounters.countOf('history.tracks.watchEvents'),
      0,
      reason: 'the Stats watcher survived the page being closed',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
