// Tests for the mirror: the rules that decide when a playlist's stored
// membership changes, and which tracks a sync is allowed to start work on.
//
// The download manager is replaced by a recorder, because what these tests
// assert is the mirror's decision — which tracks it offered — not the transfer
// machinery, which `download_persistence_test.dart` covers.

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';

/// The tracks handed to `addAllToQueue`, one entry per call.
class _Recorder extends DownloadManagerNotifier {
  final List<List<SpotubeFullTrackObject>> batches = [];

  @override
  void addAllToQueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
    bool useRetryFilePath = false,
  }) {
    batches.add(tracks);
  }

  List<String> get offeredIds => [
        for (final batch in batches)
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

/// A page of two tracks, as the plugin would hand one over.
SpotubePaginationResponseObject<SpotubeFullTrackObject> _page({
  required List<String> ids,
  required int total,
  required bool hasMore,
}) {
  return SpotubePaginationResponseObject(
    limit: 2,
    nextOffset: hasMore ? ids.length : null,
    total: total,
    hasMore: hasMore,
    items: [for (final id in ids) _track(id)],
  );
}

String _storedPlaylistName(PlaylistDownloadMirrorTableData header) {
  return SpotubeSimplePlaylistObject.fromJson(
          jsonDecode(header.playlistData) as Map<String, dynamic>)
      .name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late AppDatabase db;
  late _Recorder downloads;
  late PlaylistMirrorService mirror;
  late SpotubeSimplePlaylistObject playlist;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    downloads = _Recorder();
    mirror = PlaylistMirrorService(database: db, downloads: downloads);
    playlist = _playlist();
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> storedOrder({String playlistId = 'playlist-a'}) async {
    return [
      for (final row in await playlistMembership(db, playlistId)) row.trackId
    ];
  }

  Future<void> recordStatus(
    String trackId,
    DownloadPersistedStatus status,
  ) {
    return writeDownloadStatus(
      db,
      DownloadRecord(
        trackId: trackId,
        filePath: '/music/$trackId.weba',
        baseName: trackId,
        status: status,
        trackData: '{}',
      ),
    );
  }

  group('mirror', () {
    test('records the header and the order it was given', () async {
      await mirror.mirror(playlist, [_track('one'), _track('two')]);

      final header = (await playlistMirrors(db)).single;
      expect(header.playlistId, 'playlist-a');
      expect(header.trackCount, 2);
      expect(_storedPlaylistName(header), 'My Playlist');
      expect(await storedOrder(), ['one', 'two']);
    });

    test('starts no transfers of its own', () async {
      await mirror.mirror(playlist, [_track('one')]);
      expect(downloads.batches, isEmpty);
    });

    test('a second download of the same playlist is the same mirror', () async {
      await mirror.mirror(playlist, [_track('one')]);
      await mirror.mirror(playlist, [_track('two'), _track('one')]);

      expect(await playlistMirrors(db), hasLength(1));
      expect(await storedOrder(), ['two', 'one']);
    });
  });

  group('reconcile', () {
    test('a playlist nobody mirrored is left alone entirely', () async {
      await mirror.reconcile(
        playlist,
        _page(ids: ['one'], total: 1, hasMore: false),
        (offset, limit) async => throw StateError('never called'),
      );

      expect(await playlistMirrors(db), isEmpty);
      expect(await storedOrder(), isEmpty);
      expect(downloads.batches, isEmpty);
    });

    test('pages to the end and stores Spotify\'s order', () async {
      await mirror.mirror(playlist, [_track('one'), _track('two')]);
      downloads.batches.clear();

      final rest = [
        _page(ids: ['three', 'four'], total: 4, hasMore: false),
      ];
      var index = 0;
      await mirror.reconcile(
        playlist,
        _page(ids: ['one', 'two'], total: 4, hasMore: true),
        (offset, limit) async => rest[index++],
      );

      expect(await storedOrder(), ['one', 'two', 'three', 'four']);
      expect((await playlistMirrors(db)).single.trackCount, 4);
      expect(
        downloads.offeredIds,
        ['one', 'two', 'three', 'four'],
        reason: 'nothing had a record yet, so all of it is work',
      );
    });

    test('a completed track is not offered again, an unknown one is', () async {
      await mirror.mirror(playlist, [_track('one')]);
      await recordStatus('one', DownloadPersistedStatus.completed);
      downloads.batches.clear();

      await mirror.reconcile(
        playlist,
        _page(ids: ['one', 'two'], total: 2, hasMore: false),
        (offset, limit) async => throw StateError('one page only'),
      );

      expect(downloads.offeredIds, ['two']);
      expect(await storedOrder(), ['one', 'two']);
      expect(
        (await downloadOfTrack(db, 'one'))?.status,
        DownloadPersistedStatus.completed,
      );
    });

    test('a canceled track stays canceled', () async {
      await mirror.mirror(playlist, [_track('one')]);
      await recordStatus('one', DownloadPersistedStatus.canceled);
      downloads.batches.clear();

      await mirror.reconcile(
        playlist,
        _page(ids: ['one'], total: 1, hasMore: false),
        (offset, limit) async => throw StateError('one page only'),
      );

      expect(downloads.offeredIds, isEmpty);
      expect(
        (await downloadOfTrack(db, 'one'))?.status,
        DownloadPersistedStatus.canceled,
        reason: 'a sync does not overrule the user pressing cancel',
      );
    });

    test('a track dropped upstream loses membership but not its file record',
        () async {
      await mirror.mirror(playlist, [_track('one'), _track('two')]);
      await recordStatus('two', DownloadPersistedStatus.completed);

      await mirror.reconcile(
        playlist,
        _page(ids: ['one'], total: 1, hasMore: false),
        (offset, limit) async => throw StateError('one page only'),
      );

      expect(await storedOrder(), ['one']);
      final dropped = await downloadOfTrack(db, 'two');
      expect(
        dropped,
        isNotNull,
        reason: 'the app still owns that file, and says so',
      );
      expect(dropped?.status, DownloadPersistedStatus.completed);
    });

    test('a rename keeps the membership rows, because identity is the id',
        () async {
      await mirror.mirror(playlist, [_track('one')]);
      final before = await playlistMembership(db, 'playlist-a');

      await mirror.reconcile(
        _playlist(name: 'Renamed, still mine'),
        _page(ids: ['one'], total: 1, hasMore: false),
        (offset, limit) async => throw StateError('one page only'),
      );

      final after = await playlistMembership(db, 'playlist-a');
      expect([for (final row in after) row.trackId], ['one']);
      expect(
        after.single.addedAtMs,
        before.single.addedAtMs,
        reason: 'a re-sync must not make an old membership look new',
      );
      expect(
        _storedPlaylistName((await playlistMirrors(db)).single),
        'Renamed, still mine',
      );
    });

    test('one sync per playlist at a time', () async {
      await mirror.mirror(playlist, [_track('one')]);
      downloads.batches.clear();

      // The first sync is parked inside its page fetch — provably holding the
      // guard — when a second open arrives. That second one must do nothing.
      final secondPage =
          Completer<SpotubePaginationResponseObject<SpotubeFullTrackObject>>();
      final first = mirror.reconcile(
        playlist,
        _page(ids: ['one'], total: 4, hasMore: true),
        (offset, limit) => secondPage.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await mirror.reconcile(
        playlist,
        _page(ids: ['three'], total: 4, hasMore: false),
        (offset, limit) async => throw StateError('never called'),
      );
      secondPage.complete(_page(ids: ['two'], total: 4, hasMore: false));
      await first;

      expect(downloads.offeredIds, ['one', 'two']);
      expect(
        await storedOrder(),
        ['one', 'two'],
        reason: 'the competing sync never wrote membership either',
      );
    });

    test('a sync that runs out of pages keeps what already arrived', () async {
      await mirror.mirror(playlist, [_track('one')]);
      downloads.batches.clear();

      await mirror.reconcile(
        playlist,
        _page(ids: ['one'], total: 4, hasMore: true),
        (offset, limit) async => throw StateError('rate limited'),
      );

      expect(await storedOrder(), ['one']);
      expect(downloads.offeredIds, ['one']);
    });
  });
}
