/// Decides *when* a playback widget push is worth its platform-channel cost.
///
/// A home-screen widget is by definition only visible while the app is not in
/// the foreground, but playback state changes every second, so pushing on every
/// change spends two channel round trips per second for the whole session on
/// updates nobody can see. Foreground requests are folded into one push that
/// fires on the way out instead.
class ForegroundCoalescer {
  ForegroundCoalescer({required this.push, required this.isForeground});

  final Future<void> Function() push;
  final bool Function() isForeground;

  bool _pending = false;
  bool _flushing = false;

  Future<void> request() async {
    if (isForeground()) {
      _pending = true;
      return;
    }
    await flush();
  }

  /// Report the lifecycle transition before the state that triggered it becomes
  /// visible to [request], so a background-driven push is not also coalesced.
  Future<void> onForegroundChanged(bool foreground) async {
    if (foreground) return;
    if (!_pending) return;
    _pending = false;
    await flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await push();
    } finally {
      _flushing = false;
    }
  }
}
