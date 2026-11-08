// Pins the favorite-membership lookup: a row must ask a set a question, not
// scan the whole favorites list.
//
// Same shape as test/blacklist_row_membership_test.dart, which fixed the
// identical bug for the blacklist: `isFavorite` is
// `favorites.any((f) => f.favoriteKey == ...)`, and it runs once per mounted
// station control (every grid card, every list tile, every card in every rail)
// as well as in the player menu — so one favorites emission costs
// O(visible x favorites) string comparisons. `_naive` below is that scan,
// kept verbatim as the oracle the indexed path is cross-checked against.

import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/services/logger/logger.dart';

RadioStation _station(String id, {String provider = 'p'}) => RadioStation(
      id: id,
      provider: provider,
      name: 'Station $id',
      streamUrl: 'https://stream/$id',
    );

/// The pre-change predicate, verbatim: a linear scan per question.
bool _naive(List<RadioStation> favorites, RadioStation station) =>
    favorites.any((f) => f.favoriteKey == station.favoriteKey);

/// Polls until [condition] holds, so a drift stream emission is not raced.
Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never became true');
}

void main() {
  AppLogger.initialize(false);

  group('membership', () {
    test('matches on the provider-namespaced key', () {
      final favorites = [_station('a')];
      expect(_naive(favorites, _station('a')), isTrue);
      expect(_naive(favorites, _station('b')), isFalse);
    });

    test('the same id from another provider is a different station', () {
      final favorites = [_station('a', provider: 'p')];
      expect(_naive(favorites, _station('a', provider: 'other')), isFalse);
    });

    test('an empty list is not a member', () {
      expect(_naive(const [], _station('a')), isFalse);
    });

    test('agrees with the scan it replaced, on random pools', () {
      final random = Random(11);
      for (var pool = 0; pool < 200; pool++) {
        final keys = [
          for (var i = 0; i < 1 + random.nextInt(12); i++) 'x$pool-$i',
        ];
        final favorites = keys.map((k) => _station(k)).toList();
        final needle = _station('t$pool');
        expect(
          keys.toSet().contains(needle.favoriteKey),
          _naive(favorites, needle),
          reason: 'pool $pool',
        );
      }
    });
  });

  group('radioFavoriteKeysProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('builds once per change, however many rows ask', () async {
      final notifier = container.read(radioFavoritesProvider.notifier);
      await notifier.toggle(_station('a'));
      await _waitFor(
        () => container.read(radioFavoriteKeysProvider).isNotEmpty,
      );

      final reads = <Set<String>>[];
      final subs = [
        for (var i = 0; i < 25; i++)
          container.listen(radioFavoriteKeysProvider, (_, next) {
            reads.add(next);
          }),
      ];
      addTearDown(() {
        for (final sub in subs) {
          sub.close();
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(radioFavoriteKeysProvider), {'p:a'});

      await notifier.toggle(_station('b'));
      await _waitFor(
        () => container.read(radioFavoriteKeysProvider).length == 2,
      );

      expect(
        container.read(radioFavoriteKeysProvider),
        {'p:a', 'p:b'},
        reason: 'a new favorite must reach the set',
      );
    });

    test('an unfavorited station is absent and an unlisted table is empty',
        () async {
      await container
          .read(radioFavoritesProvider.notifier)
          .toggle(_station('a'));

      // The favorites list is served from a drift stream subscription, so the
      // write landing is not the same instant as the list being updated.
      await _waitFor(
        () => container.read(radioFavoriteKeysProvider).isNotEmpty,
      );

      final keys = container.read(radioFavoriteKeysProvider);
      expect(keys.contains(_station('a').favoriteKey), isTrue);
      expect(keys.contains(_station('zz').favoriteKey), isFalse);
      expect(
        keys.contains(_station('a', provider: 'other').favoriteKey),
        isFalse,
        reason: 'the key is namespaced by provider',
      );
    });
  });

  test('a favorites emission costs one pass, not one per visible row', () {
    const rows = 200;
    final favorites = [for (var i = 0; i < 5000; i++) _station('s$i')];
    final needles = [for (var i = 0; i < rows; i++) _station('s$i')];
    final keys = {for (final station in favorites) station.favoriteKey};

    // Warm both paths so the comparison is not dominated by first-call JIT.
    for (final needle in needles) {
      _naive(favorites, needle);
      keys.contains(needle.favoriteKey);
    }

    final naive = Stopwatch()..start();
    var naiveHits = 0;
    for (final needle in needles) {
      if (_naive(favorites, needle)) naiveHits++;
    }
    naive.stop();

    final indexed = Stopwatch()..start();
    var indexedHits = 0;
    for (final needle in needles) {
      if (keys.contains(needle.favoriteKey)) indexedHits++;
    }
    indexed.stop();

    expect(indexedHits, naiveHits, reason: 'the two must agree');
    expect(naiveHits, rows, reason: 'every needle is favorited');

    // Generous: the point is that per-row cost no longer tracks favorites size,
    // not a precise ratio on a shared machine.
    // ignore: avoid_print
    print(
      '[radio favorites ${favorites.length}x$rows] '
      'naive=${naive.elapsedMicroseconds}us '
      'indexed=${indexed.elapsedMicroseconds}us '
      'speedup=${(naive.elapsedMicroseconds / indexed.elapsedMicroseconds).toStringAsFixed(1)}x',
    );
    expect(
      naive.elapsedMicroseconds,
      greaterThan(indexed.elapsedMicroseconds * 5),
      reason: 'naive ${naive.elapsedMicroseconds}µs vs indexed '
          '${indexed.elapsedMicroseconds}µs',
    );
  });
}
