part of '../database.dart';

@TableIndex(
  name: 'unique_playlist_download',
  unique: true,
  columns: {#playlistId, #trackId},
)
@TableIndex(
  name: 'playlist_download_order',
  columns: {#playlistId, #position},
)

/// Which tracks are in which Spotify playlist, and in what order.
///
/// Membership only — no file, no state. `playlistId` is the Spotify playlist
/// id, never its name, so renaming a playlist upstream keeps its downloads and
/// `position` is upstream's order, not ours. The composite unique index is what
/// makes "one row per (playlist, track)" a database guarantee instead of a
/// convention.
class PlaylistDownloadTable extends Table {
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();
  IntColumn get position => integer()();
  IntColumn get addedAtMs => integer()();
}
