import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';

/// Whether the equalizer's "Mono audio" effect is on.
///
/// Stored in the key-value store like the other single audio toggles: it is a
/// session-independent preference, and the audio filter chain composes it with
/// the equalizer, normalization and stereo widening.
class MonoAudioNotifier extends Notifier<bool> {
  @override
  bool build() => KVStoreService.monoAudio;

  Future<void> setEnabled(bool value) async {
    state = value;
    await KVStoreService.setMonoAudio(value);
  }
}

final monoAudioProvider =
    NotifierProvider<MonoAudioNotifier, bool>(MonoAudioNotifier.new);
