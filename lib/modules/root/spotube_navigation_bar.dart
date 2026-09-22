import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' show Badge;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
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

/// Whether the chrome pinned over the content should skip its backdrop blur.
///
/// Both writers below change value on a frame where something is moving across
/// the surface behind the nav bar and the collapsed player: a scroll anywhere in
/// the app, and the player sheet, whose [navigationPanelHeight] is rewritten on
/// every frame of a drag. Either way a `BackdropFilter` would re-blur that frame's
/// content for a frost nobody sees while it moves, so the surfaces draw plain
/// until the motion stops. The threshold is a state change, not a per-frame one.
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

    final navbarTileList = useMemoized(
      () => getNavbarTileList(context.l10n),
      [context.l10n],
    );

    final coveredByPanel = ref.watch(navigationPanelCoversBar);
    final blurFrozen = ref.watch(chromeBlurFrozen);

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
              surfaceBlur: blurFrozen ? 0 : context.theme.surfaceBlur,
              surfaceOpacity: context.theme.surfaceOpacity,
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
                      context.navigateTo(tile.route);
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
