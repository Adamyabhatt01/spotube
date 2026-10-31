import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';

/// Requested crossfade length between tracks, in seconds (0 is off).
///
/// The value persists and binds to `audio.crossfade` today; the audible
/// overlap needs a second output a single media_kit player does not have, so
/// no `af` filter is faked for it — the effect lands with a backend that can
/// schedule the next track early.
class CrossfadeNotifier extends Notifier<double> {
  @override
  double build() => KVStoreService.crossfadeDuration;

  Future<void> setSeconds(double seconds) async {
    final clamped = seconds.isFinite ? seconds.clamp(0.0, 15.0) : 0.0;
    state = clamped;
    await KVStoreService.setCrossfadeDuration(clamped);
  }
}

final crossfadeProvider =
    NotifierProvider<CrossfadeNotifier, double>(CrossfadeNotifier.new);
