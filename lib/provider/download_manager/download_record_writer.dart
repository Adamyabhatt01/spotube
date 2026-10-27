import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager/download_paths.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';

/// Writes the download manager's in-memory queue to the `track_download` /
/// playlist-membership rows.
///
/// Every write is best-effort: the rows are a record of transfers, not a gate
/// on them, so a lost write is reported and the next session's
/// [reconcilePersisted] or the filesystem checks in the manager still describe
/// reality.
class DownloadRecordWriter {
  final Ref ref;

  DownloadRecordWriter(this.ref);

  /// Where [task]'s track is going on disk, plus everything the row needs.
  ///
  /// Always via [downloadSavePath], so the path in the database and the path a
  /// worker writes to cannot drift, and `baseName` is the same string
  /// `DownloadedFileIndex` keys on. The `trackData` payload comes from the
  /// task's cached encode; a task without one falls back to encoding on
  /// demand, so an ad-hoc construction still works.
  DownloadRecord recordFor(
    DownloadTask task,
    DownloadPersistedStatus status, {
    String? error,
    int? sizeBytes,
  }) {
    final track = task.track;
    final presets = ref.read(audioSourcePresetsProvider);
    // Presets start empty while the audio plugin loads, and a persisted
    // index can go stale when the plugin's list shrinks. Direct indexing
    // threw RangeError here; fail with a meaningful error instead.
    final container = selectedDownloadContainer(presets);
    if (container == null) {
      throw StateError(
        'No download container preset at index '
        '${presets.selectedDownloadingContainerIndex} '
        '(${presets.presets.length} available)',
      );
    }
    final downloadLocation = ref.read(
        userPreferencesProvider.select((value) => value.downloadLocation));
    final savePath = downloadSavePath(
      track,
      downloadLocation,
      container,
      useRetryFilePath: task.useRetryFilePath,
    );

    return DownloadRecord(
      trackId: track.id,
      filePath: savePath,
      baseName: basenameWithoutExtension(savePath),
      status: status,
      trackData: task.trackData ?? jsonEncode(track.toJson()),
      error: error,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> recordQueued(List<DownloadTask> tasks) async {
    await _writing('queue', () async {
      await recordQueuedDownloads(
        ref.read(databaseProvider),
        [
          for (final task in tasks)
            recordFor(task, DownloadPersistedStatus.queued),
        ],
      );
    });
  }

  Future<void> attachMembership(
    String playlistId,
    List<String> trackIds,
  ) async {
    await _writing('membership', () async {
      await attachTracksToPlaylist(
        ref.read(databaseProvider),
        playlistId: playlistId,
        trackIds: trackIds,
      );
    });
  }

  Future<void> persistStatus(
    DownloadTask task,
    DownloadStatus status, {
    String? error,
  }) async {
    await _writing('status', () async {
      await writeDownloadStatus(
        ref.read(databaseProvider),
        recordFor(
          task,
          persistedStatusFor(status),
          sizeBytes: task.totalSizeBytes,
          // An exception string can carry a whole response body, and it is
          // stored per row in a database the UI reads on every list build.
          error: error == null ? null : truncateDownloadError(error, 500),
        ),
      );
    });
  }

  /// Brings the persisted view in line with a process that started over.
  ///
  /// Two things can only be settled from outside the row: a status still
  /// `queued`/`downloading` belongs to a worker that no longer exists, and a
  /// `completed` row whose file has gone is no longer a completed download.
  /// Existence checks run in waves of [downloadExistenceWaveSize] — the
  /// batching `localTracksProvider` uses — so a large download folder does not
  /// open every handle at once.
  Future<void> reconcilePersisted() async {
    final database = ref.read(databaseProvider);
    try {
      await database.transaction(
        () => markInFlightAsInterrupted(database),
      );

      final completed = await downloadsIn(
        database,
        const {DownloadPersistedStatus.completed},
      );
      for (var start = 0;
          start < completed.length;
          start += downloadExistenceWaveSize) {
        final wave = completed.sublist(
          start,
          (start + downloadExistenceWaveSize).clamp(0, completed.length),
        );
        final vanished = <String>[];
        await Future.wait(
          wave.map((row) async {
            if (!await File(row.filePath).exists()) vanished.add(row.trackId);
          }),
        );
        // Losing the file is reported, never repaired: nothing here deletes or
        // re-creates an audio file.
        await markDownloadsMissing(database, vanished);
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  Future<void> _writing(String what, Future<void> Function() write) async {
    try {
      await write();
    } catch (e, stack) {
      AppLogger.reportError('Could not record download $what: $e', stack);
    }
  }
}
