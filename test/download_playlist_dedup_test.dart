// Tests for the deduplication rule of the download queue: one track is one
// task, one row and one file however many playlists ask for it.
//
// Every track here already has its file on disk, which is exactly what
// "downloaded" means to `_downloadTrack` — the transfer short-circuits on the
// existence check. So the queue runs for real, with no network and no source
// resolver: `sourcedTrackProvider` throws on purpose and a test that ever
// starts resolving a source fails loudly here.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';

import 'support/common_fakes.dart';

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

/// Where `_savePathFor` puts [track] for the `weba` container in [location].
String _expectedPath(String location, SpotubeFullTrackObject track) {
  return p.join(
    location,
    ServiceUtils.sanitizeFilename(
      '${track.name} - ${track.artists.map((e) => e.name).join(', ')}.weba',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late AppDatabase db;
  late Directory root;
  late ProviderContainer container;
  late DownloadManagerNotifier notifier;

  List<String> queuedIds() =>
      container.read(downloadManagerProvider).map((e) => e.track.id).toList();

  List<String> sortedIds(Iterable<String> ids) => ids.toList()..sort();

  Future<List<String>> membershipOf(String playlistId) async =>
      (await playlistMembership(db, playlistId)).map((e) => e.trackId).toList();

  Future<List<TrackDownloadTableData>> rows() =>
      db.select(db.trackDownloadTable).get();

  Future<TrackDownloadTableData?> rowOf(String trackId) =>
      downloadOfTrack(db, trackId);

  /// The file [_track] would download into, planted so the existence check ends
  /// the transfer. Returns its path.
  String plant(SpotubeFullTrackObject track) {
    final path = _expectedPath(root.path, track);
    File(path).writeAsStringSync('already on disk');
    return path;
  }

  /// Wait for [trackId]'s row to reach a state a worker writes last, so no
  /// continuation of its download is still running when the test moves on.
  Future<TrackDownloadTableData> settle(String trackId) async {
    const terminal = {
      DownloadPersistedStatus.completed,
      DownloadPersistedStatus.failed,
      DownloadPersistedStatus.canceled,
      DownloadPersistedStatus.missing,
    };
    TrackDownloadTableData? row;
    for (var i = 0; i < 100; i++) {
      row = await rowOf(trackId);
      if (terminal.contains(row?.status)) return row!;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail(
      'track $trackId never reached a terminal state '
      '(last row: ${row?.status}, error: ${row?.error})',
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('dl_dedup_');
    PathProviderPlatform.instance = FakePathProvider(root.path);

    final presets = AudioSourcePresetsState(
      presets: [
        SpotubeAudioSourceContainerPreset.lossy(
          type: SpotubeMediaCompressionType.lossy,
          name: 'weba',
          qualities: [SpotubeAudioLossyContainerQuality(bitrate: 128000)],
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(
            PreferencesTable.defaults().copyWith(downloadLocation: root.path),
          ),
        ),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
        audioSourcePresetsProvider.overrideWith(
          () => FixedPresetsNotifier(presets),
        ),
        sourcedTrackProvider
            .overrideWith(() => NeverResolvesSourcedTrackNotifier()),
      ],
    );
    notifier = container.read(downloadManagerProvider.notifier);
  });

  tearDown(() async {
    // A worker left mid-transfer reads providers from its own container, so
    // emptying the queue (which cancels in-flight tokens) comes before the
    // dispose.
    notifier.clearAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    container.dispose();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('one track, one download', () {
    test('a track arriving in a second batch is not queued twice', () {
      final a = _track('a');
      final b = _track('b');
      final c = _track('c');

      // Read synchronously: the queue is decided in the enqueue, before any
      // transfer has a chance to move a task out of `queued`.
      notifier.addAllToQueue([a, b], collectionId: 'playlist-a');
      notifier.addAllToQueue([b, c], collectionId: 'playlist-b');

      expect(
        queuedIds(),
        ['a', 'b', 'c'],
        reason: '`addAllToQueue` used to append a second task for `b`',
      );
    });

    test('a duplicate inside one batch is queued once', () {
      notifier.addAllToQueue([_track('a'), _track('a')]);

      expect(queuedIds(), ['a']);
    });

    test('a track two playlists share gets one row and two memberships',
        () async {
      final a = _track('a');
      final b = _track('b');
      final c = _track('c');
      plant(a);
      final sharedPath = plant(b);
      plant(c);
      final writtenBefore = File(sharedPath).statSync().modified;

      notifier.addAllToQueue([a, b], collectionId: 'playlist-a');
      notifier.addAllToQueue([b, c], collectionId: 'playlist-b');
      for (final id in ['a', 'b', 'c']) {
        expect((await settle(id)).status, DownloadPersistedStatus.completed,
            reason: 'the planted file is what "downloaded" means');
      }

      expect(
        sortedIds((await rows()).map((row) => row.trackId)),
        ['a', 'b', 'c'],
        reason: 'three tracks, one row each — `b` is not one row per playlist',
      );
      expect(await membershipOf('playlist-a'), ['a', 'b']);
      expect(await membershipOf('playlist-b'), ['b', 'c']);
      expect(
        await playlistsHoldingTrack(db, 'b'),
        {'playlist-a', 'playlist-b'},
      );
      expect(
        root.listSync().whereType<File>().map((f) => f.path).toList(),
        contains(sharedPath),
      );
      expect(File(sharedPath).statSync().modified, writtenBefore,
          reason: 'the second playlist must not have rewritten the file');
    });

    test('offering a finished track from a third playlist starts no transfer',
        () async {
      final b = _track('b');
      final path = plant(b);
      notifier.addAllToQueue([b], collectionId: 'playlist-a');
      await settle(b.id);
      notifier.clearAll();

      // The queue no longer holds it, so this is the case a name-matching scan
      // used to be the only defence against. The row answers it now.
      notifier.addAllToQueue([b], collectionId: 'playlist-b');
      expect((await settle(b.id)).status, DownloadPersistedStatus.completed);

      expect((await rows()).where((row) => row.trackId == 'b'), hasLength(1));
      expect(await membershipOf('playlist-b'), ['b']);
      expect(File(path).readAsStringSync(), 'already on disk');
    });
  });

  group('rows are keyed by track, not by file', () {
    test('two tracks that sanitize to one name keep their own rows', () async {
      // Two interludes both called "Intro" by one artist collide on file name.
      // The primary key is the Spotify id, so one never describes the other.
      final colliding =
          p.join(root.path, ServiceUtils.sanitizeFilename('Intro.weba'));
      DownloadRecord queued(String trackId) => DownloadRecord(
            trackId: trackId,
            filePath: colliding,
            baseName: 'Intro',
            status: DownloadPersistedStatus.queued,
            trackData: '{}',
          );
      await recordQueuedDownloads(db, [queued('x'), queued('y')]);

      expect(sortedIds((await rows()).map((row) => row.trackId)), ['x', 'y']);

      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: 'y',
          filePath: colliding,
          baseName: 'Intro',
          status: DownloadPersistedStatus.completed,
          trackData: '{}',
        ),
      );

      expect(
        (await rowOf('x'))?.status,
        DownloadPersistedStatus.queued,
        reason: 'finishing one track must not complete its namesake',
      );
    });

    test('losing a membership never touches the file or its row', () async {
      final track = _track('a');
      final path = plant(track);
      notifier.addAllToQueue([track], collectionId: 'playlist-a');
      await settle(track.id);

      await writePlaylistMembership(
        db,
        playlistId: 'playlist-a',
        trackIds: const [],
      );

      expect(await membershipOf('playlist-a'), isEmpty);
      expect(
          (await rowOf(track.id))?.status, DownloadPersistedStatus.completed);
      expect(File(path).existsSync(), isTrue);
    });
  });

  // Two different Spotify ids whose sanitized filename collides: this is a
  // real event (a cover and an original sharing "Artist - Title") and the
  // prefilter cannot claim both files exist when at most one track owns the
  // path.
  group('when two queued tracks share a file name', () {
    test('both claimants fail rather than one silently completing', () async {
      final original = _track('orig').copyWith(name: 'Collision');
      final twin = _track('twin').copyWith(name: 'Collision');
      plant(original);

      notifier.addAllToQueue([original, twin]);

      final origRow = await settle(original.id);
      final twinRow = await settle(twin.id);
      expect(origRow.status, DownloadPersistedStatus.failed,
          reason:
              'the prefilter cannot tell which of them the planted file is');
      expect(twinRow.status, DownloadPersistedStatus.failed);
      expect(origRow.error, contains('same file'));
      expect(twinRow.error, contains('same file'));
    });
  });

  // Scale is what the pre-optimization plan measures against. Anything here
  // that stops passing after a change means the change altered correctness,
  // not just speed.
  group('at scale', () {
    /// One `writePlaylistMembership` of a 500-track order is what a synced
    /// mirrored playlist costs: the exact ids, in the exact order, no dupes.
    test('a 500-track membership rewrite is exact', () async {
      final ids = [for (var i = 0; i < 500; i++) 't$i'];
      final stopwatch = Stopwatch()..start();
      await writePlaylistMembership(
        db,
        playlistId: 'big',
        trackIds: ids,
      );
      stopwatch.stop();
      // Baseline: prints in `flutter test --reporter expanded` so the next
      // optimization can quote a before/after instead of guessing.
      // ignore: avoid_print
      print('membership 500 write: ${stopwatch.elapsedMilliseconds} ms');

      final rows = await playlistMembership(db, 'big');
      expect(rows, hasLength(500));
      expect(rows.map((r) => r.trackId).toList(), ids,
          reason: 'order is the payload; a partial rewrite would be worse');
      expect(
        rows.map((r) => r.position).toList(),
        [for (var i = 0; i < 500; i++) i],
        reason: 'position must equal the list index, not the insert order',
      );
    });

    test('rewriting a 500-track membership keeps addedAt for survivors',
        () async {
      final original = [for (var i = 0; i < 500; i++) 't$i'];
      await writePlaylistMembership(
        db,
        playlistId: 'big',
        trackIds: original,
      );
      final before = await playlistMembership(db, 'big');
      final addedAtById = {
        for (final row in before) row.trackId: row.addedAtMs,
      };

      // Reverse the order and drop the first: every survivor must keep the
      // timestamp it was originally added with.
      final next = original.reversed.skip(1).toList();
      await writePlaylistMembership(
        db,
        playlistId: 'big',
        trackIds: next,
      );

      final after = await playlistMembership(db, 'big');
      expect(after, hasLength(499));
      for (final row in after) {
        expect(row.addedAtMs, addedAtById[row.trackId],
            reason: 'reorder must not make an old membership look new');
      }
    });
  });
}
