import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('RecentSearchesNotifier', () {
    test('build seeds from the store', () async {
      await KVStoreService.setRecentSearches(['a', 'b']);
      final container = makeContainer();
      expect(container.read(recentSearchesProvider), ['a', 'b']);
    });

    test('add prepends and dedupes, moving repeats to the front', () async {
      final container = makeContainer();
      await container.read(recentSearchesProvider.notifier).add('a');
      await container.read(recentSearchesProvider.notifier).add('b');
      await container.read(recentSearchesProvider.notifier).add('a');
      expect(container.read(recentSearchesProvider), ['a', 'b']);
      expect(KVStoreService.recentSearches, ['a', 'b']);
    });

    test('add respects the store cap, dropping oldest', () async {
      final container = makeContainer();
      for (var i = 0; i < KVStoreService.maxRecentSearches + 5; i++) {
        await container.read(recentSearchesProvider.notifier).add('s$i');
      }
      final state = container.read(recentSearchesProvider);
      expect(state.length, KVStoreService.maxRecentSearches);
      expect(state.first, 's${KVStoreService.maxRecentSearches + 4}');
      expect(KVStoreService.recentSearches, state);
    });

    test('remove drops the term and persists', () async {
      final container = makeContainer();
      await container.read(recentSearchesProvider.notifier).add('a');
      await container.read(recentSearchesProvider.notifier).add('b');
      await container.read(recentSearchesProvider.notifier).remove('a');
      expect(container.read(recentSearchesProvider), ['b']);
      expect(KVStoreService.recentSearches, ['b']);
    });

    test('clear empties and persists', () async {
      final container = makeContainer();
      await container.read(recentSearchesProvider.notifier).add('a');
      await container.read(recentSearchesProvider.notifier).clear();
      expect(container.read(recentSearchesProvider), isEmpty);
      expect(KVStoreService.recentSearches, isEmpty);
    });
  });
}
