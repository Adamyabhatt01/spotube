import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:spotube/models/parser/range_headers.dart';

/// Mirrors a proxied audio response into the on-disk music cache safely.
///
/// The previous implementation appended EVERY range response to one `.part`
/// file, so overlapping/repeated/out-of-order ranges — or two concurrent
/// requests for the same track — could produce a scrambled file whose length
/// coincidentally matched the expected total and got renamed to the permanent
/// cache. This class only mirrors responses that cover the ENTIRE file in one
/// sequential write (`200` with a known length, or `206 bytes=0-total-1`),
/// truncates the `.part` before writing, deletes it on any failure, and
/// serializes mirrors per track.
class PlaybackCacheMirror {
  PlaybackCacheMirror._({
    required this.partFile,
    required this.cacheFile,
    required this.expectedTotal,
    required this.onComplete,
  });

  /// Creates a mirror for [cacheFile], writing through `cacheFile.part`.
  /// Returns null when another mirror for the same file is already running —
  /// concurrent requests must not interleave writes into one `.part`.
  static PlaybackCacheMirror? tryBegin({
    required File cacheFile,
    required int expectedTotal,
    Future<void> Function(int fileLength)? onComplete,
  }) {
    final partPath = '${cacheFile.path}.part';
    if (!_activeParts.add(partPath)) return null;
    return PlaybackCacheMirror._(
      partFile: File(partPath),
      cacheFile: cacheFile,
      expectedTotal: expectedTotal,
      onComplete: onComplete,
    );
  }

  static final Set<String> _activeParts = {};

  /// Test-only: whether a part path is currently being mirrored.
  static bool isMirroring(String partPath) => _activeParts.contains(partPath);

  final File partFile;
  final File cacheFile;
  final int expectedTotal;
  final Future<void> Function(int fileLength)? onComplete;

  bool _released = false;

  void _release() {
    if (_released) return;
    _released = true;
    _activeParts.remove(partFile.path);
  }

  /// True when the response body covers the complete file from byte 0, in
  /// which case it can be mirrored into a valid cache. All other responses
  /// (partial, open-ended, malformed) stream through without touching the
  /// cache. Returns the expected total length, or null when not mirrorable.
  static int? completeCoverLength({
    required int? statusCode,
    required String? contentRangeHeader,
    required String? contentLengthHeader,
  }) {
    if (statusCode == 200) {
      final length = int.tryParse(contentLengthHeader ?? '');
      return (length != null && length > 0) ? length : null;
    }
    if (statusCode != 206 || contentRangeHeader == null) return null;

    final ContentRangeHeader range;
    try {
      range = ContentRangeHeader.parse(contentRangeHeader);
    } on FormatException {
      return null;
    }
    if (range.total <= 0 || range.start != 0 || range.end != range.total - 1) {
      return null;
    }
    return range.total;
  }

  IOSink? _sink;
  StreamSubscription<Uint8List>? _upstream;
  bool _settled = false;

  /// True while the async error handler is mid-cleanup. An `error` followed
  /// by `done` from the source would otherwise let `onDone` close the client
  /// stream before the error is forwarded, silently swallowing it.
  bool _errorInProgress = false;

  Future<void> _abandon() async {
    _release();
    try {
      if (await partFile.exists()) await partFile.delete();
    } catch (_) {
      // Best-effort cleanup; a stale .part is never renamed so it cannot
      // corrupt the cache, and the next mirror truncates it anyway.
    }
  }

  /// Tees [source] to the part file and returns the stream to serve to the
  /// client. The returned stream buffers until the client subscribes, so no
  /// bytes are lost between the mirror's subscription and shelf's piping.
  Future<Stream<Uint8List>> attach(Stream<Uint8List> source) async {
    final controller = StreamController<Uint8List>();
    final sink =
        await partFile.create(recursive: true).then((f) => f.openWrite());
    _sink = sink;

    Future<void> finish() async {
      if (_settled) return;
      _settled = true;
      await sink.close();
      final fileLength = await partFile.length();
      if (fileLength != expectedTotal) {
        await _abandon();
        return;
      }
      _release();
      await partFile.rename(cacheFile.path);
      if (onComplete != null) await onComplete!(fileLength);
    }

    _upstream = source.listen(
      (data) {
        controller.add(data);
        sink.add(data);
      },
      onError: (Object error, StackTrace stack) async {
        if (_settled || _errorInProgress) return;
        _settled = true;
        _errorInProgress = true;
        await sink.close();
        await _abandon();
        _errorInProgress = false;
        if (!controller.isClosed) controller.addError(error, stack);
        await controller.close();
      },
      onDone: () async {
        if (_errorInProgress) return;
        await finish();
        if (!_errorInProgress && !controller.isClosed) {
          await controller.close();
        }
      },
    );

    controller.onCancel = () async {
      await _upstream?.cancel();
      final sink = _sink;
      if (sink != null && !_settled) {
        _settled = true;
        await sink.close();
      }
      await _abandon();
    };

    return controller.stream;
  }
}
