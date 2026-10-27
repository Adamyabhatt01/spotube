import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' show Badge;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/scroll_motion.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

final navigationPanelHeight = StateProvider<double>((ref) => 50);

/// Whether the player sheet has risen far enough to make the bar redundant.
///
/// [navigationPanelHeight] is written on every animation frame of a sheet drag,
/// so consumers take this threshold instead of the raw value: the bar has two
/// states, and rebuilding its whole subtree per frame to discover that is what
/// makes opening the player stutter.
final navigationPanelCoversBar = Provider<bool>(
  (ref) => ref.watch(navigationPanelHeight.select((height) => height < 10)),
);

/// Whether full-screen backdrop surfaces should skip their blur while moving.
///
/// The writers below change value on a frame where content is moving behind a
/// `BackdropFilter`: a scroll anywhere in the app, and the player sheet, whose
/// [navigationPanelHeight] is rewritten on every frame of a drag. Used by the
/// theme wallpaper and the track header, where the filter covers a large area.
///
/// The pinned bottom chrome deliberately does **not** consume this anymore.
/// Dropping sigma to zero there was not a measured CPU win, and with a
/// translucent theme it removed the bar's only visible tint mid-scroll — the
/// exact "frost disappears while scrolling" regression.
final chromeBlurFrozen = Provider<bool>((ref) {
  return ref.watch(scrollInFlightProvider) ||
      ref.watch(navigationPanelHeight.select((height) => height != 50));
});

class SpotubeNavigationBar extends HookConsumerWidget {
  const SpotubeNavigationBar({
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final size = MediaQuery.sizeOf(context);

    final downloadCount = ref.watch(
      downloadManagerProvider.select(
        (tasks) => tasks
            .where(
              (e) =>
                  e.status == DownloadStatus.downloading ||
                  e.status == DownloadStatus.queued,
            )
            .length,
      ),
    );
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    final layout = context.layout;
    final themeUi = ref.watch(themeUiProvider).asData?.value;

    final screens = useMemoized(
      () => themeScreenTiles(themeUi),
      [themeUi],
    );

    // A non-empty theme list replaces the bar's entries, in its order, and
    // may add destinations of its own through `screen:<id>`.
    final navbarTileList = useMemoized(
      () {
        final host = getNavbarTileList(context.l10n);
        if (layout.navbarItems.isEmpty) return host;
        return themeEntriesFor(
          host: getNavbarTileRegistry(context.l10n),
          themeIds: layout.navbarItems,
          screens: screens,
        );
      },
      [context.l10n, layout, screens],
    );

    final coveredByPanel = ref.watch(navigationPanelCoversBar);
    // Same rule as the desktop title bar: with the desktop behind the bar,
    // any fill is the window, and in-app blur over transparency blurs
    // nothing (the compositor owns blur here).
    final realTransparent = ref.watch(realTransparencyActiveProvider);

    final router = context.watchRouter;
    final selectedIndex = max(
      0,
      navbarTileList.indexWhere(
        (e) => router.currentPath.startsWith(e.pathPrefix),
      ),
    );

    if (layoutMode == LayoutMode.extended ||
        (size.mdAndUp && layoutMode == LayoutMode.adaptive)) {
      return const SizedBox();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      // Collapsing to zero rather than swapping in a SizedBox keeps the bar
      // mounted across the threshold and lets the 100 ms curve do the work the
      // sheet's per-frame writes used to do. The content sits in a viewport, so
      // a zero-height box costs no layout.
      height: coveredByPanel ? 0 : 50,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Divider(),
            NavigationBar(
              index: selectedIndex,
              backgroundColor: realTransparent ? Colors.transparent : null,
              // The inner AppBar fills `card` at the surface opacity, so
              // blur alone cannot clear it — opacity goes to zero with it.
              surfaceOpacity:
                  realTransparent ? 0 : context.theme.surfaceOpacity,
              // Do not drop the frost during scroll: with a translucent theme
              // that removed the bar's only visible tint. Android is on
              // Impeller again since the 3.38.10 bump, whose engine carries
              // the flutter/flutter#173622 fix, so the filter can stay live
              // instead of being swapped out mid-scroll.
              surfaceBlur: realTransparent ? 0 : context.theme.surfaceBlur,
              children: [
                for (final tile in navbarTileList)
                  NavigationButton(
                    style: navbarTileList[selectedIndex] == tile
                        ? const ButtonStyle.fixed(density: ButtonDensity.icon)
                        : const ButtonStyle.muted(density: ButtonDensity.icon),
                    child: Badge(
                      isLabelVisible: tile.id == "library" && downloadCount > 0,
                      label: Text(downloadCount.toString()),
                      child: Icon(tile.icon),
                    ),
                    onPressed: () {
                      openSideBarTile(context, ref, tile);
                    },
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
