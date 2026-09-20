import 'dart:convert';

import 'package:spotube/models/database/database.dart';

/// Keys of the persisted last-known-good library lists in
/// [LibrarySnapshotTable]. Values are the fully-materialized item arrays
/// of the corresponding saved-list providers.
const librarySnapshotKeySavedArtists = 'savedArtists';
const librarySnapshotKeySavedAlbums = 'savedAlbums';
const librarySnapshotKeySavedTracks = 'savedTracks';
const librarySnapshotKeySavedPlaylists = 'savedPlaylists';

/// Overwrites the snapshot for [key] with the JSON of [items].
/// Items are freezed metadata objects; `toJson` is dynamic-dispatched.
Future<void> writeLibrarySnapshot<K>(
  AppDatabase database,
  String key,
  List<K> items,
) async {
  await database.transaction(() async {
    await (database.delete(database.librarySnapshotTable)
          ..where((t) => t.key.equals(key)))
        .go();
    await database.into(database.librarySnapshotTable).insert(
          LibrarySnapshotTableData(
            key: key,
            data:
                jsonEncode(items.map((e) => (e as dynamic).toJson()).toList()),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  });
}

/// Returns the cached items for [key], or null on miss or corrupt payload
/// (self-healing cache miss: the next successful full load overwrites it).
Future<List<K>?> readLibrarySnapshot<K>(
  AppDatabase database,
  String key,
  K Function(Map<String, dynamic>) decode,
) async {
  final row = await (database.select(database.librarySnapshotTable)
        ..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  if (row == null) return null;

  try {
    final items = jsonDecode(row.data) as List<dynamic>;
    return items
        .map((e) => decode(Map<String, dynamic>.from(e as Map)))
        .toList();
  } on FormatException catch (_) {
    return null;
  } on TypeError catch (_) {
    return null;
  }
}

/// Library snapshots are per-account; drop them on logout.
Future<void> clearLibrarySnapshots(AppDatabase database) {
  return database.delete(database.librarySnapshotTable).go();
}
