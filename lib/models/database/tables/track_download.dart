part of '../database.dart';

/// The persisted half of [DownloadStatus], plus two states that only exist
/// because something survived a process boundary.
///
/// `interrupted` and `missing` are not lies about a transfer: the first means
/// the app died mid-write (`.ai/AUDIT_STATE.md` — a killed download used to
/// come back as nothing at all), the second means a row that completed once
/// no longer has a file behind it. Both are deliberately non-terminal in the
/// sense that they are visible and retryable, and neither is ever rewritten as
/// `completed` without a fresh transfer.
enum DownloadPersistedStatus {
  queued,
  downloading,
  completed,
  failed,
  canceled,
  interrupted,
  missing;
}

/// One row per audio file this app owns, keyed by the *Spotify track id*.
///
/// Identity deliberately lives here and nowhere else: a track appearing in
/// three playlists gets one row, and the playlists each get a membership row
/// in [PlaylistDownloadTable]. `filePath` is recorded rather than recomputed,
/// which is what lets "is this downloaded?" stop being a name match over the
/// whole local library (the ~1.5–2ms per track-change scan measured at 5,000
/// files in `.ai/AUDIT_STATE.md`).
///
/// `trackData` is the full [SpotubeFullTrackObject] so a mirrored playlist can
/// be rendered and re-downloaded without the network; the same TEXT-JSON
/// approach as [AudioPlayerStateTable.tracks].
class TrackDownloadTable extends Table {
  TextColumn get trackId => text().unique()();
  TextColumn get filePath => text()();
  TextColumn get baseName => text()();
  TextColumn get status => textEnum<DownloadPersistedStatus>()();
  TextColumn get error => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  IntColumn get updatedAtMs => integer()();
  TextColumn get trackData => text()();
}
