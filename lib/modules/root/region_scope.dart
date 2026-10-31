import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';

/// Per-region state a shell layout owns: collapsed flags and dragged sizes.
///
/// Both maps are keyed by the region's `storageKey` when it declares one, or
/// its resolved id otherwise. They are seeded lazily from [KVStoreService] at
/// the point of use, so a shell that never touches them pays no synchronous
/// preference reads.

/// Collapsed state, keyed like [RegionState.storageKey].
final regionCollapseProvider = StateProvider<Map<String, bool>>((ref) => {});

/// Dragged sizes in logical pixels, keyed like [RegionState.storageKey].
final regionSizeProvider = StateProvider<Map<String, double>>((ref) => {});

/// The rendered state of one shell region.
///
/// Published through an [InheritedWidget] so a slot rendered inside the region
/// can bind `region.<id>.width`, `.height`, `.collapsed` and `.visible`
/// without the shell having to thread values through every node renderer.
class RegionState {
  final String id;
  final Size size;
  final bool collapsed;
  final bool visible;

  const RegionState({
    required this.id,
    required this.size,
    required this.collapsed,
    required this.visible,
  });

  Map<String, Object?> get bindings => {
        'region.$id.width': size.width,
        'region.$id.height': size.height,
        'region.$id.collapsed': collapsed,
        'region.$id.visible': visible,
      };
}

class RegionScope extends InheritedWidget {
  final RegionState state;

  const RegionScope({required this.state, required super.child, super.key});

  static RegionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RegionScope>();

  static RegionState? stateOf(BuildContext context) => maybeOf(context)?.state;

  @override
  bool updateShouldNotify(RegionScope oldWidget) {
    return oldWidget.state.id != state.id ||
        oldWidget.state.size != state.size ||
        oldWidget.state.collapsed != state.collapsed ||
        oldWidget.state.visible != state.visible;
  }
}

/// The key a region's persisted state lives under.
String regionStorageKey({required String id, String? storageKey}) =>
    storageKey ?? id;

bool storedRegionCollapsed(String key) =>
    KVStoreService.isInitialized && KVStoreService.resizableCollapsed(key);

double storedRegionSize(String key, double fallback) =>
    KVStoreService.isInitialized
        ? KVStoreService.resizableSize(key, fallback)
        : fallback;

double? storedRegionSizeOrNull(String key) =>
    KVStoreService.isInitialized
        ? KVStoreService.resizableSizeOrNull(key)
        : null;

Future<void> persistRegionCollapsed(String key, bool value) async {
  if (!KVStoreService.isInitialized) return;
  await KVStoreService.setResizableCollapsed(key, value);
}

Future<void> persistRegionSize(String key, double value) async {
  if (!KVStoreService.isInitialized) return;
  await KVStoreService.setResizableSize(key, value);
}

Future<void> clearStoredRegionSize(String key) async {
  if (!KVStoreService.isInitialized) return;
  await KVStoreService.clearResizableSize(key);
}
