import 'dart:async';
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
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  canceled,
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
      : dio = Dio(),
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

    return [];
  }

  DownloadTask? getTaskByTrackId(String trackId) {
    return state.firstWhereOrNull((element) => element.track.id == trackId);
  }

  void addToQueue(SpotubeFullTrackObject track) {
    if (state.any((element) => element.track.id == track.id)) return;
    state = [
      ...state,
      DownloadTask(
        track: track,
        status: DownloadStatus.queued,
        cancelToken: CancelToken(),
      ),
    ];

    ref.read(sourcedTrackProvider(track));

    _pumpDownloadPool(); // No await should be invoked to avoid stuck UI
  }

  void addAllToQueue(List<SpotubeFullTrackObject> tracks) {
    if (tracks.isEmpty) return;
    state = [
      ...state,
      ...tracks.map((e) => DownloadTask(
            track: e,
            status: DownloadStatus.queued,
            cancelToken: CancelToken(),
          )),
    ];

    ref.read(sourcedTrackProvider(tracks.first));
    // Phase 1 (batched existence check) runs async, then pumps the pool.
    // No await should be invoked to avoid stuck UI
    _prefilterAndStart();
  }

  void retry(SpotubeFullTrackObject track) {
    if (state.firstWhereOrNull((e) => e.track.id == track.id)?.status
        case DownloadStatus.canceled || DownloadStatus.failed) {
      _setStatus(track, DownloadStatus.queued);
      _pumpDownloadPool(); // No await should be invoked to avoid stuck UI
    }
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

  void _setStatus(SpotubeFullTrackObject track, DownloadStatus status) {
    state = state.map((e) {
      if (e.track.id == track.id) {
        if ((status == DownloadStatus.canceled) && e.cancelToken.isCancelled) {
          e.cancelToken.cancel();
        }

        return e.copyWith(status: status);
      }
      return e;
    }).toList();
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

  Future<void> _downloadTrack(DownloadTask task) async {
    try {
      _setStatus(task.track, DownloadStatus.downloading);
      final track = await ref.read(sourcedTrackProvider(task.track).future);
      if (task.cancelToken.isCancelled) {
        _setStatus(task.track, DownloadStatus.canceled);
      }
      final presets = ref.read(audioSourcePresetsProvider);
      final container =
          presets.presets[presets.selectedDownloadingContainerIndex];
      final downloadLocation = ref.read(
          userPreferencesProvider.select((value) => value.downloadLocation));

      final url = track.getUrlOfQuality(
        container,
        presets.selectedDownloadingQualityIndex,
      );

      if (url == null) {
        throw Exception("No download URL found for selected codec");
      }

      final savePath =
          _savePathFor(track.query, downloadLocation, container);

      final savePathFile = File(savePath);
      if (await savePathFile.exists()) {
        // dio automatically replaces the file if it exists so no deletion required
        if (!await _shouldReplaceFileOnExist(task)) {
          _setStatus(track.query, DownloadStatus.completed);
          return;
        }
      }

      final response = await dio.chunkDownload(
        url,
        savePath,
        cancelToken: task.cancelToken,
        onReceiveProgress: (count, total) {
          if (task.totalSizeBytes == null) {
            state = state.map((e) {
              if (e.track.id == track.query.id) {
                return e.copyWith(totalSizeBytes: total);
              }
              return e;
            }).toList();
          }
          task._downloadedBytesStreamController.add(count);
        },
        deleteOnError: true,
        fileAccessMode: FileAccessMode.write,
      );
      if (response.statusCode != null && response.statusCode! < 400) {
        _setStatus(track.query, DownloadStatus.completed);
      } else {
        _setStatus(track.query, DownloadStatus.failed);
        return;
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
    } catch (e, stack) {
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        _setStatus(task.track, DownloadStatus.failed);
        AppLogger.reportError(e, stack);
      }
    }
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
    final current =
        state.firstWhereOrNull((e) => e.track.id == track.id);
    if (current?.status == DownloadStatus.queued) {
      _setStatus(track, DownloadStatus.completed);
    }
  }

  /// Phase 2: keep up to [_maxConcurrentDownloads] workers draining the
  /// queue. Late arrivals are picked up as well, since workers claim
  /// whatever is queued when they become free.
  void _pumpDownloadPool() {
    while (_activeWorkers < _maxConcurrentDownloads) {
      final hasQueued =
          state.any((e) => e.status == DownloadStatus.queued);
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
