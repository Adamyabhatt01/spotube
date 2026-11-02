import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

/// Loads the user's context-menu configuration once at startup and persists
/// every edit as one KV JSON string.
///
/// A malformed stored value degrades to defaults; it never blocks the app or
/// loses the menus. Writes are fire-and-forget because the in-memory state is
/// already authoritative for the open menu.
class ContextMenuConfigNotifier extends Notifier<ContextMenuConfig> {
  @override
  ContextMenuConfig build() {
    if (!KVStoreService.isInitialized) return ContextMenuConfig.defaults;
    final raw = KVStoreService.contextMenuConfigJson;
    if (raw == null || raw.isEmpty) return ContextMenuConfig.defaults;
    try {
      return ContextMenuConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      return ContextMenuConfig.defaults;
    }
  }

  void _publish(ContextMenuConfig next) {
    state = next;
    if (!KVStoreService.isInitialized) return;
    if (next.targets.isEmpty) {
      KVStoreService.clearContextMenuConfig();
    } else {
      KVStoreService.setContextMenuConfigJson(jsonEncode(next.toJson()));
    }
  }

  void setTargetConfig(
    ContextMenuTarget target,
    ContextMenuTargetConfig config,
  ) {
    _publish(state.withTarget(target, config));
  }

  void resetTarget(ContextMenuTarget target) {
    _publish(state.resetTarget(target));
  }

  void resetAll() {
    _publish(ContextMenuConfig.defaults);
  }
}

final contextMenuConfigProvider =
    NotifierProvider<ContextMenuConfigNotifier, ContextMenuConfig>(
  ContextMenuConfigNotifier.new,
);

/// One target's configuration, for widgets that only care about their own
/// surface.
final contextMenuTargetConfigProvider =
    Provider.family<ContextMenuTargetConfig, ContextMenuTarget>((ref, target) {
  return ref.watch(contextMenuConfigProvider).forTarget(target);
});
