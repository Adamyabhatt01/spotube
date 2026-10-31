import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

class VolumeProvider extends Notifier<double> {
  VolumeProvider();

  /// The last audible level, so [setMuted] can restore it. Muting drives the
  /// output to silence without overwriting the stored preference: a restart
  /// always comes back at the saved volume, never at zero.
  double _lastAudible = KVStoreService.volume;

  @override
  build() {
    ref.read(audioPlayerPortProvider).setVolume(KVStoreService.volume);
    return KVStoreService.volume;
  }

  Future<void> setVolume(double volume) async {
    if (volume > 0) _lastAudible = volume;
    state = volume;
    await ref.read(audioPlayerPortProvider).setVolume(volume);
    KVStoreService.setVolume(volume);
  }

  /// Silences or restores the output as runtime state only. The persisted
  /// volume keeps the user's level, so unmuting returns to where they were and
  /// a relaunch never inherits a muted state.
  Future<void> setMuted(bool muted) async {
    if (muted) {
      if (state > 0) _lastAudible = state;
      state = 0;
      await ref.read(audioPlayerPortProvider).setVolume(0);
    } else {
      final target = _lastAudible > 0 ? _lastAudible : KVStoreService.volume;
      state = target;
      await ref.read(audioPlayerPortProvider).setVolume(target);
    }
  }
}

final volumeProvider =
    NotifierProvider<VolumeProvider, double>(() => VolumeProvider());
