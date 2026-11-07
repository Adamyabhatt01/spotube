import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/utils/platform.dart';

/// Wraps a host item with every way to open its context menu.
///
/// Desktop: right-click at the pointer. Touch: long-press opens the compact
/// sheet. Keyboard: Shift+F10 or the dedicated context-menu key opens at the
/// item's centre. The menu is built on open, never during `build`, and focus
/// returns to the item after any dismissal.
class ContextMenuRegion extends StatefulWidget {
  final ContextMenuItemContext item;

  /// Built on open, never during `build` — so a row in a 10,000-track list
  /// holds no provider subscription just because a menu exists.
  final ContextMenuBuilder Function(BuildContext context) builderFor;
  final Widget child;
  final Future<void> Function(
    BuildContext context,
    ProviderContainer container,
    ContextMenuAction action,
  ) onSelected;
  final bool enabled;

  /// Optional confirmation for destructive rows. When null the host callback
  /// owns confirmation (as the playlist delete path already does).
  final Future<bool> Function(ContextMenuAction action)? confirmDestructive;

  /// Defaults to [kIsMobile]. Exposed for widget tests.
  final bool? longPressEnabled;

  const ContextMenuRegion({
    super.key,
    required this.item,
    required this.builderFor,
    required this.child,
    required this.onSelected,
    this.enabled = true,
    this.confirmDestructive,
    this.longPressEnabled,
  });

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  /// The one context menu allowed to be open at a time. Each region only
  /// knows its own overlay, so without this a right-click on item B leaves
  /// item A's menu floating next to it.
  static OverlayCompleter<dynamic>? _openMenu;

  final FocusNode _focusNode = FocusNode(debugLabel: 'context-menu-item');
  OverlayCompleter<dynamic>? _overlay;
  final Map<String, ContextMenuAction> _byId = {};
  bool _showIcons = true;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissOverlay() {
    final overlay = _overlay;
    _overlay = null;
    if (overlay != null && !overlay.isCompleted) overlay.remove();
  }

  List<ContextMenuAction> _build() {
    final builder = widget.builderFor(context);
    _showIcons = builder.config.forTarget(widget.item.target).showIcons;
    final actions = builder.build(
      ContextMenuItemContext(
        target: widget.item.target,
        item: widget.item.item,
        flags: {...widget.item.flags, ...builder.itemFlags},
      ),
    );
    _byId
      ..clear()
      ..addEntries(
          _flatten(actions).map((action) => MapEntry(action.id, action)));
    return actions;
  }

  Iterable<ContextMenuAction> _flatten(List<ContextMenuAction> actions) sync* {
    for (final action in actions) {
      yield action;
      yield* _flatten(action.children);
    }
  }

  Future<void> _select(String id) async {
    final action = _byId[id];
    if (action == null) return;
    if (action.destructive && widget.confirmDestructive != null) {
      final confirmed = await widget.confirmDestructive!(action);
      if (!confirmed) return;
      if (!mounted) return;
    }
    await widget.onSelected(
      context,
      ProviderScope.containerOf(context, listen: false),
      action,
    );
  }

  void _openAt(Offset position) {
    if (!widget.enabled) return;
    final actions = _build();
    if (actions.isEmpty) return;
    _dismissOverlay();
    final previous = _openMenu;
    if (previous != null && previous != _overlay && !previous.isCompleted) {
      previous.remove();
    }

    final size = MediaQuery.sizeOf(context);
    final clamped = Offset(
      position.dx.clamp(8.0, size.width - 8.0),
      position.dy.clamp(8.0, size.height - 8.0),
    );

    _overlay = showAdaptiveMenuDropdown<String>(
      context: context,
      position: clamped + const Offset(4, 4),
      items: (_) => _adaptiveItems(actions),
      onSelected: (id) => unawaited(_select(id)),
      follow: false,
      alignment: Alignment.topLeft,
    );
    _openMenu = _overlay;
    unawaited(
      _overlay!.future.whenComplete(() {
        if (_openMenu == _overlay) _openMenu = null;
        _overlay = null;
        if (mounted) _focusNode.requestFocus();
      }),
    );
  }

  void _openAtCentre() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _openAt(box.localToGlobal(box.size.center(Offset.zero)));
  }

  void _openSheet() {
    if (!widget.enabled) return;
    final actions = _build();
    if (actions.isEmpty) return;
    _dismissOverlay();
    HapticFeedback.mediumImpact();
    unawaited(
      openAdaptiveMenuSheet<String>(
        context: context,
        items: (_) => _sheetItems(actions),
        onSelected: (id) => unawaited(_select(id)),
      ).whenComplete(() {
        if (mounted) _focusNode.requestFocus();
      }),
    );
  }

  /// Sheet rows cannot nest, so a submenu is flattened with its children's
  /// labels standing on their own.
  List<AdaptiveMenuButton<String>> _sheetItems(
    List<ContextMenuAction> actions,
  ) {
    final result = <AdaptiveMenuButton<String>>[];
    for (final action in actions) {
      if (action.children.isEmpty) {
        result.add(_adaptiveButton(action));
      } else {
        result.add(
          AdaptiveMenuButton<String>(
            enabled: false,
            child: Text(action.label),
          ),
        );
        for (final child in action.children) {
          result.add(_adaptiveButton(child));
        }
      }
    }
    return result;
  }

  List<AdaptiveMenuButton<String>> _adaptiveItems(
    List<ContextMenuAction> actions,
  ) {
    return [for (final action in actions) _adaptiveButton(action)];
  }

  AdaptiveMenuButton<String> _adaptiveButton(ContextMenuAction action) {
    final icon = contextMenuIcon(action.icon);
    final showIcon = _showIcons && icon != null;
    Widget? leading;
    if (action.checked != null) {
      leading = action.checked == true
          ? const Icon(RadixIcons.check, size: 16)
          : const SizedBox(width: 16, height: 16);
    } else if (showIcon) {
      leading = Icon(icon, size: 16);
    }

    return AdaptiveMenuButton<String>(
      value: action.children.isEmpty ? action.id : null,
      enabled: action.enabled,
      leading: leading,
      onPressed: action.children.isEmpty ? null : (_) {},
      subMenu: action.children.isEmpty
          ? null
          : [for (final child in action.children) _menuButton(child)],
      child: Text(
        action.label,
        style: action.destructive
            ? TextStyle(color: Theme.of(context).colorScheme.destructive)
            : null,
      ),
    );
  }

  MenuButton _menuButton(ContextMenuAction action) {
    final icon = contextMenuIcon(action.icon);
    final showIcon = _showIcons && icon != null;
    Widget? leading;
    if (action.checked != null) {
      leading = action.checked == true
          ? const Icon(RadixIcons.check, size: 16)
          : const SizedBox(width: 16, height: 16);
    } else if (showIcon) {
      leading = Icon(icon, size: 16);
    }

    return MenuButton(
      enabled: action.enabled,
      leading: leading,
      onPressed: (menuContext) {
        unawaited(_select(action.id));
        closeOverlay(menuContext);
      },
      child: Text(
        action.label,
        style: action.destructive
            ? TextStyle(color: Theme.of(context).colorScheme.destructive)
            : null,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isContextKey = event.logicalKey == LogicalKeyboardKey.contextMenu;
    final isShiftF10 = event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!isContextKey && !isShiftF10) return KeyEventResult.ignored;
    _openAtCentre();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final longPressEnabled =
        widget.enabled && (widget.longPressEnabled ?? kIsMobile);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: widget.enabled
            ? (details) => _openAt(details.globalPosition)
            : null,
        onLongPressStart: longPressEnabled ? (_) => _openSheet() : null,
        child: widget.child,
      ),
    );
  }
}
