import 'dart:async';

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

SpotubeSimpleAlbumObject _album(String id) => SpotubeSimpleAlbumObject(
      id: id,
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: [
        SpotubeSimpleArtistObject(
          id: 'ar-$id',
          name: 'Artist ar-$id',
          externalUri: 'https://example.test/artist/ar-$id',
        ),
      ],
      albumType: SpotubeAlbumType.album,
    );

SpotubeSimplePlaylistObject _playlist(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://example.test/playlist/$id',
      owner: SpotubeUserObject(
        id: 'owner-$id',
        name: 'Owner $id',
        externalUri: 'https://example.test/user/owner-$id',
      ),
    );

/// Saved-artists notifier whose network calls always look rate-limited.
class _Always429SavedArtists
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  final seenOffsets = <int>[];

  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

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

final _savedArtistsProvider = AsyncNotifierProvider<_Always429SavedArtists,
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
      expect(cached?.items.map((e) => e.id), ['x1', 'x2', 'x3']);
      expect(cached?.items.first.name, 'Artist x1');
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
      expect(cached?.items.map((e) => e.id), ['new1', 'new2']);
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

    test('an explicit encoder round-trips polymorphic browse sections',
        () async {
      final section = SpotubeBrowseSectionObject<Object>(
        id: 'section-1',
        title: 'Shelf',
        externalUri: 'https://example.test/browse/section-1',
        browseMore: false,
        items: [
          _playlist('p1'),
          _album('a1'),
          _artist('ar1'),
        ],
      );
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeyBrowseSections,
        [section],
        encode: spotubeBrowseSectionToJson,
      );

      final cached = await readLibrarySnapshot(
        database,
        librarySnapshotKeyBrowseSections,
        (json) => SpotubeBrowseSectionObject<Object>.fromJson(
          json,
          spotubeBrowseItemFromJson,
        ),
      );
      expect(cached?.items.single.id, 'section-1');
      expect(
        cached?.items.single.items,
        [
          isA<SpotubeSimplePlaylistObject>(),
          isA<SpotubeSimpleAlbumObject>(),
          isA<SpotubeFullArtistObject>(),
        ],
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

      final items = await container.read(_scriptedProvider.notifier).fetchAll();
      expect(items.map((e) => e.id), ['p1', 'p2', 'p3']);

      // fetchAll awaits persistSnapshot, so the row is already on disk.
      final cached = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        SpotubeFullArtistObject.fromJson,
      );
      expect(cached?.items.map((e) => e.id), ['p1', 'p2', 'p3']);
    });
  });

  group('stale fallback in buildSavedList', () {
    test('a 429 never reaches a list that has a snapshot', () async {
      await clearLibrarySnapshots(database);
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        [_artist('c1'), _artist('c2')],
      );

      final container = containerWith();
      final notifier = container.read(_savedArtistsProvider.notifier);
      final state = await container.read(_savedArtistsProvider.future);

      expect(state.items.map((e) => e.id), ['c1', 'c2']);
      expect(state.hasMore, isFalse,
          reason: 'restored snapshot must be marked complete');

      // The probe does happen - it is what refreshes the list - but behind the
      // page already on screen, so its retries and its error are nobody's
      // spinner. Before stale-while-revalidate the build awaited all of it.
      final revalidated = notifier.revalidation;
      expect(revalidated, isNotNull, reason: 'the revalidation is in flight');
      await revalidated;
      expect(notifier.seenOffsets.length, maxRateLimitAutoRetries + 1,
          reason: 'the bounded retries ran, in the background');
      expect(
        container.read(_savedArtistsProvider).value?.items.map((e) => e.id),
        ['c1', 'c2'],
        reason: 'a failed revalidation keeps the last-known-good list',
      );
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

  group('stale-while-revalidate', () {
    late _HeldProbeSavedArtists notifier;

    setUp(() async {
      await clearLibrarySnapshots(database);
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        [_artist('c1')],
      );
      notifier = _HeldProbeSavedArtists();
      // Never leave the probe open: its 15s budget would outlive the test.
      addTearDown(() {
        if (!notifier.probe.isCompleted) {
          notifier.probe.complete(_page(const []));
        }
      });
    });

    test('the snapshot answers while the probe is still open', () async {
      final container = containerWith(
        extra: [_heldProbeProvider.overrideWith(() => notifier)],
      );

      final page = await container.read(_heldProbeProvider.future);

      expect(page.items.map((e) => e.id), ['c1']);
      expect(notifier.probes, 1, reason: 'the revalidation did start');
      expect(
        notifier.probe.isCompleted,
        isFalse,
        reason: 'and it is the request build() used to wait for',
      );

      notifier.probe.complete(_page([_artist('f1'), _artist('f2')]));
      await notifier.revalidation;

      expect(
        container.read(_heldProbeProvider).value?.items.map((e) => e.id),
        ['f1', 'f2'],
        reason: 'the fresh page replaces the served snapshot',
      );
      final persisted = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        SpotubeFullArtistObject.fromJson,
      );
      expect(
        persisted?.items.map((e) => e.id),
        ['f1', 'f2'],
        reason: 'and becomes the next last-known-good list',
      );
    });

    test('a page the caller moved first is not rolled back', () async {
      final container = containerWith(
        extra: [_heldProbeProvider.overrideWith(() => notifier)],
      );
      await container.read(_heldProbeProvider.future);

      // Stands in for a favorite button: an optimistic write that owns the
      // state from now on. A first page fetched before it happened must not
      // resurrect what the user just removed.
      notifier.replaceWith([_artist('c1'), _artist('kept')]);
      notifier.probe.complete(_page([_artist('f1')]));
      await notifier.revalidation;

      expect(
        container.read(_heldProbeProvider).value?.items.map((e) => e.id),
        ['c1', 'kept'],
      );
    });
  });

  group('revalidation merges the page-1 probe into the snapshot', () {
    late _HeldProbeSavedArtists notifier;

    setUp(() async {
      await clearLibrarySnapshots(database);
      // Stands in for a library that was fully walked in an earlier session.
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        [
          _artist('a1'),
          _artist('a2'),
          _artist('a3'),
          _artist('a4'),
          _artist('a5')
        ],
      );
      notifier = _HeldProbeSavedArtists();
      addTearDown(() {
        if (!notifier.probe.isCompleted) {
          notifier.probe.complete(_page(const []));
        }
      });
    });

    test('a page-1 probe keeps the walked tail rather than shrinking to it',
        () async {
      final container = containerWith(
        extra: [_heldProbeProvider.overrideWith(() => notifier)],
      );
      await container.read(_heldProbeProvider.future);

      // The network's first page reorders the top and adds a fresh favorite
      // (a6), and reports there is more beyond it. It cannot speak to anything
      // past page 1, so the snapshot's tail survives in its own order.
      notifier.probe
          .complete(_firstPage([_artist('a6'), _artist('a1'), _artist('a3')]));
      await notifier.revalidation;

      expect(
        container.read(_heldProbeProvider).value?.items.map((e) => e.id),
        ['a6', 'a1', 'a3', 'a2', 'a4', 'a5'],
        reason: 'page 1 verbatim, then snapshot items the page did not name',
      );
      expect(
        container.read(_heldProbeProvider).value?.hasMore,
        isFalse,
        reason: 'the merged list is the complete materialized list',
      );
      final persisted = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        SpotubeFullArtistObject.fromJson,
      );
      expect(
        persisted?.items.map((e) => e.id),
        ['a6', 'a1', 'a3', 'a2', 'a4', 'a5'],
        reason: 'the merged list becomes the next last-known-good snapshot',
      );
    });

    test('a probe with no further page replaces the list outright', () async {
      final container = containerWith(
        extra: [_heldProbeProvider.overrideWith(() => notifier)],
      );
      await container.read(_heldProbeProvider.future);

      // `hasMore == false` means the network returned the whole saved list:
      // everything the snapshot held beyond it was genuinely unsaved, and must
      // not be resurrected by the merge.
      notifier.probe.complete(_page([_artist('b1'), _artist('b2')]));
      await notifier.revalidation;

      expect(
        container.read(_heldProbeProvider).value?.items.map((e) => e.id),
        ['b1', 'b2'],
      );
    });
  });

  group('snapshot persist debounce', () {
    test('a burst of toggles persists once, with the final list', () async {
      await clearLibrarySnapshots(database);
      final container = containerWith(
        extra: [
          _schedulableProvider.overrideWith(() => _SchedulableSavedArtists())
        ],
      );
      // The provider is auto-dispose; a subscription keeps the notifier (and
      // its pending timer) alive for the test.
      final sub = container.listen(_schedulableProvider, (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(_schedulableProvider.notifier);
      await container.read(_schedulableProvider.future);

      for (final id in ['t1', 't2', 't3', 't4', 't5']) {
        notifier.toggle(id);
      }
      expect(
        await _rowCount(database, librarySnapshotKeySavedArtists),
        0,
        reason: 'nothing written inside the debounce window',
      );

      // Real clock: drift's in-memory database answers on the event loop, so
      // the window is waited out rather than faked.
      await Future.delayed(
        PaginatedAsyncNotifierMixin.snapshotPersistDebounce +
            const Duration(seconds: 2),
      );

      final persisted = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedArtists,
        SpotubeFullArtistObject.fromJson,
      );
      expect(persisted?.items.map((e) => e.id), ['t5'],
          reason: 'one trailing write carrying the latest state');
      expect(
        await _rowCount(database, librarySnapshotKeySavedArtists),
        1,
        reason: 'five schedules, one snapshot row',
      );
    });

    test('a provider disposed inside the window writes nothing', () async {
      await clearLibrarySnapshots(database);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          _schedulableProvider.overrideWith(() => _SchedulableSavedArtists()),
        ],
      );
      final sub = container.listen(_schedulableProvider, (_, __) {});
      final notifier = container.read(_schedulableProvider.notifier);
      await container.read(_schedulableProvider.future);
      notifier.toggle('gone');
      // Dropping the subscription disposes the provider with the timer still
      // pending.
      sub.close();
      container.dispose();

      await Future.delayed(
        PaginatedAsyncNotifierMixin.snapshotPersistDebounce +
            const Duration(seconds: 1),
      );
      expect(
        await _rowCount(database, librarySnapshotKeySavedArtists),
        0,
        reason: 'the pending schedule died with the provider',
      );
    });
  });
}

SpotubePaginationResponseObject<SpotubeFullArtistObject> _firstPage(
  List<SpotubeFullArtistObject> items,
) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: items.length,
      total: items.length + 1,
      hasMore: true,
      items: items,
    );

SpotubePaginationResponseObject<SpotubeFullArtistObject> _page(
  List<SpotubeFullArtistObject> items,
) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

/// Saved-artists notifier whose probe is held open by the test, which is the
/// only way to see that the build no longer waits for it.
class _HeldProbeSavedArtists
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  final probe =
      Completer<SpotubePaginationResponseObject<SpotubeFullArtistObject>>();
  int probes = 0;

  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    probes++;
    return probe.future;
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> build() =>
      buildSavedList(cooldown: Duration.zero);

  void replaceWith(List<SpotubeFullArtistObject> items) {
    state = AsyncData(_page(items));
  }
}

final _heldProbeProvider = AsyncNotifierProvider<_HeldProbeSavedArtists,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => throw UnimplementedError(),
);

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
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

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

final _scriptedProvider = AsyncNotifierProvider<_Scripted429AfterSeed,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => throw UnimplementedError(),
);

/// Saved-artists notifier with a settable page and a schedulable persist,
/// for debounce behavior (M-01).
class _SchedulableSavedArtists
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async =>
      throw StateError('unused');

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> build() =>
      Future.value(_page(const []));

  void toggle(String id) {
    state = AsyncData(_page([_artist(id)]));
    scheduleSnapshotPersist();
  }
}

final _schedulableProvider = AsyncNotifierProvider<_SchedulableSavedArtists,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => throw UnimplementedError(),
);

/// Counts snapshot rows written under [key] without disturbing the shared
/// in-memory database.
Future<int> _rowCount(AppDatabase database, String key) async {
  final rows = await (database.select(
    database.librarySnapshotTable,
  )..where((t) => t.key.equals(key)))
      .get();
  return rows.length;
}
