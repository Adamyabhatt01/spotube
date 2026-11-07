// uniqueByKey must produce exactly what the nested unique() scan produced
// (first occurrence wins, order preserved) at O(n) instead of O(n²).

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/extensions/list.dart';

void main() {
  group('uniqueByKey equivalence with unique', () {
    // Mirrors the queue-load call site: dedupe by a derived key.
    List<String> nested(List<String> items) =>
        items.unique((a, b) => a.toLowerCase() == b.toLowerCase());

    List<String> keyed(List<String> items) =>
        items.uniqueByKey((item) => item.toLowerCase());

    test('empty and singleton', () {
      expect(keyed(const []), isEmpty);
      expect(keyed(const ['a']), ['a']);
    });

    test('no duplicates is the identity', () {
      const items = ['a', 'b', 'c'];
      expect(keyed(items), items);
    });

    test('keeps first occurrence, preserves order', () {
      const items = ['b', 'A', 'c', 'a', 'B', 'd'];
      expect(keyed(items), nested(items));
      expect(keyed(items), ['b', 'A', 'c', 'd']);
    });

    test('all duplicates collapse to one', () {
      const items = ['x', 'X', 'x'];
      expect(keyed(items), ['x']);
    });

    test('large input matches nested result', () {
      final items = [
        for (var i = 0; i < 2000; i++) 'track-${i % 500}',
      ];
      expect(keyed(items), nested(items));
      expect(keyed(items), hasLength(500));
    });
  });
}
