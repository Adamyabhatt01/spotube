import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';

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

/// Whether [error] is a VPN protection failure: either a [VpnException]
/// directly, or one attached to a Dio error (Dio normalizes adapter throws
/// to `DioExceptionType.unknown`, keeping the original in `.error`).
/// Deterministic by nature — retrying cannot help and must never transmit.
bool isVpnProtectionError(Object error) {
  if (error is VpnException) return true;
  return error is DioException && error.error is VpnException;
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

  /// True when this task retries a failed/interrupted attempt.
  ///
  /// A failed transfer can leave a partial file at the normal destination.
  /// Retries therefore write to a deterministic id-suffixed path instead of
  /// the normal one: the old file is never mistaken for the retry's output and
  /// is never overwritten. The path is recorded on the row, so later sessions
  /// reuse the successful retry exactly like any other download.
  final bool useRetryFilePath;

  /// The `SpotubeFullTrackObject.toJson()` this task's database row stores.
  /// Encoded once at enqueue and reused for every later status write; the row
  /// payload is what the mirror parses to render a playlist offline, and it
  /// cannot drift from what the task started with. Nullable so an ad-hoc task
  /// (a test constructing one directly, for example) can omit it and fall back
  /// to encoding on the first write.
  final String? trackData;

  final StreamController<int> _downloadedBytesStreamController;

  Stream<int> get downloadedBytesStream =>
      _downloadedBytesStreamController.stream;

  void emitDownloadedBytes(int count) {
    final controller = _downloadedBytesStreamController;
    if (!controller.isClosed) controller.add(count);
  }

  /// Releases the progress stream of a task that is being dropped. Idempotent.
  void closeProgressStream() {
    final controller = _downloadedBytesStreamController;
    if (!controller.isClosed) controller.close();
  }

  DownloadTask({
    required this.track,
    required this.status,
    required this.cancelToken,
    this.totalSizeBytes,
    this.useRetryFilePath = false,
    this.trackData,
    StreamController<int>? downloadedBytesStreamController,
  }) : _downloadedBytesStreamController =
            downloadedBytesStreamController ?? StreamController.broadcast();

  DownloadTask copyWith({
    SpotubeFullTrackObject? track,
    DownloadStatus? status,
    CancelToken? cancelToken,
    int? totalSizeBytes,
    bool? useRetryFilePath,
    String? trackData,
    StreamController<int>? downloadedBytesStreamController,
  }) {
    return DownloadTask(
      track: track ?? this.track,
      status: status ?? this.status,
      cancelToken: cancelToken ?? this.cancelToken,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      useRetryFilePath: useRetryFilePath ?? this.useRetryFilePath,
      trackData: trackData ?? this.trackData,
      downloadedBytesStreamController:
          downloadedBytesStreamController ?? _downloadedBytesStreamController,
    );
  }
}
