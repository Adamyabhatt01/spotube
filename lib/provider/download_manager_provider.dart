import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide join;
import 'package:spotube/collections/routes.dart';
import 'package:spotube/components/dialogs/replace_downloaded_dialog.dart';
import 'package:spotube/extensions/dio.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/utils/service_utils.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  canceled,
}

/// Delays between download attempts (3 attempts total). Downloads are
/// long-lived transfers; short-aggressive retries would hammer struggling
/// servers, so backoff is seconds-scale.
const downloadRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 6),
];

/// Whether a failed download attempt is worth retrying. Transient network
/// conditions (timeouts, refused/reset connections, 5xx, 429) are retried;
/// permanent failures (cancellation, other 4xx, missing URL, local file
/// errors) fail fast instead of looping pointlessly.
bool isRetryableDownloadError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return false;
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        // 429 is transient by definition (quota window), like 5xx.
        return status >= 500 || status == 429;
      case DioExceptionType.badCertificate:
        return false;
    }
  }
  return false;
}

/// Whether [error] is an out-of-space filesystem failure (errno ENOSPC).
/// Callers tag these reports so disk-full failures are distinguishable
/// from network failures in logs.
bool isNoSpaceError(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == 28) return true;
    return error.message.toLowerCase().contains('no space left');
  }
  if (error is DioException) {
    final underlying = error.error;
    if (underlying != null) return isNoSpaceError(underlying);
  }
  return false;
}

/// Throttle rule for download progress events feeding the per-row
/// StreamBuilder. Chunk callbacks arrive ~100/sec per connection; the UI
/// only needs periodic updates. Always emits the terminal event
/// ([count] >= [total] with a known total) so a throttled bar still
/// lands exactly on 100% — completion is additionally signaled by the
/// task status flip, which never throttles. Unknown totals (<= 0) only
/// throttle; completion is status-driven there.
bool shouldEmitDownloadProgress({
  required int count,
  required int total,
  required DateTime now,
  required DateTime lastEmit,
  Duration interval = const Duration(milliseconds: 250),
}) {
  if (total > 0 && count >= total) return true;
  return now.difference(lastEmit) >= interval;
}

class DownloadTask {
  final SpotubeFullTrackObject track;
  final DownloadStatus status;
  final CancelToken cancelToken;
  final int? totalSizeBytes;
  final StreamController<int> _downloadedBytesStreamController;

  Stream<int> get downloadedBytesStream =>
      _downloadedBytesStreamController.stream;

  DownloadTask({
    required this.track,
    required this.status,
    required this.cancelToken,
    this.totalSizeBytes,
    StreamController<int>? downloadedBytesStreamController,
  }) : _downloadedBytesStreamController =
            downloadedBytesStreamController ?? StreamController.broadcast();

  DownloadTask copyWith({
    SpotubeFullTrackObject? track,
    DownloadStatus? status,
    CancelToken? cancelToken,
    int? totalSizeBytes,
    StreamController<int>? downloadedBytesStreamController,
  }) {
    return DownloadTask(
      track: track ?? this.track,
      status: status ?? this.status,
      cancelToken: cancelToken ?? this.cancelToken,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      downloadedBytesStreamController:
          downloadedBytesStreamController ?? _downloadedBytesStreamController,
    );
  }
}

class DownloadManagerNotifier extends Notifier<List<DownloadTask>> {
  final Dio dio;
  DownloadManagerNotifier()
      : dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
        )),
        super();

  @override
  build() {
    ref.onDispose(() {
      for (final task in state) {
        if (task.status == DownloadStatus.downloading) {
          task.cancelToken.cancel();
        }
        task._downloadedBytesStreamController.close();
      }
    });

    // Nothing in `state` survived the process boundary, but `track_download`
    // did: it may still be claiming a transfer that died with the last process,
    // and it is the only record that a file downloaded in an earlier session
    // exists at all.
    unawaited(reconcilePersisted());

    return [];
  }

  /// Brings the persisted view in line with a process that started over.
  ///
  /// Two things can only be settled from outside the row: a status still
  /// `queued`/`downloading` belongs to a worker that no longer exists, and a
  /// `completed` row whose file has gone is no longer a completed download.
  /// Existence checks run in waves of 32 — the batching
  /// `localTracksProvider` uses — so a large download folder does not open
  /// every handle at once.
  @visibleForTesting
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
          start += _existenceWaveSize) {
        final wave = completed.sublist(
          start,
          (start + _existenceWaveSize).clamp(0, completed.length),
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

  static const int _existenceWaveSize = 32;

  DownloadTask? getTaskByTrackId(String trackId) {
    return state.firstWhereOrNull((element) => element.track.id == trackId);
  }

  /// The one entry point for every download request, single track or batch.
  ///
  /// [collectionId] is the Spotify playlist a request came from, when it came
  /// from one. It becomes a membership row and nothing else: ownership of the
  /// file stays with [DownloadRecord.trackId], which is why the same track
  /// reached from two playlists is one download.
  ///
  /// Returns whether anything was accepted. The caller decides how to start it:
  /// a single track goes straight to the pool, while a batch runs
  /// [_prefilterAndStart] first so one existence check and one replace-policy
  /// dialog cover the whole set.
  bool _enqueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
  }) {
    if (tracks.isEmpty) return false;

    // One guard for both shapes. `addAllToQueue` used to append without it, so a
    // batch re-queued whatever was already in flight, and the same track
    // requested from two playlists started two transfers. `live` accumulates, so
    // it also collapses duplicates inside a single batch.
    final live = state.map((e) => e.track.id).toSet();
    final incoming = [
      for (final track in tracks)
        if (live.add(track.id)) track,
    ];

    if (collectionId != null) {
      unawaited(
        _attachMembership(
          collectionId,
          [for (final track in tracks) track.id],
        ),
      );
    }
    if (incoming.isEmpty) return false;

    state = [
      ...state,
      ...incoming.map(
        (track) => DownloadTask(
          track: track,
          status: DownloadStatus.queued,
          cancelToken: CancelToken(),
        ),
      ),
    ];

    unawaited(_recordQueued(incoming));

    // The prefetch stays on the first track only, as it was for batches;
    // a per-track prefetch would resolve every row of a playlist at once.
    ref.read(sourcedTrackProvider(incoming.first));

    return true;
  }

  void addToQueue(
    SpotubeFullTrackObject track, {
    String? collectionId,
  }) {
    if (!_enqueue([track], collectionId: collectionId)) return;
    _pumpDownloadPool(); // No await should be invoked to avoid stuck UI
  }

  void addAllToQueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
  }) {
    if (!_enqueue(tracks, collectionId: collectionId)) return;
    // Phase 1 (batched existence check) runs async, then pumps the pool.
    // No await should be invoked to avoid stuck UI
    _prefilterAndStart();
  }

  static const _statusByDownloadStatus = {
    DownloadStatus.queued: DownloadPersistedStatus.queued,
    DownloadStatus.downloading: DownloadPersistedStatus.downloading,
    DownloadStatus.completed: DownloadPersistedStatus.completed,
    DownloadStatus.failed: DownloadPersistedStatus.failed,
    DownloadStatus.canceled: DownloadPersistedStatus.canceled,
  };

  /// Where [track] is going on disk, plus everything the row needs.
  ///
  /// Always via [_savePathFor], so the path in the database and the path a
  /// worker writes to cannot drift, and `baseName` is the same string
  /// `DownloadedFileIndex` keys on.
  DownloadRecord _recordFor(
    SpotubeFullTrackObject track,
    DownloadPersistedStatus status, {
    String? error,
    int? sizeBytes,
  }) {
    final presets = ref.read(audioSourcePresetsProvider);
    final container =
        presets.presets[presets.selectedDownloadingContainerIndex];
    final downloadLocation = ref.read(
        userPreferencesProvider.select((value) => value.downloadLocation));
    final savePath = _savePathFor(track, downloadLocation, container);

    return DownloadRecord(
      trackId: track.id,
      filePath: savePath,
      baseName: basenameWithoutExtension(savePath),
      status: status,
      trackData: jsonEncode(track.toJson()),
      error: error,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> _recordQueued(List<SpotubeFullTrackObject> tracks) async {
    await _writing('queue', () async {
      await recordQueuedDownloads(
        ref.read(databaseProvider),
        [
          for (final track in tracks)
            _recordFor(track, DownloadPersistedStatus.queued),
        ],
      );
    });
  }

  Future<void> _attachMembership(
      String playlistId, List<String> trackIds) async {
    await _writing('membership', () async {
      await attachTracksToPlaylist(
        ref.read(databaseProvider),
        playlistId: playlistId,
        trackIds: trackIds,
      );
    });
  }

  Future<void> _persistStatus(
    DownloadTask task,
    DownloadStatus status, {
    String? error,
  }) async {
    await _writing('status', () async {
      await writeDownloadStatus(
        ref.read(databaseProvider),
        _recordFor(
          task.track,
          _statusByDownloadStatus[status]!,
          sizeBytes: task.totalSizeBytes,
          // An exception string can carry a whole response body, and it is
          // stored per row in a database the UI reads on every list build.
          error: error == null ? null : _take(error, 500),
        ),
      );
    });
  }

  static String _take(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  /// A database write that fails must not cost the user their download.
  ///
  /// The rows are a record of transfers, not a gate on them: if the write is
  /// lost, the next session's [reconcilePersisted] and the filesystem checks in
  /// [_prefilterAndStart] still describe reality.
  Future<void> _writing(String what, Future<void> Function() write) async {
    try {
      await write();
    } catch (e, stack) {
      AppLogger.reportError('Could not record download $what: $e', stack);
    }
  }

  void retry(SpotubeFullTrackObject track) {
    final existing = state.firstWhereOrNull((e) => e.track.id == track.id);
    if (existing == null ||
        (existing.status != DownloadStatus.canceled &&
            existing.status != DownloadStatus.failed)) {
      return;
    }
    // A spent CancelToken can never be reused — re-queue with a fresh one.
    state = state
        .map((e) => e.track.id == track.id
            ? e.copyWith(
                status: DownloadStatus.queued, cancelToken: CancelToken())
            : e)
        .toList();
    _pumpDownloadPool(); // No await should be invoked to avoid stuck UI
  }

  void cancel(SpotubeFullTrackObject track) {
    if (state.firstWhereOrNull((e) => e.track.id == track.id)?.status ==
        DownloadStatus.failed) {
      return;
    }
    _setStatus(track, DownloadStatus.canceled);
  }

  void clearAll() {
    for (final task in state) {
      if (task.status == DownloadStatus.downloading) {
        task.cancelToken.cancel();
      }
    }
    state = [];
  }

  /// [sourceToken] identifies the CancelToken of the [DownloadTask] instance a
  /// worker was started with. Status writes carrying it are ignored when the
  /// live entry has since been re-created with a fresh token (e.g. cancel →
  /// retry): the still-finishing old worker must never act on the new
  /// generation — it would re-cancel and revert the retried download.
  ///
  /// This is the only writer of download status, in memory and on disk. The
  /// database write is derived from the entry that actually won the transition
  /// below and runs unawaited, so a slow disk cannot stall a transfer and a
  /// refused transition is never persisted.
  ///
  /// That includes [_prefilterAndStart]'s already-on-disk completions, which are
  /// matched by sanitized file name: the row records the same file the rest of
  /// the app already treats as this track's download, so the database, the row
  /// state and first playback cannot disagree about it.
  void _setStatus(
    SpotubeFullTrackObject track,
    DownloadStatus status, {
    CancelToken? sourceToken,
    String? error,
  }) {
    DownloadTask? winner;
    state = state.map((e) {
      if (e.track.id == track.id) {
        if (sourceToken != null && !identical(e.cancelToken, sourceToken)) {
          return e;
        }
        if ((status == DownloadStatus.canceled) && !e.cancelToken.isCancelled) {
          e.cancelToken.cancel();
        }

        // A canceled task must never transition back to completed: the
        // in-flight transfer may finish after the user canceled and would
        // otherwise overwrite the canceled state (and write metadata).
        if (status == DownloadStatus.completed &&
            e.status == DownloadStatus.canceled) {
          return e;
        }

        winner = e;
        return e.copyWith(status: status);
      }
      return e;
    }).toList();

    if (winner case final DownloadTask task) {
      unawaited(_persistStatus(task, status, error: error));
    }

    if (status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.canceled) {
      _pruneTerminalTasks();
    }
  }

  /// Keeps only the most recent [_maxRetainedTerminalTasks] terminal tasks
  /// (completed/failed/canceled) so a long download history does not grow
  /// the in-memory task list (and the metadata each task holds) unbounded.
  /// Active tasks (queued/downloading) are always retained.
  static const int _maxRetainedTerminalTasks = 100;

  void _pruneTerminalTasks() {
    final terminal = <DownloadTask>[];
    final active = <DownloadTask>[];
    for (final task in state) {
      if (task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.downloading) {
        active.add(task);
      } else {
        terminal.add(task);
      }
    }

    final dropped = terminal.length > _maxRetainedTerminalTasks
        ? terminal.sublist(0, terminal.length - _maxRetainedTerminalTasks)
        : const <DownloadTask>[];
    final keepTerminal = terminal.length > _maxRetainedTerminalTasks
        ? terminal.sublist(terminal.length - _maxRetainedTerminalTasks)
        : terminal;

    // Release per-task resources of dropped entries.
    for (final task in dropped) {
      if (task.status == DownloadStatus.downloading) {
        task.cancelToken.cancel();
      }
      if (!task._downloadedBytesStreamController.isClosed) {
        task._downloadedBytesStreamController.close();
      }
    }

    final pruned = [...active, ...keepTerminal];
    if (pruned.length != state.length) {
      state = pruned;
    }
  }

  bool _isShowingDialog = false;

  Future<bool> _shouldReplaceFileOnExist(DownloadTask task) async {
    return _resolveReplacePolicy(task.track);
  }

  /// Resolves whether already-downloaded files should be replaced.
  ///
  /// Asked at most once per decision: the answer is stored in
  /// [replaceDownloadedFileState], so the phase-1 prefilter and the
  /// per-track safety net share a single user decision.
  Future<bool> _resolveReplacePolicy(SpotubeTrackObject track) async {
    if (rootNavigatorKey.currentContext == null || _isShowingDialog) {
      return false;
    }
    final replaceAll = ref.read(replaceDownloadedFileState);
    if (replaceAll != null) return replaceAll;
    _isShowingDialog = true;
    try {
      return await showDialog<bool>(
            context: rootNavigatorKey.currentContext!,
            builder: (context) => ReplaceDownloadedDialog(
              track: track,
            ),
          ) ??
          false;
    } finally {
      _isShowingDialog = false;
    }
  }

  /// Runs [operation] with bounded exponential retry for transient
  /// download failures. Cancellation aborts immediately (no sleep, no
  /// retry); permanent errors fail fast via [isRetryableDownloadError].
  /// Returns only on success — failures propagate to [_downloadTrack]'s
  /// catch, which marks the task failed exactly once.
  Future<T> _chunkDownloadWithRetry<T>(
    DownloadTask task,
    Future<T> Function() operation,
  ) async {
    for (var attempt = 0;; attempt++) {
      if (task.cancelToken.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }
      try {
        return await operation();
      } catch (e) {
        if (!isRetryableDownloadError(e) ||
            attempt >= downloadRetryDelays.length) {
          rethrow;
        }
        await Future.delayed(downloadRetryDelays[attempt]);
      }
    }
  }

  Future<void> _downloadTrack(DownloadTask task) async {
    try {
      if (task.cancelToken.isCancelled) {
        _setStatus(task.track, DownloadStatus.canceled,
            sourceToken: task.cancelToken);
        return;
      }
      _setStatus(task.track, DownloadStatus.downloading);
      final presets = ref.read(audioSourcePresetsProvider);
      final container =
          presets.presets[presets.selectedDownloadingContainerIndex];
      final downloadLocation = ref.read(
          userPreferencesProvider.select((value) => value.downloadLocation));
      final autoQuality = ref.read(
        userPreferencesProvider.select((value) => value.autoDownloadQuality),
      );

      await Directory(downloadLocation).create(recursive: true);

      final savePath = _savePathFor(task.track, downloadLocation, container);

      final savePathFile = File(savePath);
      if (await savePathFile.exists()) {
        // dio automatically replaces the file if it exists so no deletion required
        if (!await _shouldReplaceFileOnExist(task)) {
          _setStatus(task.track, DownloadStatus.completed,
              sourceToken: task.cancelToken);
          return;
        }
      }

      Object? lastError;
      StackTrace? lastStack;

      // 1. Primary attempt: the default plugin + user-selected engine,
      //    preserving the original behavior exactly.
      try {
        final primary = await ref.read(sourcedTrackProvider(task.track).future);
        final url = _pickDownloadUrl(primary, container, presets, autoQuality);
        if (url != null) {
          await _chunkDownloadTrack(
            task,
            url: url,
            savePath: savePath,
            savePathFile: savePathFile,
            container: container,
          );
          return;
        }
        lastError = Exception("No download URL found for selected codec");
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
      }

      if (task.cancelToken.isCancelled) {
        _setStatus(task.track, DownloadStatus.canceled,
            sourceToken: task.cancelToken);
        return;
      }

      // 2. Fallback: walk the source cascade (other engines, other plugins,
      //    sibling matches, any available quality) until one succeeds.
      final resolver = SourceResolver(ref);
      final candidates = await resolver.candidates();

      for (final candidate in candidates) {
        if (task.cancelToken.isCancelled) {
          _setStatus(task.track, DownloadStatus.canceled,
              sourceToken: task.cancelToken);
          return;
        }

        try {
          final track = await resolver.resolve(candidate, task.track);
          final candidatesToTry = [
            track,
            for (final sibling in track.siblings)
              await resolver.resolveMatch(candidate, task.track, sibling),
          ];

          for (final resolved in candidatesToTry) {
            if (task.cancelToken.isCancelled) {
              _setStatus(task.track, DownloadStatus.canceled,
                  sourceToken: task.cancelToken);
              return;
            }
            final url = _pickDownloadUrl(
              resolved,
              container,
              presets,
              autoQuality,
            );
            if (url == null) continue;

            try {
              await _chunkDownloadTrack(
                task,
                url: url,
                savePath: savePath,
                savePathFile: savePathFile,
                container: container,
              );
              return;
            } catch (e, stack) {
              lastError = e;
              lastStack = stack;
            }
          }
        } catch (e, stack) {
          lastError = e;
          lastStack = stack;
        }
      }

      if (lastError case final Object error) {
        Error.throwWithStackTrace(error, lastStack ?? StackTrace.current);
      }
      throw Exception("All download sources failed for ${task.track.name}");
    } catch (e, stack) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // Cancellation (including retry-loop abort) is not a failure.
        return;
      }
      _setStatus(
        task.track,
        DownloadStatus.failed,
        sourceToken: task.cancelToken,
        error: e.toString(),
      );
      if (isNoSpaceError(e)) {
        AppLogger.reportError('Download out of disk space: $e', stack);
      } else {
        AppLogger.reportError(
            'Download failed for ${task.track.name}: $e', stack);
      }
    }
  }

  /// Selects the download URL for [track]. When [autoQuality] is enabled,
  /// the selected container/quality is not required — the best available
  /// stream (any container) is used instead.
  String? _pickDownloadUrl(
    SourcedTrack track,
    SpotubeAudioSourceContainerPreset container,
    AudioSourcePresetsState presets,
    bool autoQuality,
  ) {
    if (autoQuality) {
      return track.getStreamOfAnyContainer(container)?.url;
    }
    return track.getUrlOfQuality(
      container,
      presets.selectedDownloadingQualityIndex,
    );
  }

  /// Performs the actual chunked download to [savePath] and writes metadata.
  /// Throws on failure so the caller can fall back to another source.
  Future<void> _chunkDownloadTrack(
    DownloadTask task, {
    required String url,
    required String savePath,
    required File savePathFile,
    required SpotubeAudioSourceContainerPreset container,
  }) async {
    var lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);
    final response = await _chunkDownloadWithRetry(
      task,
      () => dio.chunkDownload(
        url,
        savePath,
        cancelToken: task.cancelToken,
        onReceiveProgress: (count, total) {
          // The captured `task` is a stale snapshot (every _setStatus creates
          // a new DownloadTask), so check the LIVE state entry instead —
          // otherwise this rebuilt the whole list on every chunk callback.
          if (total > 0 &&
              state
                      .firstWhereOrNull(
                        (e) =>
                            e.track.id == task.track.id &&
                            identical(e.cancelToken, task.cancelToken),
                      )
                      ?.totalSizeBytes ==
                  null) {
            state = state.map((e) {
              if (e.track.id == task.track.id &&
                  identical(e.cancelToken, task.cancelToken)) {
                return e.copyWith(totalSizeBytes: total);
              }
              return e;
            }).toList();
          }
          // Throttled: chunk callbacks arrive ~100/sec/connection and
          // each event rebuilds the row. The terminal event always
          // passes (see [shouldEmitDownloadProgress]).
          final now = DateTime.now();
          if (shouldEmitDownloadProgress(
            count: count,
            total: total,
            now: now,
            lastEmit: lastProgressEmit,
          )) {
            lastProgressEmit = now;
            final controller = task._downloadedBytesStreamController;
            if (!controller.isClosed) controller.add(count);
          }
        },
        deleteOnError: true,
        fileAccessMode: FileAccessMode.write,
      ),
    );

    if (response.statusCode != null && response.statusCode! < 400) {
      if (task.cancelToken.isCancelled) {
        // Canceled mid-transfer — leave the task in `canceled`.
        return;
      }
      _setStatus(task.track, DownloadStatus.completed,
          sourceToken: task.cancelToken);
    } else {
      throw Exception("Download failed with status ${response.statusCode}");
    }

    if (container.getFileExtension() == "weba") return;

    final imageBytes = await ServiceUtils.downloadImage(
      (task.track.album.images).asUrlString(
        placeholder: ImagePlaceholder.albumArt,
        index: 1,
      ),
    );
    await MetadataGod.writeMetadata(
      file: savePath,
      metadata: task.track.toMetadata(
        fileLength: await savePathFile.length(),
        imageBytes: imageBytes,
      ),
    );
  }

  /// Maximum number of tracks downloaded concurrently.
  ///
  /// Note that every track download already fans out to multiple range
  /// connections internally (see `chunkDownload`), so this limit is
  /// intentionally conservative.
  static const int _maxConcurrentDownloads = 3;

  int _activeWorkers = 0;

  /// Computes the on-disk destination of a track for the given settings.
  ///
  /// Shared by the phase-1 prefilter and [_downloadTrack] so the checked
  /// path and the downloaded path can never drift apart.
  String _savePathFor(
    SpotubeFullTrackObject track,
    String downloadLocation,
    SpotubeAudioSourceContainerPreset container,
  ) {
    return join(
      downloadLocation,
      ServiceUtils.sanitizeFilename(
        "${track.name} - ${track.artists.map((e) => e.name).join(", ")}.${container.getFileExtension()}",
      ),
    );
  }

  /// Phase 1 of bulk downloads: batch-check which queued tracks already
  /// exist on disk (pure filesystem stats, no network) and resolve what to
  /// do with them before any downloading starts.
  ///
  /// Tasks resolving to the same file are deduplicated so parallel workers
  /// can never write to the same target concurrently.
  Future<void> _prefilterAndStart() async {
    final queued =
        state.where((e) => e.status == DownloadStatus.queued).toList();

    final downloadLocation = ref.read(
        userPreferencesProvider.select((value) => value.downloadLocation));
    final presets = ref.read(audioSourcePresetsProvider);
    final container =
        presets.presets[presets.selectedDownloadingContainerIndex];

    // Group queued tasks by destination path.
    final groups = <String, List<DownloadTask>>{};
    for (final task in queued) {
      final savePath = _savePathFor(task.track, downloadLocation, container);
      (groups[savePath] ??= []).add(task);
    }

    // Check all destinations concurrently.
    final existence = <String, bool>{};
    await Future.wait(groups.keys.map((savePath) async {
      existence[savePath] = await File(savePath).exists();
    }));

    // A single upfront policy decision for every already-downloaded file,
    // instead of one modal dialog per track mid-download.
    final hasExisting = existence.values.any((exists) => exists);
    bool replace = false;
    if (hasExisting) {
      final firstExisting = groups.entries
          .firstWhere((entry) => existence[entry.key] == true)
          .value
          .first
          .track;
      replace = await _resolveReplacePolicy(firstExisting);
    }

    for (final entry in groups.entries) {
      final tasks = entry.value;
      if (existence[entry.key]! && !replace) {
        // Already downloaded and not replacing: skip everything.
        for (final task in tasks) {
          _markCompletedIfQueued(task.track);
        }
      } else {
        // Download (or re-download) the first, drop redundant duplicates.
        for (final task in tasks.skip(1)) {
          _markCompletedIfQueued(task.track);
        }
      }
    }

    _pumpDownloadPool();
  }

  /// Marks a task completed, but only if a worker hasn't claimed it in the
  /// meantime (phase 1 runs async and may overlap with a running pool).
  void _markCompletedIfQueued(SpotubeFullTrackObject track) {
    final current = state.firstWhereOrNull((e) => e.track.id == track.id);
    if (current?.status == DownloadStatus.queued) {
      _setStatus(track, DownloadStatus.completed);
    }
  }

  /// Phase 2: keep up to [_maxConcurrentDownloads] workers draining the
  /// queue. Late arrivals are picked up as well, since workers claim
  /// whatever is queued when they become free.
  void _pumpDownloadPool() {
    while (_activeWorkers < _maxConcurrentDownloads) {
      final hasQueued = state.any((e) => e.status == DownloadStatus.queued);
      if (!hasQueued) return;
      _activeWorkers++;
      _downloadWorker().whenComplete(() {
        _activeWorkers--;
        _pumpDownloadPool();
      });
    }
  }

  Future<void> _downloadWorker() async {
    while (true) {
      final task = _claimNextQueuedTask();
      if (task == null) return;
      try {
        await _downloadTrack(task);
      } catch (_) {
        // [_downloadTrack] reports its own failures via status updates.
        // Never let a worker die loudly and stall the pool.
      }
    }
  }

  /// Synchronously marks the next queued task as downloading and hands it
  /// to the caller. Synchronous, so two workers can never claim one task.
  DownloadTask? _claimNextQueuedTask() {
    final task =
        state.firstWhereOrNull((e) => e.status == DownloadStatus.queued);
    if (task == null) return null;
    _setStatus(task.track, DownloadStatus.downloading);
    return task;
  }
}

final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, List<DownloadTask>>(
  DownloadManagerNotifier.new,
);
