import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/sidebar/sidebar_provider.dart';

void main() {
  group('resolveSidebarLibraryOrder', () {
    test('empty stored order yields defaults', () {
      expect(
        resolveSidebarLibraryOrder([]),
        defaultSidebarLibraryOrder,
      );
    });

    test('stored order is preserved', () {
      expect(
        resolveSidebarLibraryOrder(
            ['local_library', 'albums', 'artists', 'playlists']),
        ['local_library', 'albums', 'artists', 'playlists', 'stations'],
      );
    });

    test('unknown ids are dropped', () {
      expect(
        resolveSidebarLibraryOrder(['albums', 'defunct_tile', 'playlists']),
        ['albums', 'playlists', 'artists', 'stations', 'local_library'],
      );
    });

    test('missing defaults are appended in default order', () {
      expect(
        resolveSidebarLibraryOrder(['albums']),
        ['albums', 'playlists', 'artists', 'stations', 'local_library'],
      );
    });

    test('all-unknown stored order falls back to defaults', () {
      expect(
        resolveSidebarLibraryOrder(['foo', 'bar']),
        defaultSidebarLibraryOrder,
      );
    });

    test('stored subset keeps relative order, defaults fill the rest', () {
      expect(
        resolveSidebarLibraryOrder(['local_library', 'playlists']),
        ['local_library', 'playlists', 'artists', 'albums', 'stations'],
      );
    });
  });

  group('moveSidebarEntry', () {
    test('moves an entry forward', () {
      expect(
        moveSidebarEntry(['a', 'b', 'c', 'd'], 0, 2),
        ['b', 'c', 'a', 'd'],
      );
    });

    test('moves an entry backward', () {
      expect(
        moveSidebarEntry(['a', 'b', 'c', 'd'], 3, 1),
        ['a', 'd', 'b', 'c'],
      );
    });

    test('same index returns an equal copy', () {
      expect(moveSidebarEntry(['a', 'b'], 1, 1), ['a', 'b']);
    });

    test('out-of-range indexes leave the order unchanged', () {
      expect(moveSidebarEntry(['a', 'b'], -1, 1), ['a', 'b']);
      expect(moveSidebarEntry(['a', 'b'], 0, 5), ['a', 'b']);
      expect(moveSidebarEntry(['a', 'b'], 4, 0), ['a', 'b']);
    });

    test('does not mutate the input', () {
      final order = ['a', 'b', 'c'];
      moveSidebarEntry(order, 0, 2);
      expect(order, ['a', 'b', 'c']);
    });
  });

  group('moveSidebarPin', () {
    test('reorders the visible subset', () {
      expect(
        moveSidebarPin(['x', 'y', 'z'], ['x', 'y', 'z'], 0, 2),
        ['y', 'z', 'x'],
      );
    });

    test('hidden ids sink below the visible ones, order kept', () {
      expect(
        moveSidebarPin(['x', 'hidden', 'y', 'z'], ['x', 'y', 'z'], 2, 0),
        ['z', 'x', 'y', 'hidden'],
      );
    });

    test('out-of-range visible indexes leave pins unchanged', () {
      expect(
        moveSidebarPin(['x', 'y'], ['x', 'y'], 0, 7),
        ['x', 'y'],
      );
    });
  });

  group('resolveSidebarDrop', () {
    const visible = ['a', 'b', 'c'];
    test('bottom half inserts after the target', () {
      expect(
        resolveSidebarDrop(visible, 'a', 'b', after: true),
        (from: 0, to: 1),
      );
    });

    test('top half inserts before the target', () {
      expect(
        resolveSidebarDrop(visible, 'c', 'a', after: false),
        (from: 2, to: 0),
      );
    });

    test('bottom half of the last row reaches the end', () {
      expect(
        resolveSidebarDrop(visible, 'a', 'c', after: true),
        (from: 0, to: 2),
      );
    });

    test('adjacent no-op drops resolve to null', () {
      // a is already before b; b is already after a.
      expect(resolveSidebarDrop(visible, 'a', 'b', after: false), isNull);
      expect(resolveSidebarDrop(visible, 'b', 'a', after: true), isNull);
    });

    test('unknown ids and self-drops resolve to null', () {
      expect(resolveSidebarDrop(visible, 'z', 'a', after: true), isNull);
      expect(resolveSidebarDrop(visible, 'a', 'z', after: true), isNull);
      expect(resolveSidebarDrop(visible, 'a', 'a', after: true), isNull);
    });
  });
}
