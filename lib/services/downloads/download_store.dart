import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Row-level reads and writes for downloaded tracks and mirrored playlists.
///
/// Pure functions over a supplied [AppDatabase], like
/// `lib/services/metadata/library_snapshot.dart`: this repo has no DAO layer,
/// so providers call straight into the database, and keeping the SQL here lets
/// both the download manager and the playlist providers share one definition of
/// what a persisted download is without importing each other.
///
/// Nothing in here decides *whether* a track should be downloaded; it records
/// what the download manager already decided and answers questions about it.
class DownloadRecord {
  final String trackId;
  final String filePath;
  final String baseName;
  final DownloadPersistedStatus status;
  final String? error;
  final int? sizeBytes;

  /// `SpotubeFullTrackObject.toJson()` encoded, so a mirrored playlist can be
  /// rendered and re-attempted without the network.
  final String trackData;

  const DownloadRecord({
    required this.trackId,
    required this.filePath,
    required this.baseName,
    required this.status,
    required this.trackData,
    this.error,
    this.sizeBytes,
  });

  TrackDownloadTableCompanion toCompanion(int updatedAtMs) {
    return TrackDownloadTableCompanion.insert(
      trackId: trackId,
      filePath: filePath,
      baseName: baseName,
      status: status,
      error: Value(error),
      sizeBytes: Value(sizeBytes),
      updatedAtMs: updatedAtMs,
      trackData: trackData,
    );
  }
}

/// The statuses a row may already have for a write of [to] to be applied.
///
/// `null` means every status may be overwritten. Only `completed` restricts,
/// because it is the one write that has a side effect outside the database:
/// metadata was written into a real file, and a canceled download's worker can
/// still land after the user canceled.
Set<DownloadPersistedStatus>? _overwritableFrom(DownloadPersistedStatus to) {
  return switch (to) {
    DownloadPersistedStatus.completed => const {
        DownloadPersistedStatus.queued,
        DownloadPersistedStatus.downloading,
        DownloadPersistedStatus.completed,
        DownloadPersistedStatus.failed,
        DownloadPersistedStatus.interrupted,
        DownloadPersistedStatus.missing,
      },
    _ => null,
  };
}

/// Records freshly queued downloads, leaving any existing row untouched.
///
/// Insert-or-ignore rather than an upsert on purpose: a row that already exists
/// describes work that is in flight or already finished, and re-queuing the same
/// track (it can arrive from a second playlist, or from a re-opened playlist)
/// must not reset that to `queued` and make a completed file look pending.
///
/// One `batch()` per call so a 500-track enqueue is 500 prepared-statement
/// rows over one round-trip instead of 500 sequential awaits.
Future<void> recordQueuedDownloads(
  AppDatabase database,
  List<DownloadRecord> records,
) async {
  if (records.isEmpty) return;
  await database.batch((batch) {
    final now = DateTime.now().millisecondsSinceEpoch;
    batch.insertAll(
      database.trackDownloadTable,
      [for (final record in records) record.toCompanion(now)],
      mode: InsertMode.insertOrIgnore,
    );
  });
}

/// Persists one status transition, creating the row if it is somehow missing.
///
/// The path and base name travel with every record rather than being read back
/// out of the old row, because they are a pure function of the track and the
/// current settings — `_savePathFor` is the one formula both writers call, so a
/// recompute cannot disagree with what the worker actually wrote.
Future<void> writeDownloadStatus(
  AppDatabase database,
  DownloadRecord record,
) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final overwritableFrom = _overwritableFrom(record.status);
  final companion = record.toCompanion(now);

  await database.into(database.trackDownloadTable).insert(
        companion,
        onConflict: DoUpdate(
          (old) => companion,
          target: [database.trackDownloadTable.trackId],
          where: overwritableFrom == null
              ? null
              : (old) => old.status.isInValues(overwritableFrom),
        ),
      );
}

/// The persisted status of each of [trackIds] that has a row.
Future<Map<String, DownloadPersistedStatus>> persistedStatuses(
  AppDatabase database,
  Iterable<String> trackIds,
) async {
  final ids = trackIds.toSet();
  if (ids.isEmpty) return const {};
  final rows = await (database.select(database.trackDownloadTable)
        ..where((t) => t.trackId.isIn(ids)))
      .get();
  return {for (final row in rows) row.trackId: row.status};
}

Future<TrackDownloadTableData?> downloadOfTrack(
  AppDatabase database,
  String trackId,
) {
  return (database.select(database.trackDownloadTable)
        ..where((t) => t.trackId.equals(trackId))
        ..limit(1))
      .getSingleOrNull();
}

/// Live view of one track's download state, for per-row UI.
Stream<TrackDownloadTableData?> watchDownloadOfTrack(
  AppDatabase database,
  String trackId,
) {
  return (database.select(database.trackDownloadTable)
        ..where((t) => t.trackId.equals(trackId))
        ..limit(1))
      .watchSingleOrNull();
}

Future<List<TrackDownloadTableData>> downloadsIn(
  AppDatabase database,
  Set<DownloadPersistedStatus> statuses,
) {
  return (database.select(database.trackDownloadTable)
        ..where((t) => t.status.isInValues(statuses)))
      .get();
}

/// Anything still marked in flight belongs to a process that is gone.
///
/// One statement, so a killed app can never leave a row that looks like an
/// active download; `interrupted` is deliberately its own state rather than
/// `failed`, because nothing went wrong except that we stopped watching.
Future<int> markInFlightAsInterrupted(AppDatabase database) async {
  return (database.update(database.trackDownloadTable)
        ..where((t) => t.status.isInValues(const {
              DownloadPersistedStatus.queued,
              DownloadPersistedStatus.downloading,
            })))
      .write(
    const TrackDownloadTableCompanion(
      status: Value(DownloadPersistedStatus.interrupted),
    ),
  );
}

Future<void> markDownloadsMissing(
  AppDatabase database,
  Iterable<String> trackIds,
) async {
  final ids = trackIds.toSet();
  if (ids.isEmpty) return;
  await (database.update(database.trackDownloadTable)
        ..where((t) => t.trackId.isIn(ids)))
      .write(
    const TrackDownloadTableCompanion(
      status: Value(DownloadPersistedStatus.missing),
    ),
  );
}

/// Records [trackIds] as members of [playlistId] without disturbing what is
/// already there.
///
/// Used when a download is started from a playlist page: one row per track,
/// appended after the current order. [writePlaylistMembership] later rewrites
/// the whole order from Spotify's answer, so an appended position is a
/// placeholder for display and never an assertion about upstream's order.
Future<void> attachTracksToPlaylist(
  AppDatabase database, {
  required String playlistId,
  required List<String> trackIds,
}) async {
  if (trackIds.isEmpty) return;
  final existing = await playlistMembership(database, playlistId);
  final held = existing.map((row) => row.trackId).toSet();
  final lastPosition = existing.isEmpty ? -1 : existing.last.position;
  final now = DateTime.now().millisecondsSinceEpoch;

  var position = lastPosition + 1;
  final toInsert = <PlaylistDownloadTableCompanion>[];
  for (final trackId in trackIds) {
    if (held.contains(trackId)) continue;
    toInsert.add(
      PlaylistDownloadTableCompanion.insert(
        playlistId: playlistId,
        trackId: trackId,
        position: position++,
        addedAtMs: now,
      ),
    );
  }
  if (toInsert.isEmpty) return;

  // The composite unique index makes a duplicate membership impossible rather
  // than merely unlikely; a second download of the same track from the same
  // playlist is a no-op.
  await database.batch(
    (batch) => batch.insertAll(
      database.playlistDownloadTable,
      toInsert,
      mode: InsertMode.insertOrIgnore,
    ),
  );
}

/// Replaces a playlist's membership with [trackIds], in that order.
///
/// [addedAtMs] is carried over for tracks that were already present, so
/// re-syncing does not make an old membership look new. Identity is the Spotify
/// track id only: a renamed playlist or track keeps its rows.
///
/// The whole list is rewritten inside one transaction because the order is the
/// payload — a partial write would leave two tracks claiming one position.
Future<void> writePlaylistMembership(
  AppDatabase database, {
  required String playlistId,
  required List<String> trackIds,
}) async {
  final existing = await (database.select(database.playlistDownloadTable)
        ..where((t) => t.playlistId.equals(playlistId)))
      .get();
  final addedAtByTrackId = {
    for (final row in existing) row.trackId: row.addedAtMs,
  };
  final now = DateTime.now().millisecondsSinceEpoch;

  // One delete + one prepared-statement insert per row, over a single
  // round-trip. A 500-track rewrite is 500 rows in the batch instead of
  // 500 sequential `await insert` calls inside a transaction.
  final membership = database.playlistDownloadTable;
  await database.batch((batch) {
    batch.deleteWhere(membership, (t) => t.playlistId.equals(playlistId));
    batch.insertAll(
      membership,
      [
        for (var position = 0; position < trackIds.length; position++)
          // A caller repeating a track id is a listing that mentions it twice;
          // the first occurrence keeps its place.
          PlaylistDownloadTableCompanion.insert(
            playlistId: playlistId,
            trackId: trackIds[position],
            position: position,
            addedAtMs: addedAtByTrackId[trackIds[position]] ?? now,
          ),
      ],
      mode: InsertMode.insertOrIgnore,
    );
  });
}

Future<List<PlaylistDownloadTableData>> playlistMembership(
  AppDatabase database,
  String playlistId,
) {
  return (database.select(database.playlistDownloadTable)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();
}

Stream<List<PlaylistDownloadTableData>> watchPlaylistMembership(
  AppDatabase database,
  String playlistId,
) {
  return (database.select(database.playlistDownloadTable)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .watch();
}

/// One row of a mirrored playlist: where Spotify puts the track, and what this
/// app knows about its file.
///
/// The download half is nullable because membership is written before the first
/// transfer is recorded, and because a track can be a member of a mirrored
/// playlist without ever having been downloaded here.
class MirroredPlaylistTrack {
  final PlaylistDownloadTableData membership;
  final TrackDownloadTableData? download;

  const MirroredPlaylistTrack({
    required this.membership,
    this.download,
  });

  String get trackId => membership.trackId;

  /// The metadata stored with the download row, or null when there is none.
  ///
  /// A mirrored playlist's rows all have a download row (its sync queues
  /// anything without one), so this is the difference between rendering the
  /// playlist from the database and needing Spotify for it.
  SpotubeFullTrackObject? get track {
    final data = download?.trackData;
    if (data == null) return null;
    try {
      return SpotubeFullTrackObject.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
    } on FormatException {
      // A row written by a newer build, or truncated by a bug: the track is
      // still a member, it just cannot be shown with a title.
      return null;
    }
  }
}

/// A mirrored playlist as one ordered list, joined to what is known about each
/// track's file, live.
///
/// One join rather than a query per row: a mirrored playlist is rendered as a
/// whole, and this is what lets it render with no network at all.
Stream<List<MirroredPlaylistTrack>> watchMirroredPlaylist(
  AppDatabase database,
  String playlistId,
) {
  final membership = database.playlistDownloadTable;
  final downloads = database.trackDownloadTable;
  return (database.select(membership).join([
    leftOuterJoin(
      downloads,
      downloads.trackId.equalsExp(membership.trackId),
    ),
  ])
        ..where(membership.playlistId.equals(playlistId))
        ..orderBy([OrderingTerm.asc(membership.position)]))
      .watch()
      .map((rows) => [
            for (final row in rows)
              MirroredPlaylistTrack(
                membership: row.readTable(membership),
                download: row.readTableOrNull(downloads),
              ),
          ]);
}

/// The header row for one mirrored playlist, or null if it never was one.
Future<PlaylistDownloadMirrorTableData?> playlistMirror(
  AppDatabase database,
  String playlistId,
) {
  return (database.select(database.playlistDownloadMirrorTable)
        ..where((t) => t.playlistId.equals(playlistId))
        ..limit(1))
      .getSingleOrNull();
}

/// Every mirrored playlist that still holds [trackId].
///
/// The refcount question the deletion rule depends on: a track dropped from one
/// playlist is still a member of another, and no caller of this is allowed to
/// treat an empty result as license to delete anything.
Future<Set<String>> playlistsHoldingTrack(
  AppDatabase database,
  String trackId,
) async {
  final rows = await (database.select(database.playlistDownloadTable)
        ..where((t) => t.trackId.equals(trackId)))
      .get();
  return {for (final row in rows) row.playlistId};
}

/// Whether the user ever mirrored [playlistId] by downloading it.
///
/// The gate every automatic path goes through: opening, playing or browsing a
/// playlist must not turn it into one the app keeps downloading.
Future<bool> isPlaylistMirrored(
  AppDatabase database,
  String playlistId,
) async {
  final row = await (database.select(database.playlistDownloadMirrorTable)
        ..where((t) => t.playlistId.equals(playlistId))
        ..limit(1))
      .getSingleOrNull();
  return row != null;
}

Future<void> writePlaylistMirror(
  AppDatabase database, {
  required String playlistId,
  required String playlistData,
  required int trackCount,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final companion = PlaylistDownloadMirrorTableCompanion.insert(
    playlistId: playlistId,
    playlistData: playlistData,
    trackCount: Value(trackCount),
    syncedAtMs: now,
  );
  await database.into(database.playlistDownloadMirrorTable).insert(
        companion,
        onConflict: DoUpdate(
          (old) => companion,
          target: [database.playlistDownloadMirrorTable.playlistId],
        ),
      );
}

/// Header rows for every mirrored playlist, in id order.
Stream<List<PlaylistDownloadMirrorTableData>> watchPlaylistMirrors(
  AppDatabase database,
) {
  return (database.select(database.playlistDownloadMirrorTable)
        ..orderBy([(t) => OrderingTerm.asc(t.playlistId)]))
      .watch();
}

Future<List<PlaylistDownloadMirrorTableData>> playlistMirrors(
  AppDatabase database,
) {
  return (database.select(database.playlistDownloadMirrorTable)
        ..orderBy([(t) => OrderingTerm.asc(t.playlistId)]))
      .get();
}
