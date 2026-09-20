part of '../database.dart';

/// Last-successful full snapshots of the Spotify saved lists (artists,
/// albums, playlists, tracks), stored as one JSON row per list.
///
/// Serves the library while Spotify rate-limits (HTTP 429) the metadata
/// plugin: written only after a fully-materialized (or single-page
/// complete) successful load, never on failure. A missing or corrupt row
/// is a self-healing cache miss, like [SourceMatchTable]. The `key` column
/// is kept unique by a create-table index (a `primaryKey` override would
/// clash with Flutter's `Column` in this part-of library); writes go
/// through delete+insert in a transaction.
class LibrarySnapshotTable extends Table {
  TextColumn get key => text().unique()();
  TextColumn get data => text()();
  IntColumn get updatedAtMs => integer()();
}
