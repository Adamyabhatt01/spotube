import 'dart:convert';

import 'package:spotube/models/database/database.dart';

/// Keys of the persisted last-known-good library lists in
/// [LibrarySnapshotTable]. Values are the fully-materialized item arrays
/// of the corresponding saved-list providers.
const librarySnapshotKeySavedArtists = 'savedArtists';
const librarySnapshotKeySavedAlbums = 'savedAlbums';
const librarySnapshotKeySavedTracks = 'savedTracks';
const librarySnapshotKeySavedPlaylists = 'savedPlaylists';

/// The version of the stored payload.
///
/// v1 was a bare JSON array of items and is still read: an array is by
/// definition the whole list. v2 wraps the array in an object that also says
/// whether the array is the whole list or only the pages that had been paged
/// in when it was written.
const librarySnapshotFormatVersion = 2;

/// A persisted library list.
class LibrarySnapshot<K> {
  /// The rows that were stored.
  final List<K> items;

  /// Whether [items] is the whole list.
  ///
  /// False means the list was still paging when it was written: the rows are
  /// the first pages of the library and the rest was never fetched. The
  /// distinction is what lets the next launch keep paging instead of
  /// mistaking one page for the entire account — and what stops a playlist
  /// created on another device from being invisible just because the
  /// snapshot it would have been in was never written.
  final bool complete;

  const LibrarySnapshot({required this.items, required this.complete});
}

/// Overwrites the snapshot for [key] with the JSON of [items].
///
/// Items are freezed metadata objects; `toJson` is dynamic-dispatched.
///
/// [complete] says whether [items] is the whole list. A partial list is
/// still worth persisting: it is what the device actually knows, and it
/// carries the rows a later launch needs to show something while the
/// network is still being asked.
Future<void> writeLibrarySnapshot<K>(
  AppDatabase database,
  String key,
  List<K> items, {
  bool complete = true,
}) async {
  await database.transaction(() async {
    await (database.delete(database.librarySnapshotTable)
          ..where((t) => t.key.equals(key)))
        .go();
    await database.into(database.librarySnapshotTable).insert(
          LibrarySnapshotTableData(
            key: key,
            data: jsonEncode({
              'v': librarySnapshotFormatVersion,
              'complete': complete,
              'items': items.map((e) => (e as dynamic).toJson()).toList(),
            }),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  });
}

/// Returns the cached snapshot for [key], or null on miss or corrupt payload
/// (self-healing cache miss: the next successful load overwrites it).
///
/// Both payload shapes are read: the v1 bare array (read as a complete
/// list) and the v2 object.
Future<LibrarySnapshot<K>?> readLibrarySnapshot<K>(
  AppDatabase database,
  String key,
  K Function(Map<String, dynamic>) decode,
) async {
  final row = await (database.select(database.librarySnapshotTable)
        ..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  if (row == null) return null;

  try {
    final decoded = jsonDecode(row.data);

    if (decoded is List) {
      return LibrarySnapshot(
        items: _decodeItems(decoded, decode),
        complete: true,
      );
    }

    if (decoded is Map) {
      final rawItems = decoded['items'];
      if (rawItems is! List) return null;
      return LibrarySnapshot(
        items: _decodeItems(rawItems, decode),
        // A payload without the flag is read as complete: it is the v1 shape
        // wearing a wrapper, and assuming it was partial would send the
        // reader paging for rows it already has.
        complete: decoded['complete'] != false,
      );
    }

    return null;
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

List<K> _decodeItems<K>(
  List<dynamic> raw,
  K Function(Map<String, dynamic>) decode,
) =>
    raw.map((e) => decode(Map<String, dynamic>.from(e as Map))).toList();
