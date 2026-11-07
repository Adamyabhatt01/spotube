import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/audio_visualizer/audio_spectrum.dart';

Float32List _tone(
  double frequency, {
  double amplitude = 1,
  int length = kAudioSpectrumWindowSize,
}) {
  final samples = Float32List(length);
  for (var i = 0; i < length; i++) {
    samples[i] = amplitude *
        math.sin(2 * math.pi * frequency * i / kAudioSpectrumSampleRate);
  }
  return samples;
}

void main() {
  group('AudioSpectrumAnalyzer', () {
    test('puts a 1 kHz tone in the band that contains 1 kHz', () {
      final analyzer = AudioSpectrumAnalyzer(tiltDbPerBand: 0);
      final bands = analyzer.analyze(_tone(1000));

      var loudest = 0;
      for (var i = 1; i < bands.length; i++) {
        if (bands[i] > bands[loudest]) loudest = i;
      }

      // log(1000 / 40) / log(16000 / 40) * 28 = 15.05
      expect(loudest, inInclusiveRange(14, 16));
      expect(bands[loudest], greaterThan(0.4));
      expect(bands.every((value) => value >= 0 && value <= 1), isTrue);
    });

    test('does not invent bars for silence', () {
      final analyzer = AudioSpectrumAnalyzer();
      final bands = analyzer.analyze(Float32List(kAudioSpectrumWindowSize));

      expect(bands, hasLength(kAudioSpectrumBandCount));
      expect(bands, everyElement(0));
    });

    test('a quiet tone produces a smaller bar than a loud one', () {
      final analyzer = AudioSpectrumAnalyzer(tiltDbPerBand: 0);
      final quiet = analyzer.analyze(_tone(1000, amplitude: 0.02));
      final loud = analyzer.analyze(_tone(1000, amplitude: 0.8));

      expect(loud[15], greaterThan(quiet[15]));
    });
  });
}
