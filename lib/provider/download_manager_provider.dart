import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide join;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager/download_paths.dart';
import 'package:spotube/provider/download_manager/download_pool.dart';
import 'package:spotube/provider/download_manager/download_record_writer.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/download_manager/download_transfer.dart';
import 'package:spotube/provider/download_manager/replace_policy.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/vpn/vpn_lease.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';
import 'package:spotube/services/vpn/pinned_client.dart';

class DownloadManagerNotifier extends Notifier<List<DownloadTask>> {
  final Dio dio;
  bool _disposed = false;
  DownloadManagerNotifier()
      : dio = (Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
        ))
          // Source-pins sockets to the held VPN lease when one exists;
          // delegates unpinned otherwise (gate off = old behavior).
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => createPinnedClient(VpnPinHolder.current),
          )),
        super();

  late final DownloadRecordWriter _writer = DownloadRecordWriter(ref);
  late final ReplacePolicyGate _replacePolicy = ReplacePolicyGate(ref);
  late final DownloadTransfer _transfer = DownloadTransfer(
    dio: dio,
    setStatus: _setStatus,
    reportTotalSize: _recordTotalSize,
    sourceDeps: () => ref.sourceDeps,
  );
  late final DownloadWorkerPool _pool = DownloadWorkerPool(
    maxConcurrent: 3,
    canStart: () => _hasDownloadContainer,
    hasQueued: () => state.any((e) => e.status == DownloadStatus.queued),
    claim: _claimNextQueuedTask,
    run: _downloadTrack,
  );

  @override
  build() {
    ref.onDispose(() {
      _disposed = true;
      for (final task in state) {
        if (task.status == DownloadStatus.downloading) {
          task.cancelToken.cancel();
        }
        task.closeProgressStream();
      }
    });

    // Nothing in `state` survived the process boundary, but `track_download`
    // did: it may still be claiming a transfer that died with the last process,
    // and it is the only record that a file downloaded in an earlier session
    // exists at all.
    unawaited(reconcilePersisted());

    // The audio-source plugin resolves asynchronously. A download queued
    // before its presets exist has no extension or destination path yet, so it
    // must wait here instead of being failed by the prefilter. Resume the
    // queue as soon as a container exists.
    ref.listen(audioSourcePresetsProvider, (previous, next) {
      if (next.presets.isEmpty) return;
      unawaited(_prefilterAndStart());
    });

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
  Future<void> reconcilePersisted() => _writer.reconcilePersisted();

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
    bool useRetryFilePath = false,
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

    // Encode each track's JSON exactly once, and store it on the task. Every
    // later status write (_persistStatus for downloading / completed / failed
    // / canceled) reuses this string, so a 500-track batch does 500 encodes
    // total instead of 500 × transitions.
    final newTasks = [
      for (final track in incoming)
        DownloadTask(
          track: track,
          status: DownloadStatus.queued,
          cancelToken: CancelToken(),
          useRetryFilePath: useRetryFilePath,
          trackData: jsonEncode(track.toJson()),
        ),
    ];
    state = [...state, ...newTasks];

    unawaited(_recordQueued(newTasks));

    // The prefetch stays on the first track only, as it was for batches;
    // a per-track prefetch would resolve every row of a playlist at once.
    // Without a loaded container the worker cannot start anyway, and resolving
    // against a half-initialized plugin only produces noise.
    if (_hasDownloadContainer) {
      ref.read(sourcedTrackProvider(incoming.first));
    }

    return true;
  }

  void addToQueue(
    SpotubeFullTrackObject track, {
    String? collectionId,
  }) {
    if (!_enqueue([track], collectionId: collectionId)) return;
    _pool.pump(); // No await should be invoked to avoid stuck UI
  }

  void addAllToQueue(
    List<SpotubeFullTrackObject> tracks, {
    String? collectionId,
    bool useRetryFilePath = false,
  }) {
    if (!_enqueue(
      tracks,
      collectionId: collectionId,
      useRetryFilePath: useRetryFilePath,
    )) {
      return;
    }
    // Phase 1 (batched existence check) runs async, then pumps the pool.
    // No await should be invoked to avoid stuck UI — but a throw inside the
    // prefilter must neither surface as an unhandled async error nor leave
    // the freshly queued tasks with nobody to pump them, so the pool gets a
    // final (idempotent) pump either way and the error is reported.
    unawaited(
      _prefilterAndStart().catchError((Object error, StackTrace stackTrace) {
        AppLogger.reportError(error, stackTrace);
      }).whenComplete(_pool.pump),
    );
  }

  /// Whether the plugin's download container list is available yet.
  ///
  /// Presets are restored asynchronously after the plugin resolves. Until then
  /// there is no file extension or destination path, so queue work must wait
  /// instead of failing.
  bool get _hasDownloadContainer {
    if (_disposed) return false;
    final presets = ref.read(audioSourcePresetsProvider);
    return selectedDownloadContainer(presets) != null;
  }

  Future<void> _recordQueued(List<DownloadTask> tasks) async {
    // Plugins load after the first frame. Without a container there is no
    // extension or destination to record yet; the tasks stay queued in memory
    // and are persisted by their first status write after presets arrive.
    if (_disposed || !_hasDownloadContainer) return;
    await _writer.recordQueued(tasks);
  }

  Future<void> _attachMembership(
      String playlistId, List<String> trackIds) async {
    await _writer.attachMembership(playlistId, trackIds);
  }

  void retry(
    SpotubeFullTrackObject track, {
    bool useRetryFilePath = false,
  }) {
    final existing = state.firstWhereOrNull((e) => e.track.id == track.id);
    if (existing == null) {
      // A row that failed in a previous process has no live task to revive.
      // Auto-download synchronization re-queues those; it explicitly asks for
      // a unique retry path so a stale partial file is left untouched.
      if (useRetryFilePath && _enqueue([track], useRetryFilePath: true)) {
        _pool.pump();
      }
      return;
    }
    if (existing.status != DownloadStatus.canceled &&
        existing.status != DownloadStatus.failed) {
      return;
    }
    // A spent CancelToken can never be reused — re-queue with a fresh one.
    state = state
        .map((e) => e.track.id == track.id
            ? e.copyWith(
                status: DownloadStatus.queued,
                cancelToken: CancelToken(),
                useRetryFilePath: e.useRetryFilePath || useRetryFilePath,
              )
            : e)
        .toList();
    _pool.pump(); // No await should be invoked to avoid stuck UI
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
      // Release per-task resources of dropped entries, mirroring
      // [_pruneTerminalTasks]: state is replaced wholesale here, so the
      // controller must be closed now or it never is.
      task.closeProgressStream();
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
      unawaited(_writer.persistStatus(task, status, error: error));
    }

    if (status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.canceled) {
      _pruneTerminalTasks();
    }
  }

  void _recordTotalSize(DownloadTask task, int total) {
    if (state
            .firstWhereOrNull((e) =>
                e.track.id == task.track.id &&
                identical(e.cancelToken, task.cancelToken))
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
      task.closeProgressStream();
    }

    final pruned = [...active, ...keepTerminal];
    if (pruned.length != state.length) {
      state = pruned;
    }
  }

  Future<bool> _shouldReplaceFileOnExist(DownloadTask task) async {
    return _replacePolicy.resolve(task.track);
  }

  Future<void> _downloadTrack(DownloadTask task) async {
    // Optional automatic-VPN gate (pause-and-wait). When the mode does not
    // cover downloads — or nothing is configured — no lease is taken and
    // the body below runs exactly as before. Otherwise one lease is held
    // for the whole track attempt (resolve, retries, cascade, tag write)
    // so concurrent downloads share a single VPN connection instead of
    // flapping it, and the last release drops only what Spotube started.
    VpnLease? vpnLease;
    if (vpnGatesDownloads(ref)) {
      try {
        vpnLease = await ref.read(vpnManagerProvider).acquire(
              isCancelled: () => task.cancelToken.isCancelled,
            );
      } on VpnCancelledException {
        _setStatus(task.track, DownloadStatus.canceled,
            sourceToken: task.cancelToken);
        return;
      } catch (e, stack) {
        _setStatus(
          task.track,
          DownloadStatus.failed,
          sourceToken: task.cancelToken,
          error: e.toString(),
        );
        AppLogger.reportError(
          'Download blocked for ${task.track.name}: '
          'VPN required but unavailable: $e',
          stack,
        );
        return;
      }
    }
    try {
      if (task.cancelToken.isCancelled) {
        _setStatus(task.track, DownloadStatus.canceled,
            sourceToken: task.cancelToken);
        return;
      }
      // Re-verified before every chunk attempt (see _chunkDownloadTrack):
      // a VPN that disappears mid-download pauses the retry loop instead
      // of continuing over the normal connection. The pin is refreshed
      // afterwards so a reconnect IP change heals on the next attempt.
      final Future<void> Function()? vpnWaitHook = vpnLease == null
          ? null
          : () async {
              final vpn = ref.read(vpnManagerProvider);
              await vpn.waitUntilConnected(
                isCancelled: () => task.cancelToken.isCancelled,
              );
              await vpn.refreshPin();
            };
      // The claim in _claimNextQueuedTask already flipped this task to
      // `downloading` (memory + one DB write); re-stating it here cost a
      // second identical write per task and could revert a cancel that
      // arrived while the lease was pending.
      final presets = ref.read(audioSourcePresetsProvider);
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
      final autoQuality = ref.read(
        userPreferencesProvider.select((value) => value.autoDownloadQuality),
      );

      await Directory(downloadLocation).create(recursive: true);

      final savePath = downloadSavePath(
        task.track,
        downloadLocation,
        container,
        useRetryFilePath: task.useRetryFilePath,
      );

      final savePathFile = File(savePath);
      if (await savePathFile.exists() && !task.useRetryFilePath) {
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
        final url = pickDownloadUrl(primary, container, presets, autoQuality);
        if (url != null) {
          await _transfer.chunkDownloadTrack(
            task,
            url: url,
            savePath: savePath,
            savePathFile: savePathFile,
            container: container,
            beforeAttempt: vpnWaitHook,
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
      //    Extracted verbatim below; [lastError]/[lastStack] carry the
      //    primary attempt's failure so the final rethrow is unchanged.
      await _transfer.downloadWithFallback(
        task,
        savePath: savePath,
        savePathFile: savePathFile,
        container: container,
        presets: presets,
        autoQuality: autoQuality,
        vpnWaitHook: vpnWaitHook,
        lastError: lastError,
        lastStack: lastStack,
      );
    } catch (e, stack) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // Cancellation (including retry-loop abort) is not a failure.
        return;
      }
      if (e is VpnCancelledException) {
        // VPN wait aborted because the download itself was cancelled:
        // same terminal state as a direct cancel, never a failure.
        _setStatus(
          task.track,
          DownloadStatus.canceled,
          sourceToken: task.cancelToken,
        );
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
    } finally {
      // Idempotent and non-throwing: safe after cancel, failure, or the
      // early completed/canceled returns above.
      await vpnLease?.release();
    }
  }

  /// Phase 1 of bulk downloads: batch-check which queued tracks already
  /// exist on disk (pure filesystem stats, no network) and resolve what to
  /// do with them before any downloading starts.
  ///
  /// Existence checks run in waves of 32 — the batching [reconcilePersisted]
  /// uses — so a whole-playlist batch does not open every handle at once.
  ///
  /// Every already-on-disk track is transitioned in one pass, not one
  /// [_setStatus] per track: a 500-track batch used to mean 500 sequential
  /// rebuilds of `state` and 500 notifications, and each rebuild was O(n)
  /// against a list still holding all 500.
  ///
  /// A filename collision (distinct tracks whose [_savePathFor] is the same
  /// path) is now a visible failure rather than a silent completion of every
  /// claimant but the first. Since [_enqueue] already deduplicates by track
  /// id, a group larger than one can only be a collision.
  Future<void> _prefilterAndStart() async {
    if (_disposed) return;
    final queued =
        state.where((e) => e.status == DownloadStatus.queued).toList();
    if (queued.isEmpty) {
      _pool.pump();
      return;
    }

    final downloadLocation = ref.read(
        userPreferencesProvider.select((value) => value.downloadLocation));
    final presets = ref.read(audioSourcePresetsProvider);
    // Direct indexing threw a RangeError when the persisted container index
    // pointed past the end of the plugin's current list. The same guard the
    // single-task path uses, so the prefilter degrades to "no container"
    // instead of crashing the download pump.
    final container = selectedDownloadContainer(presets);
    if (container == null) {
      // Presets are restored asynchronously. Leave the queue intact; the
      // presets listener calls this again once a download container exists.
      // Failing here used to turn every startup download into a permanent
      // `failed` row before the plugin had even loaded.
      return;
    }

    // Group queued tasks by destination path.
    final groups = <String, List<DownloadTask>>{};
    for (final task in queued) {
      final savePath = downloadSavePath(
        task.track,
        downloadLocation,
        container,
        useRetryFilePath: task.useRetryFilePath,
      );
      (groups[savePath] ??= []).add(task);
    }

    // Bounded wave of existence checks.
    final existence = <String, bool>{};
    final paths = groups.keys.toList();
    for (var start = 0;
        start < paths.length;
        start += downloadExistenceWaveSize) {
      final wave = paths.sublist(
        start,
        (start + downloadExistenceWaveSize).clamp(0, paths.length),
      );
      await Future.wait([
        for (final path in wave)
          File(path).exists().then((value) => existence[path] = value),
      ]);
    }

    // A single upfront policy decision for every already-downloaded file,
    // instead of one modal dialog per track mid-download. Retry tasks bypass
    // it: their id-suffixed destination is theirs alone, and overwriting a
    // previous failed attempt is the point.
    final existingNeedingPolicy = groups.entries.where((entry) =>
        existence[entry.key] == true &&
        entry.value.any((task) => !task.useRetryFilePath));
    bool replace = false;
    if (existingNeedingPolicy.isNotEmpty) {
      final firstExisting = existingNeedingPolicy.first.value.first.track;
      replace = await _replacePolicy.resolve(firstExisting);
    }

    final onDiskTracks = <SpotubeFullTrackObject>[];
    final collidedTracks = <SpotubeFullTrackObject>[];
    for (final entry in groups.entries) {
      final tasks = entry.value;
      if (tasks.length > 1) {
        collidedTracks.addAll(tasks.map((task) => task.track));
        continue;
      }
      if (existence[entry.key]! && !tasks.single.useRetryFilePath && !replace) {
        onDiskTracks.add(tasks.single.track);
      }
    }

    _completeQueued(onDiskTracks);
    for (final track in collidedTracks) {
      _setStatus(
        track,
        DownloadStatus.failed,
        error:
            'Two queued downloads resolve to the same file on disk; only one '
            'can claim it. Move or rename the existing file and retry.',
      );
    }

    _pool.pump();
  }

  /// Flips every still-queued task in [tracks] to completed in one pass.
  ///
  /// Only fires on tasks that are genuinely still queued so a worker that
  /// claimed one of them between the prefilter's snapshot and this write
  /// keeps the state it already moved to.
  void _completeQueued(List<SpotubeFullTrackObject> tracks) {
    if (tracks.isEmpty) return;
    final ids = tracks.map((t) => t.id).toSet();
    final winners = [
      for (final e in state)
        if (e.status == DownloadStatus.queued && ids.contains(e.track.id)) e,
    ];
    if (winners.isEmpty) return;

    final winnerIds = winners.map((t) => t.track.id).toSet();
    state = [
      for (final e in state)
        if (winnerIds.contains(e.track.id) && e.status == DownloadStatus.queued)
          e.copyWith(status: DownloadStatus.completed)
        else
          e,
    ];
    for (final task in winners) {
      unawaited(_writer.persistStatus(task, DownloadStatus.completed));
    }
    _pruneTerminalTasks();
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
