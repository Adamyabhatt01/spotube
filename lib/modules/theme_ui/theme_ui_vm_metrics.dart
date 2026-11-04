import 'package:flutter/foundation.dart';

/// Debug-only counters for the two theme VM entry points.
///
/// The contract forbids a `getUi()` or `onUiAction()` call from `build`: both
/// are plugin round-trips, and `getUi()` may construct a whole document. A
/// provider can look correct and still re-run when a watched dependency
/// changes, so these counters make the claim observable at runtime — open the
/// binding overlay, interact, and watch them. They are compile-time disabled
/// in profile/release builds, where the counter overhead has no user value.
class ThemeUiVmMetrics {
  ThemeUiVmMetrics._();

  /// How many times the active theme's `getUi()` has been invoked.
  static int getUiCalls = 0;

  /// How many times the active theme's `onUiAction()` has been invoked.
  static int onUiActionCalls = 0;

  static void recordGetUi() {
    if (kDebugMode) getUiCalls++;
  }

  static void recordOnUiAction() {
    if (kDebugMode) onUiActionCalls++;
  }

  static String get summary =>
      'getUi $getUiCalls · onUiAction $onUiActionCalls';

  @visibleForTesting
  static void reset() {
    getUiCalls = 0;
    onUiActionCalls = 0;
  }
}
