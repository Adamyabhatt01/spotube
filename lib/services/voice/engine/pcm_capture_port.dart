// Mic PCM sources. One owner for the microphone (the visualizer captures the
// output monitor, a different stream), and a fixture source so the engine can
// be regression-tested against recorded audio instead of a live mic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

const int kVoiceSampleRate = 16000;

/// 100 ms of mono s16le at [kVoiceSampleRate].
const int kVoiceChunkBytes = kVoiceSampleRate ~/ 5;

/// 16 kHz mono signed 16-bit little-endian PCM in ~100 ms chunks (3200 bytes).
abstract interface class PcmCapturePort {
  Stream<Uint8List> get chunks;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Slices an arbitrary byte stream into fixed-size chunks, holding the tail
/// back until enough bytes arrive — same pending-buffer shape as
/// [AudioSpectrumCapture].
class _PcmRechunker {
  _PcmRechunker(this.chunkBytes, this.out);

  final int chunkBytes;
  final StreamController<Uint8List> out;
  Uint8List _pending = Uint8List(0);

  void add(List<int> data) {
    if (out.isClosed) return;
    final merged = Uint8List(_pending.length + data.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + data.length, data);
    _pending = merged;
    while (_pending.length >= chunkBytes) {
      out.add(Uint8List.fromList(_pending.sublist(0, chunkBytes)));
      _pending = Uint8List.fromList(_pending.sublist(chunkBytes));
    }
  }

  void reset() {
    _pending = Uint8List(0);
  }
}

/// Linux capture through `parec` on the default source, mirroring the
/// visualizer's monitor capture: stderr drained, exit code surfaced honestly.
class PulsePcmCapture implements PcmCapturePort {
  static const _chunkBytes = kVoiceChunkBytes; // 100 ms @ 16 kHz s16 mono

  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  Process? _process;
  _PcmRechunker? _rechunker;
  bool _disposed = false;
  bool _closed = false;

  @override
  Stream<Uint8List> get chunks => _controller.stream;

  @override
  Future<void> start() async {
    // `_closed` means stop() already ran: the single-subscription controller
    // is finished, so a restart would produce silence with no error.
    if (_process != null || _disposed || _closed) return;

    final process = await Process.start('parec', const [
      '--format=s16le',
      '--rate=$kVoiceSampleRate',
      '--channels=1',
      '--mode=record',
      '--client-name=Spotube voice',
      '--stream-name=Spotube voice commands',
    ]);

    if (_disposed) {
      process.kill();
      return;
    }
    _process = process;

    final rechunker = _rechunker = _PcmRechunker(_chunkBytes, _controller);
    process.stdout.listen(
      rechunker.add,
      onError: (Object error, StackTrace stack) => _fail(error, stack),
      onDone: _close,
      cancelOnError: true,
    );
    process.stderr.transform(utf8.decoder).listen((_) {});

    unawaited(process.exitCode.then((code) {
      if (!_disposed && !_closed && code != 0) {
        _fail('parec exited with code $code');
      }
    }));
  }

  @override
  Future<void> stop() async {
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _process?.kill();
    _process = null;
    _rechunker?.reset();
    if (!_controller.isClosed) _controller.close();
  }

  void _fail(Object error, [StackTrace? stack]) {
    // A single-subscription controller retains an added error until something
    // listens, so a missing/denied parec still surfaces to the UI rather than
    // vanishing because the indicator had not subscribed yet.
    if (!_controller.isClosed) _controller.addError(error, stack);
    _close();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _close();
  }
}

/// Android capture through the `record` plugin, with platform echo
/// cancellation and noise suppression requested (best effort: they are built
/// for the voice-call path and may not cancel our own media stream).
class RecordPcmCapture implements PcmCapturePort {
  static const _chunkBytes = kVoiceChunkBytes;

  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  _PcmRechunker? _rechunker;
  bool _disposed = false;
  bool _failed = false;
  bool _started = false;

  @override
  Stream<Uint8List> get chunks => _controller.stream;

  @override
  Future<void> start() async {
    if (_sub != null || _disposed || _failed) return;
    // request defaults to true, so this is the permission prompt itself.
    if (!await _recorder.hasPermission()) {
      _failed = true;
      if (!_controller.isClosed) {
        _controller.addError(const MicPermissionMissing());
        await _controller.close();
      }
      return;
    }

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: kVoiceSampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
    ));

    final rechunker = _rechunker = _PcmRechunker(_chunkBytes, _controller);
    _started = true;
    _sub = stream.listen(
      rechunker.add,
      onError: (Object e, StackTrace s) {
        if (!_controller.isClosed) _controller.addError(e, s);
      },
      onDone: () {
        if (!_controller.isClosed) _controller.close();
      },
    );
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    // `stop` on a recorder that never started (permission denied) throws a
    // PlatformException; only a live stream has something to stop.
    if (_started) {
      _started = false;
      await _recorder.stop();
    }
    _rechunker?.reset();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _recorder.dispose();
    if (!_controller.isClosed) await _controller.close();
  }
}

class MicPermissionMissing implements Exception {
  const MicPermissionMissing();
}

/// Replays a 16 kHz mono s16le WAV through the same chunk shape as a live
/// capture. Paced (real time) or flat-out, for the fixture regression harness.
class WavFixturePcmCapture implements PcmCapturePort {
  WavFixturePcmCapture(this.path, {this.paced = true});

  final String path;
  final bool paced;

  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  Timer? _timer;
  bool _disposed = false;

  @override
  Stream<Uint8List> get chunks => _controller.stream;

  @override
  Future<void> start() async {
    if (_disposed) return;
    final bytes = await File(path).readAsBytes();
    final pcm = _parseWavPcm16(bytes);
    const chunkBytes = kVoiceChunkBytes;
    final interval = paced ? const Duration(milliseconds: 100) : Duration.zero;

    var offset = 0;
    _timer = Timer.periodic(interval, (timer) async {
      if (offset >= pcm.length) {
        timer.cancel();
        if (!_controller.isClosed) await _controller.close();
        return;
      }
      final end = (offset + chunkBytes).clamp(0, pcm.length);
      _controller.add(Uint8List.sublistView(pcm, offset, end));
      offset = end;
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    if (!_controller.isClosed) await _controller.close();
  }

  /// Minimal RIFF walk: assumes PCM s16 mono 16k (all fixtures we control).
  static Uint8List _parseWavPcm16(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    if (view.lengthInBytes < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('not a RIFF/WAVE file');
    }
    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = view.getUint32(pos + 4, Endian.little);
      if (id == 'data') {
        return Uint8List.sublistView(bytes, pos + 8, pos + 8 + size);
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('no data chunk in wav');
  }
}
