/// Throttle gate for per-tick position consumers (SMTC, MediaSession,
/// glance widget): the native position stream fires ~5/sec, but these
/// sinks only need whole-second granularity.
///
/// Contract (all covered by tests):
/// - same track + same second → suppress;
/// - same track + new second → emit;
/// - new track (or first tick) + same second → emit, so the first update
///   after a track change / playback start is never swallowed by a
///   coinciding second value;
/// - terminal/completion states bypass this gate entirely (separate
///   handlers) and are never throttled.
///
/// Second-based (not wall-clock): immune to NTP/suspend jumps.
class PositionTickGate {
  String? _lastTrackId;
  int _lastSecond = -1;

  bool shouldEmit({
    required String? trackId,
    required Duration position,
  }) {
    final second = position.inSeconds;
    if (trackId != _lastTrackId || second != _lastSecond) {
      _lastTrackId = trackId;
      _lastSecond = second;
      return true;
    }
    return false;
  }

  /// Forgets history (e.g. on seek discontinuities handled elsewhere).
  void reset() {
    _lastTrackId = null;
    _lastSecond = -1;
  }
}
