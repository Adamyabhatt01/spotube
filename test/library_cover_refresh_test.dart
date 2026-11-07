import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

SpotubeSimplePlaylistObject _playlist(String id, {String? cover}) =>
    SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: 'A playlist under test',
      externalUri: 'https://example.test/playlist/$id',
      owner: SpotubeUserObject(
        id: 'owner-1',
        name: 'Owner',
        externalUri: 'https://example.test/user/owner-1',
      ),
      images: [
        SpotubeImageObject(
          url: cover ?? 'https://example.test/cover/$id-old',
          width: 640,
          height: 640,
        ),
      ],
    );

String? _cover(SpotubePaginationResponseObject<SpotubeSimplePlaylistObject> s,
        String id) =>
    s.items.firstWhere((playlist) => playlist.id == id).images.single.url;

/// A saved-playlists notifier that re-walks every page and serves scripted
/// pages, one per distinct offset.
class _WalkedSavedPlaylists
    extends PaginatedAsyncNotifier<SpotubeSimplePlaylistObject>
    with SavedListCacheMixin<SpotubeSimplePlaylistObject> {
  final Map<int, SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      pages;
  final bool failFetch;
  final seenOffsets = <int>[];

  _WalkedSavedPlaylists(this.pages, {this.failFetch = false});

  @override
  String? get snapshotKey => librarySnapshotKeySavedPlaylists;

  @override
  SpotubeSimplePlaylistObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeSimplePlaylistObject.fromJson;

  @override
  bool get refreshAllPages => true;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
    int offset,
    int limit,
  ) async {
    seenOffsets.add(offset);
    if (failFetch) throw StateError('offline');
    final page = pages[offset];
    if (page == null) throw StateError('unexpected offset $offset');
    return page;
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() => buildSavedList(cooldown: Duration.zero);
}

final _walkedProvider = AsyncNotifierProvider<_WalkedSavedPlaylists,
    SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>(
  () => throw UnimplementedError(),
);

/// A list with no snapshot: it pages on demand, so `fetchMore` exercises the
/// append merge.
class _PagedSavedPlaylists
    extends PaginatedAsyncNotifier<SpotubeSimplePlaylistObject> {
  _PagedSavedPlaylists(this.pages);
  final Map<int, SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      pages;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
    int offset,
    int limit,
  ) async =>
      pages[offset]!;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() => fetch(0, 20);
}

final _pagedProvider = AsyncNotifierProvider<_PagedSavedPlaylists,
    SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>(
  () => throw UnimplementedError(),
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

  setUp(() async {
    await clearLibrarySnapshots(database);
  });

  ProviderContainer containerWith(List<Override> overrides) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('warm playlist build walks every page', () {
    test('replaces stale covers beyond page one and persists them', () async {
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedPlaylists,
        [_playlist('p1'), _playlist('p2'), _playlist('p3')],
      );

      final notifier = _WalkedSavedPlaylists({
        0: SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: 2,
          total: 3,
          hasMore: true,
          items: [
            _playlist('p1', cover: 'https://example.test/cover/p1-new'),
            _playlist('p2', cover: 'https://example.test/cover/p2-new'),
          ],
        ),
        2: SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: null,
          total: 3,
          hasMore: false,
          items: [
            _playlist('p3', cover: 'https://example.test/cover/p3-new'),
          ],
        ),
      });

      final container = containerWith([
        _walkedProvider.overrideWith(() => notifier),
      ]);

      final served = await container.read(_walkedProvider.future);
      expect(
        served.items.map((p) => p.id),
        ['p1', 'p2', 'p3'],
        reason: 'the snapshot answers the build immediately',
      );
      await notifier.revalidation;

      expect(
        notifier.seenOffsets,
        [0, 2],
        reason: 'every page was confirmed, not only the first',
      );
      final state = container.read(_walkedProvider).value!;
      expect(_cover(state, 'p1'), 'https://example.test/cover/p1-new');
      expect(_cover(state, 'p2'), 'https://example.test/cover/p2-new');
      expect(
        _cover(state, 'p3'),
        'https://example.test/cover/p3-new',
        reason: 'the stale page-two row is the reported bug',
      );

      final persisted = await readLibrarySnapshot(
        database,
        librarySnapshotKeySavedPlaylists,
        SpotubeSimplePlaylistObject.fromJson,
      );
      expect(persisted?.items.map((p) => p.images.single.url), [
        'https://example.test/cover/p1-new',
        'https://example.test/cover/p2-new',
        'https://example.test/cover/p3-new',
      ]);
    });

    test('a failed walk keeps the served list untouched', () async {
      await writeLibrarySnapshot(
        database,
        librarySnapshotKeySavedPlaylists,
        [_playlist('p1')],
      );

      final notifier = _WalkedSavedPlaylists(
        const {},
        failFetch: true,
      );

      final container = containerWith([
        _walkedProvider.overrideWith(() => notifier),
      ]);
      await container.read(_walkedProvider.future);
      await notifier.revalidation;

      expect(
        container.read(_walkedProvider).value?.items.map((p) => p.id),
        ['p1'],
      );
      expect(
        _cover(container.read(_walkedProvider).value!, 'p1'),
        'https://example.test/cover/p1-old',
      );
    });
  });

  group('append merge', () {
    test('a fresh duplicate replaces the stale row instead of being dropped',
        () async {
      final notifier = _PagedSavedPlaylists({
        0: SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: 2,
          total: 2,
          hasMore: true,
          items: [_playlist('p1')],
        ),
        2: SpotubePaginationResponseObject(
          limit: 2,
          nextOffset: null,
          total: 2,
          hasMore: false,
          items: [
            _playlist('p1', cover: 'https://example.test/cover/p1-new'),
          ],
        ),
      });

      final container = containerWith([
        _pagedProvider.overrideWith(() => notifier),
      ]);
      await container.read(_pagedProvider.future);

      await container.read(_pagedProvider.notifier).fetchMore();

      final state = container.read(_pagedProvider).value!;
      expect(state.items.map((p) => p.id), ['p1'],
          reason: 'still one row for one id');
      expect(
        _cover(state, 'p1'),
        'https://example.test/cover/p1-new',
        reason: 'the network copy wins over the one already on screen',
      );
    });
  });
}
