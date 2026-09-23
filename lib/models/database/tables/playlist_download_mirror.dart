part of '../database.dart';

/// One row per playlist the user has mirrored, holding just enough to render
/// the entry in the Playlists section without a network round trip.
///
/// Membership and order live in [PlaylistDownloadTable]; this is the header.
/// `playlistData` is the whole [SpotubeSimplePlaylistObject] as JSON (the same
/// TEXT-JSON approach as [AudioPlayerStateTable.tracks]) because reconstructing
/// the model by hand would drop `description`, `externalUri` and `owner`, which
/// the playlist page already reads. Keyed by the Spotify playlist id, never its
/// name, so renaming upstream changes a row's payload and nothing else.
///
/// Bounded by construction — a row exists only for a playlist the user
/// explicitly downloaded, never for everything Spotify offers — which is what
/// keeps it inside the "bounded caches only" rule at `.ai/ARCHITECTURE.md`.
class PlaylistDownloadMirrorTable extends Table {
  TextColumn get playlistId => text().unique()();
  TextColumn get playlistData => text()();

  /// Spotify's own count, which can exceed the number of membership rows after
  /// a cheap first-page-only background resync.
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  IntColumn get syncedAtMs => integer()();
}
