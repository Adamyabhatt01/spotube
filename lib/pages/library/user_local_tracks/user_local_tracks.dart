import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/library/local_folder/local_folder_item.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/downloads/local_library_wipe.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

/// File deletions go in bounded waves.
///
/// `File.delete` is one syscall per file and a downloaded library can hold
/// thousands of them; awaiting a wave at a time yields the isolate between
/// groups instead of blocking the UI for the whole walk. Returns the number of
/// files that could not be removed — a record is already gone by then, so the
/// count is reported to the user rather than swallowed.
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
            // Already absent is the outcome the wipe wanted, not a failure.
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

@RoutePage()
class UserLocalLibraryPage extends HookConsumerWidget {
  static const name = 'user_local_library';
  const UserLocalLibraryPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    // Memoized: a fresh Future per build makes useFuture re-subscribe and
    // rebuild forever (flutter_hooks treats every new instance as a change).
    final cacheDirFuture = useMemoized(
      UserPreferencesNotifier.getMusicCacheDir,
      const [],
    );
    final cacheDir = useFuture(cacheDirFuture);
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final preferences = ref.watch(userPreferencesProvider);

    final addLocalLibraryLocation = useCallback(() async {
      if (kIsMobile || kIsMacOS) {
        final dirStr = await FilePicker.platform.getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        if (preferences.localLibraryLocation.contains(dirStr)) return;
        preferencesNotifier.setLocalLibraryLocation(
            [...preferences.localLibraryLocation, dirStr]);
      } else {
        String? dirStr = await getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        if (preferences.localLibraryLocation.contains(dirStr)) return;
        preferencesNotifier.setLocalLibraryLocation(
            [...preferences.localLibraryLocation, dirStr]);
      }
    }, [preferences.localLibraryLocation]);

    final wiping = useState(false);

    // This is just to pre-load the tracks.
    // For now, this gets all of them.
    ref.watch(localTracksProvider);

    final deleteLocalLibrary = useCallback(() async {
      if (wiping.value) return;
      final musicCacheDir = await UserPreferencesNotifier.getMusicCacheDir();
      final rows = await allDownloads(ref.read(databaseProvider));
      final targets = selectFilesToDelete(
        filePaths: rows.map((row) => row.filePath),
        downloadRoot: preferences.downloadLocation,
        cacheRoot: musicCacheDir,
        libraryLocations: preferences.localLibraryLocation,
      );
      final targetPaths = targets.toSet();
      final bytes = sumDownloadedBytes([
        for (final row in rows)
          if (targetPaths.contains(p.normalize(row.filePath))) row.sizeBytes,
      ]);

      if (targets.isEmpty && rows.isEmpty) {
        if (!context.mounted) return;
        showToast(
          context: context,
          builder: (context, overlay) =>
              Text(context.l10n.delete_local_library_nothing_to_delete),
        );
        return;
      }

      if (!context.mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.delete_local_library),
          content: Text(
            context.l10n.delete_local_library_confirmation(
              targets.length,
              formatByteTotal(bytes),
            ),
          ),
          actions: [
            Button.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.decline),
            ),
            Button.destructive(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.accept),
            ),
          ],
        ),
      );

      if (accepted != true) return;

      wiping.value = true;
      try {
        // Records first: this also cancels in-flight transfers and invalidates
        // any background playlist sync, so nothing re-creates a row or writes a
        // file behind the wipe.
        await ref.read(playlistMirrorServiceProvider).forgetEverything();

        final cache = Directory(musicCacheDir);
        if (cache.existsSync()) {
          await cache.delete(recursive: true);
        }

        final undeletable = await _deleteInWaves(targets);

        ref.invalidate(localTracksProvider);

        if (!context.mounted) return;
        showToast(
          context: context,
          builder: (context, overlay) {
            final message = undeletable == 0
                ? context.l10n.deleted_local_library(targets.length)
                : context.l10n.deleted_local_library_with_failures(
                    // Generated in sorted-placeholder order: files first, then
                    // undeletable — not source-appearance order.
                    targets.length,
                    undeletable,
                  );
            return SurfaceCard(
              child: Basic(content: Text(message)),
            );
          },
        );
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
        ref.invalidate(localTracksProvider);
      } finally {
        wiping.value = false;
      }
    }, [
      preferences.downloadLocation,
      preferences.localLibraryLocation,
      context,
      ref,
      wiping,
    ]);

    final locations = [
      preferences.downloadLocation,
      if (cacheDir.hasData) cacheDir.data!,
      ...preferences.localLibraryLocation,
    ];

    return LayoutBuilder(
        builder: (context, constrains) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Button.destructive(
                        leading: const Icon(SpotubeIcons.trash),
                        onPressed: wiping.value ? null : deleteLocalLibrary,
                        child: Text(context.l10n.delete_local_library),
                      ),
                      Button.secondary(
                        leading: const Icon(SpotubeIcons.folderAdd),
                        onPressed: addLocalLibraryLocation,
                        child: Text(context.l10n.add_library_location),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisExtent: constrains.isXs
                            ? 230 * context.theme.scaling
                            : constrains.mdAndDown
                                ? 280 * context.theme.scaling
                                : 250 * context.theme.scaling,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: locations.length,
                      itemBuilder: (context, index) {
                        return LocalFolderItem(
                          folder: locations[index],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ));
  }
}
