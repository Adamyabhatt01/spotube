import 'dart:async';

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/logger/logger.dart';

/// Bookmarked stations, newest first.
///
/// The list is served from the [RadioFavoritesTable] snapshot so it renders
/// offline; the actual stream URL is re-resolved through the directory at play
/// time by whoever consumes this list.
class RadioFavoritesNotifier extends AutoDisposeAsyncNotifier<List<RadioStation>> {
  @override
  FutureOr<List<RadioStation>> build() async {
    final db = ref.watch(databaseProvider);
    final query = db.select(db.radioFavoritesTable)
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);

    final subscription = query.watch().listen((rows) {
      state = AsyncData(rows.map((r) => r.station).toList());
    });
    ref.onDispose(subscription.cancel);

    return (await query.get()).map((r) => r.station).toList();
  }

  Future<void> toggle(RadioStation station) async {
    final db = ref.read(databaseProvider);
    try {
      final existing = await (db.select(db.radioFavoritesTable)
            ..where((t) =>
                t.stationId.equals(station.id) &
                t.provider.equals(station.provider)))
          .getSingleOrNull();

      if (existing == null) {
        await db.into(db.radioFavoritesTable).insert(
              RadioFavoritesTableCompanion.insert(
                stationId: station.id,
                provider: station.provider,
                data: station.toJson(),
              ),
            );
      } else {
        await (db.delete(db.radioFavoritesTable)
              ..where((t) => t.id.equals(existing.id)))
            .go();
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio favorites toggle');
    }
  }

  Future<void> remove(RadioStation station) async {
    final db = ref.read(databaseProvider);
    try {
      await (db.delete(db.radioFavoritesTable)
            ..where((t) =>
                t.stationId.equals(station.id) &
                t.provider.equals(station.provider)))
          .go();
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio favorites remove');
    }
  }
}

final radioFavoritesProvider =
    AutoDisposeAsyncNotifierProvider<RadioFavoritesNotifier, List<RadioStation>>(
  RadioFavoritesNotifier.new,
);

/// Whether a station is bookmarked, computed against the currently loaded
/// list. Cheap: the caller watches [radioFavoritesProvider] to rebuild.
bool isFavorite(Iterable<RadioStation> favorites, RadioStation station) =>
    favorites.any((f) => f.favoriteKey == station.favoriteKey);

/// The bookmarked stations' keys as a set, so a row can ask a question instead
/// of scanning.
///
/// Same shape as `blacklistedIdsProvider`: [isFavorite] is a linear scan over
/// the whole favorites list, and it runs once per mounted station control (every
/// grid card, every list tile, every card in every rail) as well as in the
/// player menu — so a favorites emission costs O(visible x favorites) string
/// comparisons. Handing out the set turns each of those into a lookup.
final radioFavoriteKeysProvider = Provider<Set<String>>((ref) {
  final favorites = ref.watch(radioFavoritesProvider).asData?.value;
  if (favorites == null || favorites.isEmpty) return const <String>{};
  return {for (final station in favorites) station.favoriteKey};
});
