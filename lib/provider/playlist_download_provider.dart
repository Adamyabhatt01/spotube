import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';

/// Keeps a downloaded playlist looking like the same playlist on Spotify.
///
/// Two entry points, and the difference between them is the whole safety of the
/// feature:
///
/// - [mirror] is what a download of the whole collection calls. It is the only
///   thing that creates a mirror row, so nothing is downloaded or kept in sync
///   because it happened to be browsed.
/// - [reconcile] runs when a playlist page loads, and does nothing at all for a
///   playlist that was never mirrored. For one that was, it rewrites membership
///   to Spotify's current order and starts what is missing.
///
/// Identity is the Spotify playlist id throughout; the name is payload, never a
/// key. Nothing here deletes an audio file, and nothing here deletes the record
/// of one either: a `track_download` row outlives the membership that created it
/// because it is the app's list of the files it owns.
class PlaylistMirrorService {
  final AppDatabase database;
  final DownloadManagerNotifier downloads;

  PlaylistMirrorService({
    required this.database,
    required this.downloads,
  });

  /// Playlists with a sync currently running, so opening the same page twice
  /// cannot interleave two writers of one membership list.
  final Set<String> _inFlight = {};

  /// Records [playlist] as mirrored, with [tracks] as its membership.
  ///
  /// Called for a download of the whole collection only. Downloading three tracks
  /// out of five hundred records those three as members — that is what
  /// [DownloadManagerNotifier.addAllToQueue]'s `collectionId` does — but it does
  /// not opt the user into keeping five hundred files current, which is the
  /// difference between "I downloaded some of this" and "this playlist is mine".
  ///
  /// Starts no transfers: the caller queued the very list it passes here.
  Future<void> mirror(
    SpotubeSimplePlaylistObject playlist,
    List<SpotubeFullTrackObject> tracks,
  ) async {
    try {
      // The header records what this action saw; the first [reconcile] replaces
      // the count with Spotify's own.
      await _settle(playlist, tracks: tracks, total: tracks.length);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Refreshes a mirrored playlist from [firstPage], then pages through the
  /// rest in the background at the same page size.
  ///
  /// Never fetches for a playlist the user did not mirror. A page that fails
  /// leaves behind the membership the earlier pages wrote, so the cached view is
  /// never replaced with a hole.
  ///
  /// One membership write, one `persistedStatuses` query and one
  /// `addAllToQueue` per reconcile — not one per page. A 500-track walk costs
  /// 5 fetches and 3 writes, not 5×3 writes.
  Future<void> reconcile(
    SpotubeSimplePlaylistObject playlist,
    SpotubePaginationResponseObject<SpotubeFullTrackObject> firstPage,
    Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> Function(
      int offset,
      int limit,
    ) fetchPage,
  ) async {
    if (_inFlight.contains(playlist.id)) return;
    if (!await isPlaylistMirrored(database, playlist.id)) return;

    _inFlight.add(playlist.id);
    try {
      // Header alone: this makes a rename or new total visible even if the
      // paging walk below dies halfway, without paying a full membership
      // rewrite at first paint.
      await writePlaylistMirror(
        database,
        playlistId: playlist.id,
        playlistData: jsonEncode(playlist.toJson()),
        trackCount: firstPage.total,
      );

      // A `Set` of track ids across every page: Spotify's paging is not
      // guaranteed disjoint when a collection changes mid-read, and one track
      // claiming two positions is the bug this prevents.
      final seen = List<SpotubeFullTrackObject>.of(firstPage.items);
      final seenIds = seen.map((track) => track.id).toSet();
      var page = firstPage;

      try {
        while (page.hasMore) {
          page = await fetchPage(page.nextOffset ?? seen.length, page.limit);
          for (final track in page.items) {
            if (seenIds.add(track.id)) seen.add(track);
          }
        }
      } catch (e, stack) {
        // Offline, rate-limited, or a plugin with no more pages to give: `seen`
        // holds the prefix that arrived, and the single write below records
        // exactly what the last successful open would have shown.
        AppLogger.reportError(e, stack);
      }

      await writePlaylistMembership(
        database,
        playlistId: playlist.id,
        trackIds: [for (final track in seen) track.id],
      );
      await _queueUnrecorded(playlist, seen);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    } finally {
      _inFlight.remove(playlist.id);
    }
  }

  /// Replaces the header row and the ordered membership with [tracks], in one
  /// transaction — the order is the payload, so half of it is worth nothing.
  Future<void> _settle(
    SpotubeSimplePlaylistObject playlist, {
    required List<SpotubeFullTrackObject> tracks,
    required int total,
  }) {
    return database.transaction(() async {
      await writePlaylistMirror(
        database,
        playlistId: playlist.id,
        playlistData: jsonEncode(playlist.toJson()),
        trackCount: total,
      );
      await writePlaylistMembership(
        database,
        playlistId: playlist.id,
        trackIds: [for (final track in tracks) track.id],
      );
    });
  }

  /// Queues the tracks of [tracks] this app has no record of at all.
  ///
  /// A track with a row in any state is left alone: `completed` is not
  /// re-downloaded, `canceled` is not taken back behind the user's back, and
  /// `failed` waits for the retry its own row offers. Only something never seen
  /// before becomes work.
  ///
  /// Membership is written before anything is queued, so the enqueue's own
  /// attach finds rows already in Spotify's order instead of appending them.
  Future<void> _queueUnrecorded(
    SpotubeSimplePlaylistObject playlist,
    List<SpotubeFullTrackObject> tracks,
  ) async {
    final known = await persistedStatuses(
      database,
      [for (final track in tracks) track.id],
    );
    final missing = [
      for (final track in tracks)
        if (!known.containsKey(track.id)) track,
    ];
    if (missing.isEmpty) return;

    downloads.addAllToQueue(missing, collectionId: playlist.id);
  }
}

final playlistMirrorServiceProvider = Provider<PlaylistMirrorService>(
  (ref) => PlaylistMirrorService(
    database: ref.read(databaseProvider),
    downloads: ref.read(downloadManagerProvider.notifier),
  ),
);

/// What this app knows about one track's file, live.
///
/// A drift stream over the `trackId` primary key, so one finished download
/// updates every row of every playlist that shows the track — and a row that
/// was queued before the app was killed is still here after it.
final downloadStateOfProvider =
    StreamProvider.autoDispose.family<TrackDownloadTableData?, String>((
  ref,
  trackId,
) =>
        watchDownloadOfTrack(ref.watch(databaseProvider), trackId));

/// A mirrored playlist as stored: order, metadata and per-track download state,
/// with no network involved.
final mirroredPlaylistProvider =
    StreamProvider.autoDispose.family<List<MirroredPlaylistTrack>, String>((
  ref,
  playlistId,
) =>
        watchMirroredPlaylist(ref.watch(databaseProvider), playlistId));

/// The tracks of a mirrored playlist, ready for a list of rows to render.
///
/// Empty when the playlist was never mirrored. A track whose stored JSON this
/// build cannot read is skipped rather than shown as an empty row: the list
/// stays coherent, and the next sync replaces it.
final mirroredPlaylistTracksProvider = StreamProvider.autoDispose
    .family<List<SpotubeFullTrackObject>, String>((ref, playlistId) {
  return watchMirroredPlaylist(ref.watch(databaseProvider), playlistId)
      .map((rows) => [
            for (final row in rows)
              if (row.track case final track?) track,
          ]);
});

/// Every playlist the user mirrored, as the objects the Playlists section lists.
final mirroredPlaylistsProvider =
    StreamProvider<List<SpotubeSimplePlaylistObject>>((ref) {
  return watchPlaylistMirrors(ref.watch(databaseProvider)).map((rows) => [
        for (final row in rows)
          SpotubeSimplePlaylistObject.fromJson(
            jsonDecode(row.playlistData) as Map<String, dynamic>,
          ),
      ]);
});
