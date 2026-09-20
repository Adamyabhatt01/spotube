// PR 2 (C1): the artist-image repair.
//
// Historically some playback-history rows were written without artist images,
// and the top-tracks provider fixed them lazily while it recomputed. The
// aggregation moved to SQL, so the repair now runs off the aggregation's
// `unresolved` flag instead of off the page it happened to materialize. These
// tests pin what must not change: the same rows get the same images, nothing
// else in a row is touched, unfixable rows are left alone for the next event,
// and a repair does not re-trigger itself forever.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/tracks.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:spotube/utils/perf_counters.dart';

import 'support/perf_fixtures.dart';

/// The row shape the old bug produced: a track whose artists carry no images.
Map<String, dynamic> _withoutArtistImages(SpotubeFullTrackObject track) {
  return track.copyWith(
    artists: [
      for (final artist in track.artists) artist.copyWith(images: null),
    ],
  ).toJson();
}

bool _artistsHaveImages(Map<String, dynamic> data) {
  return (data['artists'] as List).every(
    (artist) => (artist as Map)['images'] != null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late List<String> fetchableArtistIds;
  final fetchedArtistIds = <String>[];

  /// The window the all-time provider uses - the repair is bounded by it.
  final windowStart = historyWindowStart(HistoryDuration.allTime);

  void setUpProviders({required List<String> fetchable}) {
    fetchableArtistIds = fetchable;
    fetchedArtistIds.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metadataPluginArtistProvider.overrideWith((ref, artistId) async {
          fetchedArtistIds.add(artistId);
          if (!fetchableArtistIds.contains(artistId)) {
            throw Exception('metadata plugin has no artist $artistId');
          }
          return SpotubeFullArtistObject(
            id: artistId,
            name: 'Fixture Artist $artistId',
            externalUri: 'https://open.spotify.com/artist/$artistId',
            images: [
              SpotubeImageObject(
                url: 'https://example.test/$artistId-640.jpg',
                height: 640,
                width: 640,
              ),
            ],
          );
        }),
      ],
    );
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<HistoryTableData>> allRows() => db.select(db.historyTable).get();

  Future<List<Object?>> unresolvedRows() =>
      historyTracksMissingArtistImages(db, windowStart: windowStart).get();

  Future<void> waitFor(Future<bool> Function() done, String what) async {
    for (var attempt = 0; attempt < 4000; attempt++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    fail('$what did not settle within 4s');
  }

  /// Opens the Stats page (all time) and lets the provider run its repair.
  Future<void> openTopTracks() async {
    final provider = historyTopTracksProvider(HistoryDuration.allTime);
    container.listen(provider, (_, __) {});
    await container.read(provider.future);
  }

  List<PlaybackHistoryTrack> topTracks() => container
      .read(historyTopTracksProvider(HistoryDuration.allTime))
      .asData!
      .value
      .items;

  test('fills in the missing artist images of every flagged row', () async {
    final brokenTrack = PerfFixtures.track('broken-artist-images');
    final artistId = brokenTrack.artists.single.id;
    setUpProviders(fetchable: [artistId]);

    await db.batch((batch) => batch.insertAll(db.historyTable, [
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 2)),
            type: HistoryEntryType.track,
            itemId: brokenTrack.id,
            data: _withoutArtistImages(brokenTrack),
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            type: HistoryEntryType.track,
            itemId: 'other',
            // A second listen of the same artist: one lookup has to fix both rows.
            data: _withoutArtistImages(brokenTrack.copyWith(id: 'other')),
          ),
        ]));
    expect(await unresolvedRows(), hasLength(2),
        reason: 'fixture did not produce flagged rows');

    await openTopTracks();
    await waitFor(
      () async => (await unresolvedRows()).isEmpty,
      'the artist image repair',
    );

    final rows = await allRows();
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(_artistsHaveImages(row.data), isTrue, reason: row.itemId);
    }
    expect(
        topTracks()
            .every((e) => e.track.artists.every((a) => a.images != null)),
        isTrue);
    // One plugin lookup per artist, not per row.
    expect(fetchedArtistIds.toSet(), {artistId});
  });

  test('rewrites the images and nothing else', () async {
    final track = PerfFixtures.track('untouched-columns');
    setUpProviders(fetchable: [track.artists.single.id]);

    await db.into(db.historyTable).insert(
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 1, 12)),
            type: HistoryEntryType.track,
            itemId: track.id,
            data: _withoutArtistImages(track),
          ),
        );
    final before = (await allRows()).single;

    await openTopTracks();
    await waitFor(
        () async => (await unresolvedRows()).isEmpty, 'the repair to land');

    final after = (await allRows()).single;
    expect(after.id, before.id);
    expect(after.createdAt, before.createdAt);
    expect(after.type, before.type);
    expect(after.itemId, before.itemId);
    expect(after.data.keys.toList()..sort(), before.data.keys.toList()..sort());

    final beforeArtist = (before.data['artists'] as List).single as Map;
    final afterArtist = (after.data['artists'] as List).single as Map;
    expect(beforeArtist['images'], isNull);
    expect(afterArtist['id'], beforeArtist['id']);
    expect(afterArtist['name'], beforeArtist['name']);
    expect(afterArtist['external_urls'], beforeArtist['external_urls']);
    expect(after.data['id'], before.data['id']);
    expect(after.data['name'], before.data['name']);
    expect(after.data['album'], before.data['album']);
    expect(after.data['duration_ms'], before.data['duration_ms']);
  });

  test('a plugin failure leaves the rows for the next event, not corrupted',
      () async {
    final track = PerfFixtures.track('unfetchable-artist');
    setUpProviders(fetchable: const []);

    await db.into(db.historyTable).insert(
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            type: HistoryEntryType.track,
            itemId: track.id,
            data: _withoutArtistImages(track),
          ),
        );

    await openTopTracks();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The provider still publishes the group; it just cannot show artwork.
    final items = topTracks();
    expect(items, hasLength(1));
    expect(items.single.count, 1);
    expect(items.single.track.artists.single.images, isNull);

    final rows = await allRows();
    expect(_artistsHaveImages(rows.single.data), isFalse);
    expect(rows.single.data['id'], track.id);
    expect(await unresolvedRows(), hasLength(1),
        reason: 'an unfixable row must stay flagged for a later retry');
  });

  test('the repair does not feed itself', () async {
    final track = PerfFixtures.track('converging');
    setUpProviders(fetchable: [track.artists.single.id]);

    await db.batch((batch) => batch.insertAll(db.historyTable, [
          for (var i = 0; i < 5; i++)
            HistoryTableCompanion.insert(
              createdAt:
                  Value(DateTime.utc(2026, 1, 1).add(Duration(minutes: i))),
              type: HistoryEntryType.track,
              itemId: 'converging-$i',
              data: _withoutArtistImages(track.copyWith(id: 'converging-$i')),
            ),
        ]));

    PerfCounters.reset();
    await openTopTracks();
    await waitFor(() async => (await unresolvedRows()).isEmpty,
        'all rows to be repaired');
    // Give a runaway loop the chance to show itself.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final events = PerfCounters.countOf('history.tracks.watchEvents');
    expect(
      events,
      lessThan(10),
      reason: '$events recomputes: the repair keeps re-triggering itself',
    );
    expect(fetchedArtistIds.toSet(), {track.artists.single.id});
    expect(topTracks(), hasLength(5));
    expect(topTracks().map((e) => e.track.id).toSet(), {
      for (var i = 0; i < 5; i++) 'converging-$i',
    });
  });

  test('legacy rows stored under external_urls stay untouched', () async {
    setUpProviders(
        fetchable: [PerfFixtures.track('current').artists.single.id]);

    // A pre-resolution row: the source payload was stored under
    // `external_urls`, so it is neither displayed nor repairable.
    final legacy = _withoutArtistImages(PerfFixtures.track('legacy'))
      ..['external_urls'] = {
        'spotify': 'https://open.spotify.com/track/legacy',
      };
    await db.batch((batch) => batch.insertAll(db.historyTable, [
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            type: HistoryEntryType.track,
            itemId: 'legacy',
            data: legacy,
          ),
          HistoryTableCompanion.insert(
            createdAt: Value(DateTime.utc(2026, 1, 2)),
            type: HistoryEntryType.track,
            itemId: 'current',
            data: _withoutArtistImages(PerfFixtures.track('current')),
          ),
        ]));

    await openTopTracks();
    await waitFor(() async => (await unresolvedRows()).isEmpty,
        'the current row to be repaired');

    final legacyRow =
        (await allRows()).singleWhere((r) => r.itemId == 'legacy');
    expect(legacyRow.data['external_urls'], isNotNull);
    expect(_artistsHaveImages(legacyRow.data), isFalse,
        reason: 'the repair must not reach legacy rows');
    expect(topTracks().map((e) => e.track.id), ['current']);
  });
}
