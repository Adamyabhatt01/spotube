import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';

/// Playlist pins that live outside the sidebar.
///
/// A theme may declare several `layout.pinTargets` and pin the same playlist
/// to each independently. The sidebar keeps its existing preferences column;
/// every other target is a KV-backed list here. Phase 8 folds these into the
/// library schema, but the action contract needs a working store now.
class ThemePinsNotifier extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() {
    if (!KVStoreService.isInitialized) return const {};
    return KVStoreService.themePinTargets();
  }

  List<String> pinsFor(String target) => state[target] ?? const <String>[];

  bool isPinned(String target, String id) => pinsFor(target).contains(id);

  /// Adds or removes [id] under [target]. A no-op when the state matches.
  void setPinned(String target, String id, {required bool pinned}) {
    final current = List<String>.of(pinsFor(target));
    if (current.contains(id) == pinned) return;

    if (pinned) {
      current.insert(0, id);
    } else {
      current.remove(id);
    }

    final next = {...state};
    if (current.isEmpty) {
      next.remove(target);
    } else {
      next[target] = List.unmodifiable(current);
    }
    state = next;

    if (KVStoreService.isInitialized) {
      KVStoreService.setThemePinTarget(target, current);
    }
  }
}

final themePinsProvider =
    NotifierProvider<ThemePinsNotifier, Map<String, List<String>>>(
  ThemePinsNotifier.new,
);
