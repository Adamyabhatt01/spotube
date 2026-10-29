import 'dart:math' as math;
import 'dart:typed_data';

/// Number of bars the visualizer draws.
const int kAudioSpectrumBandCount = 28;

/// FFT window and hop. At 44.1 kHz the window is ~46 ms and a new frame is
/// produced every ~23 ms, which is smooth enough to look live without making
/// the main isolate work for it.
const int kAudioSpectrumSampleRate = 44100;
const int kAudioSpectrumWindowSize = 2048;
const int kAudioSpectrumHopSize = 1024;

/// Turns mono PCM into log-spaced, smoothed bar heights.
///
/// This is a real spectrum: a Hann-windowed FFT per hop, one peak per
/// log-spaced frequency band, converted to dBFS. There is deliberately no
/// synthetic motion here; silence produces empty bars, so the visualizer can
/// never pretend audio is playing.
class AudioSpectrumAnalyzer {
  AudioSpectrumAnalyzer({
    this.sampleRate = kAudioSpectrumSampleRate,
    this.bandCount = kAudioSpectrumBandCount,
    this.windowSize = kAudioSpectrumWindowSize,
    this.minFrequency = 40,
    this.maxFrequency = 16000,
    this.floorDb = -58,
    this.ceilingDb = -6,
    this.tiltDbPerBand = 0.55,
  }) {
    _window = Float64List(windowSize);
    for (var i = 0; i < windowSize; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (windowSize - 1));
    }
    _real = Float64List(windowSize);
    _imag = Float64List(windowSize);
    _smoothed = List<double>.filled(bandCount, 0);

    final nyquistBin = windowSize ~/ 2;
    final ratio = maxFrequency / minFrequency;
    for (var band = 0; band < bandCount; band++) {
      final low = minFrequency * math.pow(ratio, band / bandCount);
      final high = minFrequency * math.pow(ratio, (band + 1) / bandCount);
      final start = (low * windowSize / sampleRate)
          .floor()
          .clamp(1, nyquistBin - 1)
          .toInt();
      final end = (high * windowSize / sampleRate)
          .ceil()
          .clamp(start + 1, nyquistBin)
          .toInt();
      _binStart.add(start);
      _binEnd.add(end);
    }
  }

  final int sampleRate;
  final int bandCount;
  final int windowSize;
  final double minFrequency;
  final double maxFrequency;
  final double floorDb;
  final double ceilingDb;
  final double tiltDbPerBand;

  late final Float64List _window;
  late final Float64List _real;
  late final Float64List _imag;
  late final List<double> _smoothed;
  final List<int> _binStart = [];
  final List<int> _binEnd = [];

  /// Analyzes [samples] and returns [bandCount] values in `0..1`.
  ///
  /// Attack is fast and release slow, so transients snap and the bars fall
  /// back smoothly instead of flickering between frames.
  List<double> analyze(Float32List samples) {
    final n = windowSize;
    if (samples.length < n) return List<double>.of(_smoothed);

    for (var i = 0; i < n; i++) {
      _real[i] = samples[i] * _window[i];
      _imag[i] = 0;
    }
    _fft();

    for (var band = 0; band < bandCount; band++) {
      var peakPower = 0.0;
      for (var bin = _binStart[band]; bin < _binEnd[band]; bin++) {
        final power = _real[bin] * _real[bin] + _imag[bin] * _imag[bin];
        if (power > peakPower) peakPower = power;
      }

      // 4 / N undoes the FFT's N/2 split (for a real sine) and the Hann
      // window's 0.5 coherent gain, leaving amplitude relative to full scale.
      final amplitude = 4 * math.sqrt(peakPower) / n;
      final db =
          20 * math.log(amplitude + 1e-9) / math.ln10 + tiltDbPerBand * band;
      var target = ((db - floorDb) / (ceilingDb - floorDb)).clamp(0.0, 1.0);
      // A gentle gamma lifts quiet detail without amplifying noise into bars.
      target = math.pow(target, 0.8).toDouble();

      final previous = _smoothed[band];
      _smoothed[band] = target > previous
          ? previous + (target - previous) * 0.65
          : previous + (target - previous) * 0.18;
    }

    return List<double>.of(_smoothed);
  }

  void _fft() {
    final n = windowSize;

    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final real = _real[i];
        final imag = _imag[i];
        _real[i] = _real[j];
        _imag[i] = _imag[j];
        _real[j] = real;
        _imag[j] = imag;
      }
    }

    for (var length = 2; length <= n; length <<= 1) {
      final angle = -2 * math.pi / length;
      final stepReal = math.cos(angle);
      final stepImag = math.sin(angle);
      final half = length >> 1;

      for (var start = 0; start < n; start += length) {
        var twiddleReal = 1.0;
        var twiddleImag = 0.0;
        for (var k = 0; k < half; k++) {
          final evenReal = _real[start + k];
          final evenImag = _imag[start + k];
          final oddReal = _real[start + k + half];
          final oddImag = _imag[start + k + half];

          final vReal = oddReal * twiddleReal - oddImag * twiddleImag;
          final vImag = oddReal * twiddleImag + oddImag * twiddleReal;

          _real[start + k] = evenReal + vReal;
          _imag[start + k] = evenImag + vImag;
          _real[start + k + half] = evenReal - vReal;
          _imag[start + k + half] = evenImag - vImag;

          final nextReal = twiddleReal * stepReal - twiddleImag * stepImag;
          twiddleImag = twiddleReal * stepImag + twiddleImag * stepReal;
          twiddleReal = nextReal;
        }
      }
    }
  }
}
