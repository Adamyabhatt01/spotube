// On-demand model download: per-file, hashed, resumable, and never committed
// under its real name before it verifies. Models are never bundled (§11); this
// writes them into app support storage, and they survive `mode: off` so
// re-enabling does not re-fetch 43 MB.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:spotube/services/voice/models/voice_model_registry.dart';

enum VoiceModelOutcome { ok, alreadyInstalled, canceled, checksumMismatch, noSpace, network }

class VoiceDownloadProgress {
  const VoiceDownloadProgress({
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int receivedBytes;
  final int totalBytes;

  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

typedef VoiceProgressCallback = void Function(VoiceDownloadProgress);

class VoiceModelDownloader {
  VoiceModelDownloader({
    required Dio dio,
    required this.directory,
  }) : _dio = dio;

  final Dio _dio;
  final String directory;

  String pathFor(VoiceModelFile file) => '$directory/${file.name}';

  /// Existence plus exact size. The full hash runs at download time; re-hashing
  /// 43 MB at every launch to notice corruption the engine would trip over
  /// within a second of loading is not a trade worth making.
  Future<bool> isInstalled(VoiceModelSpec spec) async {
    for (final file in spec.files) {
      if (!await _sizeMatches(File(pathFor(file)), file)) return false;
    }
    return true;
  }

  Future<void> uninstall(VoiceModelSpec spec) async {
    for (final file in spec.files) {
      await _ignoreMissing(File(pathFor(file)).delete);
      await _ignoreMissing(File(_partPath(file)).delete);
    }
  }

  /// Free space on POSIX. Android has no `df` worth trusting, so it returns
  /// null there and a full disk shows up as a write failure instead.
  Future<int?> freeBytes() async {
    if (Platform.isAndroid) return null;
    try {
      final result = await Process.run('df', ['-P', '-B1', directory]);
      if (result.exitCode != 0) return null;
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      // `df -P` columns: filesystem, total, used, available, capacity, mount.
      // Index 4 is the capacity percentage ("53%"), which never parses — the
      // available-bytes column is 3.
      return int.tryParse(lines[1].split(RegExp(r'\s+'))[3]);
    } on ProcessException {
      return null;
    }
  }

  Future<VoiceModelOutcome> install(
    VoiceModelSpec spec, {
    VoiceProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    await Directory(directory).create(recursive: true);

    final remaining = await _remainingBytes(spec);
    final free = await freeBytes();
    // A little headroom: a partial file that cannot be finished is worse than
    // a download that never started.
    if (remaining > 0 &&
        free != null &&
        free < remaining + 4 * 1024 * 1024) {
      return VoiceModelOutcome.noSpace;
    }

    var allPresent = true;
    for (var i = 0; i < spec.files.length; i++) {
      final outcome = await _installWithMirrors(
        spec.files[i],
        index: i,
        count: spec.files.length,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (outcome != VoiceModelOutcome.ok &&
          outcome != VoiceModelOutcome.alreadyInstalled) {
        return outcome;
      }
      if (outcome != VoiceModelOutcome.alreadyInstalled) allPresent = false;
    }
    // Distinguishing "nothing to do" from "fetched it" keeps the settings UI
    // from claiming a download happened when it did not.
    return allPresent
        ? VoiceModelOutcome.alreadyInstalled
        : VoiceModelOutcome.ok;
  }

  Future<int> _remainingBytes(VoiceModelSpec spec) async {
    var remaining = 0;
    for (final file in spec.files) {
      if (await _sizeMatches(File(pathFor(file)), file)) continue;
      final part = File(_partPath(file));
      final have = await part.exists() ? (await part.stat()).size : 0;
      remaining += (file.approxBytes - have).clamp(0, file.approxBytes);
    }
    return remaining;
  }

  /// Primary URL first, then each mirror, resuming from the `.part` file the
  /// previous attempt left behind.
  Future<VoiceModelOutcome> _installWithMirrors(
    VoiceModelFile file, {
    required int index,
    required int count,
    VoiceProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final urls = [file.url, ...file.mirrorUrls];
    VoiceModelOutcome outcome = VoiceModelOutcome.network;
    for (final url in urls) {
      outcome = await _installFile(
        file,
        url: url,
        index: index,
        count: count,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (outcome == VoiceModelOutcome.ok ||
          outcome == VoiceModelOutcome.alreadyInstalled ||
          outcome == VoiceModelOutcome.canceled ||
          outcome == VoiceModelOutcome.noSpace ||
          outcome == VoiceModelOutcome.checksumMismatch) {
        return outcome;
      }
    }
    return outcome;
  }

  Future<VoiceModelOutcome> _installFile(
    VoiceModelFile file, {
    required String url,
    required int index,
    required int count,
    VoiceProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final target = File(pathFor(file));
    if (await _sizeMatches(target, file)) {
      return VoiceModelOutcome.alreadyInstalled;
    }

    // A second pass only happens when the host ignored our Range and sent the
    // whole file; two tries is enough to learn that a server will not resume.
    for (var attempt = 0; attempt < 2; attempt++) {
      final outcome = await _writeOnce(
        file,
        url: url,
        index: index,
        count: count,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (outcome != null) return outcome;
    }
    return VoiceModelOutcome.network;
  }

  /// Returns null when the partial was thrown away and the request should be
  /// re-issued from byte 0.
  Future<VoiceModelOutcome?> _writeOnce(
    VoiceModelFile file, {
    required String url,
    required int index,
    required int count,
    VoiceProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final target = File(pathFor(file));
    final part = File(_partPath(file));
    var offset = await part.exists() ? (await part.stat()).size : 0;
    if (offset > file.approxBytes) {
      await _ignoreMissing(part.delete);
      offset = 0;
    }

    final digests = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digests);
    // A resumed file hashes from its first byte too, or the digest would cover
    // only the tail and never match the pinned value.
    if (offset > 0) {
      await for (final chunk in part.openRead(0, offset)) {
        hasher.add(chunk);
      }
    }

    IOSink? sink;
    var received = offset;
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-',
          },
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );

      if ((response.statusCode ?? 200) == 200 && offset > 0) {
        // The host ignored Range: appending its whole file onto our partial
        // would duplicate the head, so drop the partial and start over. The
        // subscription has to be cancelled explicitly — leaving the body open
        // holds the connection.
        await response.data?.stream.listen((_) {}).cancel();
        await _ignoreMissing(part.delete);
        return null;
      }

      sink = part.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(
          VoiceDownloadProgress(
            fileName: file.name,
            fileIndex: index,
            fileCount: count,
            receivedBytes: received,
            totalBytes: file.approxBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on DioException catch (e) {
      await sink?.close();
      if (CancelToken.isCancel(e)) {
        // The partial stays: resuming is the whole point of writing `.part`.
        return VoiceModelOutcome.canceled;
      }
      return VoiceModelOutcome.network;
    } on FileSystemException {
      await sink?.close();
      return VoiceModelOutcome.noSpace;
    }

    hasher.close();
    if (received != file.approxBytes) {
      // Truncated mid-transfer; the partial is kept so the next attempt
      // resumes instead of re-fetching everything.
      return VoiceModelOutcome.network;
    }
    if (digests.hex != file.sha256) {
      await _ignoreMissing(part.delete);
      return VoiceModelOutcome.checksumMismatch;
    }

    // Verify-then-commit.
    if (await target.exists()) await target.delete();
    await part.rename(pathFor(file));
    return VoiceModelOutcome.ok;
  }

  /// Existence plus at-least-expected size. `approxBytes` is a recorded
  /// estimate, not a contract: the sha256 check at download time is the real
  /// verification, so a file a byte larger than the estimate must not read as
  /// "not installed" forever. A smaller file still means truncated.
  Future<bool> _sizeMatches(File file, VoiceModelFile spec) async {
    if (!await file.exists()) return false;
    return (await file.stat()).size >= spec.approxBytes;
  }

  String _partPath(VoiceModelFile file) => '$directory/${file.name}.part';

  Future<void> _ignoreMissing(Future<void> Function() action) async {
    try {
      await action();
    } on FileSystemException {
      // Nothing to clean up.
    }
  }
}

/// Collects the finished [crypto.Digest] so it can be compared as hex.
class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _digest;

  @override
  void add(crypto.Digest data) => _digest = data;

  @override
  void close() {}

  String? get hex => _digest == null ? null : _toHex(_digest!.bytes);
}

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
