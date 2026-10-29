import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/audio_visualizer/audio_spectrum_capture.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

enum AudioSpectrumStatus {
  /// The capture process is starting; no frames yet.
  starting,

  /// Real FFT frames are arriving from the system output.
  live,

  /// This platform has no capture path, or `parec` failed to start.
  unavailable,
}

class AudioSpectrumState {
  final AudioSpectrumStatus status;
  final List<double> bands;

  const AudioSpectrumState({
    required this.status,
    this.bands = const [],
  });
}

/// Real-time spectrum of what the system is playing.
///
/// The equalizer page is the only listener, so capture runs only while it is
/// open. Unsupported platforms report [AudioSpectrumStatus.unavailable] and
/// the UI stops there — it never falls back to simulated motion.
final audioSpectrumProvider =
    StreamProvider.autoDispose<AudioSpectrumState>((ref) async* {
  if (kIsTest || !kIsLinux || kIsFlatpak) {
    yield const AudioSpectrumState(
      status: AudioSpectrumStatus.unavailable,
    );
    return;
  }

  final capture = AudioSpectrumCapture();
  ref.onDispose(capture.dispose);

  yield const AudioSpectrumState(status: AudioSpectrumStatus.starting);

  try {
    await capture.start();
    await for (final bands in capture.frames) {
      yield AudioSpectrumState(
        status: AudioSpectrumStatus.live,
        bands: bands,
      );
    }
  } catch (error, stack) {
    AppLogger.reportError(error, stack, 'audio visualizer');
    yield const AudioSpectrumState(
      status: AudioSpectrumStatus.unavailable,
    );
  }
});
