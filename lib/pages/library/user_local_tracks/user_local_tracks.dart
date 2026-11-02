import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/dialogs/delete_downloads_dialog.dart';
import 'package:spotube/modules/library/local_folder/local_folder_item.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';

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
      wiping.value = true;
      try {
        await showDeleteDownloadsDialog(context, ref);
      } finally {
        wiping.value = false;
      }
    }, [context, ref, wiping]);

    final locations = [
      preferences.downloadLocation,
      if (cacheDir.hasData) cacheDir.data!,
      ...preferences.localLibraryLocation,
    ];

    // Pages the theme parents to Local Library. They appear in the host
    // body; a theme that owns `library.local.content` links its own pages
    // through actions instead.
    final themeUi = ref.watch(themeUiProvider).asData?.value;
    final themePages = themePageTiles(themeUi, parent: 'library.local');

    // The grid is the host's fallback: a theme that fills
    // `library.local.content` owns the body, but the add/delete controls stay
    // host-owned (the slot is read-only in this phase), so they remain in the
    // fallback rather than disappearing with it.
    return ThemePageContent(
      slot: 'library.local.content',
      scroll: false,
      bindings: {
        'library.folders': themeLibraryFolders(locations),
        'library.counts': {'folders': locations.length},
      },
      fallback: LayoutBuilder(
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
              if (themePages.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tile in themePages)
                      Button.secondary(
                        leading: Icon(tile.icon),
                        onPressed: () => openSideBarTile(context, ref, tile),
                        child: Text(tile.title),
                      ),
                  ],
                ),
                const Gap(8),
              ],
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
        ),
      ),
    );
  }
}
