// Recent searches stay bounded: the list was prepend-only, growing in
// SharedPreferences for the app's whole lifetime while the per-keystroke
// autocomplete filter re-read and fuzzy-matched all of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  test('writes are capped, most-recent-first', () async {
    await KVStoreService.setRecentSearches(
      [for (var i = 0; i < 50; i++) 'query $i'],
    );

    final stored = KVStoreService.recentSearches;
    expect(stored, hasLength(KVStoreService.maxRecentSearches));
    expect(stored.first, 'query 0', reason: 'prepend order survives the cap');
    expect(stored.last, 'query 19');
  });

  test('short lists pass through untouched', () async {
    await KVStoreService.setRecentSearches(['a', 'b']);
    expect(KVStoreService.recentSearches, ['a', 'b']);
  });
}
