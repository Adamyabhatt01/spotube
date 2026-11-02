import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_defaults.dart';

/// Resolves a host l10n key, with optional interpolation values.
typedef ContextMenuLabeler = String Function(
  String key, [
  Map<String, String>? args,
]);

/// Merges the host defaults, the theme's `ui.menus` additions and the user's
/// configuration into the rows a surface actually shows.
///
/// The builder is pure: it takes the config, the theme's pin targets and the
/// theme's declared capabilities, and returns descriptors. The widget that
/// owns the item supplies the callback table. That split is what keeps every
/// host surface on one defaults table without teaching this module about
/// playlists, tracks or downloads.
class ContextMenuBuilder {
  final ContextMenuConfig config;
  final List<ThemePinTarget> pinTargets;
  final Set<String> capabilities;
  final Map<String, List<Map<String, dynamic>>> themeMenus;
  final ContextMenuLabeler label;

  /// Host action ids the owning surface can actually run. Null means every
  /// default row is available. Theme actions are never filtered by this: the
  /// host does not know what a theme's action needs.
  final Set<String>? availableActions;

  /// Item state the surface publishes for `when` evaluation and label swaps
  /// (`owner`, `playing`, `pinnedTargets`, ...). Resolved when the menu opens,
  /// so the builder — not the widget — carries it.
  final Map<String, Object?> itemFlags;

  const ContextMenuBuilder({
    required this.label,
    this.config = ContextMenuConfig.defaults,
    this.pinTargets = const [],
    this.capabilities = const {},
    this.themeMenus = const {},
    this.availableActions,
    this.itemFlags = const {},
  });

  static const maxItems = 32;
  static const maxDepth = 2;

  /// Builds the menu for [target]'s rows merged over [itemFlags].
  ///
  /// [evaluateWhen] is false for the settings preview, where an owner-only or
  /// pinned-only row must still be configurable. [enforceCapabilities] is
  /// false for the same preview: the settings list shows what the theme
  /// declared, not what the current document happens to grant.
  List<ContextMenuAction> build(
    ContextMenuItemContext item, {
    bool evaluateWhen = true,
    bool enforceCapabilities = true,
    bool includeHidden = false,
  }) {
    final targetConfig = config.forTarget(item.target);
    final hidden = targetConfig.hidden;
    final pinnedTargets = _pinnedTargets(item);
    final targets = _effectivePinTargets(targetConfig);

    final actions = <ContextMenuAction>[];

    for (final template in contextMenuDefaults[item.target] ?? const []) {
      if (availableActions != null &&
          !availableActions!.contains(template.id)) {
        continue;
      }
      if (evaluateWhen && !evaluateContextMenuWhen(template.when, item)) {
        continue;
      }

      if (template.id == 'pin' || template.id == 'unpin') {
        final pin = _pinAction(
          template,
          targets,
          pinnedTargets,
          singleTarget: targets.length == 1,
          showUnpin: template.id == 'unpin',
        );
        if (pin == null) continue;
        // A single target resolves to `pin:<target>`; the settings list stores
        // that id, while the template ids stay `pin`/`unpin`. Accept all three
        // so hiding the row in settings also hides it in the live menu.
        if (hidden.contains(template.id) ||
            hidden.contains('pin') ||
            hidden.contains('unpin') ||
            hidden.contains(pin.id)) {
          continue;
        }
        actions.add(pin);
        continue;
      }

      actions.add(
        ContextMenuAction(
          id: template.id,
          label: label(_labelKeyFor(template, item), template.labelArgs),
          icon: _iconFor(template, item),
          destructive: template.destructive,
          submenu: template.submenu,
          when: template.when,
        ),
      );
    }

    // Theme actions append by default; the user can hide or reorder them like
    // any host row. Duplicate ids are a validator error, but an installed
    // plugin may bypass validation, so the host drops the later copy rather
    // than rendering two rows the user's config cannot tell apart.
    final themeIds = <String>{};
    for (final raw
        in themeMenus[item.target.id] ?? const <Map<String, dynamic>>[]) {
      final action = parseThemeMenuAction(raw);
      if (action == null) continue;
      if (!themeIds.add(action.id)) continue;
      if (evaluateWhen && !evaluateContextMenuWhen(action.when, item)) {
        continue;
      }
      if (enforceCapabilities &&
          action.capability != null &&
          !capabilities.contains(action.capability)) {
        continue;
      }
      actions.add(action);
    }

    final visible = [
      for (final action in actions)
        if (includeHidden || !hidden.contains(action.id)) action,
    ];

    final ordered = _applyOrder(visible, targetConfig.order);
    return ordered.take(maxItems).toList(growable: false);
  }

  List<ThemePinTarget> _effectivePinTargets(
    ContextMenuTargetConfig targetConfig,
  ) {
    final declared = pinTargets.isEmpty
        ? [ThemePinTarget(id: 'sidebar', label: label('sidebar'))]
        : pinTargets;
    return [
      for (final target in declared)
        if (!targetConfig.hiddenPinTargets.contains(target.id)) target,
    ];
  }

  Set<String> _pinnedTargets(ContextMenuItemContext item) {
    final raw = item.flags['pinnedTargets'];
    if (raw is Iterable) {
      return {
        for (final value in raw)
          if (value is String) value,
      };
    }
    return const {};
  }

  /// A single target toggles in place; several become a checkable submenu.
  ContextMenuAction? _pinAction(ContextMenuActionTemplate template,
      List<ThemePinTarget> targets, Set<String> pinned,
      {required bool singleTarget, required bool showUnpin}) {
    if (targets.isEmpty) return null;

    if (singleTarget) {
      final target = targets.single;
      final isPinned = pinned.contains(target.id);
      if (showUnpin != isPinned) return null;
      return ContextMenuAction(
        id: 'pin:${target.id}',
        label: label(
          isPinned ? 'unpin_from' : 'pin_to',
          {'target': target.label},
        ),
        icon: isPinned ? 'unpin' : 'pin',
        when: template.when,
      );
    }

    // Multiple targets: one "Pin to…" submenu, each row checked independently.
    if (showUnpin) return null;
    final children = <ContextMenuAction>[
      for (final target in targets.take(maxItems - 1))
        ContextMenuAction(
          id: 'pin:${target.id}',
          label: label(
            pinned.contains(target.id) ? 'unpin_from' : 'pin_to',
            {'target': target.label},
          ),
          icon: pinned.contains(target.id) ? 'unpin' : 'pin',
          checked: pinned.contains(target.id),
        ),
    ];
    if (children.isEmpty) return null;

    return ContextMenuAction(
      id: 'pin',
      label: label('pin_to_ellipsis'),
      icon: 'pin',
      submenu: ContextMenuSubmenu.pinTargets,
      children: children,
      when: template.when,
    );
  }

  /// Target/state-sensitive label key for a default row.
  ///
  /// The defaults table is static, but a `play` row reads as `Pause` while
  /// audio is sounding; [ContextMenuActionTemplate.labelKeys] carries that.
  static String _labelKeyFor(
    ContextMenuActionTemplate template,
    ContextMenuItemContext item,
  ) {
    for (final entry in template.labelKeys.entries) {
      if (item.flag(entry.key)) return entry.value;
    }
    return template.labelKey;
  }

  static String? _iconFor(
    ContextMenuActionTemplate template,
    ContextMenuItemContext item,
  ) {
    for (final entry in template.iconKeys.entries) {
      if (item.flag(entry.key)) return entry.value;
    }
    return template.icon;
  }

  /// Applies explicit user order without disturbing unlisted rows.
  ///
  /// Each id in [order] is moved to its listed index; ids the user never
  /// touched keep their host default position. A new host action therefore
  /// appears where the host put it, and an unknown id is ignored.
  static List<ContextMenuAction> _applyOrder(
    List<ContextMenuAction> actions,
    List<String> order,
  ) {
    if (order.isEmpty) return actions;
    final result = List<ContextMenuAction>.of(actions);
    for (var index = 0; index < order.length; index++) {
      final id = order[index];
      final current = result.indexWhere((action) => action.id == id);
      if (current == -1) continue;
      final bounded = index.clamp(0, result.length - 1);
      if (current == bounded) continue;
      final action = result.removeAt(current);
      result.insert(bounded, action);
    }
    return result;
  }
}
