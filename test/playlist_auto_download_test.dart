// Automatic-download synchronization: opt-in is per playlist, work is paged,
// and a track's recorded file is reusable from any playlist. The download
// manager is replaced by a recorder: these tests assert the mirror's decisions
// (what to fetch, what to offer, what to persist), not the transfer pool.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';

class _Recorder extends DownloadManagerNotifier {
  final List<List<SpotubeFullTrackObject>> batches = [];
  final List<List<SpotubeFullTrackObject>> retryBatches = [];
  final Set<String> liveTrackIds = {};
  final Set<String> failedTrackIds = {};
  final List<String> retriedIds = [];
  final List<bool> retriedWithRetryPath = [];

  @override
  DownloadTask? getTaskByTrackId(String trackId) {
    if (!liveTrackIds.contains(trackId) && !failedTrackIds.contains(trackId)) {
      return null;
    }
    return DownloadTask(
      track: _track(trackId),
      status: failedTrackIds.contains(trackId)
          ? DownloadStatus.failed
          : DownloadStatus.queued,
      cancelToken: CancelToken(),
      trackData: '{}',
    );
  }

  @override
  void retry(
    SpotubeFullTrackObject track, {
    bool useRetryFilePath = false,
  }) {
    retriedIds.add(track.id);
    retriedWithRetryPath.add(useRetryFilePath);
  }

  @override
  void addAllToQueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
    bool useRetryFilePath = false,
  }) {
    (useRetryFilePath ? retryBatches : batches).add(tracks);
  }

  List<String> get offeredIds => [
        for (final batch in [...batches, ...retryBatches])
          for (final track in batch) track.id,
      ];

  List<String> get retryOfferedIds => [
        for (final batch in retryBatches)
          for (final track in batch) track.id,
      ];
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST000000$id',
    explicit: false,
  );
}

SpotubeSimplePlaylistObject _playlist({
  String id = 'playlist-a',
  String name = 'My Playlist',
}) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: name,
    description: 'A playlist under test',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

SpotubePaginationResponseObject<SpotubeFullTrackObject> _page({
  required List<String> ids,
  required int total,
  required bool hasMore,
  int? nextOffset,
}) {
  return SpotubePaginationResponseObject(
    limit: 50,
    nextOffset: hasMore ? nextOffset ?? ids.length : null,
    total: total,
    hasMore: hasMore,
    items: [for (final id in ids) _track(id)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late AppDatabase db;
  late Directory root;
  late _Recorder downloads;
  late SpotubeSimplePlaylistObject playlist;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('auto_download_');
    downloads = _Recorder();
    playlist = _playlist();
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  String filePath(String trackId) => p.join(root.path, '$trackId.weba');

  void plant(String trackId) {
    File(filePath(trackId)).writeAsStringSync('already on disk');
  }

  Future<void> record(
    String trackId,
    DownloadPersistedStatus status, {
    bool plantFile = true,
  }) async {
    if (plantFile) plant(trackId);
    await writeDownloadStatus(
      db,
      DownloadRecord(
        trackId: trackId,
        filePath: filePath(trackId),
        baseName: trackId,
        status: status,
        trackData: '{}',
      ),
    );
  }

  Future<void> autoHeader(SpotubeSimplePlaylistObject item) {
    return writePlaylistMirror(
      db,
      playlistId: item.id,
      playlistData: jsonEncode(item.toJson()),
      trackCount: 0,
      autoDownload: true,
    );
  }

  Future<List<String>> storedOrder(String playlistId) async => [
        for (final row in await playlistMembership(db, playlistId)) row.trackId,
      ];

  PlaylistMirrorService serviceWith(
    Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> Function(
      String playlistId,
      int offset,
      int limit,
    ) fetch, {
    Duration throttle = Duration.zero,
  }) {
    return PlaylistMirrorService(
      database: db,
      downloads: downloads,
      fetchTracksPage: fetch,
      autoSyncThrottle: throttle,
    );
  }

  test('pages through a playlist and writes membership after the last page',
      () async {
    await autoHeader(playlist);
    final pages = {
      0: _page(ids: ['a', 'b'], total: 3, hasMore: true, nextOffset: 2),
      2: _page(ids: ['c'], total: 3, hasMore: false),
    };
    final service = serviceWith(
      (playlistId, offset, limit) async => pages[offset]!,
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(await storedOrder(playlist.id), ['a', 'b', 'c']);
    expect(downloads.offeredIds, ['a', 'b', 'c']);
    final header = await playlistMirror(db, playlist.id);
    expect(header?.autoDownload, isTrue);
    expect(header?.trackCount, 3);
  });

  test('a valid file recorded by another playlist is reused, not queued',
      () async {
    await record('shared', DownloadPersistedStatus.completed);
    final other = _playlist(id: 'playlist-b');
    await autoHeader(playlist);
    await autoHeader(other);

    final service = serviceWith(
      (playlistId, offset, limit) async => _page(
        ids: ['shared'],
        total: 1,
        hasMore: false,
      ),
    );
    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.batches, isEmpty);
    expect(await storedOrder(playlist.id), ['shared']);
    expect(await storedOrder(other.id), ['shared']);
    expect(
      (await db.select(db.trackDownloadTable).get()).where(
        (row) => row.trackId == 'shared',
      ),
      hasLength(1),
      reason: 'one track is one global row, not one per playlist',
    );
  });

  test('a completed row whose file vanished is marked missing and requeued',
      () async {
    await record('gone', DownloadPersistedStatus.completed, plantFile: false);
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['gone'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(
      (await downloadOfTrack(db, 'gone'))?.status,
      DownloadPersistedStatus.missing,
      reason: 'a completed row must not claim a file that is not there',
    );
    expect(downloads.offeredIds, ['gone']);
  });

  test('a live task is not queued again', () async {
    downloads.liveTrackIds.add('running');
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['running'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.batches, isEmpty);
    expect(await storedOrder(playlist.id), ['running']);
  });

  test('a failed in-memory task is retried instead of duplicated', () async {
    downloads.failedTrackIds.add('offline');
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['offline'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.batches, isEmpty);
    expect(downloads.retriedIds, ['offline']);
    expect(
      downloads.retriedWithRetryPath,
      [true],
      reason: 'a retried failure must not reuse its partial file',
    );
    expect(await storedOrder(playlist.id), ['offline']);
  });

  test('a persisted failed row is retried even when a file survived', () async {
    // A failure can leave a non-empty partial file. It is not a completed
    // download just because it has bytes.
    await record('broken', DownloadPersistedStatus.failed);
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['broken'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.batches, isEmpty);
    expect(downloads.retryOfferedIds, ['broken']);
    expect(await storedOrder(playlist.id), ['broken']);
  });

  test('an interrupted row is retried on restart instead of reused', () async {
    await record('killed', DownloadPersistedStatus.interrupted);
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['killed'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.retryOfferedIds, ['killed']);
  });

  test('a canceled row is never retried by a background sync', () async {
    await record('canceled', DownloadPersistedStatus.canceled);
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['canceled'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(downloads.batches, isEmpty);
    expect(downloads.retryBatches, isEmpty);
    expect(await storedOrder(playlist.id), ['canceled']);
  });

  test('an empty completed file is marked missing and retried', () async {
    await record('empty', DownloadPersistedStatus.completed, plantFile: false);
    File(filePath('empty')).writeAsStringSync('');
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['empty'], total: 1, hasMore: false),
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(
      (await downloadOfTrack(db, 'empty'))?.status,
      DownloadPersistedStatus.missing,
    );
    expect(downloads.retryOfferedIds, ['empty']);
  });

  test('a failed walk writes no membership and retries on the next trigger',
      () async {
    await autoHeader(playlist);
    var failSecondPage = true;
    final service = serviceWith(
      (playlistId, offset, limit) async {
        if (offset == 0) {
          return _page(
            ids: ['a'],
            total: 2,
            hasMore: true,
            nextOffset: 1,
          );
        }
        if (failSecondPage) throw StateError('offline');
        return _page(ids: ['b'], total: 2, hasMore: false);
      },
      throttle: const Duration(hours: 1),
    );

    await service.syncAutoDownloadPlaylists(force: true);
    expect(
      await storedOrder(playlist.id),
      isEmpty,
      reason: 'a partial fetch must not replace the stored membership',
    );

    failSecondPage = false;
    // No force: a previous failure bypasses the success throttle.
    await service.syncAutoDownloadPlaylists();
    expect(await storedOrder(playlist.id), ['a', 'b']);
  });

  test('a sync requested during another walk is deferred, not dropped',
      () async {
    await autoHeader(playlist);
    final reconcileFetchStarted = Completer<void>();
    final releaseSecondPage =
        Completer<SpotubePaginationResponseObject<SpotubeFullTrackObject>>();
    final autoFetchStarted = Completer<void>();
    var autoFetches = 0;

    final service = serviceWith(
      (playlistId, offset, limit) async {
        autoFetches++;
        if (!autoFetchStarted.isCompleted) autoFetchStarted.complete();
        return _page(ids: ['fresh'], total: 1, hasMore: false);
      },
    );

    // The page-load reconcile holds `_inFlight` while its second page is in
    // flight; the toggle's sync request lands exactly in that window.
    final reconcileRun = service.reconcile(
      playlist,
      _page(ids: ['one'], total: 2, hasMore: true, nextOffset: 1),
      (offset, limit) {
        reconcileFetchStarted.complete();
        return releaseSecondPage.future;
      },
    );
    await reconcileFetchStarted.future;

    await service.syncAutoDownloadPlaylist(playlist);
    expect(autoFetches, 0,
        reason: 'the deferred run waits for the in-flight one');

    releaseSecondPage.complete(
      _page(ids: ['two'], total: 2, hasMore: false),
    );
    await reconcileRun;
    await autoFetchStarted.future.timeout(const Duration(seconds: 2));

    // The fetch callback starts before the deferred sync's membership write;
    // wait for that write to land before asserting and before teardown.
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while ((await storedOrder(playlist.id)).join(',') != 'fresh') {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(autoFetches, 1);
    expect(await storedOrder(playlist.id), ['fresh']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('deleting a playlist during a walk cannot recreate its mirror',
      () async {
    await autoHeader(playlist);
    final reachedSecondPage = Completer<void>();
    final secondPage =
        Completer<SpotubePaginationResponseObject<SpotubeFullTrackObject>>();
    final service = serviceWith(
      (playlistId, offset, limit) async {
        if (offset == 0) {
          return _page(
            ids: ['a'],
            total: 2,
            hasMore: true,
            nextOffset: 1,
          );
        }
        if (!reachedSecondPage.isCompleted) reachedSecondPage.complete();
        return secondPage.future;
      },
    );

    final run = service.syncAutoDownloadPlaylists(force: true);
    await reachedSecondPage.future;
    await service.forget(playlist.id);
    secondPage.complete(_page(ids: ['b'], total: 2, hasMore: false));
    await run;

    expect(await playlistMirror(db, playlist.id), isNull);
    expect(await storedOrder(playlist.id), isEmpty);
    expect(
      downloads.offeredIds,
      isNot(contains('b')),
      reason: 'a page fetched after deletion must not start work',
    );
  });

  test('disabling auto-download keeps membership, rows and files', () async {
    await record('kept', DownloadPersistedStatus.completed);
    await autoHeader(playlist);
    final service = serviceWith(
      (playlistId, offset, limit) async =>
          _page(ids: ['kept'], total: 1, hasMore: false),
    );
    await service.syncAutoDownloadPlaylists(force: true);

    await service.setAutoDownload(playlist, false);

    final header = await playlistMirror(db, playlist.id);
    expect(header, isNotNull);
    expect(header?.autoDownload, isFalse);
    expect(await storedOrder(playlist.id), ['kept']);
    expect(
      (await downloadOfTrack(db, 'kept'))?.status,
      DownloadPersistedStatus.completed,
    );
    expect(File(filePath('kept')).existsSync(), isTrue);
  });

  test('playlists that never opted in are not fetched', () async {
    await writePlaylistMirror(
      db,
      playlistId: playlist.id,
      playlistData: jsonEncode(playlist.toJson()),
      trackCount: 0,
      autoDownload: false,
    );
    var calls = 0;
    final service = serviceWith(
      (playlistId, offset, limit) async {
        calls++;
        return _page(ids: ['a'], total: 1, hasMore: false);
      },
    );

    await service.syncAutoDownloadPlaylists(force: true);

    expect(calls, 0);
    expect(await storedOrder(playlist.id), isEmpty);
  });

  test('removing a mirror never removes a download row or its file', () async {
    await record('owned', DownloadPersistedStatus.completed);
    await writePlaylistMembership(
      db,
      playlistId: playlist.id,
      trackIds: ['owned'],
    );
    await autoHeader(playlist);

    await deletePlaylistMirror(db, playlist.id);

    expect(await playlistMirror(db, playlist.id), isNull);
    expect(await storedOrder(playlist.id), isEmpty);
    expect(
      (await downloadOfTrack(db, 'owned'))?.status,
      DownloadPersistedStatus.completed,
    );
    expect(File(filePath('owned')).existsSync(), isTrue);
  });
}
