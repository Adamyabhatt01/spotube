// The whole-library wipe: which files a download record entitles the app to
// delete, what a bulk clear removes, and what still cannot resurrect a record.
//
// `filePath` is recorded, not owned — an existing file can be adopted and a row
// keeps its old path after the download location moves — so the boundary test is
// the safety property, and it is deliberately filesystem-free.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/downloads/download_wipe.dart';
import 'package:spotube/services/downloads/local_library_wipe.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

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

SpotubeSimplePlaylistObject _playlist({String id = 'playlist-a'}) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: 'My Playlist',
    description: 'A playlist under test',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

/// Downloads that record nothing.
///
/// `clearAll` reads the notifier's `state`, which a notifier built outside a
/// container has no element for, so the double overrides it and counts the call
/// instead — the wipe's guarantee is precisely that the queue was emptied.
class _NoopDownloads extends DownloadManagerNotifier {
  int clearAllCalls = 0;

  @override
  void clearAll() => clearAllCalls++;

  @override
  void addAllToQueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
    bool useRetryFilePath = false,
  }) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  const downloadRoot = '/storage/emulated/0/Download/Spotube';
  const cacheRoot =
      '/storage/emulated/0/Android/data/io.codeat.spotube/cache/Cached Tracks';

  group('selectFilesToDelete', () {
    test('keeps files inside the download root and the cache leaf', () {
      final selected = selectFilesToDelete(
        filePaths: [
          p.join(downloadRoot, 'a.weba'),
          p.join(cacheRoot, 'b.mp4'),
        ],
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: const [],
      );

      expect(selected, hasLength(2));
    });

    test('spares files inside a library location the user added', () {
      const ownMusic = '/storage/emulated/0/Music';

      final selected = selectFilesToDelete(
        filePaths: [
          p.join(ownMusic, 'recorded-by-user.flac'),
          p.join(downloadRoot, 'ours.weba'),
        ],
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: const [ownMusic],
      );

      expect(selected, [p.normalize(p.join(downloadRoot, 'ours.weba'))]);
    });

    test('deletes nothing when the download root sits in a library location',
        () {
      // The user pointed Spotube's downloads at a folder they also added as
      // music. Every download path is then also a user path.
      final selected = selectFilesToDelete(
        filePaths: [p.join('/storage/Music/Spotube', 'a.weba')],
        downloadRoot: '/storage/Music/Spotube',
        cacheRoot: cacheRoot,
        libraryLocations: const ['/storage/Music'],
      );

      expect(selected, isEmpty);
    });

    test('spares an adopted file and a file left at an old location', () {
      final selected = selectFilesToDelete(
        filePaths: [
          '/storage/emulated/0/Download/Spotube.old/gone.weba',
          '/data/data/io.codeat.spotube/files/tracks/hand-off.weba',
        ],
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: const [],
      );

      expect(selected, isEmpty);
    });

    test('ignores empty paths and collapses duplicates', () {
      final selected = selectFilesToDelete(
        filePaths: [
          '',
          p.join(downloadRoot, 'shared.weba'),
          p.join(downloadRoot, 'shared.weba'),
        ],
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: const [],
      );

      expect(selected, hasLength(1));
    });

    test('sums only recorded sizes', () {
      expect(sumDownloadedBytes([100, null, 250]), 350);
      expect(sumDownloadedBytes(const []), 0);
    });

    test('formats byte totals', () {
      expect(formatByteTotal(512), '512 B');
      expect(formatByteTotal(1536), '1.5 KB');
      expect(formatByteTotal(5 << 30), '5.0 GB');
    });
  });

  group('clearAllDownloadRecords', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('drops mirrors, membership and downloads, and nothing else', () async {
      final playlist = _playlist();
      await writePlaylistMirror(
        db,
        playlistId: playlist.id,
        playlistData: jsonEncode(playlist.toJson()),
        trackCount: 2,
        autoDownload: true,
      );
      await writePlaylistMembership(
        db,
        playlistId: playlist.id,
        trackIds: const ['t1', 't2'],
      );
      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: 't1',
          filePath: p.join(downloadRoot, 't1.weba'),
          baseName: 't1',
          status: DownloadPersistedStatus.completed,
          trackData: '{}',
          sizeBytes: 10,
        ),
      );
      await db.into(db.librarySnapshotTable).insert(
            LibrarySnapshotTableData(
              key: librarySnapshotKeySavedAlbums,
              data: '[]',
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      await clearAllDownloadRecords(db);

      expect(await allDownloads(db), isEmpty);
      expect(await playlistMirrors(db), isEmpty);
      expect(await playlistMembership(db, playlist.id), isEmpty);
      // Not this action's business: a Spotify-state cache outlives the wipe.
      expect(
        await db.select(db.librarySnapshotTable).get(),
        hasLength(1),
      );
    });

    test('allDownloads reports every row whatever its status', () async {
      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: 'q1',
          filePath: p.join(downloadRoot, 'q1.weba'),
          baseName: 'q1',
          status: DownloadPersistedStatus.queued,
          trackData: '{}',
        ),
      );

      final rows = await allDownloads(db);

      expect(rows.map((row) => row.trackId), ['q1']);
      expect(rows.single.sizeBytes, isNull);
    });
  });

  group('forgetEverything', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() async => db.close());

    test(
        'a background walk in flight when the library is wiped leaves no '
        'rows behind', () async {
      // The walk is parked mid-fetch across the wipe. Two independent guards
      // cover it: the generation the wipe invalidates (a playlist this service
      // never saw reads as generation 0, so only the global epoch can change
      // that answer) and the header read in `_stillWanted`, which now finds
      // nothing. Both must hold — the walk may not write a header, a membership
      // list or a download row.
      const unseen = 'playlist-never-touched';
      final playlist = _playlist(id: unseen);
      await writePlaylistMirror(
        db,
        playlistId: unseen,
        playlistData: jsonEncode(playlist.toJson()),
        trackCount: 1,
        autoDownload: true,
      );

      final parked = Completer<void>();
      final serviceWithGate = PlaylistMirrorService(
        database: db,
        downloads: _NoopDownloads(),
        fetchTracksPage: (playlistId, offset, limit) async {
          await parked.future;
          return SpotubePaginationResponseObject(
            limit: limit,
            nextOffset: null,
            total: 1,
            hasMore: false,
            items: [_track('t1')],
          );
        },
      );

      final walk = serviceWithGate.syncAutoDownloadPlaylist(playlist);
      await Future<void>.delayed(Duration.zero);

      await serviceWithGate.forgetEverything();
      parked.complete();
      await walk;

      expect(await playlistMirrors(db), isEmpty);
      expect(await playlistMembership(db, unseen), isEmpty);
      expect(await allDownloads(db), isEmpty);
    });

    test('clears the queue so a late completion writes nothing', () async {
      final downloads = _NoopDownloads();
      final wipeService = PlaylistMirrorService(
        database: db,
        downloads: downloads,
      );
      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: 't9',
          filePath: p.join(downloadRoot, 't9.weba'),
          baseName: 't9',
          status: DownloadPersistedStatus.completed,
          trackData: '{}',
        ),
      );

      await wipeService.forgetEverything();

      expect(await allDownloads(db), isEmpty);
      // The emptied queue is what stops a transfer that finishes late from
      // writing both a row and a file.
      expect(downloads.clearAllCalls, 1);
    });
  });

  group('planDownloadWipe / executeDownloadWipe', () {
    late AppDatabase db;
    late Directory root;
    late String downloadRoot;
    late String cacheRoot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = await Directory.systemTemp.createTemp('spotube-wipe-');
      downloadRoot = p.join(root.path, 'Spotube');
      cacheRoot = p.join(root.path, 'cache');
      await Directory(downloadRoot).create();
      await Directory(cacheRoot).create();
    });

    tearDown(() async {
      await db.close();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    Future<void> record(String trackId, String path, {int? size}) {
      return writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: trackId,
          filePath: path,
          baseName: trackId,
          status: DownloadPersistedStatus.completed,
          trackData: '{}',
          sizeBytes: size,
        ),
      );
    }

    test('plans only owned files and deletes them plus the cache', () async {
      final ours = File(p.join(downloadRoot, 'ours.weba'))
        ..writeAsStringSync('0123456789');
      final cached = File(p.join(cacheRoot, 'cached.mp4'))
        ..writeAsStringSync('cache');
      final user = File(p.join(root.path, 'user.flac'))
        ..writeAsStringSync('user');
      await record('t1', ours.path, size: 10);
      await record('t2', user.path, size: 99);

      final plan = await planDownloadWipe(
        database: db,
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: const [],
      );

      expect(plan.files, [p.normalize(ours.path)]);
      expect(plan.bytes, 10);
      expect(plan.hasRecords, isTrue);

      expect(await executeDownloadWipe(plan), 0);
      expect(ours.existsSync(), isFalse);
      // The cache directory is removed wholesale, not only recorded rows.
      expect(cached.existsSync(), isFalse);
      // A record does not make a user's own file deletable.
      expect(user.existsSync(), isTrue);
    });

    test('a library location keeps its files and contributes no bytes',
        () async {
      final userMusic = p.join(root.path, 'Music');
      await Directory(userMusic).create();
      final theirs = File(p.join(userMusic, 'theirs.flac'))
        ..writeAsStringSync('theirs');
      await record('t3', theirs.path, size: 99);

      final plan = await planDownloadWipe(
        database: db,
        downloadRoot: downloadRoot,
        cacheRoot: cacheRoot,
        libraryLocations: [userMusic],
      );

      expect(plan.files, isEmpty);
      expect(plan.bytes, 0);
      expect(plan.hasRecords, isTrue);
    });
  });
}
