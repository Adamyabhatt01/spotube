import 'package:spotube/models/equalizer/equalizer.dart';

/// Builds the mpv `af` chain for the current effects.
///
/// mpv has one `af` slot, so every filter the app uses has to be composed here;
/// writing a chain from two places silently removes the other filter. Bands at
/// 0 dB are omitted, stereo widening sits after the EQ so it widens the shaped
/// signal, normalization follows it, and the mono downmix is appended last so
/// it sums the final stereo output.
///
/// [dynaudnormSupported], [spatialAudioSupported] and [monoAudioSupported] are
/// false on builds whose libmpv lacks the corresponding FFmpeg filter (the
/// bundled Android and Windows builds). Referencing a filter the build does not
/// have fails the whole chain and can take audio down with it, so callers must
/// pass the platform capability.
String buildAudioFilterChain({
  required EqualizerSettings equalizer,
  required bool normalizeAudio,
  required bool spatialAudio,
  required bool monoAudio,
  required bool dynaudnormSupported,
  required bool spatialAudioSupported,
  required bool monoAudioSupported,
}) {
  final filters = <String>[];

  if (equalizer.enabled) {
    final gains = equalizer.normalizedGains;
    for (var i = 0; i < kEqualizerBandCount; i++) {
      final gain = gains[i];
      if (gain == 0) continue;
      filters.add(
        'equalizer=f=${kEqualizerFrequencyTokens[i]}'
        ':width_type=o:width=1:g=${_gainToken(gain)}',
      );
    }
  }

  if (spatialAudio && spatialAudioSupported) {
    // Widen the stereo image without changing the mono centre. 2.5 is the
    // filter's default; anything above 3 starts to hollow out vocals.
    filters.add('extrastereo=m=2.5');
  }

  if (normalizeAudio && dynaudnormSupported) {
    filters.add('dynaudnorm=g=5:f=250:r=0.9:p=0.5');
  }

  if (monoAudio && monoAudioSupported) {
    // Downmix after the stereo effects: the pan filter has to see the final
    // stereo image, not the untouched input.
    //
    // `pan` must go through mpv's `lavfi` wrapper. mpv hands the text after
    // `=` to libavfilter as an option list, so a bare `pan=mono|c0=...` is
    // read as an option named `mono|c0` and the graph build fails with
    // "Audio filter initialized failed!". The bracketed graph is passed
    // through verbatim and parses like it does on the ffmpeg command line.
    filters.add('lavfi=[pan=mono|c0=0.5*c0+0.5*c1]');
  }

  return filters.join(',');
}

String _gainToken(double gain) {
  return gain == gain.roundToDouble()
      ? gain.toInt().toString()
      : gain.toStringAsFixed(1);
}
