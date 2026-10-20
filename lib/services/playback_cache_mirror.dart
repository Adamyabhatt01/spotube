import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:spotube/models/parser/range_headers.dart';
import 'package:spotube/services/logger/logger.dart';

/// Reports a mirror failure without letting diagnostics become a second
/// failure. In unit tests the app logger is intentionally uninitialized.
void _reportError(Object error, StackTrace stack, String context) {
  try {
    unawaited(AppLogger.reportError(error, stack, context).catchError((_) {}));
  } catch (_) {
    // Logging is best-effort.
  }
}

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
    try {
      // Delete before releasing: a new mirror must not be able to recreate
      // the same .part while this cleanup is still in flight, or it would be
      // deleted by the old mirror's cleanup.
      if (await partFile.exists()) await partFile.delete();
    } catch (_) {
      // Best-effort cleanup; a stale .part is never renamed so it cannot
      // corrupt the cache, and the next mirror truncates it anyway.
    } finally {
      _release();
    }
  }

  /// Tees [source] to the part file and returns the stream to serve to the
  /// client. The returned stream buffers until the client subscribes, so no
  /// bytes are lost between the mirror's subscription and shelf's piping.
  Future<Stream<Uint8List>> attach(Stream<Uint8List> source) async {
    final controller = StreamController<Uint8List>();
    final IOSink sink;
    try {
      sink = await partFile.create(recursive: true).then((f) => f.openWrite());
    } catch (e, stack) {
      // tryBegin() already reserved the slot. A filesystem failure here must
      // not disable caching for this track until the process restarts.
      await _abandon();
      // No listener was attached yet, so awaiting close() would never
      // complete for this single-subscription controller.
      unawaited(controller.close());
      _reportError(e, stack, 'PlaybackCacheMirror.attach');
      rethrow;
    }
    _sink = sink;

    Future<void> finish() async {
      if (_settled) return;
      _settled = true;
      try {
        await sink.close();
        final fileLength = await partFile.length();
        if (fileLength != expectedTotal) {
          await _abandon();
          return;
        }
        // Promote before releasing the reservation: a concurrent request must
        // not recreate/truncate `.part` between the rename decision and the
        // rename itself.
        await partFile.rename(cacheFile.path);
        _release();
        if (onComplete != null) {
          try {
            await onComplete!(fileLength);
          } catch (e, stack) {
            // The bytes are already a complete, valid cache entry. Metadata
            // tagging is best-effort; it must not hold the HTTP response open.
            _reportError(
              e,
              stack,
              'PlaybackCacheMirror.onComplete',
            );
          }
        }
      } catch (e, stack) {
        // A sink/rename/length failure means there is no valid cache to
        // promote. Clean up, but never let the exception escape the stream
        // callback: the response still has to see EOF.
        await _abandon();
        _reportError(e, stack, 'PlaybackCacheMirror.finish');
      } finally {
        _release();
      }
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
        try {
          await sink.close();
        } catch (e, st) {
          _reportError(e, st, 'PlaybackCacheMirror.sinkClose');
        }
        await _abandon();
        _errorInProgress = false;
        if (!controller.isClosed) controller.addError(error, stack);
        if (!controller.isClosed) await controller.close();
      },
      onDone: () async {
        if (_errorInProgress) return;
        try {
          await finish();
        } catch (e, stack) {
          // finish() owns its cleanup, but keep the response contract even if
          // an unexpected error escapes.
          _reportError(e, stack, 'PlaybackCacheMirror.done');
        } finally {
          if (!_errorInProgress && !controller.isClosed) {
            await controller.close();
          }
        }
      },
    );

    controller.onCancel = () async {
      await _upstream?.cancel();
      // finish() set _settled before closing the sink. It owns finalization
      // from that point; deleting the part here would race the pending rename.
      if (_settled) return;
      _settled = true;
      final sink = _sink;
      if (sink != null) {
        try {
          await sink.close();
        } catch (e, stack) {
          _reportError(e, stack, 'PlaybackCacheMirror.cancelClose');
        }
      }
      await _abandon();
    };

    // Backpressure: without these, a client that pauses (socket buffer full,
    // or mpv stalling) still leaves the dio source pushing bytes that pile up
    // in the controller's buffer unbounded. Pausing the upstream makes the
    // mirror honor the client's flow control instead of buffering the track.
    controller.onPause = () => _upstream?.pause();
    controller.onResume = () => _upstream?.resume();

    return controller.stream;
  }
}
