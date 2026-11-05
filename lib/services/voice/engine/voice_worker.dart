// Isolate entry for all sherpa-onnx work: FFI pointers can't cross isolates,
// so every native object (VAD, recognizers, streams) is created, used and
// freed here. The main side only ever sees PCM going in and VoiceEvents
// coming back.
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../config/voice_config.dart';
import '../matching/phrase_matcher.dart';
import '../matching/text_normalizer.dart';
import 'pcm_capture_port.dart';
import 'voice_engine.dart';

/// Control-message shapes between the engine proxy and this worker.
abstract final class WorkerMessages {
  static const startOp = 'start';
  static const pcmOp = 'pcm';
  static const updateOp = 'update';
  static const tapOp = 'tap';
  static const endOp = 'end';
  static const suppressOp = 'suppress';
  static const stopOp = 'stop';

  static Map<String, Object?> start(VoiceEngineParams params) =>
      {op: startOp, 'params': params};
  static Map<String, Object?> pcm(TransferableTypedData data) =>
      {op: pcmOp, 'data': data};
  static Map<String, Object?> updatePhrases(
    List<String>? wake,
    Map<String, List<String>>? commands,
    String? language,
    bool? suppressDispatch,
  ) =>
      {
        op: updateOp,
        'wake': wake,
        'commands': commands,
        'language': language,
        'suppress': suppressDispatch,
      };
  static Map<String, Object?> tap() => {op: tapOp};
  static Map<String, Object?> endWindow() => {op: endOp};
  static Map<String, Object?> suppress(int untilMicroseconds) =>
      {op: suppressOp, 'until': untilMicroseconds};
  static Map<String, Object?> stop() => {op: stopOp};

  static const op = 'op';
}

void voiceWorkerEntry(SendPort main) {
  final port = RawReceivePort();
  final worker = _VoiceWorker(main: main, port: port);
  port.handler = worker.handle;
  // Handshake first, before any model work: the main side waits on this to
  // know it has a channel, and waits no further than that.
  main.send(port.sendPort);
}

enum _Session { idle, commandWindow }

class _VoiceWorker {
  _VoiceWorker({required this.main, required this.port});

  final SendPort main;
  final RawReceivePort port;

  VoiceEngineParams? _params;
  PhraseMatcher matcher = const PhraseMatcher();

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  sherpa_onnx.VoiceActivityDetector? _vad;

  _Session _session = _Session.idle;
  Timer? _windowTimer;
  int _suppressUntilUs = 0;
  bool _started = false;
  bool _disposed = false;

  // Rolling tail for wake: last few utterance texts of the wake stage.
  final List<String> _tail = [];
  String _windowTranscript = '';
  String _lastStageText = '';
  String _lastDispatched = '';

  // Silence detection: zero/flat sample runs are muted or silenced mics,
  // which report no error at all.
  int _silentMs = 0;
  bool _silenceReported = false;

  // Backpressure: audio time accounted for vs wall clock. Every received
  // chunk advances the audio clock — fed or dropped — so a decode slower
  // than realtime shows up as growing lag instead of an ever-lengthening
  // queue of stale audio.
  static const _maxLagMicros = 300 * 1000;
  int _lagEpochUs = 0;
  int _streamAudioUs = 0;

  void handle(dynamic message) {
    if (message is! Map) return;
    switch (message[WorkerMessages.op]) {
      case WorkerMessages.startOp:
        _start(message['params'] as VoiceEngineParams);
      case WorkerMessages.pcmOp:
        _pcm(message['data'] as TransferableTypedData);
      case WorkerMessages.updateOp:
        _update(message);
      case WorkerMessages.tapOp:
        _openWindow('tap');
      case WorkerMessages.endOp:
        // Close the window, keep the models: what "stop listening" and the
        // earcon-suppression path need.
        _endWindow('manual');
      case WorkerMessages.suppressOp:
        _suppressUntilUs = message['until'] as int;
      case WorkerMessages.stopOp:
        _endWindow('manual');
        _releaseNative();
        _lagEpochUs = 0;
        _streamAudioUs = 0;
        _started = false;
        main.send(const EngineStoppedEvent());
    }
  }

  void _start(VoiceEngineParams params) {
    _params = params;
    _lagEpochUs = 0;
    _streamAudioUs = 0;
    try {
      _requireFiles(params);
      sherpa_onnx.initBindings(params.dylibPath);
      _buildNative(params);
      _started = true;
    } catch (error) {
      // Not AppLogger: its reporters go over plugin channels, which a bare
      // worker isolate has no attachment to.
      developer.log('$error', name: 'voice worker start failed');
      main.send(EngineFailedEvent(_classifyFailure(error)));
    }
  }

  /// Checked before the native layer sees the paths: onnxruntime's reaction to
  /// a missing model is a config dump on stderr at best, so an un-downloaded
  /// model has to be named here rather than discovered there.
  void _requireFiles(VoiceEngineParams params) {
    final required = <String?>[
      params.streamingEncoderPath,
      params.streamingDecoderPath,
      params.streamingJoinerPath,
      params.streamingTokensPath,
      if (params.mode == VoiceMode.wake) params.vadModelPath,
    ];
    for (final path in required.whereType<String>()) {
      if (!File(path).existsSync()) {
        throw StateError('voice model file is missing: $path');
      }
    }
  }

  VoiceFailure _classifyFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('model') ||
        text.contains('onnx') ||
        text.contains('no such file')) {
      return VoiceFailure.modelMissing;
    }
    return VoiceFailure.captureUnavailable;
  }

  void _buildNative(VoiceEngineParams params) {
    final encoder = params.streamingEncoderPath;
    final decoder = params.streamingDecoderPath;
    final joiner = params.streamingJoinerPath;
    if (encoder == null || decoder == null || joiner == null) {
      throw StateError('streaming model paths required to build recognizer');
    }
    _recognizer = sherpa_onnx.OnlineRecognizer(
      sherpa_onnx.OnlineRecognizerConfig(
        model: sherpa_onnx.OnlineModelConfig(
          transducer: sherpa_onnx.OnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: params.streamingTokensPath,
          numThreads: 1,
          provider: 'cpu',
        ),
        decodingMethod: 'greedy_search',
        enableEndpoint: true,
      ),
    );
    _stream = _recognizer!.createStream();

    final vadPath = params.vadModelPath;
    if (params.mode == VoiceMode.wake && vadPath != null) {
      _vad = sherpa_onnx.VoiceActivityDetector(
        config: sherpa_onnx.VadModelConfig(
          sileroVad: sherpa_onnx.SileroVadModelConfig(
            model: vadPath,
            threshold: 0.5,
            minSilenceDuration: 0.25,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: 5.0,
          ),
          sampleRate: kVoiceSampleRate,
          numThreads: 1,
          provider: 'cpu',
        ),
        bufferSizeInSeconds: 15,
      );
    }
  }

  void _update(Map message) {
    final p = _params;
    if (p == null) return;
    _params = VoiceEngineParams(
      language: (message['language'] as String?) == null
          ? p.language
          : VoiceLanguage.fromCode(message['language'] as String),
      mode: p.mode,
      wakePhrases: (message['wake'] as List?)?.cast<String>() ?? p.wakePhrases,
      commandPhrases: _mergeCommands(message['commands'], p.commandPhrases),
      streamingEncoderPath: p.streamingEncoderPath,
      streamingDecoderPath: p.streamingDecoderPath,
      streamingJoinerPath: p.streamingJoinerPath,
      streamingTokensPath: p.streamingTokensPath,
      vadModelPath: p.vadModelPath,
      offlineModelDir: p.offlineModelDir,
      dylibPath: p.dylibPath,
      suppressDispatch: message['suppress'] as bool? ?? p.suppressDispatch,
      commandWindowSeconds: p.commandWindowSeconds,
    );
  }

  Map<VoiceCommandId, List<String>> _mergeCommands(
    Object? raw,
    Map<VoiceCommandId, List<String>> current,
  ) {
    if (raw is! Map) return current;
    final out = <VoiceCommandId, List<String>>{};
    for (final entry in raw.entries) {
      try {
        out[VoiceCommandId.values.byName(entry.key as String)] =
            (entry.value as List).cast<String>();
      } on Exception {
        continue;
      }
    }
    return out.isEmpty ? current : out;
  }

  void _pcm(TransferableTypedData transfer) {
    if (!_started || _disposed) return;
    final now = DateTime.now().microsecondsSinceEpoch;

    final int16 = Int16List.view(transfer.materialize());
    if (int16.isEmpty) return;
    final chunkUs = int16.length * 1000000 ~/ kVoiceSampleRate;

    if (_lagEpochUs == 0) _lagEpochUs = now;
    _streamAudioUs += chunkUs;
    final lagUs = (now - _lagEpochUs) - _streamAudioUs;

    // Suppressed audio (an earcon played out loud) still advances the audio
    // clock — it is real time the recognizer must not hear, not backlog.
    if (now < _suppressUntilUs) return;
    if (lagUs > _maxLagMicros) {
      // Behind realtime: drop the chunk and reset the recognizer so its
      // partial does not keep decoding audio that is already stale.
      _resetStream();
      return;
    }

    _trackSilence(int16);

    final samples = Float32List(int16.length);
    for (var i = 0; i < int16.length; i++) {
      samples[i] = int16[i] / 32768.0;
    }

    final vad = _vad;
    if (_params?.mode == VoiceMode.wake && vad != null) {
      _wakeStage(samples, vad);
    } else {
      _directStage(samples);
    }
  }

  void _trackSilence(Int16List int16) {
    var peak = 0;
    for (final s in int16) {
      final abs = s < 0 ? -s : s;
      if (abs > peak) peak = abs;
    }
    // Anything under ~0.05% of full scale counts as flat.
    if (peak < 32) {
      _silentMs += int16.length * 1000 ~/ kVoiceSampleRate;
      if (_silentMs > 5000 && !_silenceReported) {
        _silenceReported = true;
        main.send(const SilenceSuspectedEvent());
      }
    } else {
      _silentMs = 0;
      _silenceReported = false;
    }
  }

  /// Wake mode: VAD gates decoding; finished utterances go through the wake
  /// matcher, and while a command window is open through the command matcher.
  void _wakeStage(Float32List samples, sherpa_onnx.VoiceActivityDetector vad) {
    vad.acceptWaveform(samples);
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      _stream?.acceptWaveform(
          samples: segment.samples, sampleRate: kVoiceSampleRate);
      final text = _readText();
      // The VAD already decided where the utterance ends. The recognizer's own
      // endpoint rule rarely fires on pre-cut segments (Phase 0 spike saw zero
      // endpoints on batch VAD replay), so segment completion is the boundary.
      _finalizeUtterance(text);
      _resetStream();
    }
  }

  void _directStage(Float32List samples) {
    _stream?.acceptWaveform(samples: samples, sampleRate: kVoiceSampleRate);
    final text = _readText();
    final rec = _recognizer;
    final stream = _stream;
    if (rec != null && stream != null && rec.isEndpoint(stream)) {
      _finalizeUtterance(text);
      _resetStream();
    }
  }

  /// Decode everything queued, emit the live partial if it changed, and return
  /// the current text.
  String _readText() {
    final rec = _recognizer;
    final stream = _stream;
    if (rec == null || stream == null) return '';
    while (rec.isReady(stream)) {
      rec.decode(stream);
    }
    final partial = rec.getResult(stream).text.trim();
    if (partial.isNotEmpty && partial != _lastStageText) {
      _lastStageText = partial;
      main.send(TranscriptTickEvent(partial));
    }
    return partial;
  }

  void _resetStream() {
    final rec = _recognizer;
    final stream = _stream;
    if (rec != null && stream != null) rec.reset(stream);
    _lastStageText = '';
  }

  void _finalizeUtterance(String text) {
    if (text.isEmpty) return;
    final params = _params;
    if (params == null) return;

    if (_session == _Session.commandWindow) {
      _windowTranscript =
          _windowTranscript.isEmpty ? text : '$_windowTranscript $text';
      if (_dispatch(_windowTranscript)) {
        _resetStream();
        _endWindow('endpoint');
      }
      return;
    }

    // Idle wake stage.
    _tail.add(text);
    if (_tail.length > 4) _tail.removeAt(0);
    final joined = _tail.join(' ');
    final remainder = params.mode == VoiceMode.wake
        ? matcher.wakeRemainder(joined, params.wakePhrases, params.language)
        : null;
    if (remainder == null) return;

    _tail.clear();
    main.send(WakeDetectedEvent(joined));
    if (remainder.trim().isNotEmpty) {
      // Same breath: "hey spotube pause".
      _dispatch(remainder);
    }
    _openWindow('wake');
  }

  /// Match and report. Returns whether something matched; session bookkeeping
  /// stays with the callers so a flush cannot re-enter a dispatch.
  bool _dispatch(String transcript) {
    final params = _params;
    if (params == null || transcript.isEmpty) return false;
    if (transcript == _lastDispatched) return true;
    final result = matcher.matchCommand(
      transcript,
      params.commandPhrases,
      params.language,
    );
    if (!result.hasMatch && !result.isAmbiguous) {
      // No match: keep listening until the window times out.
      return false;
    }
    _lastDispatched = transcript;
    main.send(CommandHeardEvent(
      transcript: transcript,
      result: result,
      suppressed: params.suppressDispatch,
    ));
    return true;
  }

  void _openWindow(String trigger) {
    final params = _params;
    if (params == null) return;
    _session = _Session.commandWindow;
    _windowTranscript = '';
    _lastDispatched = '';
    _windowTimer?.cancel();
    _windowTimer = Timer(
      Duration(seconds: params.commandWindowSeconds),
      () => _endWindow('timeout'),
    );
  }

  /// Close the command window. Whatever is still in the recognizer stream is
  /// dispatched first: a speaker who stops mid-utterance, and an unpaced fixture
  /// replay, both leave audio with no trailing silence for the endpoint rule to
  /// react to, and dropping that text would drop the command.
  void _endWindow(String reason) {
    _windowTimer?.cancel();
    _windowTimer = null;
    if (_session != _Session.commandWindow) return;
    _session = _Session.idle;

    // `_windowTranscript` holds utterances that already ended and were reset;
    // `pending` is what is in the stream since then. They cover different
    // audio, so they join.
    final pending = _tailText();
    final full =
        _windowTranscript.isEmpty ? pending : '$_windowTranscript $pending';
    _windowTranscript = '';
    _lastDispatched = '';

    _dispatch(full);
    main.send(VoiceWindowClosedEvent(reason));
  }

  /// Decode whatever is queued and return the current text without emitting a
  /// tick.
  String _tailText() {
    final rec = _recognizer;
    final stream = _stream;
    if (rec == null || stream == null) return '';
    while (rec.isReady(stream)) {
      rec.decode(stream);
    }
    return rec.getResult(stream).text.trim();
  }

  void _releaseNative() {
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    _vad?.free();
    _vad = null;
  }

  void dispose() {
    _disposed = true;
    _windowTimer?.cancel();
    _releaseNative();
    port.close();
  }
}
