import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/downloads/local_library_wipe.dart';
import 'package:spotube/services/logger/logger.dart';

/// What a "delete all downloads" action would remove.
///
/// [files] only contains paths inside the two roots the app owns, so the
/// confirmation can state an exact file count and the wipe can never touch a
/// user's own library folders.
class DownloadWipePlan {
  final List<String> files;
  final int bytes;
  final bool hasRecords;
  final String cacheRoot;

  const DownloadWipePlan({
    required this.files,
    required this.bytes,
    required this.hasRecords,
    required this.cacheRoot,
  });
}

/// Reads the download records and resolves which files the app may delete.
Future<DownloadWipePlan> planDownloadWipe({
  required AppDatabase database,
  required String downloadRoot,
  required String cacheRoot,
  required List<String> libraryLocations,
}) async {
  final rows = await allDownloads(database);
  final targets = selectFilesToDelete(
    filePaths: rows.map((row) => row.filePath),
    downloadRoot: downloadRoot,
    cacheRoot: cacheRoot,
    libraryLocations: libraryLocations,
  );
  final targetPaths = targets.toSet();
  final bytes = sumDownloadedBytes([
    for (final row in rows)
      if (targetPaths.contains(p.normalize(row.filePath))) row.sizeBytes,
  ]);

  return DownloadWipePlan(
    files: targets,
    bytes: bytes,
    hasRecords: rows.isNotEmpty,
    cacheRoot: cacheRoot,
  );
}

/// Deletes the planned files and the music cache.
///
/// Records must already be gone (see `PlaylistMirrorService.forgetEverything`),
/// otherwise a background sync could rewrite a file behind the wipe. Returns
/// the number of files that could not be removed.
Future<int> executeDownloadWipe(DownloadWipePlan plan) async {
  if (plan.cacheRoot.isNotEmpty) {
    final cache = Directory(plan.cacheRoot);
    if (cache.existsSync()) {
      await cache.delete(recursive: true);
    }
  }
  return _deleteInWaves(plan.files);
}

/// File deletions go in bounded waves.
///
/// `File.delete` is one syscall per file and a downloaded library can hold
/// thousands of them; awaiting a wave at a time yields the isolate between
/// groups instead of blocking the UI for the whole walk. Already-absent files
/// count as success — that is the outcome the wipe wanted.
Future<int> _deleteInWaves(List<String> paths) async {
  const waveSize = 32;
  var failed = 0;
  for (var i = 0; i < paths.length; i += waveSize) {
    final wave = paths.sublist(i, min(i + waveSize, paths.length));
    final results = await Future.wait([
      for (final path in wave)
        () async {
          try {
            final file = File(path);
            if (!await file.exists()) return true;
            await file.delete();
            return true;
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            return false;
          }
        }(),
    ]);
    failed += results.where((deleted) => !deleted).length;
  }
  return failed;
}
