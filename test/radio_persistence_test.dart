// Radio persistence: favorites toggle/unique/re-render and the radio-scoped
// recently-played read (dedup by station, ordering, ignore non-radio rows).
// All against an in-memory Drift database; no network, no native player.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';
import 'package:spotube/services/logger/logger.dart';

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

RadioStation _station(String id, {String provider = 'p'}) => RadioStation(
      id: id,
      provider: provider,
      name: 'Station $id',
      streamUrl: 'https://stream/$id',
      tags: const ['jazz'],
    );

void main() {
  AppLogger.initialize(false);

  late AppDatabase database;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    // autoDispose providers need a live listener to build and stay current;
    // a bare `read` returns AsyncLoading and then tears the notifier down.
    final favSub = container.listen(radioFavoritesProvider, (_, __) {});
    final histSub = container.listen(radioHistoryProvider, (_, __) {});
    addTearDown(favSub.close);
    addTearDown(histSub.close);
  });

  List<RadioStation> readFavorites() =>
      container.read(radioFavoritesProvider).requireValue;

  List<RadioStation> readHistory() =>
      container.read(radioHistoryProvider).requireValue;

  group('favorites', () {
    test('toggle adds then removes', () async {
      final notifier = container.read(radioFavoritesProvider.notifier);

      await notifier.toggle(_station('a'));
      await _flush();
      expect(readFavorites().map((s) => s.id), ['a']);

      await notifier.toggle(_station('a'));
      await _flush();
      expect(readFavorites(), isEmpty);
    });

    test('same id from different providers are distinct bookmarks', () async {
      final notifier = container.read(radioFavoritesProvider.notifier);

      await notifier.toggle(_station('x', provider: 'one'));
      await notifier.toggle(_station('x', provider: 'two'));
      await _flush();

      expect(readFavorites().map((s) => s.provider).toSet(), {'one', 'two'});
    });

    test('stored station round-trips through the JSON snapshot', () async {
      final original = _station('r');
      final notifier = container.read(radioFavoritesProvider.notifier);

      await notifier.toggle(original);
      await _flush();

      expect(readFavorites().single, original);
    });

    test('isFavorite matches by provider-namespaced key', () async {
      final notifier = container.read(radioFavoritesProvider.notifier);
      await notifier.toggle(_station('a', provider: 'p'));
      await _flush();

      final favorites = readFavorites();
      expect(isFavorite(favorites, _station('a', provider: 'p')), isTrue);
      expect(isFavorite(favorites, _station('a', provider: 'other')), isFalse);
    });
  });

  group('recently played', () {
    Future<void> seedRadio(
      RadioStation station, {
      required DateTime createdAt,
    }) {
      return database.into(database.historyTable).insert(
            HistoryTableCompanion.insert(
              createdAt: Value(createdAt),
              type: HistoryEntryType.radio,
              itemId: station.favoriteKey,
              data: station.toJson(),
            ),
          );
    }

    test('dedups to the latest visit per station, newest first', () async {
      final base = DateTime(2026);
      await seedRadio(_station('a'), createdAt: base);
      await seedRadio(
        _station('b'),
        createdAt: base.add(const Duration(minutes: 5)),
      );
      await seedRadio(
        _station('a'),
        createdAt: base.add(const Duration(minutes: 10)),
      ); // revisit a

      await _flush();
      final recent = readHistory();

      expect(
        recent.map((s) => s.id),
        ['a', 'b'],
        reason: 'a revisited most recently, then b, each listed once',
      );
    });

    test('ignores non-radio history rows', () async {
      await database.into(database.historyTable).insert(
            HistoryTableCompanion.insert(
              type: HistoryEntryType.track,
              itemId: 't1',
              data: const {'foo': 'bar'},
            ),
          );
      await seedRadio(
        _station('z'),
        createdAt: DateTime(2026).add(const Duration(minutes: 1)),
      );

      await _flush();
      final recent = readHistory();

      expect(recent.map((s) => s.id), ['z']);
    });
  });
}
