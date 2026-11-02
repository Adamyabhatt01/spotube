import 'package:flutter/foundation.dart';

import 'package:spotube/modules/context_menu/context_menu_target.dart';

/// Per-target user configuration for a context menu.
///
/// Host actions can be hidden and reordered, never redefined. A theme action
/// is appended by default and obeys the same knobs. The model is immutable so
/// the provider can publish a new value without mutating the old one.
@immutable
class ContextMenuTargetConfig {
  /// Explicit reorder. Ids absent here keep their host default position.
  final List<String> order;

  /// Ids the user removed from the menu.
  final Set<String> hidden;

  /// Pin targets hidden from the "Pin to…" submenu. Existing pins stay.
  final Set<String> hiddenPinTargets;

  final bool showIcons;
  final bool confirmDestructive;

  const ContextMenuTargetConfig({
    this.order = const [],
    this.hidden = const {},
    this.hiddenPinTargets = const {},
    this.showIcons = true,
    this.confirmDestructive = true,
  });

  static const defaults = ContextMenuTargetConfig();

  ContextMenuTargetConfig copyWith({
    List<String>? order,
    Set<String>? hidden,
    Set<String>? hiddenPinTargets,
    bool? showIcons,
    bool? confirmDestructive,
  }) {
    return ContextMenuTargetConfig(
      order: order ?? this.order,
      hidden: hidden ?? this.hidden,
      hiddenPinTargets: hiddenPinTargets ?? this.hiddenPinTargets,
      showIcons: showIcons ?? this.showIcons,
      confirmDestructive: confirmDestructive ?? this.confirmDestructive,
    );
  }

  Map<String, dynamic> toJson() => {
        if (order.isNotEmpty) 'order': order,
        if (hidden.isNotEmpty) 'hidden': hidden.toList(),
        if (hiddenPinTargets.isNotEmpty)
          'hiddenPinTargets': hiddenPinTargets.toList(),
        if (!showIcons) 'showIcons': false,
        if (!confirmDestructive) 'confirmDestructive': false,
      };

  bool get isDefault => toJson().isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContextMenuTargetConfig &&
        listEquals(order, other.order) &&
        setEquals(hidden, other.hidden) &&
        setEquals(hiddenPinTargets, other.hiddenPinTargets) &&
        showIcons == other.showIcons &&
        confirmDestructive == other.confirmDestructive;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(order),
        Object.hashAll(hidden),
        Object.hashAll(hiddenPinTargets),
        showIcons,
        confirmDestructive,
      );

  factory ContextMenuTargetConfig.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final json = raw.cast<String, dynamic>();

    List<String> strings(Object? value, {int max = 64}) {
      if (value is! List) return const [];
      final result = <String>[];
      for (final entry in value) {
        if (entry is String && entry.isNotEmpty && entry.length <= 64) {
          result.add(entry);
        }
        if (result.length >= max) break;
      }
      return List.unmodifiable(result);
    }

    final showIcons = json['showIcons'];
    final confirmDestructive = json['confirmDestructive'];

    return ContextMenuTargetConfig(
      order: strings(json['order']),
      hidden: strings(json['hidden']).toSet(),
      hiddenPinTargets: strings(json['hiddenPinTargets'], max: 16).toSet(),
      showIcons: showIcons is bool ? showIcons : true,
      confirmDestructive:
          confirmDestructive is bool ? confirmDestructive : true,
    );
  }
}

/// The whole stored context-menu configuration, keyed by target id.
@immutable
class ContextMenuConfig {
  final Map<String, ContextMenuTargetConfig> targets;

  const ContextMenuConfig({this.targets = const {}});

  static const defaults = ContextMenuConfig();

  ContextMenuTargetConfig forTarget(ContextMenuTarget target) =>
      targets[target.id] ?? ContextMenuTargetConfig.defaults;

  ContextMenuConfig withTarget(
    ContextMenuTarget target,
    ContextMenuTargetConfig config,
  ) {
    final next = Map<String, ContextMenuTargetConfig>.of(targets);
    if (config.isDefault) {
      next.remove(target.id);
    } else {
      next[target.id] = config;
    }
    return ContextMenuConfig(targets: Map.unmodifiable(next));
  }

  ContextMenuConfig resetTarget(ContextMenuTarget target) =>
      withTarget(target, ContextMenuTargetConfig.defaults);

  Map<String, dynamic> toJson() => {
        for (final entry in targets.entries) entry.key: entry.value.toJson(),
      };

  factory ContextMenuConfig.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final targets = <String, ContextMenuTargetConfig>{};
    for (final entry in raw.entries) {
      final target = ContextMenuTarget.fromId(entry.key);
      if (target == null) continue;
      targets[target.id] = ContextMenuTargetConfig.fromJson(entry.value);
    }
    return ContextMenuConfig(targets: Map.unmodifiable(targets));
  }
}
