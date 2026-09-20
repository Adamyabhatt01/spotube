import 'dart:async';
import 'dart:io';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show FrbException;
import 'package:spotube/utils/async_waves.dart';
import 'package:spotube/utils/service_utils.dart';

const supportedAudioTypes = [
  "audio/webm",
  "audio/ogg",
  "audio/mpeg",
  "audio/mp4",
  "audio/opus",
  "audio/wav",
  "audio/aac",
  "audio/flac",
  "audio/x-flac",
  "audio/x-wav",
];

const imgMimeToExt = {
  "image/png": ".png",
  "image/jpeg": ".jpg",
  "image/webp": ".webp",
  "image/gif": ".gif",
};

typedef MetadataFile = ({
  Metadata? metadata,
  File file,
  String? art,
});

/// Maximum metadata reads in flight at once. The previous unbounded
/// `Future.wait` launched one concurrent bridge call per library file
/// (1,000+ on large libraries), spiking CPU/RAM/bridge contention. Waves
/// keep resource usage predictable; elapsed time stays near sequential
/// waves since bridge calls within a wave still overlap.
const _scanWaveSize = 32;

/// Sentinel aborting a scan whose provider was disposed/rebuilt, so stale
/// results can never publish over a newer scan.
class _ScanCancelled implements Exception {
  const _ScanCancelled();
}

/// The temp path an embedded picture is written to.
///
/// Two things the old inline naming got wrong:
/// - the extension came from `imgMimeToExt[...]!`, so an embedded picture in
///   an unlisted type (bmp, apng, tga, ...) threw inside the read and the
///   whole track vanished from the library instead of just losing its cover;
/// - the name was only the sanitized basename, so two files with the same
///   name in different folders shared one art file, and the exists-check
///   froze whichever cover was written first for every other track.
String localArtFilePath(
  String tempDirPath,
  String sourcePath,
  String? mimeType,
) {
  return join(
    tempDirPath,
    "spotube",
    "${ServiceUtils.sanitizeFilename(basenameWithoutExtension(sourcePath))}"
        "-${_pathDigest(sourcePath)}"
        "${imgMimeToExt[mimeType] ?? ".jpg"}",
  );
}

/// Stable 30-bit fingerprint of [path]. Only needs to disambiguate files that
/// already share a basename, and stays below 2^53 so it cannot lose precision
/// on the web build.
String _pathDigest(String path) {
  var hash = 0x811c9dc5 & 0x3FFFFFFF;
  for (final unit in path.codeUnits) {
    hash = (hash * 31 + unit) & 0x3FFFFFFF;
  }
  return hash.toRadixString(16);
}

/// Deletes extracted artwork that no track in [kept] references.
///
/// Orphans are what the file name is made of: `localArtFilePath` hashes the
/// source path one-way, so a deleted, renamed or re-downloaded track leaves a
/// cover behind that nothing can trace back to a missing file. The only rule
/// that works is "this scan did not ask for it" — which is why the keep-set is
/// passed in and why the caller must guarantee a scan that saw every library
/// location.
///
/// Never throws. It runs after the library is already published, and a cover
/// that refused to go away is not worth an error on the next scan.
Future<void> pruneOrphanedArt(
  String tempDirPath,
  Set<String> kept,
) async {
  final artDir = Directory(join(tempDirPath, 'spotube'));
  var removed = 0;
  var freedBytes = 0;
  try {
    if (!await artDir.exists()) return;
    await for (final entity in artDir.list()) {
      if (entity case File(:final path) when !kept.contains(path)) {
        try {
          freedBytes += await entity.length();
          await entity.delete();
          ++removed;
        } catch (_) {
          // In use by a decode, or vanished between the listing and the
          // delete. The next scan picks it up again.
        }
      }
    }
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
  }
  if (removed > 0) {
    PerfCounters.note('local.artPruned', removed);
    PerfCounters.note('local.artPrunedBytes', freedBytes);
  }
}

/// Reads one file's metadata plus its embedded art to the temp dir.
/// Per-item failures degrade to a null-metadata entry (track still
/// listed from its filename) or null (unreadable file, skipped).
Future<MetadataFile?> _readFileMetadata(File file, String tempDirPath) async {
  PerfCounters.note('local.metadataCalls');
  final sw = kPerfCountersEnabled ? (Stopwatch()..start()) : null;
  try {
    final metadata = await MetadataGod.readMetadata(file: file.path);
    sw?.stop();
    PerfCounters.time('local.metadataTime', sw?.elapsed ?? Duration.zero);

    final picture = metadata.picture;
    String? artPath;
    if (picture != null) {
      final imageFile = File(
        localArtFilePath(tempDirPath, file.path, picture.mimeType),
      );
      if (!await imageFile.exists()) {
        await imageFile.create(recursive: true);
        await imageFile.writeAsBytes(
          picture.data,
          mode: FileMode.writeOnly,
        );
      }
      artPath = imageFile.path;
    }

    return (metadata: metadata, file: file, art: artPath);
  } catch (e, stack) {
    if (e case FrbException() || TimeoutException()) {
      return (file: file, metadata: null, art: null);
    }
    AppLogger.reportError(e, stack);
    return null;
  }
}

final localTracksProvider =
    FutureProvider<Map<String, List<SpotubeLocalTrackObject>>>((ref) async {
  try {
    if (kIsWeb) return {};
    final Map<String, List<SpotubeLocalTrackObject>> libraryToTracks = {};

    // Set by dispose: abandons remaining locations instead of publishing
    // stale results over a newer scan. Must register synchronously here
    // (not after awaits) to be effective.
    var cancelled = false;
    ref.onDispose(() => cancelled = true);

    final downloadLocation = ref.watch(
      userPreferencesProvider.select((s) => s.downloadLocation),
    );

    if (downloadLocation.isEmpty) {
      return {};
    }

    final downloadDir = Directory(downloadLocation);
    final cacheDir =
        Directory(await UserPreferencesNotifier.getMusicCacheDir());
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    // Joined string, not the raw list: the drift row regenerates NEW
    // List instances on every preference write (drift's generated ==
    // compares List fields by identity), so watching the list would
    // rescan the whole library on any unrelated preference change.
    // NUL cannot appear in a filesystem path.
    final localLibraryLocationsKey = ref.watch(
      userPreferencesProvider.select(
        (s) => s.localLibraryLocation.join('\u0000'),
      ),
    );
    final localLibraryLocations = localLibraryLocationsKey.isEmpty
        ? const <String>[]
        : localLibraryLocationsKey.split('\u0000');

    // Hoisted: one platform-channel call per scan instead of one per file.
    final tempDirPath = (await getTemporaryDirectory()).path;

    // Every cover this scan asked for, i.e. every art file still traceable to
    // a track in the library. Anything else in the art dir is an orphan.
    final referencedArt = <String>{};

    // Pruning is only sound if the scan saw the whole library: a location that
    // is unmounted, or one whose listing failed halfway, yields a keep-set
    // missing that folder's covers, and the sweep would delete files belonging
    // to tracks that are still there.
    var libraryFullyScanned = true;

    for (final location in [
      downloadLocation,
      cacheDir.path,
      ...localLibraryLocations
    ]) {
      if (cancelled) break;
      if (location.isEmpty) continue;
      final entities = <File>[];
      if (await Directory(location).exists()) {
        try {
          // Stream the directory instead of materializing every entry into
          // a list, then filter on the fly. Large libraries would otherwise
          // hold a transient list of every file entity in memory.
          await for (final e in Directory(location).list(recursive: true)) {
            final mime = lookupMimeType(e.path) ??
                (extension(e.path) == ".opus" ? "audio/opus" : null);
            if (e is File && supportedAudioTypes.contains(mime)) {
              entities.add(e);
            }
          }
        } catch (e, stack) {
          libraryFullyScanned = false;
          AppLogger.reportError(e, stack);
        }
      } else {
        libraryFullyScanned = false;
      }

      try {
        final filesWithMetadata = await collectInWaves(
          entities
              .map((file) => () => _readFileMetadata(file, tempDirPath))
              .toList(),
          waveSize: _scanWaveSize,
          onWaveDone: (_) {
            if (cancelled) throw const _ScanCancelled();
          },
        ).then((value) => value.nonNulls.toList());

        // Pure object construction (proven trivial): stays on main.
        final tracksFromMetadata = filesWithMetadata
            .map(
              (fileWithMetadata) => SpotubeTrackObject.localTrackFromFile(
                fileWithMetadata.file,
                metadata: fileWithMetadata.metadata,
                art: fileWithMetadata.art,
              ) as SpotubeLocalTrackObject,
            )
            .toList();

        referencedArt.addAll(
          filesWithMetadata.map((e) => e.art).nonNulls,
        );

        libraryToTracks[location] = tracksFromMetadata;
      } on _ScanCancelled {
        break;
      }
    }

    if (!cancelled && libraryFullyScanned) {
      // Not awaited: the library is complete and publishable now, and a
      // directory sweep is not something the user should wait on to see their
      // tracks. The prune swallows its own failures, so it cannot reach the
      // catch below and throw the scan result away either.
      unawaited(pruneOrphanedArt(tempDirPath, referencedArt));
    }

    return libraryToTracks;
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
    return {};
  }
});
