/// Equalizer presets and band definitions.
///
/// The band list is deliberately an FFmpeg peaking-filter multi-band, not the
/// old mpv 10-band `equalizer`: the bundled libmpv builds for Android and
/// Windows compile only FFmpeg's `equalizer` filter, which implements a single
/// peaking band. Ten of those are chained in `audio_filter_chain.dart`.
enum EqualizerPreset {
  flat,
  bassBoost,
  trebleBoost,
  vocal,
  rock,
  electronic,

  /// Set when the user moves an individual band; no preset table applies.
  custom,
}

/// Band center frequencies as FFmpeg filter tokens, low to high.
const List<String> kEqualizerFrequencyTokens = [
  '31.25',
  '62.5',
  '125',
  '250',
  '500',
  '1000',
  '2000',
  '4000',
  '8000',
  '16000',
];

/// Short labels for the band sliders.
const List<String> kEqualizerBandLabels = [
  '31',
  '62',
  '125',
  '250',
  '500',
  '1k',
  '2k',
  '4k',
  '8k',
  '16k',
];

const int kEqualizerBandCount = 10;

const double kEqualizerMinGain = -12;
const double kEqualizerMaxGain = 12;
const double kEqualizerGainStep = 0.5;

/// Gain tables in dB, indexed like [kEqualizerFrequencyTokens].
///
/// [EqualizerPreset.custom] has no table: it keeps whatever gains the user
/// already has.
const Map<EqualizerPreset, List<double>> kEqualizerPresetGains = {
  EqualizerPreset.flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  EqualizerPreset.bassBoost: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  EqualizerPreset.trebleBoost: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6],
  EqualizerPreset.vocal: [-2, -2, -1, 1, 3, 4, 3, 1, 0, 0],
  EqualizerPreset.rock: [5, 4, 3, 1, -1, -1, 0, 2, 3, 4],
  EqualizerPreset.electronic: [5, 4, 1, 0, -2, 1, 0, 2, 4, 5],
};

/// The gains a preset selects, or the current gains for
/// [EqualizerPreset.custom].
List<double> equalizerGainsForPreset(
  EqualizerPreset preset, {
  List<double> current = const [],
}) {
  final table = kEqualizerPresetGains[preset];
  return table == null
      ? EqualizerSettings.normalizeGains(current)
      : List<double>.unmodifiable(table);
}

class EqualizerSettings {
  final bool enabled;
  final EqualizerPreset preset;

  /// Raw persisted gains; may be empty, short, long, or out of range.
  final List<double> gains;

  const EqualizerSettings({
    this.enabled = false,
    this.preset = EqualizerPreset.flat,
    this.gains = const [],
  });

  /// Exactly [kEqualizerBandCount] gains in dB, clamped to ±12 and snapped to
  /// the 0.5 dB step. Missing entries are flat and non-finite values become 0.
  List<double> get normalizedGains => normalizeGains(gains);

  static List<double> normalizeGains(List<double> values) {
    final result = List<double>.filled(kEqualizerBandCount, 0);
    final count = values.length < kEqualizerBandCount
        ? values.length
        : kEqualizerBandCount;
    for (var i = 0; i < count; i++) {
      result[i] = _snap(values[i]);
    }
    return result;
  }

  static double _snap(double value) {
    if (!value.isFinite) return 0;
    final snapped =
        (value / kEqualizerGainStep).roundToDouble() * kEqualizerGainStep;
    return snapped
        .clamp(kEqualizerMinGain, kEqualizerMaxGain)
        .toDouble();
  }
}
