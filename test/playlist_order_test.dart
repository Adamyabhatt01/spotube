import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/playlist_order.dart';

SpotubeSimplePlaylistObject _playlist(String id) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: 'Playlist $id',
    description: 'A playlist under test',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

List<String> _ids(List<SpotubeSimplePlaylistObject> playlists) =>
    [for (final playlist in playlists) playlist.id];

void main() {
  group('applyMainPlaylistOrder', () {
    test('null and empty orders keep the source order', () {
      final source = [_playlist('a'), _playlist('b')];
      expect(_ids(applyMainPlaylistOrder(source, null)), ['a', 'b']);
      expect(_ids(applyMainPlaylistOrder(source, [])), ['a', 'b']);
    });

    test('stored order wins, missing playlists append in source order', () {
      final source = [
        _playlist('a'),
        _playlist('b'),
        _playlist('c'),
        _playlist('d'),
      ];
      expect(
        _ids(applyMainPlaylistOrder(source, ['c', 'a'])),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('stale ids are skipped and never become placeholders', () {
      final source = [_playlist('a'), _playlist('b')];
      expect(
        _ids(applyMainPlaylistOrder(source, ['ghost', 'b'])),
        ['b', 'a'],
      );
    });

    test('does not mutate the input', () {
      final source = [_playlist('a'), _playlist('b')];
      applyMainPlaylistOrder(source, ['b', 'a']);
      expect(_ids(source), ['a', 'b']);
    });
  });

  group('applyPinnedFirst', () {
    test('pinned ids lead in pin order, the rest keep their order', () {
      final source = [
        _playlist('a'),
        _playlist('b'),
        _playlist('c'),
        _playlist('d'),
      ];
      expect(
        _ids(applyPinnedFirst(source, ['c', 'a'])),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('no pins is the identity', () {
      final source = [_playlist('a'), _playlist('b')];
      expect(_ids(applyPinnedFirst(source, const [])), ['a', 'b']);
    });

    test('a pin with no playlist behind it is skipped', () {
      final source = [_playlist('a'), _playlist('b')];
      expect(
        _ids(applyPinnedFirst(source, ['ghost', 'b'])),
        ['b', 'a'],
      );
    });

    test('an all-stale pin list is the identity', () {
      final source = [_playlist('a'), _playlist('b')];
      expect(
        _ids(applyPinnedFirst(source, ['ghost', 'gone'])),
        ['a', 'b'],
      );
    });

    test('does not mutate the input', () {
      final source = [_playlist('a'), _playlist('b')];
      applyPinnedFirst(source, ['b']);
      expect(_ids(source), ['a', 'b']);
    });
  });

  group('moveMainPlaylistEntry', () {
    test('reorders the visible entries', () {
      expect(
        moveMainPlaylistEntry(['a', 'b', 'c'], ['a', 'b', 'c'], 0, 2),
        ['b', 'c', 'a'],
      );
    });

    test('hidden ids sink below the visible ones, order kept', () {
      expect(
        moveMainPlaylistEntry(
          ['a', 'hidden', 'b', 'c'],
          ['a', 'b', 'c'],
          2,
          0,
        ),
        ['c', 'a', 'b', 'hidden'],
      );
    });

    test('a first move from the null sentinel keeps every visible id', () {
      expect(
        moveMainPlaylistEntry(null, ['a', 'b', 'c'], 2, 0),
        ['c', 'a', 'b'],
      );
    });

    test('out-of-range indexes leave the stored order alone', () {
      expect(
        moveMainPlaylistEntry(['a', 'b'], ['a', 'b'], 0, 7),
        ['a', 'b'],
      );
    });
  });

  group('order persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('sidebar pins and main order are stored independently', () async {
      await db.into(db.preferencesTable).insert(
            PreferencesTableCompanion.insert(
              id: const Value(0),
              pinnedPlaylistIds: const Value(['side-b', 'side-a']),
              mainPlaylistOrder: const Value(['main-b', 'main-a']),
            ),
          );

      await (db.update(db.preferencesTable)
            ..where((table) => table.id.equals(0)))
          .write(
        const PreferencesTableCompanion(
          pinnedPlaylistIds: Value(['side-a']),
        ),
      );

      var row = await db.select(db.preferencesTable).getSingle();
      expect(row.pinnedPlaylistIds, ['side-a']);
      expect(row.mainPlaylistOrder, ['main-b', 'main-a']);

      await (db.update(db.preferencesTable)
            ..where((table) => table.id.equals(0)))
          .write(
        const PreferencesTableCompanion(
          mainPlaylistOrder: Value(['main-a', 'main-b']),
        ),
      );

      row = await db.select(db.preferencesTable).getSingle();
      expect(row.pinnedPlaylistIds, ['side-a']);
      expect(row.mainPlaylistOrder, ['main-a', 'main-b']);
    });

    test('an intentional empty order is not the null sentinel', () async {
      await db.into(db.preferencesTable).insert(
            PreferencesTableCompanion.insert(
              id: const Value(0),
              pinnedPlaylistIds: const Value(['side-a']),
            ),
          );

      var row = await db.select(db.preferencesTable).getSingle();
      expect(
        row.mainPlaylistOrder,
        isNull,
        reason: 'new and not-yet-seeded rows are uninitialized',
      );

      await (db.update(db.preferencesTable)
            ..where((table) => table.id.equals(0)))
          .write(
        const PreferencesTableCompanion(
          mainPlaylistOrder: Value([]),
        ),
      );

      row = await db.select(db.preferencesTable).getSingle();
      expect(
        row.mainPlaylistOrder,
        isEmpty,
        reason: 'empty means the user chose no order, not "seed from pins"',
      );
      expect(row.pinnedPlaylistIds, ['side-a']);
    });
  });
}
