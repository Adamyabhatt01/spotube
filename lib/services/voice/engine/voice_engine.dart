// The main-isolate face of the voice engine. All sherpa objects and decoding
// live in a worker isolate (the bindings are synchronous FFI — a Whisper
// decode would otherwise freeze the UI); this proxy ships PCM in and events
// out. Event objects are plain data, so the worker sends them directly.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/voice/config/voice_config.dart';
import 'package:spotube/services/voice/matching/phrase_matcher.dart';
import 'package:spotube/services/voice/matching/text_normalizer.dart';

import 'voice_worker.dart';

sealed class VoiceEvent {
  const VoiceEvent();
}

class WakeDetectedEvent extends VoiceEvent {
  final String transcript;
  const WakeDetectedEvent(this.transcript);
}

class CommandHeardEvent extends VoiceEvent {
  final String transcript;

  /// None when nothing matched; ambiguous when two candidates scored alike.
  final VoiceCommandResult result;

  /// True in the editor's Test-phrase mode: parsed, but nothing dispatches.
  final bool suppressed;
  const CommandHeardEvent({
    required this.transcript,
    required this.result,
    this.suppressed = false,
  });
}

class TranscriptTickEvent extends VoiceEvent {
  final String partial;
  const TranscriptTickEvent(this.partial);
}

/// A long run of zero/flat samples: the mic is muted or silenced by a
/// higher-priority capture, which surfaces as silence, not as an error.
class SilenceSuspectedEvent extends VoiceEvent {
  const SilenceSuspectedEvent();
}

class EngineFailedEvent extends VoiceEvent {
  final VoiceFailure failure;
  const EngineFailedEvent(this.failure);
}

enum VoiceFailure { micBusy, captureUnavailable, modelMissing, engineDied }

class VoiceWindowClosedEvent extends VoiceEvent {
  /// 'endpoint', 'timeout', 'manual' or 'wake'.
  final String reason;
  const VoiceWindowClosedEvent(this.reason);
}

/// Ack that the worker has torn its native handles down; `dispose` waits for it
/// because killing the isolate first would leak the onnxruntime allocations.
class EngineStoppedEvent extends VoiceEvent {
  const EngineStoppedEvent();
}

/// Everything the worker needs to build native objects. Paths are absolute
/// files already placed by the model registry/downloader.
class VoiceEngineParams {
  final VoiceLanguage language;
  final VoiceMode mode;
  final List<String> wakePhrases;
  final Map<VoiceCommandId, List<String>> commandPhrases;

  /// Stage-1/wake and the en/es/fr command model (transducer int8 set).
  final String? streamingEncoderPath;
  final String? streamingDecoderPath;
  final String? streamingJoinerPath;
  final String streamingTokensPath;

  /// Shared silero VAD; unused in tap-to-talk (a user-initiated window needs
  /// no gate).
  final String? vadModelPath;

  /// hi/ar stage-2: offline (Whisper) model directory, used only when the
  /// streaming set cannot serve [language].
  final String? offlineModelDir;

  /// Optional dylib directory override for spikes/tests; null lets the
  /// Flutter plugin's packaging resolve the library.
  final String? dylibPath;

  final bool suppressDispatch;
  final int commandWindowSeconds;

  const VoiceEngineParams({
    required this.language,
    required this.mode,
    required this.wakePhrases,
    required this.commandPhrases,
    this.streamingEncoderPath,
    this.streamingDecoderPath,
    this.streamingJoinerPath,
    required this.streamingTokensPath,
    this.vadModelPath,
    this.offlineModelDir,
    this.dylibPath,
    this.suppressDispatch = false,
    this.commandWindowSeconds = 6,
  });
}

abstract interface class VoiceEngine {
  Stream<VoiceEvent> get events;
  bool get isRunning;

  Future<void> start(VoiceEngineParams params);

  /// Raw 16 kHz mono s16le bytes from the capture port, main side.
  void feedPcm(Uint8List bytes);

  /// Live phrase change without respawning the isolate (editor Test-phrase).
  Future<void> updatePhrases({
    List<String>? wakePhrases,
    Map<VoiceCommandId, List<String>>? commandPhrases,
    VoiceLanguage? language,
    bool? suppressDispatch,
  });

  /// Tap-to-talk: open a command window now.
  Future<void> beginTapWindow();

  /// Close the command window but keep listening: the "stop listening"
  /// command, and the editor leaving test-phrase mode.
  Future<void> endCommandWindow();

  /// Drop decoding until [until] — after a wake earcon played out loud.
  Future<void> suppressUntil(DateTime until);

  Future<void> stop();
  Future<void> dispose();
}

/// Isolate-backed engine: control goes out as plain maps over one [SendPort],
/// events come back as whole [VoiceEvent] objects.
class IsolateVoiceEngine implements VoiceEngine {
  final StreamController<VoiceEvent> _controller =
      StreamController<VoiceEvent>.broadcast();

  Isolate? _isolate;
  SendPort? _control;
  RawReceivePort? _receive;
  ReceivePort? _errors;
  bool _running = false;
  bool _disposed = false;
  Completer<void>? _stopAck;

  @override
  Stream<VoiceEvent> get events => _controller.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start(VoiceEngineParams params) async {
    if (_running) return;

    final handshake = Completer<void>();
    final receive = _receive = RawReceivePort();
    receive.handler = (raw) {
      if (raw is SendPort) {
        _control = raw;
        if (!handshake.isCompleted) handshake.complete();
      } else if (raw is VoiceEvent && !_controller.isClosed) {
        if (raw is EngineStoppedEvent && _stopAck != null) {
          if (!_stopAck!.isCompleted) _stopAck!.complete();
          return;
        }
        _controller.add(raw);
      }
    };

    // Uncaught errors in the worker are not fatal to the app, but they do end
    // the session: report them as a failure the UI can show. Isolate.spawn
    // sends a two-element [error, stackTraceString] list for an error, and the
    // exit response (null unless one is given) when the isolate terminates.
    final errors = _errors = ReceivePort();
    errors.listen((raw) {
      if (_controller.isClosed || _disposed) return;
      // Termination arrives as the `response` value, which defaults to null;
      // an uncaught error arrives as a [error, stackTraceString] list.
      if (raw == null) {
        if (!_running) return;
        _running = false;
        _controller.add(const EngineFailedEvent(VoiceFailure.engineDied));
        return;
      }
      final error = raw is List && raw.isNotEmpty ? raw.first : raw;
      AppLogger.reportError(error, null, 'voice worker isolate');
      _running = false;
      _controller.add(const EngineFailedEvent(VoiceFailure.engineDied));
    });

    _isolate = await Isolate.spawn(
      voiceWorkerEntry,
      receive.sendPort,
      debugName: 'voice-worker',
      errorsAreFatal: false,
      onError: errors.sendPort,
      onExit: errors.sendPort,
    );
    try {
      // Bounded: a worker that spawns but dies before sending its port would
      // otherwise hang this future forever, leaving the controller's
      // `_starting` flag stuck and `sync()` permanently inert.
      await handshake.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _isolate?.kill();
      _isolate = null;
      _receive?.close();
      _receive = null;
      _errors?.close();
      _errors = null;
      rethrow;
    }
    _send(WorkerMessages.start(params));
    _running = true;
  }

  void _send(Map<String, Object?> message) => _control?.send(message);

  @override
  void feedPcm(Uint8List bytes) {
    // TransferableTypedData moves the buffer's memory to the worker without
    // copying it.
    _send(WorkerMessages.pcm(TransferableTypedData.fromList([bytes])));
  }

  @override
  Future<void> updatePhrases({
    List<String>? wakePhrases,
    Map<VoiceCommandId, List<String>>? commandPhrases,
    VoiceLanguage? language,
    bool? suppressDispatch,
  }) async {
    _send(WorkerMessages.updatePhrases(
      wakePhrases,
      commandPhrases?.map((k, v) => MapEntry(k.name, v)),
      language?.code,
      suppressDispatch,
    ));
  }

  @override
  Future<void> beginTapWindow() async => _send(WorkerMessages.tap());

  @override
  Future<void> endCommandWindow() async => _send(WorkerMessages.endWindow());

  @override
  Future<void> suppressUntil(DateTime until) async =>
      _send(WorkerMessages.suppress(until.microsecondsSinceEpoch));

  @override
  Future<void> stop() async {
    if (!_running) return;
    final ack = _stopAck = Completer<void>();
    _send(WorkerMessages.stop());
    _running = false;
    // Killing the isolate before it frees its own onnxruntime handles leaks
    // native memory, so the ack is waited for — bounded, because a worker that
    // is already gone should not hang the app on exit.
    await ack.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
    _stopAck = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _control = null;
    _receive?.close();
    _receive = null;
    _errors?.close();
    _errors = null;
    await _controller.close();
  }
}
