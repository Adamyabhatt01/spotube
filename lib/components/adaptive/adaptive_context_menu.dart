import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:spotube/utils/platform.dart';

/// Wraps [child] with the two pointer gestures that open the same action menu.
///
/// Right-click opens a dropdown at the cursor on every platform; long-press
/// opens the compact bottom sheet only on touch platforms. Taps and scroll
/// drags still reach [child] because the long-press recognizer loses the
/// gesture arena as soon as the pointer moves.
class AdaptiveContextMenu<T> extends StatefulWidget {
  final Widget child;
  final List<AdaptiveMenuButton<T>> Function(BuildContext context) items;
  final ValueChanged<T>? onSelected;
  final bool enabled;

  /// Defaults to [kIsMobile]. Exposed so widget tests can exercise the touch
  /// path on a desktop test host.
  final bool? longPressEnabled;

  const AdaptiveContextMenu({
    super.key,
    required this.child,
    required this.items,
    this.onSelected,
    this.enabled = true,
    this.longPressEnabled,
  });

  @override
  State<AdaptiveContextMenu<T>> createState() => _AdaptiveContextMenuState<T>();
}

class _AdaptiveContextMenuState<T> extends State<AdaptiveContextMenu<T>> {
  OverlayCompleter<dynamic>? _overlay;

  /// Removes the overlay unless the menu already dismissed itself.
  ///
  /// Tapping an entry completes the overlay's future; calling `remove` again
  /// on shadcn's drawer/popover completers asserts "Future already completed".
  void _dismissOverlay() {
    final overlay = _overlay;
    _overlay = null;
    if (overlay != null && !overlay.isCompleted) overlay.remove();
  }

  void _showAt(Offset position) {
    if (!widget.enabled) return;
    _dismissOverlay();
    _overlay = showAdaptiveMenuDropdown<T>(
      context: context,
      // Nudge clear of the cursor so the first row is not under the pointer.
      position: position + const Offset(4, 4),
      items: widget.items,
      onSelected: widget.onSelected,
      // The explicit position is the anchor; shadcn's default would snap the
      // menu back to this widget's render box on every frame.
      follow: false,
      alignment: Alignment.topLeft,
    );
  }

  void _showSheet() {
    if (!widget.enabled) return;
    _dismissOverlay();
    HapticFeedback.mediumImpact();
    openAdaptiveMenuSheet<T>(
      context: context,
      items: widget.items,
      onSelected: widget.onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final longPressEnabled =
        widget.enabled && (widget.longPressEnabled ?? kIsMobile);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown:
          widget.enabled ? (details) => _showAt(details.globalPosition) : null,
      onLongPressStart: longPressEnabled ? (_) => _showSheet() : null,
      child: widget.child,
    );
  }
}
