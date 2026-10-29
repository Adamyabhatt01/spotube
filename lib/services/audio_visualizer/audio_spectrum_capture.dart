import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spotube/services/audio_visualizer/audio_spectrum.dart';
import 'package:spotube/services/logger/logger.dart';

const int _bytesPerSample = 4;
const int _windowBytes = kAudioSpectrumWindowSize * _bytesPerSample;
const int _hopBytes = kAudioSpectrumHopSize * _bytesPerSample;

/// Captures the default output monitor with `parec` and emits FFT frames.
///
/// The player backends do not expose PCM, so the only honest source on Linux
/// is the system audio monitor. Capture starts when the equalizer page opens
/// and stops when it closes, which also keeps it from recording anything in
/// the background.
class AudioSpectrumCapture {
  final AudioSpectrumAnalyzer _analyzer = AudioSpectrumAnalyzer();
  final StreamController<List<double>> _controller = StreamController();

  Process? _process;
  Uint8List _pending = Uint8List(0);
  bool _disposed = false;
  bool _closed = false;

  Stream<List<double>> get frames => _controller.stream;

  Future<void> start() async {
    if (_process != null || _disposed) return;

    final process = await Process.start(
      'parec',
      const [
        '--format=float32le',
        '--rate=$kAudioSpectrumSampleRate',
        '--channels=1',
        '--latency-msec=20',
        '--device=@DEFAULT_MONITOR@',
        '--client-name=Spotube visualizer',
        '--stream-name=Spotube visualizer',
      ],
    );

    if (_disposed) {
      process.kill();
      return;
    }
    _process = process;

    process.stdout.listen(
      _onChunk,
      onError: (Object error, StackTrace stack) {
        _fail(error, stack);
      },
      onDone: _onDone,
      cancelOnError: true,
    );
    // Drain stderr; parec reports connection problems there. Only the exit
    // code is surfaced to the UI, but an undrained pipe can block the process.
    process.stderr.transform(utf8.decoder).listen((_) {});

    unawaited(process.exitCode.then((code) {
      if (!_disposed && !_closed && code != 0) {
        _fail('parec exited with code $code');
      }
    }));
  }

  void _onChunk(List<int> chunk) {
    if (_disposed || _closed) return;

    final merged = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    _pending = merged;

    while (_pending.length >= _windowBytes) {
      final window = Uint8List.sublistView(_pending, 0, _windowBytes);
      final samples = Float32List.view(
        window.buffer,
        window.offsetInBytes,
        kAudioSpectrumWindowSize,
      );
      final bands = _analyzer.analyze(samples);
      if (!_controller.isClosed) _controller.add(bands);

      final remaining = _pending.length - _hopBytes;
      _pending = Uint8List(remaining)
        ..setRange(0, remaining, _pending, _hopBytes);
    }
  }

  void _onDone() {
    _close();
  }

  void _fail(Object error, [StackTrace? stack]) {
    AppLogger.reportError(error, stack, 'audio visualizer');
    if (!_controller.isClosed) _controller.addError(error);
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _process?.kill();
    _process = null;
    if (!_controller.isClosed) _controller.close();
  }

  void dispose() {
    _disposed = true;
    _close();
  }
}
