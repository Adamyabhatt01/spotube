import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:spotube/services/artwork_cache_manager.dart';

import 'package:shadcn_flutter/shadcn_flutter.dart' hide Element;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/update_dialog.dart';

import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/memory/memory_budget.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/collections/env.dart';

import 'package:version/version.dart';
import 'package:spotube/models/sort.dart';

abstract class ServiceUtils {
  static List<T> sortTracks<T extends SpotubeTrackObject>(
      List<T> tracks, SortBy sortBy) {
    if (sortBy == SortBy.none) return tracks;
    return List<T>.from(tracks)
      ..sort((a, b) {
        switch (sortBy) {
          case SortBy.ascending:
            return a.name.compareTo(b.name);
          case SortBy.descending:
            return b.name.compareTo(a.name);
          // newest/oldest have no date sort yet and fall through to default.
          case SortBy.duration:
            return a.durationMs.compareTo(b.durationMs);
          case SortBy.artist:
            // Local tracks and some plugin payloads have an empty artist list;
            // `first` used to throw while the user changed the sort order.
            return (a.artists.isEmpty ? '' : a.artists.first.name).compareTo(
              b.artists.isEmpty ? '' : b.artists.first.name,
            );
          case SortBy.album:
            return a.album.name.compareTo(b.album.name);
          default:
            return 0;
        }
      });
  }

  static Future<void> checkForUpdates(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!Env.enableUpdateChecker) return;
    final database = ref.read(databaseProvider);
    final checkUpdate = await (database.selectOnly(database.preferencesTable)
          ..addColumns([database.preferencesTable.checkUpdate])
          ..where(database.preferencesTable.id.equals(0)))
        .map((row) => row.read(database.preferencesTable.checkUpdate))
        .getSingleOrNull();

    if (checkUpdate == false) return;
    final packageInfo = await PackageInfo.fromPlatform();

    // A failed lookup is the expected case, not an error: a fork build whose
    // repository has published nothing yet simply has nowhere to update from.
    final Response response;
    try {
      response = await ref.read(appDioProvider).getUri(
        Uri.parse(
          Env.releaseChannel == ReleaseChannel.nightly
              ? "https://api.github.com/repos/${Env.updateRepo}/actions/workflows/spotube-release-binary.yml/runs?status=success&per_page=1"
              : "https://api.github.com/repos/${Env.updateRepo}/releases/latest",
        ),
        options: Options(
          responseType: ResponseType.json,
        ),
      );
    } on Object {
      return;
    }

    final data = response.data;
    if (data is! Map) return;

    if (Env.releaseChannel == ReleaseChannel.nightly) {
      final runs = data["workflow_runs"];
      final currentBuild = int.tryParse(packageInfo.buildNumber);
      final buildNum = runs is List && runs.isNotEmpty
          ? (runs.first as Map)["run_number"]
          : null;

      if (buildNum is! int ||
          currentBuild == null ||
          buildNum <= currentBuild ||
          !context.mounted) {
        return;
      }

      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(66),
        builder: (context) {
          return RootAppUpdateDialog.nightly(nightlyBuildNum: buildNum);
        },
      );
    } else {
      final tagName = data["tag_name"];
      if (tagName is! String || !context.mounted) return;

      final Version? latestVersion;
      try {
        latestVersion = tagName == "nightly"
            ? null
            : Version.parse(tagName.replaceAll("v", ""));
      } on FormatException {
        return;
      }

      final currentVersion = packageInfo.version == "Unknown"
          ? null
          : Version.parse(packageInfo.version);

      if (currentVersion == null ||
          latestVersion == null ||
          (latestVersion.isPreRelease && !currentVersion.isPreRelease) ||
          (!latestVersion.isPreRelease && currentVersion.isPreRelease)) {
        return;
      }

      if (latestVersion <= currentVersion) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(66),
        builder: (context) {
          return RootAppUpdateDialog(version: latestVersion);
        },
      );
    }
  }

  static Future<Uint8List?> downloadImage(
    String imageUrl,
  ) async {
    try {
      final fileStream = ArtworkCacheManager.instance.getImageFile(imageUrl);

      final bytes = List<int>.empty(growable: true);

      await for (final data in fileStream) {
        if (data is FileInfo) {
          bytes.addAll(await data.file.readAsBytes());
          break;
        }
      }

      return Uint8List.fromList(bytes);
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      return null;
    }
  }

  /// In-memory artwork bytes keyed by URL, shared by every consumer.
  ///
  /// The download worker, the playback-cache finalizer and the palette hook
  /// all asked for the same album art through [downloadImage], which shares
  /// only the on-disk cache: each caller re-read the file, and concurrent
  /// callers each started their own fetch. This memo serves repeat and
  /// concurrent requests from one future. Failures are not retained (a null
  /// result evicts its own entry) so a transient outage stays retryable.
  ///
  /// Bounded by **bytes**, not by entry count. The entries are encoded
  /// cover images whose sizes differ by an order of magnitude (a 640x640
  /// Spotify rendition is ~150 KB, a small one ~5 KB), so an entry-count
  /// cap lets a handful of large covers cost megabytes without bound. The
  /// byte budget is device-aware (see [MemoryBudget]); the entry count is
  /// kept as a backstop so a pathological run of tiny images cannot make
  /// the map itself large.
  static final Map<String, Future<Uint8List?>> _artworkBytesMemo = {};

  /// The byte size of each resolved entry, so the budget can be enforced
  /// without awaiting the futures (which would be racy).
  static final Map<String, int> _artworkBytesSizes = {};

  static int _artworkBytesTotal = 0;

  static const int _maxArtworkMemoEntries = 64;

  static int get _maxArtworkMemoBytes => MemoryBudget.artworkMemoBytes;

  static Future<Uint8List?> artworkBytes(String imageUrl) {
    return _artworkBytesMemo.putIfAbsent(imageUrl, () {
      // [downloadImage] never throws (it reports and returns null), so this
      // derived future always completes cleanly and cannot surface as an
      // unhandled zone error.
      return downloadImage(imageUrl).then((bytes) {
        if (bytes == null) {
          _artworkBytesMemo.remove(imageUrl);
        } else {
          _artworkBytesSizes[imageUrl] = bytes.length;
          _artworkBytesTotal += bytes.length;
          _evictArtworkMemoOverflow(imageUrl);
        }
        return bytes;
      });
    });
  }

  /// Drops the oldest entries until the memo is inside its byte budget and
  /// its entry-count backstop.
  ///
  /// [protected] is the entry that just resolved: it is never evicted, so a
  /// caller that is about to receive these bytes always gets them.
  static void _evictArtworkMemoOverflow(String protected) {
    while (_artworkBytesTotal > _maxArtworkMemoBytes ||
        _artworkBytesMemo.length > _maxArtworkMemoEntries) {
      final oldest = _artworkBytesMemo.keys.firstWhere(
        (key) => key != protected,
        orElse: () => protected,
      );
      if (oldest == protected) break;
      _artworkBytesMemo.remove(oldest);
      final size = _artworkBytesSizes.remove(oldest) ?? 0;
      _artworkBytesTotal -= size;
    }
  }

  @visibleForTesting
  static int get debugArtworkMemoLength => _artworkBytesMemo.length;

  @visibleForTesting
  static int get debugArtworkMemoBytes => _artworkBytesTotal;

  @visibleForTesting
  static void debugClearArtworkMemo() {
    _artworkBytesMemo.clear();
    _artworkBytesSizes.clear();
    _artworkBytesTotal = 0;
  }

  static String sanitizeFilename(String input, {String replacement = ''}) {
    final result = input
        // illegalRe
        .replaceAll(
          RegExp(r'[\/\?<>\\:\*\|"]'),
          replacement,
        )
        // controlRe
        .replaceAll(
          RegExp(
            r'[\x00-\x1f\x80-\x9f]',
          ),
          replacement,
        )
        // reservedRe
        .replaceFirst(
          RegExp(r'^\.+$'),
          replacement,
        )
        // windowsReservedRe
        .replaceFirst(
          RegExp(
            r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
            caseSensitive: false,
          ),
          replacement,
        )
        // windowsTrailingRe
        .replaceFirst(RegExp(r'[\. ]+$'), replacement);

    return result.length > 255 ? result.substring(0, 255) : result;
  }

  /// The `"<name> - <artists>"` stem a track's files are named by. One source
  /// of truth for the contract between the downloader (`_savePathFor`), the
  /// proxy (`downloadedFileBaseName`, `_getTrackCacheFilePath`) and the music
  /// cache evictor (`_evictMusicCacheCopies`) — previously re-derived inline
  /// at each site, so one join silently breaking the prefix match could go
  /// unnoticed.
  ///
  /// [spaceAfterComma] is load-bearing, byte-for-byte: downloads name
  /// user-facing files with `", "` while the streaming-cache file embeds
  /// `(<source id>)` and is matched by the `","` prefix.
  static String trackFileStem(
    SpotubeTrackObject track, {
    required bool spaceAfterComma,
  }) {
    final artists = track.artists
        .map((e) => e.name)
        .join(spaceAfterComma ? ", " : ",");
    return "${track.name} - $artists";
  }
}
