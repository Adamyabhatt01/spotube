import 'dart:async';

/// Trailing-edge, latest-wins debouncer for persistence writes.
///
/// Collapses a burst of rapid successive calls into a single execution
/// carrying the most recent [action]. Used for flap-prone player flags
/// (playing/loop/shuffle) where each raw event would otherwise trigger an
/// immediate Drift UPDATE plus a full state rebuild.
///
/// UI state must still update synchronously at the call site — only the
/// persistence side goes through here. Call [flush] on owner dispose so the
/// latest value is never lost if the owner dies mid-debounce.
class DebouncedWriter {
  DebouncedWriter([
    this.delay = const Duration(milliseconds: 400),
    this.onError,
  ]);

  final Duration delay;

  /// Invoked if a debounced/flushed action throws, so persistence failures
  /// never become unhandled async errors. Defaults to rethrowing into the
  /// zone when absent (pass an explicit handler at schedule sites that can
  /// fail, e.g. database writes).
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  Future<void> Function()? _pending;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stack) {
      if (onError != null) {
        onError!(e, stack);
      } else {
        Zone.current.handleUncaughtError(e, stack);
      }
    }
  }

  /// Schedule [action], replacing any still-pending one.
  void call(Future<void> Function() action) {
    _pending = action;
    _timer?.cancel();
    _timer = Timer(delay, () async {
      final action = _pending;
      _pending = null;
      _timer = null;
      if (action != null) await _run(action);
    });
  }

  /// Run the pending action immediately, if any.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final action = _pending;
    _pending = null;
    if (action != null) await _run(action);
  }

  /// Drop the pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  bool get hasPending => _pending != null;
}
