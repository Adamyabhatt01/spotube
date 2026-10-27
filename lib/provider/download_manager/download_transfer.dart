import 'dart:io';

import 'package:dio/dio.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart';
import 'package:spotube/extensions/dio.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager/download_paths.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/music_cache_policy.dart';
import 'package:spotube/services/sourced_track/source_dependencies.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/utils/service_utils.dart';

typedef DownloadStatusSetter = void Function(
  SpotubeFullTrackObject track,
  DownloadStatus status, {
  CancelToken? sourceToken,
  String? error,
});

typedef DownloadSizeReporter = void Function(DownloadTask task, int total);

/// The network half of a download: the retry loop, the chunked transfer and
/// the post-transfer metadata/cache cleanup.
///
/// Status transitions and per-task size reporting are callbacks, so the
/// manager remains the only writer of queue state.
class DownloadTransfer {
  final Dio dio;
  final DownloadStatusSetter setStatus;
  final DownloadSizeReporter reportTotalSize;
  final SourceDependencies Function() sourceDeps;

  DownloadTransfer({
    required this.dio,
    required this.setStatus,
    required this.reportTotalSize,
    required this.sourceDeps,
  });

  /// Fallback half of a transfer: walks the source cascade (other engines,
  /// other plugins, sibling matches, any available quality) until one chunked
  /// download succeeds. [lastError]/[lastStack] carry the primary attempt's
  /// failure into the final rethrow, so the failure taxonomy the caller's
  /// catch handles is unchanged. Cancel re-checks, the VPN wait hook and the
  /// per-candidate loop all stay as they were; every `return` here is a
  /// success or cancel exiting the attempt, which reaches the caller's
  /// `finally` exactly as before.
  Future<void> downloadWithFallback(
    DownloadTask task, {
    required String savePath,
    required File savePathFile,
    required SpotubeAudioSourceContainerPreset container,
    required AudioSourcePresetsState presets,
    required bool autoQuality,
    required Future<void> Function()? vpnWaitHook,
    required Object? lastError,
    required StackTrace? lastStack,
  }) async {
    final resolver = SourceResolver(sourceDeps());
    final candidates = await resolver.candidates();

    for (final candidate in candidates) {
      if (task.cancelToken.isCancelled) {
        setStatus(
          task.track,
          DownloadStatus.canceled,
          sourceToken: task.cancelToken,
        );
        return;
      }

      try {
        // Bounded like playback's cascade: a stalled search/manifest must
        // fall through to the next candidate, never hang the worker. The
        // chunk download below is deliberately unbounded (files take minutes).
        final track = await resolver
            .resolve(candidate, task.track)
            .timeout(sourceCandidateBudget);
        final candidatesToTry = [
          track,
          for (final sibling in track.siblings)
            await resolver
                .resolveMatch(candidate, task.track, sibling)
                .timeout(sourceCandidateBudget),
        ];

        for (final resolved in candidatesToTry) {
          if (task.cancelToken.isCancelled) {
            setStatus(
              task.track,
              DownloadStatus.canceled,
              sourceToken: task.cancelToken,
            );
            return;
          }
          final url = pickDownloadUrl(
            resolved,
            container,
            presets,
            autoQuality,
          );
          if (url == null) continue;

          try {
            await chunkDownloadTrack(
              task,
              url: url,
              savePath: savePath,
              savePathFile: savePathFile,
              container: container,
              beforeAttempt: vpnWaitHook,
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
  }

  /// Runs [operation] with bounded exponential retry for transient
  /// download failures. Cancellation aborts immediately (no sleep, no
  /// retry); permanent errors fail fast via [isRetryableDownloadError].
  /// Returns only on success — failures propagate to the caller's catch,
  /// which marks the task failed exactly once.
  ///
  /// [beforeAttempt] runs ahead of every attempt (including the first).
  /// The VPN gate passes a wait-for-connection hook here so a mid-download
  /// VPN loss pauses instead of retrying over the normal connection. Null
  /// by default: ungated downloads behave exactly as before.
  Future<T> _chunkDownloadWithRetry<T>(
    DownloadTask task,
    Future<T> Function() operation, {
    Future<void> Function()? beforeAttempt,
  }) async {
    for (var attempt = 0;; attempt++) {
      if (task.cancelToken.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }
      try {
        if (beforeAttempt != null) await beforeAttempt();
        return await operation();
      } catch (e) {
        // VPN protection failures (e.g. proxy conflict, surfaced by Dio
        // as `unknown` with the VpnException attached) are deterministic:
        // retrying cannot help and must never transmit, so fail fast.
        if (isVpnProtectionError(e)) {
          rethrow;
        }
        if (!isRetryableDownloadError(e) ||
            attempt >= downloadRetryDelays.length) {
          rethrow;
        }
        await Future.delayed(downloadRetryDelays[attempt]);
      }
    }
  }

  /// Performs the actual chunked download to [savePath] and writes metadata.
  /// Throws on failure so the caller can fall back to another source.
  Future<void> chunkDownloadTrack(
    DownloadTask task, {
    required String url,
    required String savePath,
    required File savePathFile,
    required SpotubeAudioSourceContainerPreset container,
    Future<void> Function()? beforeAttempt,
  }) async {
    var lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);
    final response = await _chunkDownloadWithRetry(
      task,
      () => dio.chunkDownload(
        url,
        savePath,
        cancelToken: task.cancelToken,
        onReceiveProgress: (count, total) {
          if (total > 0) {
            reportTotalSize(task, total);
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
            task.emitDownloadedBytes(count);
          }
        },
        deleteOnError: true,
      ),
      beforeAttempt: beforeAttempt,
    );

    if (response.statusCode != null && response.statusCode! < 400) {
      if (task.cancelToken.isCancelled) {
        // Canceled mid-transfer — leave the task in `canceled`.
        return;
      }
      setStatus(
        task.track,
        DownloadStatus.completed,
        sourceToken: task.cancelToken,
      );
    } else {
      throw Exception("Download failed with status ${response.statusCode}");
    }

    // The file now lives in the library; the playback server's mirrored copy
    // of the same audio is pure duplicate from here on.
    await _evictMusicCacheCopies(task.track, container);

    if (container.getFileExtension() == "weba") return;

    // Shared memo with the playback-cache finalizer and palette hook: a track
    // that was streamed (and mirrored) before being downloaded, or a sibling
    // from the same album, must not re-fetch the same cover.
    final imageBytes = await ServiceUtils.artworkBytes(
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

  /// Deletes music-cache copies of [track] after its download landed.
  ///
  /// The cache file is named `"<name> - <artists> (<source id>).<ext>"` (see
  /// the playback server); the source id belongs to the streaming resolve and
  /// is unknown here, so copies are matched by the name+artists prefix the
  /// server writes and this container's extension. A whole one-level list is
  /// cheap next to the transfer that just finished, and no match is a no-op
  /// for a track that was never streamed.
  Future<void> _evictMusicCacheCopies(
    SpotubeFullTrackObject track,
    SpotubeAudioSourceContainerPreset container,
  ) async {
    try {
      final prefix = ServiceUtils.sanitizeFilename(
        ServiceUtils.trackFileStem(track, spaceAfterComma: false),
      );
      final extension = '.${container.getFileExtension()}';
      final dir = Directory(await UserPreferencesNotifier.getMusicCacheDir());
      if (!await dir.exists()) return;

      final stale = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = basename(entity.path);
        if (name.startsWith(prefix) &&
            name.length > prefix.length &&
            name.endsWith(extension)) {
          stale.add(entity);
        }
      }
      if (stale.isEmpty) return;

      // Gone from the usage map too, so the eviction ranker never treats a
      // deleted path as recently served.
      for (final file in stale) {
        await file.delete();
        MusicCacheUsage.forget(file.path);
      }
    } catch (e, stack) {
      // Disk hygiene after a completed download: never fails the download.
      AppLogger.reportError(e, stack, 'music cache eviction after download');
    }
  }
}
