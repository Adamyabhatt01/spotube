import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'dart:async';

/// Reply envelope used between the worker isolate and the main isolate.
/// The worker always sends `['ok', payload]` or `['err', message]` so a
/// failing method completes the caller's Future instead of hanging it.
const _kReplyOk = 'ok';
const _kReplyErr = 'err';

/// In-flight method call bookkeeping: pending completers are completed
/// with an error when the worker dies or the instance is disposed, so
/// no caller is left hanging after the isolate is gone.
class _PendingCall {
  _PendingCall(this.completer, this.responsePort);

  final Completer<Object?> completer;
  final ReceivePort responsePort;
}

class IsolatedYoutubeExplode {
  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final ReceivePort _exitPort;
  final Completer<void> _exitCompleter;
  final StreamSubscription<dynamic> _exitSubscription;

  final Map<SendPort, _PendingCall> _pendingCalls = {};

  IsolatedYoutubeExplode._(
    Isolate isolate,
    ReceivePort receivePort,
    SendPort sendPort,
    ReceivePort exitPort,
    Completer<void> exitCompleter,
    StreamSubscription<dynamic> exitSubscription,
  )   : _isolate = isolate,
        _receivePort = receivePort,
        _sendPort = sendPort,
        _exitPort = exitPort,
        _exitCompleter = exitCompleter,
        _exitSubscription = exitSubscription {
    // When the worker exits, reset the singleton and fail every
    // in-flight call so callers see an error instead of a hang. The
    // next [initialize] then respawns the worker cleanly.
    unawaited(
      _exitCompleter.future.then((_) => _handleWorkerExit()),
    );
  }

  static IsolatedYoutubeExplode? _instance;

  /// Single-flight in-progress initialization, so concurrent callers
  /// share one isolate spawn instead of racing and leaking isolates.
  static Future<void>? _initializeFuture;

  static IsolatedYoutubeExplode get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError(
        'IsolatedYoutubeExplode is not initialized. '
        'Call IsolatedYoutubeExplode.initialize() first.',
      );
    }
    return instance;
  }

  static bool get isInitialized => _instance != null;

  static Future<void> initialize() {
    final instance = _instance;
    if (instance != null) {
      return Future.value();
    }
    return _initializeFuture ??= _doInitialize();
  }

  static Future<void> _doInitialize() async {
    ReceivePort? receivePort;
    ReceivePort? exitPort;
    StreamSubscription<dynamic>? handshakeSubscription;
    Isolate? isolate;

    try {
      receivePort = ReceivePort();

      final handshakeCompleter = Completer<SendPort>();
      handshakeSubscription = receivePort.listen((message) {
        if (message is SendPort && !handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(message);
        }
      });

      isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

      // One exit notification drives both the handshake guard (worker
      // dies before sending its port) and the post-init failure path.
      exitPort = ReceivePort();
      final exitCompleter = Completer<void>();
      final exitSubscription = exitPort.listen((_) {
        if (!exitCompleter.isCompleted) exitCompleter.complete();
      });
      isolate.addOnExitListener(exitPort.sendPort);

      unawaited(exitCompleter.future.then((_) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            StateError('The YouTube worker isolate exited during startup.'),
          );
        }
      }));

      // Bounded handshake: a wedged worker startup must not hang
      // the caller forever.
      final sendPort = await handshakeCompleter.future.timeout(
        const Duration(seconds: 30),
      );
      await handshakeSubscription.cancel();
      handshakeSubscription = null;

      _instance = IsolatedYoutubeExplode._(
        isolate,
        receivePort,
        sendPort,
        exitPort,
        exitCompleter,
        exitSubscription,
      );
    } catch (_) {
      await handshakeSubscription?.cancel();
      exitPort?.close();
      receivePort?.close();
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      _initializeFuture = null;
    }
  }

  static Future<void> _isolateEntry(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    final youtubeExplode = YoutubeExplode();
    final stopWatch = kDebugMode ? Stopwatch() : null;

    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      final SendPort replyPort = message[0];
      final String methodName = message[1];
      final List<dynamic> arguments = message[2];

      try {
        if (stopWatch != null) {
          if (stopWatch.isRunning) {
            stopWatch.stop();
            final symbol = stopWatch.elapsedMilliseconds < 1000 ? "⚠️" : "⏱️";
            debugPrint(
              "$symbol YoutubeExplode operation gap ${stopWatch.elapsedMilliseconds} ms",
            );
            stopWatch.reset();
          } else {
            stopWatch.start();
          }
        }

        final Future<Object?> result = switch (methodName) {
          "search" => youtubeExplode.search
              .search(
                arguments[0] as String,
                filter: TypeFilters.video,
              )
              .then((s) => s.toList()),
          "video" => youtubeExplode.videos.get(arguments[0] as String),
          "manifest" => youtubeExplode.videos.streamsClient.getManifest(
                arguments[0] as String,
                requireWatchPage: arguments.elementAtOrNull(1) ?? true,
                ytClients:
                    arguments.elementAtOrNull(2) as List<YoutubeApiClient>?,
              ),
          _ => Future<Object?>.error(
              ArgumentError('Invalid method name: $methodName'),
            ),
        };

        replyPort.send([_kReplyOk, await result]);
      } catch (e) {
        // Never let a worker-side failure strand the caller's Future.
        try {
          replyPort.send([_kReplyErr, e.toString()]);
        } catch (_) {
          // The reply port is already closed (caller disposed/cancelled).
        }
      }
    });
  }

  Future<T> _runMethod<T>(String methodName, List<dynamic> args) async {
    final completer = Completer<Object?>();
    final responsePort = ReceivePort();
    _pendingCalls[responsePort.sendPort] = _PendingCall(completer, responsePort);

    late final StreamSubscription<dynamic> subscription;
    subscription = responsePort.listen((message) {
      _pendingCalls.remove(responsePort.sendPort);
      try {
        if (message is List && message.length == 2) {
          if (message[0] == _kReplyErr) {
            completer.completeError(
              StateError(
                'IsolatedYoutubeExplode.$methodName failed: ${message[1]}',
              ),
            );
            return;
          }
          completer.complete(message[1]);
          return;
        }
        completer.completeError(
          StateError(
            'IsolatedYoutubeExplode.$methodName returned a malformed reply.',
          ),
        );
      } finally {
        unawaited(subscription.cancel());
        responsePort.close();
      }
    });

    _sendPort.send([responsePort.sendPort, methodName, args]);

    final stopwatch = Stopwatch()..start();
    try {
      return (await completer.future.timeout(engineCallBudget)) as T;
    } on TimeoutException {
      // The worker still holds this reply port and will eventually send to it,
      // so the bookkeeping has to go or the entry and the port both leak. The
      // worker's own send is already guarded against a closed port.
      _pendingCalls.remove(responsePort.sendPort);
      unawaited(subscription.cancel());
      responsePort.close();
      PerfCounters.note('engine.youtube_explode.$methodName.timeout');
      rethrow;
    } finally {
      PerfCounters.time('engine.youtube_explode.$methodName', stopwatch.elapsed);
    }
  }

  void _failPendingCalls(Object error) {
    final pending = _pendingCalls.values.toList();
    _pendingCalls.clear();
    for (final call in pending) {
      if (!call.completer.isCompleted) {
        call.completer.completeError(error);
      }
      call.responsePort.close();
    }
  }

  void _handleWorkerExit() {
    if (!identical(_instance, this)) return;
    _instance = null;
    unawaited(_exitSubscription.cancel());
    _failPendingCalls(
      StateError('The YouTube worker isolate exited unexpectedly.'),
    );
    _receivePort.close();
    _exitPort.close();
  }

  Future<List<Video>> search(String query) async {
    return _runMethod<List<Video>>("search", [query]);
  }

  Future<Video> video(String videoId) async {
    return _runMethod<Video>("video", [videoId]);
  }

  Future<StreamManifest> manifest(
    String videoId, {
    bool requireWatchPage = false,
    List<YoutubeApiClient>? ytClients,
  }) async {
    return _runMethod<StreamManifest>("manifest", [
      videoId,
      requireWatchPage,
      ytClients,
    ]);
  }

  void dispose() {
    if (!identical(_instance, this)) {
      return;
    }
    _instance = null;
    _failPendingCalls(
      StateError('IsolatedYoutubeExplode was disposed.'),
    );
    unawaited(_exitSubscription.cancel());
    _exitPort.close();
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class YouTubeExplodeEngine implements YouTubeEngine {
  static bool get isAvailableForPlatform => true;

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    await IsolatedYoutubeExplode.initialize();

    final instance = IsolatedYoutubeExplode.instance;

    // YouTube currently 403s the ANDROID client's stream URLs (bot/PO-token
    // enforcement), so it is no longer in the primary set: a manifest full
    // of android-client URLs used to validate empty downstream and send
    // playback into an endless refresh loop.
    Future<StreamManifest> manifestFor(List<YoutubeApiClient> clients) =>
        instance.manifest(
          videoId,
          requireWatchPage: false,
          ytClients: clients,
        );

    StreamManifest streamManifest;
    List<AudioOnlyStreamInfo> audioStreams;
    try {
      streamManifest = await manifestFor([
        YoutubeApiClient.ios,
        YoutubeApiClient.androidVr,
      ]);
      audioStreams = streamManifest.audioOnly
          .where((stream) => stream.bitrate.bitsPerSecond >= 40960)
          .toList();
      if (audioStreams.isEmpty) {
        throw VideoUnavailableException(
          'Video "$videoId" has no audio streams above 40 kbps',
        );
      }
    } catch (_) {
      // iOS / Android-VR manifests were rejected outright. The TV client is
      // the robust fallback (upstream uses it for restricted videos); it
      // auto-fetches the watch page for signature decoding, so it works
      // even with requireWatchPage: false.
      streamManifest = await manifestFor([YoutubeApiClient.tv]);
      audioStreams = streamManifest.audioOnly
          .where((stream) => stream.bitrate.bitsPerSecond >= 40960)
          .toList();
    }

    return StreamManifest(
      audioStreams.map(
        (stream) => AudioOnlyStreamInfo(
          stream.videoId,
          stream.tag,
          stream.url,
          stream.container,
          stream.size,
          stream.bitrate,
          stream.audioCodec,
          switch (stream.bitrate.bitsPerSecond) {
            > 130 * 1024 => "high",
            > 64 * 1024 => "medium",
            _ => "low",
          },
          stream.fragments,
          stream.codec,
          stream.audioTrack,
        ),
      ),
    );
  }

  @override
  Future<Video> getVideo(String videoId) async {
    await IsolatedYoutubeExplode.initialize();
    return IsolatedYoutubeExplode.instance.video(videoId);
  }

  @override
  Future<List<YouTubeSearchResult>> searchVideos(String query) async {
    await IsolatedYoutubeExplode.initialize();

    final videos = await IsolatedYoutubeExplode.instance.search(query);
    return videos.map(YouTubeSearchResult.fromVideo).toList();
  }

  void dispose() {
    if (!IsolatedYoutubeExplode.isInitialized) return;
    IsolatedYoutubeExplode.instance.dispose();
  }
}
