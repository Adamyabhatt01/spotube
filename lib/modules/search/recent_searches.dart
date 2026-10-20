import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

/// Reactive recent searches, persisted in SharedPreferences.
///
/// Previously the search bar re-read the static
/// `KVStoreService.recentSearches` through a `useMemoized` + manual
/// `refreshTick` counter, so any future write path that forgot to bump the
/// tick went silently stale. Writes now go through this notifier and every
/// reader subscribes, so there is no implicit contract left.
///
/// Reads are synchronous: `SharedPreferences` is hydrated once in
/// `KVStoreService.initialize()` before the UI builds, so a plain
/// [Notifier] (not an `AsyncNotifier`) is the correct shape. The 20-item
/// cap and drop-oldest eviction live in `KVStoreService.setRecentSearches`
/// and are preserved as-is; state is re-read after each persist so the
/// in-memory list always matches what is on disk.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => KVStoreService.recentSearches;

  /// Records a search, moving a repeat to the front (same set-literal
  /// semantics the bar used before: `{value, ...recents}`).
  Future<void> add(String term) async {
    await KVStoreService.setRecentSearches(
      [term, for (final s in state) if (s != term) s],
    );
    state = KVStoreService.recentSearches;
  }

  Future<void> remove(String term) async {
    await KVStoreService.setRecentSearches(
      [for (final s in state) if (s != term) s],
    );
    state = KVStoreService.recentSearches;
  }

  Future<void> clear() async {
    await KVStoreService.setRecentSearches(const []);
    state = KVStoreService.recentSearches;
  }
}
