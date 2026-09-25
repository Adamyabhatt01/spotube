import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Reorder groups inside the sidebar. A drop is only accepted within its own
/// group, so library tiles and pinned playlists can never cross lists.
enum SidebarReorderGroup { library, pins }

/// Adapts a box [child] to the surrounding navigation container:
/// `NavigationSidebar` lays out every child as a **sliver** (each wrapped in
/// a `SliverPadding` in a `CustomScrollView`), while `NavigationRail` lays
/// out plain boxes. A bare box child in the sidebar fails sliver protocol at
/// mount time — the same reason `NavigationButton` renders a
/// `SliverToBoxAdapter` there.
Widget _adaptiveNavItem(BuildContext context, Widget child) {
  final navData = Data.maybeOf<NavigationControlData>(context);
  if (navData?.containerType != NavigationContainerType.sidebar) {
    // Rail (or no container): boxes render directly.
    return child;
  }
  return SliverToBoxAdapter(
    child: Data.inherit(
      data: _boxScope(navData!),
      child: child,
    ),
  );
}

/// Re-scopes sidebar container data to a bar container so a nested
/// [NavigationButton] takes its box path instead of rendering a sliver
/// inside drag boxes. Every other field passes through, so label visibility,
/// spacing and padding compute exactly as before. The caller passes the
/// style/alignment the sidebar container would otherwise compute
/// (`ghost`/`secondary` + `centerStart` for labelled rows; nothing for the
/// rail, where the real container data still applies).
NavigationControlData _boxScope(NavigationControlData data) {
  return NavigationControlData(
    containerType: NavigationContainerType.bar,
    parentLabelType: data.parentLabelType,
    parentLabelPosition: data.parentLabelPosition,
    parentLabelSize: data.parentLabelSize,
    parentPadding: data.parentPadding,
    direction: data.direction,
    selectedIndex: data.selectedIndex,
    onSelected: data.onSelected,
    expanded: data.expanded,
    childCount: data.childCount,
    spacing: data.spacing,
    keepCrossAxisSize: data.keepCrossAxisSize,
    keepMainAxisSize: data.keepMainAxisSize,
  );
}

/// A sidebar row draggable across its whole area: on desktop the row grabs
/// the pointer anywhere for an immediate drag (with a grab/grabbing cursor);
/// on touch (which never hovers) a long-press anywhere on the row starts the
/// drag. A short tap keeps the wrapped row's normal action. No dedicated
/// reorder mode and no visible handles — the cursor is the only cue.
///
/// Implements [NavigationBarItem] (non-selectable, like [NavigationButton]) so
/// it sits directly in `NavigationSidebar`/`NavigationRail` children. The
/// visuals come from [row] — a regular [NavigationButton] — so selection
/// styling, tooltips and label marquee are unchanged.
///
/// The desktop drag layer is a transparent overlay (`translucent` hit test),
/// so taps, tooltips and the button's own hover visuals keep working on the
/// real button underneath: a tap with no movement loses the drag arena and
/// reaches the button. Touch scrolling is unaffected because the overlay only
/// exists while hovering, which touch devices never do.
///
/// Drops are directional: the top half of a row inserts before it, the bottom
/// half after it — so the bottom half of the last row reaches the very end.
/// The insertion line previews the side while hovering. Drops resolve through
/// [onAcceptInGroup]; the caller maps them to visible indexes (via
/// `resolveSidebarDrop`) and persists with `moveSidebarEntry`/`moveSidebarPin`.
class SidebarReorderableItem extends StatefulWidget
    implements NavigationBarItem {
  /// Raw id within [group] (library tile id, or playlist id for pins).
  final String id;

  final SidebarReorderGroup group;

  /// The row visuals; taps on it behave exactly as before.
  final NavigationButton row;

  /// Compact drag ghost shown under the pointer while dragging.
  final Widget feedback;

  /// `(draggedId, targetId, after)` — raw ids within [group]; [after] is
  /// true when the pointer was on the row's bottom half at drop time.
  final void Function(String draggedId, String targetId,
      {required bool after}) onAcceptInGroup;

  const SidebarReorderableItem({
    super.key,
    required this.id,
    required this.group,
    required this.row,
    required this.feedback,
    required this.onAcceptInGroup,
  });

  @override
  bool get selectable => false;

  @override
  State<SidebarReorderableItem> createState() => _SidebarReorderableItemState();
}

class _SidebarReorderableItemState extends State<SidebarReorderableItem> {
  bool _hovering = false;
  bool _overlayDragging = false;

  /// Key on the row's [DragTarget], used to resolve its box for directional
  /// drops. (The state's own `context` is composite — `findRenderObject` on
  /// it walks up to the surrounding sliver, not the row.)
  final GlobalKey _targetKey = GlobalKey();

  /// Drag anchor shared across rows: `DragTargetDetails.offset` subtracts the
  /// anchor inside the draggable (`_lastOffset = globalPosition -
  /// dragStartPoint`), so the target recovers the true pointer as
  /// `details.offset + anchor`. The anchor (down position relative to the
  /// source row's box) is recorded below on every press — down events are
  /// always freshly hit-tested, while move/up events reuse the down hit path
  /// (`_pendingHitTestResults`), so per-row move listeners cannot track a
  /// drag across rows. Cleared when the drag ends.
  static Offset? _dragAnchor;

  /// Which side the dragged item currently previews: false = line on top
  /// (insert before), true = line at the bottom (insert after), null = no
  /// compatible drag hovering.
  bool? _dropAfter;

  String get _dragData => '${widget.group.name}|${widget.id}';

  bool _accepts(String data) {
    final parts = data.split('|');
    return parts.length == 2 &&
        parts[0] == widget.group.name &&
        parts[1] != widget.id;
  }

  /// True when the pointer is on this row's bottom half, recovering the true
  /// pointer from the anchor-relative [reportedOffset] (see [_dragAnchor]).
  bool _isLowerHalf(Offset reportedOffset) {
    final anchor = _dragAnchor;
    final box = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchor == null || box == null || !box.hasSize) return false;
    return box.globalToLocal(reportedOffset + anchor).dy >
        box.size.height / 2;
  }

  void _clearAnchor() {
    _dragAnchor = null;
  }

  @override
  Widget build(BuildContext context) {
    final fadedRow = _overlayDragging
        ? Opacity(opacity: 0.35, child: widget.row)
        : widget.row;
    return _adaptiveNavItem(
      context,
      DragTarget<String>(
        key: _targetKey,
        onWillAcceptWithDetails: (details) => _accepts(details.data),
        onMove: (details) {
          if (!_accepts(details.data)) return;
          setState(() {
            _dropAfter = _isLowerHalf(details.offset);
          });
        },
        onLeave: (_) => setState(() => _dropAfter = null),
        onAcceptWithDetails: (details) {
          setState(() => _dropAfter = null);
          widget.onAcceptInGroup(
            details.data.split('|')[1],
            widget.id,
            after: _isLowerHalf(details.offset),
          );
        },
        builder: (context, candidate, rejected) {
          final colorScheme = Theme.of(context).colorScheme;
          final Border? edge = _dropAfter == null
              ? null
              : Border(
                  top: _dropAfter!
                      ? BorderSide.none
                      : BorderSide(width: 2, color: colorScheme.primary),
                  bottom: _dropAfter!
                      ? BorderSide(width: 2, color: colorScheme.primary)
                      : BorderSide.none,
                );
          return MouseRegion(
            cursor: _overlayDragging
                ? SystemMouseCursors.grabbing
                : (_hovering ? SystemMouseCursors.grab : MouseCursor.defer),
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: DecoratedBox(
              decoration: BoxDecoration(border: edge),
              child: LongPressDraggable<String>(
                data: _dragData,
                feedback: widget.feedback,
                // The row stays in place at reduced opacity so the list does
                // not collapse while its item is being moved.
                childWhenDragging: Opacity(opacity: 0.35, child: widget.row),
                onDragEnd: (_) => _clearAnchor(),
                onDraggableCanceled: (_, __) => _clearAnchor(),
                // Down-only anchor tracking for [_dragAnchor]: down events
                // are always freshly hit-tested, so the press position is
                // exact. (Move/up listeners would be useless here — those
                // events reuse the down hit path.) Translucent so taps keep
                // falling through to the button.
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    final box = _targetKey.currentContext?.findRenderObject()
                        as RenderBox?;
                    if (box == null || !box.hasSize) return;
                    _dragAnchor =
                        event.position - box.localToGlobal(Offset.zero);
                  },
                  child: Stack(
                    children: [
                      fadedRow,
                      // Desktop drag layer: covers the whole row but only
                      // exists while hovering, so touch scrolling never sees
                      // it. Translucent hit testing lets taps fall through to
                      // the real button; only a real move claims the drag.
                      if (_hovering)
                        Positioned.fill(
                          child: Draggable<String>(
                            data: _dragData,
                            feedback: widget.feedback,
                            hitTestBehavior: HitTestBehavior.translucent,
                            onDragStarted: () =>
                                setState(() => _overlayDragging = true),
                            onDragEnd: (_) {
                              _clearAnchor();
                              setState(() => _overlayDragging = false);
                            },
                            onDraggableCanceled: (_, __) {
                              _clearAnchor();
                              setState(() => _overlayDragging = false);
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slim drop zone pinned after the last row of a reorder group, so an item
/// can be dropped *below* the final row even without aiming at its bottom
/// half. Invisible until a same-group drag hovers it, when it shows the
/// insertion line.
///
/// Also implements [NavigationBarItem] (non-selectable) for direct use in
/// `NavigationSidebar`/`NavigationRail` children.
class SidebarTrailingDropZone extends StatelessWidget
    implements NavigationBarItem {
  final SidebarReorderGroup group;

  /// Raw ids of the group's visible rows, in order.
  final List<String> visibleIds;

  /// Raw id of the dragged row within [group].
  final void Function(String draggedId) onAccept;

  const SidebarTrailingDropZone({
    super.key,
    required this.group,
    required this.visibleIds,
    required this.onAccept,
  });

  @override
  bool get selectable => false;

  bool _accepts(String data) {
    final parts = data.split('|');
    return parts.length == 2 &&
        parts[0] == group.name &&
        visibleIds.isNotEmpty &&
        visibleIds.contains(parts[1]) &&
        // Already last: nothing to do, so don't even highlight.
        parts[1] != visibleIds.last;
  }

  @override
  Widget build(BuildContext context) {
    return _adaptiveNavItem(
      context,
      DragTarget<String>(
        onWillAcceptWithDetails: (details) => _accepts(details.data),
        onAcceptWithDetails: (details) =>
            onAccept(details.data.split('|')[1]),
        builder: (context, candidate, rejected) {
          if (candidate.isEmpty) return const SizedBox(height: 12);
          final colorScheme = Theme.of(context).colorScheme;
          return SizedBox(
            height: 16,
            child: Center(
              child: Container(
                height: 2,
                color: colorScheme.primary,
              ),
            ),
          );
        },
      ),
    );
  }
}
