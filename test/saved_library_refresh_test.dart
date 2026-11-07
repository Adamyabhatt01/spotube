// The reported symptom: a playlist created on one device did not show up on
// another device signed into the same account, even though Spotify itself
// showed it.
//
// The cause was on the host, not in the plugin: the saved-playlists list is
// read once per app session (its build serves the disk snapshot and
// revalidates behind it), and nothing ever asked the plugin again. A device
// that stayed open kept showing whatever the network said when it started.
//
// These tests pin the fix at the layer where the bug lived:
//
//  * a refresh re-reads the library and adopts a playlist another device
//    created — including one that landed on a later page, because Spotify
//    appends new playlists to the *end* of the library;
//  * a refresh that fails leaves the last-known-good list alone;
//  * a snapshot that was still paging is stored as incomplete, so the next
//    launch knows to keep paging instead of mistaking one page for the whole
//    account;
//  * a burst of triggers costs one re-read.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/library/library_refresh.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

import 'support/common_fakes.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://open.spotify.com/user/$id',
    );

SpotubeSimplePlaylistObject _playlist(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
    );

/// The Spotify account both "devices" read from.
///
/// One shared object with one shared list of playlists is the account; the
/// devices are the two provider containers below it. A playlist is appended
/// to the end of the list, exactly as Spotify appends a newly created
/// playlist to the end of a library.
class _FakeAccount {
  _FakeAccount([List<SpotubeSimplePlaylistObject>? playlists])
      : playlists = playlists ?? [];

  final List<SpotubeSimplePlaylistObject> playlists;

  /// Set to make every read fail, the way a dropped connection would.
  bool offline = false;

  /// How many pages the plugin hands out per read. Deliberately small so a
  /// library of a few playlists spans several pages — the shape that hid the
  /// bug, because a new playlist landed past page one.
  static const pageSize = 2;

  int reads = 0;

  void add(SpotubeSimplePlaylistObject playlist) => playlists.add(playlist);
}

/// A saved-playlists notifier that reads [account] instead of a plugin.
class _FakeSavedPlaylists
    extends PaginatedAsyncNotifier<SpotubeSimplePlaylistObject>
    with SavedListCacheMixin<SpotubeSimplePlaylistObject> {
  _FakeSavedPlaylists(this.account);

  final _FakeAccount account;

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
    account.reads++;
    if (account.offline) throw StateError('offline');

    final all = account.playlists;
    final page = all.skip(offset).take(_FakeAccount.pageSize).toList();
    final next = offset + page.length;

    return SpotubePaginationResponseObject(
      limit: _FakeAccount.pageSize,
      nextOffset: next < all.length ? next : null,
      total: all.length,
      hasMore: next < all.length,
      items: page,
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() =>
      buildSavedList(cooldown: Duration.zero);
}

final _playlistsProvider = AsyncNotifierProvider<_FakeSavedPlaylists,
    SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>(
  () => throw UnimplementedError(),
);

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('the library is re-read when another device changed it', () {
    test('a playlist created on one device reaches the other', () async {
      final dbA = newMemoryDatabase();
      final dbB = newMemoryDatabase();
      addTearDown(dbA.close);
      addTearDown(dbB.close);

      final account = _FakeAccount([
        _playlist('p1'),
        _playlist('p2'),
        _playlist('p3'),
      ]);

      ProviderContainer device(AppDatabase db) {
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      final deviceA = device(dbA);
      final deviceB = device(dbB);

      // Both devices read the library while it holds three playlists. The
      // first read is the cold path: one page, so two of the three.
      await deviceA.read(_playlistsProvider.future);
      await deviceB.read(_playlistsProvider.future);

      // Device A creates a playlist. Spotify appends it to the end.
      account.add(_playlist('p4'));

      // Device B is stale — this is the reported symptom. It asked the
      // network once, at startup, and never again.
      expect(
        deviceB.read(_playlistsProvider).value?.items.map((p) => p.id),
        isNot(contains('p4')),
        reason: 'without a re-read the second device never learns of it',
      );

      // The re-read is what makes the two devices agree.
      final ids =
          await deviceB.read(_playlistsProvider.notifier).refreshIds();

      expect(ids, contains('p4'));
      expect(
        deviceB.read(_playlistsProvider).value?.items.map((p) => p.id),
        contains('p4'),
        reason: 'the new row has to be on screen, not only in the answer',
      );
    });

    test('the re-read reaches past the first page', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      final account = _FakeAccount([
        _playlist('p1'),
        _playlist('p2'),
        _playlist('p3'),
        _playlist('p4'),
      ]);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(_playlistsProvider.future);
      expect(
        container.read(_playlistsProvider).value?.items.map((p) => p.id),
        ['p1', 'p2'],
        reason: 'the cold path reads one page',
      );

      await container.read(_playlistsProvider.notifier).refresh();

      expect(
        container.read(_playlistsProvider).value?.items.map((p) => p.id),
        ['p1', 'p2', 'p3', 'p4'],
        reason: 'a new playlist lands at the end of the library, so a '
            'page-one probe would never see it',
      );
    });

    test('the re-read is written to disk, so a restart keeps it', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      final account = _FakeAccount([_playlist('p1'), _playlist('p2')]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(_playlistsProvider.future);
      account.add(_playlist('p3'));
      await container.read(_playlistsProvider.notifier).refresh();

      final persisted = await readLibrarySnapshot(
        db,
        librarySnapshotKeySavedPlaylists,
        SpotubeSimplePlaylistObject.fromJson,
      );
      expect(persisted?.items.map((p) => p.id), ['p1', 'p2', 'p3']);
      expect(persisted?.complete, isTrue);
    });

    test('a failed re-read keeps the last-known-good list', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      final account = _FakeAccount([_playlist('p1'), _playlist('p2')]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(_playlistsProvider.future);
      final before =
          container.read(_playlistsProvider).value?.items.map((p) => p.id);

      account.offline = true;
      final ids = await container.read(_playlistsProvider.notifier).refreshIds();

      expect(
        ids,
        isNull,
        reason: '"we could not ask" is not the same answer as "it is not '
            'there", and the caller has to be able to tell them apart',
      );
      expect(
        container.read(_playlistsProvider).value?.items.map((p) => p.id),
        before,
        reason: 'a stale list is better than an error replacing it',
      );
    });

    test('an unchanged library costs one request', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      final account = _FakeAccount([
        _playlist('p1'),
        _playlist('p2'),
        _playlist('p3'),
      ]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(_playlistsProvider.future);
      await container.read(_playlistsProvider.notifier).refresh();

      final readsAfterTheFirst = account.reads;
      await container.read(_playlistsProvider.notifier).refresh();

      expect(
        account.reads - readsAfterTheFirst,
        1,
        reason: 'the page-one probe already says whether the library moved; '
            'reading the rest of the pages for nothing is the request budget '
            'going to waste',
      );
    });

    test('a changed library is read to the end', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      final account = _FakeAccount([
        _playlist('p1'),
        _playlist('p2'),
        _playlist('p3'),
      ]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(_playlistsProvider.future);
      await container.read(_playlistsProvider.notifier).refresh();

      account.add(_playlist('p4'));
      await container.read(_playlistsProvider.notifier).refresh();

      expect(
        container.read(_playlistsProvider).value?.items.map((p) => p.id),
        ['p1', 'p2', 'p3', 'p4'],
        reason: 'the new row is at the end of the library, so the rest of '
            'the pages have to be read',
      );
    });
  });

  group('the snapshot says whether it is the whole list', () {
    test('a list that was still paging is stored as incomplete', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      await writeLibrarySnapshot(
        db,
        librarySnapshotKeySavedPlaylists,
        [_playlist('p1'), _playlist('p2')],
        complete: false,
      );

      final snapshot = await readLibrarySnapshot(
        db,
        librarySnapshotKeySavedPlaylists,
        SpotubeSimplePlaylistObject.fromJson,
      );
      expect(snapshot?.items.map((p) => p.id), ['p1', 'p2']);
      expect(
        snapshot?.complete,
        isFalse,
        reason: 'one page is not the whole library, and saying so is what '
            'lets the next launch keep paging',
      );
    });

    test('a v1 array payload still reads as a complete list', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      await db.into(db.librarySnapshotTable).insert(
            LibrarySnapshotTableData(
              key: 'legacy',
              data: jsonEncode([_playlist('x1').toJson()]),
              updatedAtMs: 1,
            ),
          );

      final snapshot = await readLibrarySnapshot(
        db,
        'legacy',
        SpotubeSimplePlaylistObject.fromJson,
      );
      expect(snapshot?.items.map((p) => p.id), ['x1']);
      expect(snapshot?.complete, isTrue);
    });

    test('an incomplete snapshot is served as an incomplete page', () async {
      final db = newMemoryDatabase();
      addTearDown(db.close);

      await writeLibrarySnapshot(
        db,
        librarySnapshotKeySavedPlaylists,
        [_playlist('p1'), _playlist('p2')],
        complete: false,
      );

      final account = _FakeAccount([_playlist('p1'), _playlist('p2')]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          _playlistsProvider.overrideWith(() => _FakeSavedPlaylists(account)),
        ],
      );
      addTearDown(container.dispose);

      final page = await container.read(_playlistsProvider.future);

      expect(page.items.map((p) => p.id), ['p1', 'p2']);
      expect(
        page.hasMore,
        isTrue,
        reason: 'the list is a prefix of the library, not the library',
      );
      expect(page.nextOffset, 2);
    });
  });

  group('the refresher', () {
    test('coalesces a burst of triggers into one re-read', () async {
      var calls = 0;
      final refresher = SavedLibraryRefresher(
        refreshers: {
          SavedLibraryList.playlists: () async => calls++,
        },
        isReady: () async => true,
        cooldown: const Duration(minutes: 1),
      );

      expect(await refresher.maybeRefresh(SavedLibraryList.playlists), isTrue);
      expect(
        await refresher.maybeRefresh(SavedLibraryList.playlists),
        isFalse,
        reason: 'the window-focus event and the page-open event fire in the '
            'same breath; they must not cost two re-reads',
      );
      expect(calls, 1);
    });

    test('re-reads every list', () async {
      final done = <String>[];
      final refresher = SavedLibraryRefresher(
        refreshers: {
          for (final name in [
            SavedLibraryList.playlists,
            SavedLibraryList.tracks,
            SavedLibraryList.albums,
            SavedLibraryList.artists,
          ])
            name: () async => done.add(name),
        },
        isReady: () async => true,
      );

      await refresher.refreshAll();

      expect(done, [
        SavedLibraryList.playlists,
        SavedLibraryList.tracks,
        SavedLibraryList.albums,
        SavedLibraryList.artists,
      ]);
    });

    test('one failing list does not stop the others', () async {
      final done = <String>[];
      final refresher = SavedLibraryRefresher(
        refreshers: {
          SavedLibraryList.playlists: () async => throw StateError('offline'),
          SavedLibraryList.albums: () async => done.add('albums'),
        },
        isReady: () async => true,
      );

      await refresher.refreshAll();

      expect(done, ['albums']);
    });

    test('nothing is re-read while signed out or offline', () async {
      var calls = 0;
      final refresher = SavedLibraryRefresher(
        refreshers: {
          SavedLibraryList.playlists: () async => calls++,
        },
        isReady: () async => false,
      );

      expect(await refresher.maybeRefresh(SavedLibraryList.playlists), isFalse);
      expect(calls, 0);
    });

    test('a list skipped for being offline is not held back by the cooldown',
        () async {
      var calls = 0;
      var ready = false;
      final refresher = SavedLibraryRefresher(
        refreshers: {
          SavedLibraryList.playlists: () async => calls++,
        },
        isReady: () async => ready,
        cooldown: const Duration(minutes: 1),
      );

      expect(await refresher.maybeRefresh(SavedLibraryList.playlists), isFalse);
      expect(calls, 0);

      // The network comes back. The list must be readable now, not a minute
      // after the attempt that never happened.
      ready = true;
      expect(await refresher.maybeRefresh(SavedLibraryList.playlists), isTrue);
      expect(calls, 1);
    });

    test('a failed re-read still counts as an attempt', () async {
      var calls = 0;
      final refresher = SavedLibraryRefresher(
        refreshers: {
          SavedLibraryList.playlists: () async {
            calls++;
            throw StateError('offline');
          },
        },
        isReady: () async => true,
        cooldown: const Duration(minutes: 1),
      );

      expect(await refresher.maybeRefresh(SavedLibraryList.playlists), isTrue);
      expect(
        await refresher.maybeRefresh(SavedLibraryList.playlists),
        isFalse,
        reason: 'retrying the same failure immediately only spends more of '
            'the rate-limit budget',
      );
      expect(calls, 1);
    });
  });
}
