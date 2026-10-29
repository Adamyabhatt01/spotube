import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/mono_audio_provider.dart';
import 'package:spotube/provider/spatial_audio_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_filter_chain.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

/// The complete mpv `af` chain for the current preferences.
///
/// One provider owns the composition so the equalizer and normalization can
/// never overwrite each other. Radio listens to this too, so both players get
/// the same chain.
final audioFilterChainProvider = Provider<String>((ref) {
  final prefs = ref.watch(userPreferencesProvider);
  return buildAudioFilterChain(
    equalizer: EqualizerSettings(
      enabled: prefs.equalizerEnabled,
      preset: prefs.equalizerPreset,
      gains: prefs.equalizerGains,
    ),
    normalizeAudio: prefs.normalizeAudio,
    spatialAudio: ref.watch(spatialAudioProvider),
    monoAudio: ref.watch(monoAudioProvider),
    dynaudnormSupported: kLibmpvSupportsDynaudnorm,
    spatialAudioSupported: kLibmpvSupportsSpatialAudio,
    monoAudioSupported: kLibmpvSupportsMonoAudio,
  );
});

/// Applies [audioFilterChainProvider] to the music player for the app's
/// lifetime.
///
/// Read once from the app root; without that read the chain would still be
/// derived by radio but never pushed to the music player. Failures are logged
/// rather than thrown: a filter change must never take playback down.
final audioEffectsProvider = Provider<void>((ref) {
  final player = ref.read(audioPlayerPortProvider);

  unawaited(_applyFilters(player, ref.read(audioFilterChainProvider)));

  ref.listen<String>(audioFilterChainProvider, (previous, next) {
    if (previous == next) return;
    unawaited(_applyFilters(player, next));
  });
});

Future<void> _applyFilters(AudioPlayerPort player, String chain) async {
  try {
    await player.setAudioFilterChain(chain);
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'audio filters');
  }
}
