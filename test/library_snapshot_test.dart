import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

const _vmCrossed429 =
    'DioException [bad response]: This exception was thrown because the '
    'response has a status code of 429 and RequestOptions.validateStatus was '
    'configured to throw for this status code.';

SpotubeFullArtistObject _artist(String id) => SpotubeFullArtistObject(
      id: id,
      name: 'Artist $id',
      externalUri: 'https://example.test/artist/$id',
    );

/// Saved-artists notifier whose network calls always look rate-limited.
class _Always429SavedArtists extends PaginatedAsyncNotifier<
    SpotubeFullArtistObject> with SavedListCacheMixin<SpotubeFullArtistObject> {
  final seenOffsets = <int>[];

  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeFullArtistObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    seenOffsets.add(offset);
    throw StateError(_vmCrossed429);
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> build() =>
      buildSavedList(cooldown: Duration.zero);
}

final _savedArtistsProvider = AsyncNotifierProvider<
    _Always429SavedArtists,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => _Always429SavedArtists(),
);

void main() {
  late AppDatabase database;

  setUpAll(() {
    AppLogger.initialize(false);
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDownAll(() async {
    await database.close();
  });

  ProviderContainer containerWith({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('library snapshot service', () {
    test('round-trips typed items through Drift', () async {
      final items = [_artist('x1'), _artist('x2'), _artist('x3')];
      await writeLibrarySnapshot(database, 'testArtists', items);

      final cached = await readLibrarySnapshot(
        database,
        'testArtists',
        SpotubeFullArtistObject.fromJson,
      );
      expect(cached?.map((e) => e.id), ['x1', 'x2', 'x3']);
      expect(cached?.first.name, 'Artist x1');
    });

    test('overwrites the snapshot for the same key', () async {
      await writeLibrarySnapshot(
        database,
        'testOverwrite',
        [_artist('old')],
      );
      await writeLibrarySnapshot(
        database,
        'testOverwrite',
        [_artist('new1'), _artist('new2')],
      );

      final cached = await readLibrarySnapshot(
        database,
        'testOverwrite',
        SpotubeFullArtistObject.fromJson,
      );
      expect(cached?.map((e) => e.id), ['new1', 'new2']);
    });

    test('missing key and corrupt payloads read as null (self-healing)',
        () async {
      expect(
        await readLibrarySnapshot(
          database,
          'neverWritten',
          SpotubeFullArtistObject.fromJson,
        ),
        isNull,
      );

      await database
          .into(database.librarySnapshotTable)
          .insert(LibrarySnapshotTableData(
            key: 'corrupt',
            data: '{not json',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ));
      expect(
        await readLibrarySnapshot(
          database,
          'corrupt',
          SpotubeFullArtistObject.fromJson,
        ),
        isNull,
      );
    });

    test('clearLibrarySnapshots drops every row', () async {
      await writeLibrarySnapshot(database, 'a', [_artist('1')]);
      await writeLibrarySnapshot(database, 'b', [_artist('2')]);

      await clearLibrarySnapshots(database);

      expect(
        await readLibrarySnapshot(
          database,
          'a',
          SpotubeFullArtistObject.fromJson,
        ),
        isNull,
      );
      expect(
        await readLibrarySnapshot(
          database,
          'b',
          SpotubeFullArtistObject.fromJson,
        ),
        isNull,
      );
    });
  });

  group('fetchAll persistence', () {
    test('completing pagination writes the snapshot', () async {
      // Same scripted two-page flow as saved_id_sets_test, but with the real
      // snapshot key and an in-memory database.
      final notifier = _Scripted429AfterSeed([
        SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: 2,
          total: 4,
          hasMore: true,
          items: [_artist('p1'), _artist('p2')],
        ),
        SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: null,
          total: 4,
          hasMore: false,
          items: [_artist('p3')],
        ),
      ]);
      final container = containerWith(
        extra: [_scriptedProvider.overrideWith(() => notifier)],
      );
      // Settle the initial build before driving fetchAll.
      await container.read(_scriptedProvider.future);

      final items = await container
          .read(_scriptedProvider.notifier)
          .fetchAll();
      expect(items.map((e) => e.id), ['p1', 'p2', 'p3']);

      // fetchAll awaits persistSnapshot, so the row is already on disk.
      final cached = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        SpotubeFullArtistObject.fromJson,
      );
      expect(cached?.map((e) => e.id), ['p1', 'p2', 'p3']);
    });
  });

  group('stale fallback in buildSavedList', () {
    test('rate-limited fetch serves the cached list', () async {
      await clearLibrarySnapshots(database);
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        [_artist('c1'), _artist('c2')],
      );

      final container = containerWith();
      final state = await container.read(_savedArtistsProvider.future);

      expect(state.items.map((e) => e.id), ['c1', 'c2']);
      expect(state.hasMore, isFalse,
          reason: 'restored snapshot must be marked complete');
      // It probed once (with the bounded retries), then fell back.
      expect(container.read(_savedArtistsProvider.notifier).seenOffsets.length,
          maxRateLimitAutoRetries + 1);
    });

    test('closed gate restores the cache without any network call', () async {
      await clearLibrarySnapshots(database);
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        [_artist('gated')],
      );

      final container = containerWith();
      container.read(rateLimitGateProvider.notifier).recordRateLimit();

      final state = await container.read(_savedArtistsProvider.future);

      expect(state.items.map((e) => e.id), ['gated']);
      expect(
        container.read(_savedArtistsProvider.notifier).seenOffsets,
        isEmpty,
        reason: 'the gate must short-circuit before any request',
      );
    });

    test('without a snapshot the rate-limit error surfaces', () async {
      await clearLibrarySnapshots(database);

      final container = containerWith();
      await expectLater(
        container.read(_savedArtistsProvider.future),
        throwsStateError,
      );
    });
  });
}

/// Scripted multi-page notifier (like download_media_test's _ScriptedPages)
/// that never throws so fetchAll completes and persists.
class _Scripted429AfterSeed
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  _Scripted429AfterSeed(this.pages);
  final List<SpotubePaginationResponseObject<SpotubeFullArtistObject>> pages;
  int _next = 0;

  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeFullArtistObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> build() =>
      Future.value(pages.first);

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    return pages[_next++ % pages.length];
  }
}

final _scriptedProvider = AsyncNotifierProvider<
    _Scripted429AfterSeed,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => throw UnimplementedError(),
);
