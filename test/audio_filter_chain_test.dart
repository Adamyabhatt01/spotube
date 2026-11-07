import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/services/audio_player/audio_filter_chain.dart';

void main() {
  EqualizerSettings eq({bool enabled = true, List<double> gains = const []}) {
    return EqualizerSettings(
      enabled: enabled,
      gains: gains.isEmpty ? const [6, 5, 4, 2, 0, 0, 0, 0, 0, 0] : gains,
    );
  }

  String chain({
    bool normalize = false,
    bool spatial = false,
    bool mono = false,
    bool dynaudnormSupported = true,
    bool spatialSupported = true,
    bool monoSupported = true,
    bool eqEnabled = true,
  }) {
    return buildAudioFilterChain(
      equalizer: eq(enabled: eqEnabled),
      normalizeAudio: normalize,
      spatialAudio: spatial,
      monoAudio: mono,
      dynaudnormSupported: dynaudnormSupported,
      spatialAudioSupported: spatialSupported,
      monoAudioSupported: monoSupported,
    );
  }

  test('omits flat bands and keeps only shaped ones', () {
    final result = chain();
    expect(result.split(',').where((f) => f.startsWith('equalizer=')),
        hasLength(4));
    expect(result, isNot(contains('g=0')));
  });

  test('appends stereo widening before normalization', () {
    final result = chain(spatial: true, normalize: true);
    expect(result, contains('extrastereo=m=2.5'));
    expect(
      result.indexOf('extrastereo') < result.indexOf('dynaudnorm'),
      isTrue,
    );
  });

  test('appends the mono downmix after the stereo effects', () {
    final result = chain(spatial: true, normalize: true, mono: true);
    // mpv reads the text after `=` as an option list, so `pan` only parses
    // inside a bracketed lavfi graph.
    expect(result, contains('lavfi=[pan=mono|c0=0.5*c0+0.5*c1]'));
    expect(result, isNot(contains(',pan=')));
    expect(
      result.indexOf('extrastereo') < result.indexOf('lavfi=[pan=mono'),
      isTrue,
    );
    expect(
      result.indexOf('dynaudnorm') < result.indexOf('lavfi=[pan=mono'),
      isTrue,
    );
  });

  test('never references filters the build does not have', () {
    final result = chain(
      spatial: true,
      normalize: true,
      mono: true,
      dynaudnormSupported: false,
      spatialSupported: false,
      monoSupported: false,
    );
    expect(result, isNot(contains('extrastereo')));
    expect(result, isNot(contains('dynaudnorm')));
    expect(result, isNot(contains('pan=mono')));
  });

  test('bypassed equalizer leaves an empty chain without other effects', () {
    expect(chain(eqEnabled: false), isEmpty);
  });
}
