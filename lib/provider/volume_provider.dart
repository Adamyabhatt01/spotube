import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

class VolumeProvider extends Notifier<double> {
  VolumeProvider();

  @override
  build() {
    ref.read(audioPlayerPortProvider).setVolume(KVStoreService.volume);
    return KVStoreService.volume;
  }

  Future<void> setVolume(double volume) async {
    state = volume;
    await ref.read(audioPlayerPortProvider).setVolume(volume);
    KVStoreService.setVolume(volume);
  }
}

final volumeProvider =
    NotifierProvider<VolumeProvider, double>(() => VolumeProvider());
