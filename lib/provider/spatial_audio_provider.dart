import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';

/// Whether the equalizer's "Virtual surround" effect is on.
///
/// Stored in the key-value store rather than a preferences column: it is a
/// single session-independent audio toggle, and the audio filter chain already
/// composes it with the equalizer and normalization.
class SpatialAudioNotifier extends Notifier<bool> {
  @override
  bool build() => KVStoreService.spatialAudio;

  Future<void> setEnabled(bool value) async {
    state = value;
    await KVStoreService.setSpatialAudio(value);
  }
}

final spatialAudioProvider =
    NotifierProvider<SpatialAudioNotifier, bool>(SpatialAudioNotifier.new);
