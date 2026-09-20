import 'dart:async';

import 'package:spotube/utils/perf_counters.dart';

/// Whole-second ticks over the player's raw position stream.
///
/// The raw stream fires ~5/sec (libmpv property updates). Everything that
/// only renders second granularity — the progress slider, Discord presence,
/// the media session / SMTC sinks, the glance widget, connect clients — used
/// to subscribe to it independently and each run its own gate, so one playing
/// track cost up to eight dispatch chains. This keeps one upstream
/// subscription and hands out a single broadcast sequence.
///
/// Emission contract:
/// - the first event of each new playback second, at most one per second;
/// - the first event after [invalidate], so a seek or any other position
///   discontinuity is never held back for up to a second;
/// - a track change needs no special case: the incoming track starts near
///   zero, which is a new second, and consumers that render metadata get the
///   change from the player-state and playlist streams they already listen to;
/// - while nothing is listening, [stream] (a broadcast stream) drops events
///   rather than buffering them, so there is no burst on resubscribe.
///
/// Seek-critical consumers (sponsor skip, scrubbing, synced lyrics, the
/// buffering watchdog) must keep using the raw stream.
class PositionTicker {
  PositionTicker(Stream<Duration> raw) {
    _subscription = raw.listen(
      _onPosition,
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast();
  StreamSubscription<Duration>? _subscription;
  int _lastSecond = -1;

  Stream<Duration> get stream => _controller.stream;

  /// Makes the next raw position event pass the gate regardless of second.
  void invalidate() => _lastSecond = -1;

  void _onPosition(Duration position) {
    final second = position.inSeconds;
    if (second == _lastSecond) return;
    _lastSecond = second;
    PerfCounters.note('position.tick');
    _controller.add(position);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}
