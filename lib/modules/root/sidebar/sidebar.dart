import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/root/sidebar/sidebar_footer.dart';

import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

class Sidebar extends HookConsumerWidget {
  final Widget child;

  const Sidebar({
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData(:colorScheme) = Theme.of(context);
    final mediaQuery = MediaQuery.sizeOf(context);

    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));

    final sidebarTileList = useMemoized(
      () => getSidebarTileList(context.l10n),
      [context.l10n],
    );

    final sidebarLibraryTileList = useMemoized(
      () => getSidebarLibraryTileList(context.l10n),
      [context.l10n],
    );

    final tileList = [...sidebarTileList, ...sidebarLibraryTileList];

    final router = context.watchRouter;

    final selectedIndex = tileList.indexWhere(
      (e) => router.currentPath.startsWith(e.pathPrefix),
    );

    if (layoutMode == LayoutMode.compact ||
        (mediaQuery.smAndDown && layoutMode == LayoutMode.adaptive)) {
      return child;
    }

    final showLabels = mediaQuery.lgAndUp && !context.iconOnlyNav;

    final navigationButtons = [
      NavigationLabel(
        child: showLabels
            ? DefaultTextStyle(
                style: TextStyle(
                  fontFamily: "Cookie",
                  fontSize: 30,
                  letterSpacing: 1.8,
                  color: colorScheme.foreground,
                ),
                child: const Text("Spotube"),
              )
            : const Text(""),
      ),
      for (final tile in sidebarTileList)
        NavigationButton(
          style: router.currentPath.startsWith(tile.pathPrefix)
              ? const ButtonStyle.secondary()
              : null,
          label: showLabels ? Text(tile.title) : null,
          child: Tooltip(
            tooltip: TooltipContainer(child: Text(tile.title)).call,
            child: Icon(tile.icon),
          ),
          onPressed: () {
            context.navigateTo(tile.route);
          },
        ),
      const NavigationDivider(),
      if (showLabels) NavigationLabel(child: Text(context.l10n.library)),
      for (final tile in sidebarLibraryTileList)
        NavigationButton(
          style: router.currentPath.startsWith(tile.pathPrefix)
              ? const ButtonStyle.secondary()
              : null,
          label: showLabels ? Text(tile.title) : null,
          onPressed: () {
            context.navigateTo(tile.route);
          },
          child: Tooltip(
            tooltip: TooltipContainer(child: Text(tile.title)).call,
            child: Icon(tile.icon),
          ),
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Expanded(
              child: showLabels
                  ? NavigationSidebar(
                      index: selectedIndex,
                      onSelected: (index) {
                        final tile = tileList[index];
                        context.navigateTo(tile.route);
                      },
                      children: navigationButtons,
                    )
                  : NavigationRail(
                      alignment: NavigationRailAlignment.start,
                      index: selectedIndex,
                      onSelected: (index) {
                        final tile = tileList[index];
                        context.navigateTo(tile.route);
                      },
                      children: navigationButtons,
                    ),
            ),
            SidebarFooter(compact: !showLabels),
            Gap(
              sidebarBottomClearanceOf(
                context,
                playerVisible: bottomPlayerVisibleOf(context, layoutMode),
              ),
            ),
          ],
        ),
        const VerticalDivider(),
        Expanded(child: child),
      ],
    );
  }
}

/// How much of the window's bottom edge the sidebar has to keep clear of.
///
/// The bottom player is a `Scaffold` footer, and with `floatingFooter: true` the
/// body gets the full window height while the footer is painted over its bottom.
/// So the sidebar's own footer — whose profile row carries the settings button —
/// needs a reservation, and an under-sized one slides that row underneath the
/// player where the button can no longer be reached.
///
/// The player is built from paddings, icons and text that all follow
/// `theme.scaling`, so the reservation has to follow it too. The literals are
/// what the player measures at scaling 1.
///
/// [playerVisible] is false when `BottomPlayer` renders a zero-size
/// `PlayerOverlay` instead of the bar, which is the case below the `lg`
/// breakpoint in the adaptive layout. It gates only what the bar grows by, not
/// the reservation itself: the literals are what the app has always kept, so
/// switching on it would move the profile row in layouts this work is not
/// about. Deliberately nothing here reads the nav switch — the settings row has
/// to stay reachable in a rail-width sidebar exactly as much as in a labelled
/// one, and keying the reservation to the nav shape is how that button went
/// missing once already.
double sidebarBottomClearanceOf(
  BuildContext context, {
  required bool playerVisible,
}) {
  final scaling = Theme.of(context).scaling;
  final clearance = (MediaQuery.sizeOf(context).lgAndUp ? 130 : 65) * scaling;
  if (!playerVisible || !context.progressBelow) return clearance;
  // `progress: below` adds the seek line under the transport controls.
  return clearance + 12 * scaling;
}
