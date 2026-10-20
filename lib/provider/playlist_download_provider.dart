import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';

/// Fetches one page of a playlist's tracks for background synchronization.
typedef PlaylistTracksPageFetcher
    = Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> Function(
  String playlistId,
  int offset,
  int limit,
);

/// Keeps downloaded playlists looking like the same playlist on Spotify.
///
/// - [mirror] records an explicit whole-playlist download.
/// - [reconcile] refreshes a mirrored playlist when its page loads.
/// - [setAutoDownload] opts a playlist into background maintenance.
/// - [syncAutoDownloadPlaylists] walks every opted-in playlist page-by-page.
///
/// Identity is the Spotify playlist id throughout; the name is payload, never a
/// key. Nothing here deletes an audio file, and nothing here deletes the record
/// of one either: a `track_download` row outlives the membership that created it
/// because it is the app's list of the files it owns.
/// Thrown inside a guarded write when the playlist was deleted after the job
/// started. It rolls the transaction back and is treated as a clean stop.
class _PlaylistSyncAborted implements Exception {
  const _PlaylistSyncAborted();
}

class PlaylistMirrorService {
  final AppDatabase database;
  final DownloadManagerNotifier downloads;
  final PlaylistTracksPageFetcher? fetchTracksPage;

  /// Test seam: production uses two minutes between successful background
  /// runs. Connectivity-triggered retries after a failure ignore it.
  final Duration autoSyncThrottle;

  /// Whether a failed background pass schedules a bounded retry. Production
  /// enables it so a transient playlist-fetch error (the plugin occasionally
  /// returns 504) does not leave the rest of the playlist unchecked until the
  /// next launch. Tests default off so they own the timing.
  final bool retryFailedAutoSync;

  /// First backoff interval; each retry doubles it. Test seam only.
  final Duration autoSyncRetryBaseDelay;

  PlaylistMirrorService({
    required this.database,
    required this.downloads,
    this.fetchTracksPage,
    this.autoSyncThrottle = const Duration(minutes: 2),
    this.retryFailedAutoSync = false,
    this.autoSyncRetryBaseDelay = const Duration(seconds: 30),
  });

  static const int _autoSyncPageSize = 50;
  static const int _validationWaveSize = 32;
  static const int _maxAutoSyncRetries = 3;

  /// Playlists with a sync currently running, so opening the same page twice
  /// cannot interleave two writers of one membership list.
  final Set<String> _inFlight = {};

  /// Deletion generations. A job captures the value when it starts and checks
  /// it before every playlist-scoped write; [forget] bumps it first.
  final Map<String, int> _generations = {};

  /// One deferred follow-up per playlist when a sync request lands while that
  /// playlist is already being walked (a page reconcile racing the toggle, for
  /// example). The in-flight job schedules it again as it leaves.
  final Map<String, SpotubeSimplePlaylistObject> _deferredAutoSync = {};

  Future<void>? _autoSyncRun;
  bool _autoSyncRetryPending = false;
  bool _lastAutoSyncFailed = false;
  DateTime? _lastAutoSyncSuccessAt;
  Timer? _autoSyncRetryTimer;
  int _autoSyncFailureCount = 0;

  /// Cancels any pending background retry. The provider owns this service for
  /// the app lifetime; tests construct it directly and leave retries off.
  void dispose() {
    _autoSyncRetryTimer?.cancel();
    _autoSyncRetryTimer = null;
  }

  int _generationOf(String playlistId) => _generations[playlistId] ?? 0;

  bool _isCurrent(String playlistId, int generation) =>
      _generationOf(playlistId) == generation;

  /// Records [playlist] as mirrored, with [tracks] as its membership.
  ///
  /// Called for a download of the whole collection only. Downloading three
  /// tracks out of five hundred records those three as members — that is what
  /// [DownloadManagerNotifier.addAllToQueue]'s `collectionId` does — but it does
  /// not opt the user into keeping five hundred files current, which is the
  /// difference between "I downloaded some of this" and "this playlist is mine".
  Future<void> mirror(
    SpotubeSimplePlaylistObject playlist,
    List<SpotubeFullTrackObject> tracks,
  ) async {
    final generation = _generationOf(playlist.id);
    try {
      await _settle(
        playlist,
        tracks: tracks,
        total: tracks.length,
        generation: generation,
      );
    } on _PlaylistSyncAborted {
      return;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Enables or disables automatic downloads for [playlist].
  ///
  /// Enabling creates the mirror header immediately and starts a background
  /// walk. Disabling only clears the flag: membership, track rows and files
  /// are deliberately left alone.
  Future<void> setAutoDownload(
    SpotubeSimplePlaylistObject playlist,
    bool enabled,
  ) async {
    final generation = _generationOf(playlist.id);
    try {
      final existing = await playlistMirror(database, playlist.id);
      if (!_isCurrent(playlist.id, generation)) return;
      await _guardWrite(
        playlist.id,
        generation,
        () => writePlaylistMirror(
          database,
          playlistId: playlist.id,
          playlistData: jsonEncode(playlist.toJson()),
          trackCount: existing?.trackCount ?? 0,
          autoDownload: enabled,
        ),
      );
      if (enabled && _isCurrent(playlist.id, generation)) {
        unawaited(syncAutoDownloadPlaylist(playlist));
      }
    } on _PlaylistSyncAborted {
      return;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Updates the cached metadata of a mirrored playlist after a rename/edit.
  ///
  /// No-op when the playlist was never mirrored. Membership and flags stay put.
  Future<void> updateMetadata(SpotubeSimplePlaylistObject playlist) async {
    try {
      await updatePlaylistMirrorData(
        database,
        playlistId: playlist.id,
        playlistData: jsonEncode(playlist.toJson()),
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Removes mirror metadata for [playlistId] without touching downloads.
  Future<void> forget(String playlistId) async {
    _generations[playlistId] = _generationOf(playlistId) + 1;
    try {
      await deletePlaylistMirror(database, playlistId);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Refreshes a mirrored playlist from [firstPage], then pages through the
  /// rest in the background at the same page size.
  ///
  /// Never fetches for a playlist the user did not mirror. The header is
  /// updated early so a rename/total shows even if paging dies; the membership
  /// is replaced afterwards with the pages that actually arrived, never a hole.
  Future<void> reconcile(
    SpotubeSimplePlaylistObject playlist,
    SpotubePaginationResponseObject<SpotubeFullTrackObject> firstPage,
    Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> Function(
      int offset,
      int limit,
    ) fetchPage,
  ) async {
    // Capture before the mirror check: a delete between the check and the
    // first write must invalidate this job.
    final generation = _generationOf(playlist.id);
    if (_inFlight.contains(playlist.id)) return;
    if (!await isPlaylistMirrored(database, playlist.id)) return;
    if (!_isCurrent(playlist.id, generation)) return;

    _inFlight.add(playlist.id);
    try {
      if (!_isCurrent(playlist.id, generation)) return;

      // Header alone: this makes a rename or new total visible even if the
      // paging walk below dies halfway, without paying a full membership
      // rewrite at first paint.
      await _guardWrite(
        playlist.id,
        generation,
        () => writePlaylistMirror(
          database,
          playlistId: playlist.id,
          playlistData: jsonEncode(playlist.toJson()),
          trackCount: firstPage.total,
        ),
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

      if (!_isCurrent(playlist.id, generation)) return;
      await _guardWrite(
        playlist.id,
        generation,
        () => writePlaylistMembership(
          database,
          playlistId: playlist.id,
          trackIds: [for (final track in seen) track.id],
        ),
      );
      if (!_isCurrent(playlist.id, generation)) return;
      await _queueUnrecorded(playlist, seen, generation);
    } on _PlaylistSyncAborted {
      return;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    } finally {
      _leaveInFlight(playlist.id);
    }
  }

  /// Releases the one-writer slot and runs a sync that was requested while
  /// this playlist was busy (the toggle landing during a page reconcile).
  void _leaveInFlight(String playlistId) {
    _inFlight.remove(playlistId);
    final deferred = _deferredAutoSync.remove(playlistId);
    if (deferred != null) {
      unawaited(
        _syncAutoDownloadPlaylist(deferred, _generationOf(playlistId)),
      );
    }
  }

  /// Runs one background synchronization pass over every opted-in playlist.
  ///
  /// Overlapping calls return the existing future. [retryIfBusy] is used by
  /// the connectivity listener: if restoration arrives during an offline-fated
  /// run, a retry is queued only when that run actually fails.
  Future<void> syncAutoDownloadPlaylists({
    bool force = false,
    bool retryIfBusy = false,
  }) {
    final active = _autoSyncRun;
    if (active != null) {
      if (retryIfBusy) _autoSyncRetryPending = true;
      return active;
    }

    final now = DateTime.now();
    final lastSuccess = _lastAutoSyncSuccessAt;
    if (!force &&
        !_lastAutoSyncFailed &&
        lastSuccess != null &&
        now.difference(lastSuccess) < autoSyncThrottle) {
      return Future.value();
    }

    // A manual/connectivity trigger supersedes a pending backoff attempt.
    _autoSyncRetryTimer?.cancel();
    _autoSyncRetryTimer = null;

    final future = _runAutoSync();
    late final Future<void> tracked;
    tracked = future.whenComplete(() {
      if (identical(_autoSyncRun, tracked)) _autoSyncRun = null;
      if (_autoSyncRetryPending) {
        _autoSyncRetryPending = false;
        if (_lastAutoSyncFailed) {
          unawaited(syncAutoDownloadPlaylists(force: true));
        }
      }
    });
    _autoSyncRun = tracked;
    return tracked;
  }

  Future<void> _runAutoSync() async {
    var failed = false;
    try {
      final headers = await autoDownloadPlaylistMirrors(database);
      for (final header in headers) {
        final generation = _generationOf(header.playlistId);
        try {
          final decoded = jsonDecode(header.playlistData);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Playlist mirror payload is not a map');
          }
          final playlist = SpotubeSimplePlaylistObject.fromJson(decoded);
          if (!await _syncAutoDownloadPlaylist(playlist, generation)) {
            failed = true;
          }
        } catch (e, stack) {
          failed = true;
          AppLogger.reportError(e, stack);
        }
      }
    } catch (e, stack) {
      failed = true;
      AppLogger.reportError(e, stack);
    }

    _lastAutoSyncFailed = failed;
    if (failed) {
      _scheduleAutoSyncRetry();
    } else {
      _autoSyncFailureCount = 0;
      _lastAutoSyncSuccessAt = DateTime.now();
      _autoSyncRetryTimer?.cancel();
      _autoSyncRetryTimer = null;
    }
  }

  /// Retries a failed pass after a short backoff (30s, 60s, 120s).
  ///
  /// Bounded: a permanently broken plugin must not turn this into an endless
  /// polling loop. Connectivity restoration and the next launch still retry
  /// after the budget is spent.
  void _scheduleAutoSyncRetry() {
    if (!retryFailedAutoSync || _autoSyncFailureCount >= _maxAutoSyncRetries) {
      return;
    }
    final attempt = _autoSyncFailureCount++;
    final delay = autoSyncRetryBaseDelay * (1 << attempt);
    _autoSyncRetryTimer?.cancel();
    _autoSyncRetryTimer = Timer(delay, () {
      _autoSyncRetryTimer = null;
      unawaited(syncAutoDownloadPlaylists(force: true));
    });
  }

  /// Synchronizes one playlist. Public so enabling the toggle can start work
  /// without waiting for the next startup.
  Future<void> syncAutoDownloadPlaylist(
    SpotubeSimplePlaylistObject playlist,
  ) async {
    final generation = _generationOf(playlist.id);
    await _syncAutoDownloadPlaylist(playlist, generation);
  }

  /// Returns false only for a real failure; deletion/disable are clean stops.
  Future<bool> _syncAutoDownloadPlaylist(
    SpotubeSimplePlaylistObject playlist,
    int generation,
  ) async {
    if (_inFlight.contains(playlist.id)) {
      _deferredAutoSync[playlist.id] = playlist;
      return true;
    }
    _inFlight.add(playlist.id);

    final validity = <String, bool>{};
    try {
      if (!await _stillWanted(playlist.id, generation)) return true;

      final fetchPage = fetchTracksPage;
      if (fetchPage == null) {
        throw StateError('No playlist page fetcher configured');
      }

      final trackIds = <String>[];
      final seen = <String>{};
      var offset = 0;
      var total = 0;

      while (true) {
        final page = await fetchPage(
          playlist.id,
          offset,
          _autoSyncPageSize,
        );
        total = page.total;

        for (final track in page.items) {
          if (seen.add(track.id)) trackIds.add(track.id);
        }

        if (!await _queueAutoDownloadTracks(
          page.items,
          playlist.id,
          generation,
          validity,
        )) {
          return true;
        }

        if (!page.hasMore) break;

        final next = page.nextOffset;
        if (next == null || next <= offset) {
          // A complete membership write needs every page. Without forward
          // progress, keep the old membership and retry on a later trigger.
          throw StateError(
            'Playlist ${playlist.id} reported more pages without an offset',
          );
        }
        offset = next;
      }

      if (!await _stillWanted(playlist.id, generation)) return true;

      await database.transaction(() async {
        if (!await _stillWanted(playlist.id, generation)) {
          throw const _PlaylistSyncAborted();
        }
        await writePlaylistMirror(
          database,
          playlistId: playlist.id,
          playlistData: jsonEncode(playlist.toJson()),
          trackCount: total,
        );
        if (!await _stillWanted(playlist.id, generation)) {
          throw const _PlaylistSyncAborted();
        }
        await writePlaylistMembership(
          database,
          playlistId: playlist.id,
          trackIds: trackIds,
        );
        if (!await _stillWanted(playlist.id, generation)) {
          throw const _PlaylistSyncAborted();
        }
      });
      return true;
    } on _PlaylistSyncAborted {
      return true;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return false;
    } finally {
      _leaveInFlight(playlist.id);
    }
  }

  Future<bool> _stillWanted(String playlistId, int generation) async {
    if (!_isCurrent(playlistId, generation)) return false;
    try {
      return await isPlaylistAutoDownloadEnabled(database, playlistId);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return false;
    }
  }

  /// Queues page tracks whose global download row is absent or invalid.
  ///
  /// Membership is written once, after the whole playlist was read, so the
  /// enqueue deliberately omits `collectionId`.
  Future<bool> _queueAutoDownloadTracks(
    List<SpotubeFullTrackObject> tracks,
    String playlistId,
    int generation,
    Map<String, bool> validityCache,
  ) async {
    if (tracks.isEmpty) return true;
    if (!await _stillWanted(playlistId, generation)) return false;

    final rows = await downloadsOfTracks(
      database,
      [for (final track in tracks) track.id],
    );

    final newCandidates = <SpotubeFullTrackObject>[];
    final retryCandidates = <SpotubeFullTrackObject>[];
    final liveRetries = <SpotubeFullTrackObject>[];
    final invalidCompleted = <String>[];

    // Bound concurrent filesystem probes; a 50-track page does not open every
    // handle at once.
    final paths = [
      for (final row in rows.values)
        if (!validityCache.containsKey(row.filePath)) row.filePath,
    ];
    for (var i = 0; i < paths.length; i += _validationWaveSize) {
      final wave = paths.skip(i).take(_validationWaveSize);
      await Future.wait([
        for (final path in wave)
          _fileIsValid(path).then((valid) => validityCache[path] = valid),
      ]);
    }

    for (final track in tracks) {
      final row = rows[track.id];
      final live = downloads.getTaskByTrackId(track.id);
      final status = row?.status;

      // Cancellation is the user's decision; a restart or a sync must not
      // undo it.
      if (status == DownloadPersistedStatus.canceled) continue;

      final valid = row != null && (validityCache[row.filePath] ?? false);

      if (live != null) {
        // Only a failed live task can be revived. A completed row with a real
        // file is already the result the sync wants, even if an old task for
        // the same track is still sitting in the failed state.
        if (live.status != DownloadStatus.failed) continue;
        if (status == DownloadPersistedStatus.completed && valid) continue;
        liveRetries.add(track);
        continue;
      }

      if (row == null) {
        newCandidates.add(track);
        continue;
      }

      if (status == DownloadPersistedStatus.completed) {
        if (valid) {
          // Global row + real non-empty file: reuse it for every playlist.
          continue;
        }
        // A vanished/empty completed file is not a completed download.
        invalidCompleted.add(track.id);
        if (await _fileExists(row.filePath)) {
          // A zero-length/partial file still occupies the normal destination;
          // the retry must not mistake it for output or overwrite it.
          retryCandidates.add(track);
        } else {
          newCandidates.add(track);
        }
        continue;
      }

      if (status == DownloadPersistedStatus.missing) {
        if (valid || await _fileExists(row.filePath)) {
          retryCandidates.add(track);
        } else {
          // Nothing on disk; the normal destination is safe to use.
          newCandidates.add(track);
        }
        continue;
      }

      // failed | interrupted | stale queued/downloading | missing with a file:
      // a previous attempt did not finish. Never trust its leftover file.
      // The retry gets an id-suffixed path, so a partial or colliding file is
      // neither mistaken for the output nor overwritten.
      retryCandidates.add(track);
    }

    if (invalidCompleted.isNotEmpty) {
      if (!await _stillWanted(playlistId, generation)) return false;
      await markDownloadsMissing(database, invalidCompleted);
    }

    if (newCandidates.isNotEmpty) {
      if (!await _stillWanted(playlistId, generation)) return false;
      downloads.addAllToQueue(newCandidates);
    }

    if (retryCandidates.isNotEmpty) {
      if (!await _stillWanted(playlistId, generation)) return false;
      downloads.addAllToQueue(
        retryCandidates,
        useRetryFilePath: true,
      );
    }

    for (final track in liveRetries) {
      if (!await _stillWanted(playlistId, generation)) return false;
      downloads.retry(track, useRetryFilePath: true);
    }
    return true;
  }

  /// Existence + non-empty length. This is not codec/checksum validation: a
  /// truncated-but-non-empty file can still pass, which is the repo's
  /// established "file is present" rule.
  Future<bool> _fileIsValid(String path) async {
    if (path.isEmpty) return false;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Whether a retry must avoid [path] because something already occupies it,
  /// even if that something is empty or unreadable.
  Future<bool> _fileExists(String path) async {
    if (path.isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Replaces the header row and the ordered membership with [tracks], in one
  /// transaction — the order is the payload, so half of it is worth nothing.
  Future<void> _settle(
    SpotubeSimplePlaylistObject playlist, {
    required List<SpotubeFullTrackObject> tracks,
    required int total,
    required int generation,
  }) {
    return database.transaction(() async {
      if (!_isCurrent(playlist.id, generation)) {
        throw const _PlaylistSyncAborted();
      }
      await writePlaylistMirror(
        database,
        playlistId: playlist.id,
        playlistData: jsonEncode(playlist.toJson()),
        trackCount: total,
      );
      if (!_isCurrent(playlist.id, generation)) {
        throw const _PlaylistSyncAborted();
      }
      await writePlaylistMembership(
        database,
        playlistId: playlist.id,
        trackIds: [for (final track in tracks) track.id],
      );
      if (!_isCurrent(playlist.id, generation)) {
        throw const _PlaylistSyncAborted();
      }
    });
  }

  /// Runs one playlist-scoped write in a transaction that rolls back if
  /// [forget] bumps the generation at any point around it.
  Future<void> _guardWrite(
    String playlistId,
    int generation,
    Future<void> Function() write,
  ) {
    return database.transaction(() async {
      if (!_isCurrent(playlistId, generation)) {
        throw const _PlaylistSyncAborted();
      }
      await write();
      if (!_isCurrent(playlistId, generation)) {
        throw const _PlaylistSyncAborted();
      }
    });
  }

  /// Queues the tracks of [tracks] this app has no record of at all.
  ///
  /// Used by page-load reconciliation only. Automatic synchronization uses
  /// [_queueAutoDownloadTracks], which also validates and retries invalid files.
  Future<void> _queueUnrecorded(
    SpotubeSimplePlaylistObject playlist,
    List<SpotubeFullTrackObject> tracks,
    int generation,
  ) async {
    if (!_isCurrent(playlist.id, generation)) return;
    final known = await persistedStatuses(
      database,
      [for (final track in tracks) track.id],
    );
    final missing = [
      for (final track in tracks)
        if (!known.containsKey(track.id)) track,
    ];
    if (missing.isEmpty) return;
    if (!_isCurrent(playlist.id, generation)) return;

    downloads.addAllToQueue(missing);
  }
}

final playlistMirrorServiceProvider = Provider<PlaylistMirrorService>((ref) {
  final service = PlaylistMirrorService(
    database: ref.read(databaseProvider),
    downloads: ref.read(downloadManagerProvider.notifier),
    retryFailedAutoSync: true,
    fetchTracksPage: (playlistId, offset, limit) async {
      final plugin = await ref.read(metadataPluginProvider.future);
      if (plugin == null) {
        throw MetadataPluginException.noDefaultMetadataPlugin();
      }
      // Liked Tracks is synthetic: it has no Spotify playlist endpoint, but
      // the saved-tracks endpoint is the same paged list the page renders.
      final fetchPage = playlistId == likedTracksPlaylistId
          ? () => plugin.user.savedTracks(offset: offset, limit: limit)
          : () => plugin.playlist.tracks(
                playlistId,
                offset: offset,
                limit: limit,
              );
      return runGated(
        ref.read(rateLimitGateProvider.notifier),
        fetchPage,
        maxRetries: maxRateLimitAutoRetries,
      );
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

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

/// Live automatic-download switch for one playlist. Missing header is off.
final playlistAutoDownloadProvider =
    StreamProvider.autoDispose.family<bool, String>(
  (ref, playlistId) =>
      watchPlaylistAutoDownload(ref.watch(databaseProvider), playlistId),
);

/// How many decoded [SpotubeFullTrackObject]s one playlist page keeps in
/// memory. A mirrored playlist re-emits its whole row set whenever any of
/// its tracks changes, and each emission used to pay one JSON decode per
/// row — a 500-track playlist completing downloads one at a time did
/// 500×500 = 250,000 decodes for one screen.
const int _maxDecodeCacheEntries = 2048;

/// The tracks of a mirrored playlist, ready for a list of rows to render.
///
/// Empty when the playlist was never mirrored. A track whose stored JSON this
/// build cannot read is skipped rather than shown as an empty row: the list
/// stays coherent, and the next sync replaces it.
///
/// The decode cache is keyed by `(trackId, updatedAtMs)` because that pair is
/// the whole input to the decode — the same two values always produce the
/// same object, and either changing means the row's payload may have changed
/// too. LRU via insertion order keeps a walk across many playlists bounded.
///
/// One subscription per playlist: the join lives here, and the per-row
/// download status lives on [downloadStateOfProvider], which is a separate
/// drift stream on the primary key. A consumer that needs the whole
/// `MirroredPlaylistTrack` (membership + download row together) should read
/// the raw stream here rather than open a second one.
final mirroredPlaylistTracksProvider = StreamProvider.autoDispose
    .family<List<SpotubeFullTrackObject>, String>((ref, playlistId) {
  final cache = <String, SpotubeFullTrackObject?>{};
  return watchMirroredPlaylist(ref.watch(databaseProvider), playlistId)
      .map((rows) {
    final tracks = <SpotubeFullTrackObject>[];
    for (final row in rows) {
      final download = row.download;
      if (download == null) continue;
      final key = '${download.trackId}#${download.updatedAtMs}';
      SpotubeFullTrackObject? decoded;
      if (cache.containsKey(key)) {
        decoded = cache.remove(key);
      } else {
        decoded = row.track;
        if (cache.length >= _maxDecodeCacheEntries) {
          cache.remove(cache.keys.first);
        }
      }
      cache[key] = decoded;
      if (decoded != null) tracks.add(decoded);
    }
    return tracks;
  });
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
