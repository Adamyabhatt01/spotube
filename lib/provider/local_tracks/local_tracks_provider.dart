import 'dart:async';
import 'dart:io';

import 'package:spotube/models/metadata/metadata.dart';
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

/// Reads one file's metadata plus its embedded art to the temp dir.
/// Per-item failures degrade to a null-metadata entry (track still
/// listed from its filename) or null (unreadable file, skipped).
Future<MetadataFile?> _readFileMetadata(File file, String tempDirPath) async {
  try {
    final metadata = await MetadataGod.readMetadata(file: file.path);

    final imageFile = File(
      join(
        tempDirPath,
        "spotube",
        ServiceUtils.sanitizeFilename(basenameWithoutExtension(file.path)) +
            imgMimeToExt[metadata.picture?.mimeType ?? "image/jpeg"]!,
      ),
    );
    if (!await imageFile.exists() && metadata.picture != null) {
      await imageFile.create(recursive: true);
      await imageFile.writeAsBytes(
        metadata.picture?.data ?? [],
        mode: FileMode.writeOnly,
      );
    }

    return (metadata: metadata, file: file, art: imageFile.path);
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
    final localLibraryLocations = ref.watch(
      userPreferencesProvider.select((s) => s.localLibraryLocation),
    );

    // Hoisted: one platform-channel call per scan instead of one per file.
    final tempDirPath = (await getTemporaryDirectory()).path;

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
          final dirEntities =
              await Directory(location).list(recursive: true).toList();

          entities.addAll(
            dirEntities.where(
              (e) {
                final mime = lookupMimeType(e.path) ??
                    (extension(e.path) == ".opus" ? "audio/opus" : null);

                return e is File && supportedAudioTypes.contains(mime);
              },
            ).cast<File>(),
          );
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
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

        libraryToTracks[location] = tracksFromMetadata;
      } on _ScanCancelled {
        break;
      }
    }
    return libraryToTracks;
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
    return {};
  }
});
