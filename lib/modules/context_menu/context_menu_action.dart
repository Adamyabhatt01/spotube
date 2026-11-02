import 'package:flutter/foundation.dart';

import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';

/// A submenu source a host action may declare.
enum ContextMenuSubmenu {
  none,

  /// Built from the theme's `layout.pinTargets` (sidebar when absent).
  pinTargets,

  /// Built from the user's playlists by the host widget that owns the item.
  playlists,
}

/// What a `when` expression and the host callbacks may inspect about the item.
///
/// [flags] is deliberately a flat bag: `item.type` is always the target id,
/// and the host widget supplies the rest (`owner`, `pinned`, `playing`,
/// `downloaded`, ...). A theme cannot reach arbitrary app state through this
/// object, only the values the host chose to publish.
@immutable
class ContextMenuItemContext {
  final ContextMenuTarget target;
  final Object? item;
  final Map<String, Object?> flags;

  const ContextMenuItemContext({
    required this.target,
    this.item,
    this.flags = const {},
  });

  bool flag(String name) => flags[name] == true;

  Object? value(String name) {
    if (name == 'type') return target.id;
    return flags[name];
  }
}

/// One resolved row in a context menu.
///
/// Built on open, never during `build`. [children] is non-empty only for a
/// submenu; the menu renderer caps depth at two (a submenu may not contain
/// another submenu).
@immutable
class ContextMenuAction {
  final String id;
  final String label;
  final String? icon;
  final bool destructive;
  final bool enabled;
  final bool? checked;
  final ContextMenuSubmenu submenu;
  final List<ContextMenuAction> children;

  /// Set for a theme-owned action; the host dispatches it through
  /// [dispatchThemeUiAction] after the same capability checks the validator
  /// applied.
  final ThemeUiAction? themeAction;

  /// Capability a theme action declares. Host actions carry it for the
  /// contract but the host itself is always allowed to run its own verbs.
  final String? capability;

  /// The authored `when` expression, kept for diagnostics.
  final String? when;

  const ContextMenuAction({
    required this.id,
    required this.label,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.checked,
    this.submenu = ContextMenuSubmenu.none,
    this.children = const [],
    this.themeAction,
    this.capability,
    this.when,
  });

  bool get isThemeAction => themeAction != null;

  ContextMenuAction copyWith({
    String? label,
    bool? enabled,
    bool? checked,
    List<ContextMenuAction>? children,
  }) {
    return ContextMenuAction(
      id: id,
      label: label ?? this.label,
      icon: icon,
      destructive: destructive,
      enabled: enabled ?? this.enabled,
      checked: checked ?? this.checked,
      submenu: submenu,
      children: children ?? this.children,
      themeAction: themeAction,
      capability: capability,
      when: when,
    );
  }
}

/// Parses a theme-declared action from `ui.menus.<target>[]`.
///
/// Fail-closed: a missing/unknown action verb, a non-`theme.` id, an
/// over-long label or an oversized submenu drops the entry rather than
/// surfacing a row the host cannot dispatch.
ContextMenuAction? parseThemeMenuAction(Object? raw) {
  if (raw is! Map) return null;
  final item = raw.cast<String, dynamic>();

  final id = item['id'];
  if (id is! String || !id.startsWith('theme.') || id.length > 64) {
    return null;
  }
  final label = item['label'];
  if (label is! String || label.trim().isEmpty || label.length > 80) {
    return null;
  }
  final action = ThemeUiAction.tryParse(item['action']);
  if (action == null) return null;

  final icon = item['icon'];
  final capability = item['capability'];
  final when = item['when'];

  return ContextMenuAction(
    id: id,
    label: label,
    icon: icon is String && icon.length <= 32 ? icon : null,
    destructive: item['destructive'] == true,
    themeAction: action,
    capability:
        capability is String && capability.length <= 48 ? capability : null,
    when: when is String && when.length <= 160 ? when : null,
  );
}

/// Evaluates the narrow `when` grammar the contract publishes.
///
/// Supported forms: `item.<flag>` and `item.<flag> == <string|bool|number>`.
/// Anything else is false, so a typo hides a theme row instead of leaking it
/// into a menu whose host callback cannot run it.
bool evaluateContextMenuWhen(String? expression, ContextMenuItemContext item) {
  if (expression == null) return true;
  final expr = expression.replaceAll(RegExp(r'\s+'), '');
  if (expr.isEmpty) return true;

  final match = RegExp(
    r'^item\.([A-Za-z][A-Za-z0-9_]*)(?:==(.+))?$',
  ).firstMatch(expr);
  if (match == null) return false;

  final name = match.group(1)!;
  final actual = item.value(name);
  final expected = match.group(2);
  if (expected == null) return actual == true;

  final literal = expected;
  if (literal == 'true') return actual == true;
  if (literal == 'false') return actual == false;
  if (literal.startsWith("'") && literal.endsWith("'")) {
    return actual?.toString() == literal.substring(1, literal.length - 1);
  }
  if (literal.startsWith('"') && literal.endsWith('"')) {
    return actual?.toString() == literal.substring(1, literal.length - 1);
  }
  final number = num.tryParse(literal);
  if (number != null) return actual == number;
  return false;
}
