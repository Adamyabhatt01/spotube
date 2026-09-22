import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether any scrollable in the app is moving.
///
/// A `BackdropFilter` re-blurs everything behind it on every frame that that
/// content changes, and on a phone the frames where chrome has something new
/// behind it are almost exactly the frames a list is moving. The frosted look is
/// kept - [chromeBlurFrozen] is what the surfaces read - it just stops being
/// re-blurred mid-flight.
final scrollInFlightProvider =
    NotifierProvider<ScrollInFlight, bool>(ScrollInFlight.new);

class ScrollInFlight extends Notifier<bool> {
  /// Longer than the gap between two frames of a fling and shorter than the
  /// pause a person makes between scrolls, so the blur never flickers back on
  /// while content still moves.
  static const settle = Duration(milliseconds: 400);

  Timer? _settleTimer;

  @override
  bool build() {
    ref.onDispose(() => _settleTimer?.cancel());
    return false;
  }

  /// Restarts the [settle] countdown. Nothing is counted, so nothing can be
  /// left unbalanced: a scrollable destroyed mid-fling simply stops restarting
  /// the timer, and the frost comes back after [settle].
  void markActive() {
    if (!state) state = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, () {
      _settleTimer = null;
      if (state) state = false;
    });
  }
}
