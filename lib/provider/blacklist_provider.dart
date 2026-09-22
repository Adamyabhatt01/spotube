import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';

class BlackListNotifier extends AsyncNotifier<List<BlacklistTableData>> {
  @override
  build() async {
    final database = ref.watch(databaseProvider);

    final subscription = database
        .select(database.blacklistTable)
        .watch()
        .listen((event) => state = AsyncData(event));

    ref.onDispose(() {
      subscription.cancel();
    });

    return await database.select(database.blacklistTable).get();
  }

  AppDatabase get _database => ref.read(databaseProvider);

  Future<void> add(BlacklistTableCompanion element) async {
    _database.into(_database.blacklistTable).insert(element);
  }

  Future<void> remove(String elementId) async {
    await (_database.delete(_database.blacklistTable)
          ..where((tbl) => tbl.elementId.equals(elementId)))
        .go();
  }

  bool contains(SpotubeTrackObject track) =>
      matches(idsOf(state.asData?.value ?? const []), track);

  /// [contains] as a function of the entries rather than of this notifier's
  /// state, so a watcher can `select` a bool out of [blacklistedIdsProvider]
  /// instead of subscribing to the whole table.
  static bool matches(Set<String> ids, SpotubeTrackObject track) {
    if (ids.isEmpty) return false;
    return ids.contains(track.id) ||
        track.artists.any((artist) => ids.contains(artist.id));
  }

  static Set<String> idsOf(List<BlacklistTableData> entries) =>
      {for (final entry in entries) entry.elementId};

  bool containsArtist(String artistId) {
    return state.asData?.value
            .any((element) => element.elementId == artistId) ??
        false;
  }

  /// Filters the non blacklisted tracks from the given [tracks]
  Iterable<SpotubeTrackObject> filter(Iterable<SpotubeTrackObject> tracks) {
    return tracks.whereNot(contains).toList();
  }
}

final blacklistProvider =
    AsyncNotifierProvider<BlackListNotifier, List<BlacklistTableData>>(
  () => BlackListNotifier(),
);

/// The table as an id set, rebuilt once per change.
///
/// Every visible row wants to know whether *it* is blacklisted. Asking through
/// the list costs a scan of the whole table per row, and a screenful of rows
/// rebuilds on each other's question; the set turns it into a lookup, and a row
/// watching [BlackListNotifier.matches] through a `select` only rebuilds when its
/// own answer changes.
final blacklistedIdsProvider = Provider<Set<String>>((ref) {
  final entries = ref.watch(blacklistProvider).asData?.value;
  if (entries == null || entries.isEmpty) return const <String>{};
  return BlackListNotifier.idsOf(entries);
});
