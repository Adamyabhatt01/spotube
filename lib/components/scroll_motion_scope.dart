import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/scroll_motion.dart';
import 'package:spotube/utils/platform.dart';

/// Reports scroll motion from one place.
///
/// [ScrollNotification]s bubble to the app root, so wrapping the routed tree in
/// this lets every list, grid, carousel and sheet report itself without opting
/// in - and lets [ScrollInFlight] be the single answer to "is anything moving".
/// Only installed on mobile, where a frame of scrolling also means a frame of
/// re-blurring everything that moves under the chrome.
class ScrollMotionScope extends ConsumerWidget {
  final Widget child;

  /// The platform gate, stated rather than read, so a test on a machine that is
  /// not a phone can exercise both halves of it.
  final bool? enabled;

  const ScrollMotionScope({
    required this.child,
    this.enabled,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    if (!(enabled ?? kIsMobile)) return child;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Only the notifications that mean movement. [ScrollMetricsNotification]
        // is layout - a window resize, a row inserted above the viewport - and
        // would otherwise cost 400 ms of unblurred chrome for something that
        // never moved past the surface.
        if (notification is! ScrollUpdateNotification &&
            notification is! ScrollStartNotification &&
            notification is! ScrollEndNotification) {
          return false;
        }
        ref.read(scrollInFlightProvider.notifier).markActive();
        // Nothing consumes the notification; it keeps bubbling so that other
        // listeners - the ones on scroll-driven UI - are unaffected.
        return false;
      },
      child: child,
    );
  }
}
