// Tests for the persisted half of downloads: `track_download` rows as the
// single record of which file this app owns, `playlist_download` rows as
// membership, and the rules that keep a track shared by two playlists one
// download.
//
// Hermetic by construction: the audio file the download manager is about to
// "download" is created by the test, so the transfer short-circuits on the
// existing-file check and no network is touched. `sourcedTrackProvider` throws
// on purpose - if a test ever starts resolving a source, it fails loudly here.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'support/common_fakes.dart';

SpotubeFullTrackObject _track({
  String id = 'persisted-track',
  String name = 'Persisted Track',
  String artist = 'Test Artist',
}) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: '$id-artist',
        name: artist,
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: '$id-album',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

DownloadRecord _record(
  SpotubeFullTrackObject track,
  DownloadPersistedStatus status, {
  String? filePath,
}) {
  return DownloadRecord(
    trackId: track.id,
    filePath: filePath ?? '/music/${track.id}.mp3',
    baseName: track.id,
    status: status,
    trackData: '{}',
  );
}

/// Where [_savePathFor] puts [track] for the `weba` container in [location].
String _expectedPath(String location, SpotubeFullTrackObject track) {
  return p.join(
    location,
    ServiceUtils.sanitizeFilename(
      '${track.name} - ${track.artists.map((e) => e.name).join(', ')}.weba',
    ),
  );
}

/// Where a retried failure writes: id-suffixed, so it cannot reuse or
/// overwrite the file the failed attempt left behind.
String _expectedRetryPath(String location, SpotubeFullTrackObject track) {
  return p.join(
    location,
    ServiceUtils.sanitizeFilename(
      '${track.name} - ${track.artists.map((e) => e.name).join(', ')} '
      '[${track.id}].weba',
    ),
  );
}

/// Presets the test can load after the queue already exists, matching an app
/// whose audio-source plugin resolves after the first frame.
class _MutablePresetsNotifier
    extends AudioSourceAvailableQualityPresetsNotifier {
  _MutablePresetsNotifier(this.initial);

  final AudioSourcePresetsState initial;

  @override
  AudioSourcePresetsState build() => initial;

  void replace(AudioSourcePresetsState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('download store', () {
    test('a re-queued track keeps the row it already had', () async {
      await writeDownloadStatus(
        db,
        _record(_track(), DownloadPersistedStatus.completed),
      );
      await recordQueuedDownloads(db, [
        _record(_track(), DownloadPersistedStatus.queued),
      ]);

      final row = await downloadOfTrack(db, 'persisted-track');
      expect(
        row?.status,
        DownloadPersistedStatus.completed,
        reason: 'a second playlist must not make a finished file look pending',
      );
    });

    test('a canceled row is never promoted to completed', () async {
      await writeDownloadStatus(
        db,
        _record(_track(), DownloadPersistedStatus.canceled),
      );
      await writeDownloadStatus(
        db,
        _record(_track(), DownloadPersistedStatus.completed),
      );

      expect(
        (await downloadOfTrack(db, 'persisted-track'))?.status,
        DownloadPersistedStatus.canceled,
        reason: "the transfer's own worker can lose this race",
      );
    });

    test('in-flight rows are interrupted and vanished files are missing',
        () async {
      await recordQueuedDownloads(db, [
        _record(_track(id: 'was-queued'), DownloadPersistedStatus.queued),
        _record(
          _track(id: 'was-downloading'),
          DownloadPersistedStatus.queued,
        ),
        _record(
          _track(id: 'gone-file'),
          DownloadPersistedStatus.completed,
          filePath: '${Directory.systemTemp.path}/not-here.mp3',
        ),
      ]);
      await writeDownloadStatus(
        db,
        _record(
          _track(id: 'was-downloading'),
          DownloadPersistedStatus.downloading,
        ),
      );

      await db.transaction(() => markInFlightAsInterrupted(db));
      await markDownloadsMissing(db, ['gone-file']);

      expect(
        (await downloadOfTrack(db, 'was-queued'))?.status,
        DownloadPersistedStatus.interrupted,
      );
      expect(
        (await downloadOfTrack(db, 'was-downloading'))?.status,
        DownloadPersistedStatus.interrupted,
      );
      expect(
        (await downloadOfTrack(db, 'gone-file'))?.status,
        DownloadPersistedStatus.missing,
      );
    });

    test('a track in two playlists is one download and two memberships',
        () async {
      await recordQueuedDownloads(db, [
        _record(_track(), DownloadPersistedStatus.queued),
      ]);
      await attachTracksToPlaylist(
        db,
        playlistId: 'playlist-a',
        trackIds: ['persisted-track'],
      );
      await attachTracksToPlaylist(
        db,
        playlistId: 'playlist-b',
        trackIds: ['persisted-track'],
      );
      // Repeating an attach is a no-op, not a second row.
      await attachTracksToPlaylist(
        db,
        playlistId: 'playlist-a',
        trackIds: ['persisted-track'],
      );

      final memberships = await (db.select(db.playlistDownloadTable)).get();
      expect(memberships, hasLength(2));
      expect(
        await playlistsHoldingTrack(db, 'persisted-track'),
        {'playlist-a', 'playlist-b'},
      );
      expect(
        await (db.select(db.trackDownloadTable)).get(),
        hasLength(1),
        reason: 'one file, one row, however many playlists point at it',
      );
    });

    test('rewriting membership takes the new order and keeps addedAt',
        () async {
      await attachTracksToPlaylist(
        db,
        playlistId: 'playlist-a',
        trackIds: ['one', 'two'],
      );
      final before = await playlistMembership(db, 'playlist-a');
      final addedAtBefore = {
        for (final row in before) row.trackId: row.addedAtMs,
      };

      await writePlaylistMembership(
        db,
        playlistId: 'playlist-a',
        trackIds: ['two', 'one', 'three'],
      );
      final after = await playlistMembership(db, 'playlist-a');

      expect(after.map((row) => row.trackId), ['two', 'one', 'three']);
      expect(
        after.map((row) => row.position),
        [0, 1, 2],
        reason: 'position is the order Spotify reported, rewritten whole',
      );
      for (final trackId in ['one', 'two']) {
        expect(
          after.where((row) => row.trackId == trackId).single.addedAtMs,
          addedAtBefore[trackId],
          reason: 'a re-sync must not make an old membership look new',
        );
      }
    });
  });

  group('download manager', () {
    late Directory root;
    late ProviderContainer container;
    late SpotubeFullTrackObject track;
    late String savePath;

    Future<DownloadPersistedStatus?> statusOf(String trackId) async =>
        (await downloadOfTrack(db, trackId))?.status;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('dl_persist_');
      PathProviderPlatform.instance = FakePathProvider(root.path);
      track = _track();
      savePath = _expectedPath(root.path, track);

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
    });

    tearDown(() async {
      // A worker left mid-transfer reads providers from its own container, so
      // emptying the queue (which cancels in-flight tokens) comes before the
      // dispose: the alternative is a failure recorded against a dead
      // container, and log noise that hides a real error.
      container.read(downloadManagerProvider.notifier).clearAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      container.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    /// The file the download manager would have written, planted beforehand so
    /// the existing-file check ends the transfer without a network round trip.
    void plantDownloadedFile() {
      File(savePath).writeAsStringSync('already on disk');
    }

    /// Wait for the row to reach a state a worker writes last, so no
    /// continuation of this download is still running when the test ends.
    Future<DownloadPersistedStatus?> settle() async {
      const terminal = {
        DownloadPersistedStatus.completed,
        DownloadPersistedStatus.failed,
        DownloadPersistedStatus.canceled,
        DownloadPersistedStatus.missing,
      };
      for (var i = 0; i < 100; i++) {
        final status = await statusOf(track.id);
        if (terminal.contains(status)) return status;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return statusOf(track.id);
    }

    test('a finished download is recorded with its path and playlist',
        () async {
      plantDownloadedFile();

      container
          .read(downloadManagerProvider.notifier)
          .addToQueue(track, collectionId: 'playlist-a');
      expect(
        await settle(),
        DownloadPersistedStatus.completed,
        reason:
            'the planted file is what "already downloaded" means: ${(await downloadOfTrack(db, track.id))?.error}',
      );

      final row = await downloadOfTrack(db, track.id);
      expect(row?.status, DownloadPersistedStatus.completed);
      expect(row?.filePath, savePath);
      expect(row?.baseName, p.basenameWithoutExtension(savePath));
      expect(
        (await playlistMembership(db, 'playlist-a')).map((e) => e.trackId),
        [track.id],
      );
    });

    test('a second playlist attaches to the same file and re-downloads nothing',
        () async {
      plantDownloadedFile();
      final originalStat = File(savePath).statSync();

      container
          .read(downloadManagerProvider.notifier)
          .addToQueue(track, collectionId: 'playlist-a');
      await settle();
      container
          .read(downloadManagerProvider.notifier)
          .addAllToQueue([track], collectionId: 'playlist-b');
      await settle();
      expect(
        await (db.select(db.trackDownloadTable)).get(),
        hasLength(1),
        reason: 'one row per owned file',
      );
      expect(
        await playlistsHoldingTrack(db, track.id),
        {'playlist-a', 'playlist-b'},
      );
      expect(
        File(savePath).statSync().size,
        originalStat.size,
        reason: 'nothing was written the second time',
      );
      expect(
        container
            .read(downloadManagerProvider)
            .where((e) => e.track.id == track.id),
        hasLength(1),
        reason: 'the in-memory queue stayed single-flight too',
      );
    });

    test('a batch cannot queue the same track twice', () async {
      final second = _track(id: 'second-track');
      container
          .read(downloadManagerProvider.notifier)
          .addAllToQueue([track, track, second]);

      final live = container.read(downloadManagerProvider);
      expect(live, hasLength(2));
      expect(
        live.map((e) => e.track.id),
        containsAllInOrder([track.id, second.id]),
      );
    });

    test('a retry uses a fresh path and leaves the failed file untouched',
        () async {
      plantDownloadedFile();
      final before = File(savePath).readAsStringSync();
      await writeDownloadStatus(
        db,
        _record(track, DownloadPersistedStatus.failed, filePath: savePath),
      );

      container.read(downloadManagerProvider.notifier).addAllToQueue(
        [track],
        useRetryFilePath: true,
      );

      final retryPath = _expectedRetryPath(root.path, track);
      // The row's path is written on the first status transition; the source
      // is intentionally unavailable here, so wait for the failed transition.
      for (var i = 0; i < 100; i++) {
        if ((await downloadOfTrack(db, track.id))?.filePath == retryPath) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final row = await downloadOfTrack(db, track.id);
      expect(row?.filePath, retryPath);
      expect(row?.status, DownloadPersistedStatus.failed);
      expect(
        File(savePath).readAsStringSync(),
        before,
        reason: 'a retry must not overwrite the file it is recovering from',
      );
    });

    test('a download queued before presets load waits, then starts', () async {
      final presetsNotifier = _MutablePresetsNotifier(
        AudioSourcePresetsState(),
      );
      final waiting = ProviderContainer(
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
          audioSourcePresetsProvider.overrideWith(() => presetsNotifier),
          sourcedTrackProvider
              .overrideWith(() => NeverResolvesSourcedTrackNotifier()),
        ],
      );
      addTearDown(() {
        waiting.read(downloadManagerProvider.notifier).clearAll();
        waiting.dispose();
      });

      waiting.read(downloadManagerProvider.notifier).addToQueue(track);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        waiting.read(downloadManagerProvider).single.status,
        DownloadStatus.queued,
        reason: 'no container means no destination, not a failure',
      );
      expect(
        await downloadOfTrack(db, track.id),
        isNull,
        reason: 'without a destination there is no queued row to record yet',
      );

      plantDownloadedFile();
      presetsNotifier.replace(
        AudioSourcePresetsState(
          presets: [
            SpotubeAudioSourceContainerPreset.lossy(
              type: SpotubeMediaCompressionType.lossy,
              name: 'weba',
              qualities: [SpotubeAudioLossyContainerQuality(bitrate: 128000)],
            ),
          ],
        ),
      );

      DownloadPersistedStatus? status;
      for (var i = 0; i < 100; i++) {
        status = await statusOf(track.id);
        if (status == DownloadPersistedStatus.completed) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(status, DownloadPersistedStatus.completed);
    });

    test('work left in flight by a dead process comes back interrupted',
        () async {
      await recordQueuedDownloads(db, [
        _record(track, DownloadPersistedStatus.queued),
      ]);

      // Reading the notifier rebuilds it, and `build()` reconciles the table.
      container.read(downloadManagerProvider);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (await statusOf(track.id) == DownloadPersistedStatus.interrupted) {
          break;
        }
      }

      expect(
        await statusOf(track.id),
        DownloadPersistedStatus.interrupted,
        reason: 'a killed download is not a completed one, and not a lie',
      );
      expect(
        container.read(downloadManagerProvider),
        isEmpty,
        reason: 'interrupted rows are not resumed into the live queue',
      );
    });
  });
}
