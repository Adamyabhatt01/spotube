import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/playback_cache_mirror.dart';

/// Recency of the cached track files this process has served.
///
/// A file's mtime says when it was written, not when it was last played, and
/// touching it on play would rewrite the "date added" the local-library view
/// shows for the cache folder. So the playback server records each serve here
/// and [enforceCacheQuota] ranks by `max(mtime, lastServed)`.
///
/// In-process only: after a restart the previous session's plays are unknown,
/// which costs at worst an avoidable re-download, never correctness.
class MusicCacheUsage {
  static const _maxTracked = 2048;

  /// Access-ordered: [markServed] re-inserts, so the first key is the least
  /// recently served path this process has touched.
  static final LinkedHashMap<String, DateTime> _servedAt =
      LinkedHashMap<String, DateTime>();

  static void markServed(String path) {
    _servedAt.remove(path);
    _servedAt[path] = DateTime.now();
    if (_servedAt.length > _maxTracked) _servedAt.remove(_servedAt.keys.first);
  }

  static DateTime? lastServed(String path) => _servedAt[path];

  @visibleForTesting
  static void resetForTest() => _servedAt.clear();
}

/// How long a `.part` has to sit untouched before [sweepIncompleteMirrors]
/// treats it as abandoned. Far past any real mirror — one continuous write of
/// a few megabytes — and short enough that a crash stops costing disk the
/// moment the app starts again.
const staleMirrorWindow = Duration(minutes: 10);

/// What one pass of [enforceCacheQuota] or [sweepIncompleteMirrors] removed.
class CacheDiskReport {
  const CacheDiskReport({required this.removedFiles, required this.freedBytes});

  final int removedFiles;
  final int freedBytes;

  static const empty = CacheDiskReport(removedFiles: 0, freedBytes: 0);

  bool get didWork => removedFiles > 0;

  @override
  String toString() => 'removed $removedFiles file(s), freed ${freedBytes}B';
}

/// Trim the music cache in [dir] down to [limitBytes], oldest-served first.
///
/// A `limitBytes` of 0 — the default — returns immediately, so an opted-out
/// user's cache keeps the pre-existing unbounded behavior.
///
/// [pinnedPaths] are never removed. Beyond those, no separate "in use"
/// registry is needed: mpv HEADs a URL before it GETs it and pre-warms the
/// queue head the same way, so the active track and the next ones were served
/// moments ago and sit at the hot end of [MusicCacheUsage]. The caller pins the
/// file it just finalized, which has been served zero times.
Future<CacheDiskReport> enforceCacheQuota({
  required Directory dir,
  required int limitBytes,
  Set<String> pinnedPaths = const {},
}) async {
  if (limitBytes <= 0) return CacheDiskReport.empty;
  if (!await dir.exists()) return CacheDiskReport.empty;

  final entries = <_CachedFile>[];
  var total = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    // A mirror in flight is not a cached track yet, and deleting it would only
    // make the next attempt start over.
    if (entity.path.endsWith('.part') ||
        PlaybackCacheMirror.isMirroring(entity.path)) {
      continue;
    }
    final stat = entity.statSync();
    if (stat.type != FileSystemEntityType.file) continue;
    entries.add(_CachedFile(path: entity.path, size: stat.size, stat: stat));
    total += stat.size;
  }

  if (total <= limitBytes) return CacheDiskReport.empty;
  entries.sort((a, b) => a.recency.compareTo(b.recency));

  var removed = 0;
  var freed = 0;
  for (final entry in entries) {
    if (total - freed <= limitBytes) break;
    if (pinnedPaths.contains(entry.path)) continue;
    try {
      await File(entry.path).delete();
    } catch (e, stack) {
      // A file the OS won't release (still open on Windows, or gone already)
      // just stays; the next finalized track reruns the pass.
      AppLogger.reportError(e, stack, 'music cache eviction');
      break;
    }
    freed += entry.size;
    removed++;
  }

  return CacheDiskReport(removedFiles: removed, freedBytes: freed);
}

/// Delete `.part` files left behind by a mirror that never finished — killed
/// app, dropped connection mid-write. Nothing else writes that suffix, and a
/// stale part is never renamed into the cache, so each one is pure waste.
///
/// Only parts untouched for [olderThan] go, since a live mirror keeps
/// appending and another Spotube instance may be mid-write. Even if that
/// window were too short, the cost is a lost cache write: the mirror's own
/// finish step refuses a part whose length doesn't match.
Future<CacheDiskReport> sweepIncompleteMirrors({
  required Directory dir,
  required Duration olderThan,
  DateTime? now,
}) async {
  if (!await dir.exists()) return CacheDiskReport.empty;

  final cutoff = (now ?? DateTime.now()).subtract(olderThan);
  var removed = 0;
  var freed = 0;

  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.part')) continue;
    if (PlaybackCacheMirror.isMirroring(entity.path)) continue;

    final stat = entity.statSync();
    if (stat.type != FileSystemEntityType.file) continue;
    if (!stat.modified.isBefore(cutoff)) continue;

    try {
      await entity.delete();
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'music cache .part sweep');
      continue;
    }
    freed += stat.size;
    removed++;
  }

  return CacheDiskReport(removedFiles: removed, freedBytes: freed);
}

class _CachedFile {
  _CachedFile({required this.path, required this.size, required this.stat});

  final String path;
  final int size;
  final FileStat stat;

  DateTime get recency {
    final served = MusicCacheUsage.lastServed(path);
    if (served == null) return stat.modified;
    return served.isAfter(stat.modified) ? served : stat.modified;
  }
}
