import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/assets.gen.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/root/sidebar/sidebar_footer.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';
import 'package:spotube/modules/root/sidebar/sidebar_reorderable_item.dart';

import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/sidebar/sidebar_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Max pinned playlists shown in icon-only rail mode. The labelled sidebar
/// scrolls natively (shadcn renders it as a vertical `CustomScrollView`), so
/// only the rail — which cannot label rows — needs a cap.
const _maxRailPins = 8;

/// Fixed cover edge for pinned playlist tiles, in the button's existing icon
/// slot. The sidebar width (200 * scaling, package-fixed) never changes.
const _pinCoverSide = 28.0;

class Sidebar extends HookConsumerWidget {
  final Widget child;

  /// Optional footer laid out under [child] in the content column, at most
  /// once. Used by the docked player variant: the bar stops at the sidebar
  /// edge instead of spanning the whole window as a scaffold footer.
  final Widget? contentFooter;

  const Sidebar({
    required this.child,
    this.contentFooter,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData(:colorScheme) = Theme.of(context);
    final mediaQuery = MediaQuery.sizeOf(context);

    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    final playerDock =
        ref.watch(userPreferencesProvider.select((s) => s.playerDock));
    final storedLibraryOrder = ref.watch(
      userPreferencesProvider.select((s) => s.sidebarLibraryOrder),
    );
    final pinnedIds = ref.watch(
      userPreferencesProvider.select((s) => s.pinnedPlaylistIds),
    );
    final playlistIndex = ref.watch(sidebarPlaylistIndexProvider);
    final me = ref.watch(metadataPluginUserProvider).asData?.value;

    final sidebarTileList = useMemoized(
      () => getSidebarTileList(context.l10n),
      [context.l10n],
    );

    final sidebarLibraryTileList = useMemoized(
      () => getSidebarLibraryTileList(context.l10n),
      [context.l10n],
    );

    // Synthetic entry, mirroring UserPlaylistsPage: built in UI because its
    // name needs l10n, which providers cannot reach.
    final likedTracksPlaylist = useMemoized(
      () => me == null
          ? null
          : SpotubeSimplePlaylistObject(
              id: "user-liked-tracks",
              name: context.l10n.liked_tracks,
              description: context.l10n.liked_tracks_description,
              externalUri: "",
              owner: me,
              images: [
                SpotubeImageObject(
                  url: Assets.images.likedTracks.path,
                  width: 300,
                  height: 300,
                )
              ],
            ),
      [context.l10n, me],
    );

    // Library group in the user's order. Reorder is scoped here only —
    // the top navigation above never enters this list.
    final orderedLibraryTiles = useMemoized(
      () {
        final byId = {for (final tile in sidebarLibraryTileList) tile.id: tile};
        return [
          for (final id in resolveSidebarLibraryOrder(storedLibraryOrder))
            if (byId[id] != null) byId[id]!,
        ];
      },
      [sidebarLibraryTileList, storedLibraryOrder],
    );

    // Pinned playlists in pin order. A pinned id with no playlist behind it
    // (deleted, offline, logged out) is skipped, never a dead tile.
    final pinnedTiles = useMemoized(
      () {
        final tiles = <SideBarTiles>[];
        for (final id in pinnedIds) {
          final playlist = id == "user-liked-tracks"
              ? likedTracksPlaylist
              : playlistIndex[id];
          if (playlist == null) continue;
          tiles.add(
            SideBarTiles(
              id: "pin:$id",
              title: playlist.name,
              pathPrefix:
                  id == "user-liked-tracks" ? "/liked-tracks" : "/playlist/$id",
              // The route guard redirects user-liked-tracks to
              // LikedPlaylistRoute, so pins navigate uniformly.
              route: PlaylistRoute(id: id, playlist: playlist),
              icon: SpotubeIcons.playlist,
              imageUrl: playlist.images.from200PxTo300PxOrSmallestImage(
                ImagePlaceholder.collection,
              ),
            ),
          );
        }
        return tiles;
      },
      [pinnedIds, playlistIndex, likedTracksPlaylist],
    );

    // Every row in render order, feeding [selectedIndex]. Selection is
    // actually drawn per tile by the `style:` checks below: shadcn only
    // assigns a logical index to `NavigationItem`, and every row here is a
    // `NavigationButton` (non-selectable, `onPressed`-driven), so neither
    // `index` nor `onSelected` fires. Kept so a later switch to
    // `NavigationItem` cannot silently mis-map a pin onto another tile.
    final tileList = [
      ...sidebarTileList,
      ...orderedLibraryTiles,
      ...pinnedTiles,
    ];

    final router = context.watchRouter;

    final selectedIndex = tileList.indexWhere(
      (e) => router.currentPath.startsWith(e.pathPrefix),
    );

    if (layoutMode == LayoutMode.compact ||
        (mediaQuery.smAndDown && layoutMode == LayoutMode.adaptive)) {
      return child;
    }

    final showLabels = mediaQuery.lgAndUp && !context.iconOnlyNav;

    final visiblePins =
        showLabels ? pinnedTiles : pinnedTiles.take(_maxRailPins).toList();
    final hasRailOverflow =
        !showLabels && pinnedTiles.length > visiblePins.length;

    final List<NavigationBarItem> navigationButtons = [
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
      for (final tile in orderedLibraryTiles)
        SidebarReorderableItem(
          key: ValueKey('lib:${tile.id}'),
          group: SidebarReorderGroup.library,
          id: tile.id,
          onAcceptInGroup: (draggedId, targetId, {required bool after}) {
            final visible = [for (final t in orderedLibraryTiles) t.id];
            final drop = resolveSidebarDrop(
              visible,
              draggedId,
              targetId,
              after: after,
            );
            if (drop == null) return;
            ref
                .read(userPreferencesProvider.notifier)
                .setSidebarLibraryOrder(
                  moveSidebarEntry(visible, drop.from, drop.to),
                );
          },
          feedback: _sidebarDragGhost(
            context: context,
            leading: Icon(tile.icon),
            title: tile.title,
          ),
          row: NavigationButton(
            // Explicit style/alignment: the reorderable wrapper re-scopes
            // the sidebar container data for its subtree (see
            // SidebarReorderableItem), so these carry what the sidebar
            // container would otherwise compute. In the rail the real
            // container data still applies, so nothing is passed there.
            style: router.currentPath.startsWith(tile.pathPrefix)
                ? const ButtonStyle.secondary()
                : (showLabels ? const ButtonStyle.ghost() : null),
            alignment:
                showLabels ? AlignmentDirectional.centerStart : null,
            label: showLabels ? Text(tile.title) : null,
            onPressed: () {
              context.navigateTo(tile.route);
            },
            child: Tooltip(
              tooltip: TooltipContainer(child: Text(tile.title)).call,
              child: Icon(tile.icon),
            ),
          ),
        ),
      // Drop zone below the last library tile: dropping onto a row can only
      // move up to that row's index, so the very bottom needs its own target.
      SidebarTrailingDropZone(
        key: const ValueKey('lib-end'),
        group: SidebarReorderGroup.library,
        visibleIds: [for (final t in orderedLibraryTiles) t.id],
        onAccept: (draggedId) {
          final visible = [for (final t in orderedLibraryTiles) t.id];
          final from = visible.indexOf(draggedId);
          if (from == -1) return;
          ref
              .read(userPreferencesProvider.notifier)
              .setSidebarLibraryOrder(
                moveSidebarEntry(visible, from, visible.length - 1),
              );
        },
      ),
      if (pinnedTiles.isNotEmpty) ...[
        const NavigationDivider(),
        if (showLabels)
          NavigationLabel(child: Text(context.l10n.pinned_playlists)),
        for (final tile in visiblePins)
          SidebarReorderableItem(
            key: ValueKey(tile.id),
            group: SidebarReorderGroup.pins,
            // Pinned tiles carry a `pin:`-prefixed id in [tileList]; the
            // persisted order uses the raw playlist id.
            id: tile.id.substring(4),
            onAcceptInGroup: (draggedId, targetId, {required bool after}) {
              final stored =
                  ref.read(userPreferencesProvider).pinnedPlaylistIds;
              final visible = [
                for (final t in visiblePins) t.id.substring(4),
              ];
              final drop = resolveSidebarDrop(
                visible,
                draggedId,
                targetId,
                after: after,
              );
              if (drop == null) return;
              ref.read(userPreferencesProvider.notifier).setPinnedPlaylistIds(
                    moveSidebarPin(stored, visible, drop.from, drop.to),
                  );
            },
            feedback: _sidebarDragGhost(
              context: context,
              leading: SidebarPinCover(
                imageUrl: tile.imageUrl,
                side: _pinCoverSide,
              ),
              title: tile.title,
            ),
            row: NavigationButton(
              // Same explicit style/alignment contract as the library rows
              // above: the wrapper re-scopes sidebar container data.
              style: router.currentPath.startsWith(tile.pathPrefix)
                  ? const ButtonStyle.secondary()
                  : (showLabels ? const ButtonStyle.ghost() : null),
              alignment:
                  showLabels ? AlignmentDirectional.centerStart : null,
              label: showLabels ? Text(tile.title) : null,
              onPressed: () {
                context.navigateTo(tile.route);
              },
              child: Tooltip(
                tooltip: TooltipContainer(child: Text(tile.title)).call,
                child: SidebarPinCover(
                  imageUrl: tile.imageUrl,
                  side: _pinCoverSide,
                ),
              ),
            ),
          ),
        // Drop zone below the last pin (above the rail overflow tile, which
        // stays fixed): the only way to move a playlist to the very bottom.
        SidebarTrailingDropZone(
          key: const ValueKey('pins-end'),
          group: SidebarReorderGroup.pins,
          visibleIds: [for (final t in visiblePins) t.id.substring(4)],
          onAccept: (draggedId) {
            final stored =
                ref.read(userPreferencesProvider).pinnedPlaylistIds;
            final visible = [
              for (final t in visiblePins) t.id.substring(4),
            ];
            final from = visible.indexOf(draggedId);
            if (from == -1) return;
            ref.read(userPreferencesProvider.notifier).setPinnedPlaylistIds(
                  moveSidebarPin(stored, visible, from, visible.length - 1),
                );
          },
        ),
        if (hasRailOverflow)
          NavigationButton(
            label: showLabels ? Text(context.l10n.show_all_playlists) : null,
            onPressed: () {
              context.navigateTo(const UserPlaylistsRoute());
            },
            child: Tooltip(
              tooltip:
                  TooltipContainer(child: Text(context.l10n.show_all_playlists))
                      .call,
              child: const Icon(SpotubeIcons.playlist),
            ),
          ),
      ],
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
                dock: playerDock,
              ),
            ),
          ],
        ),
        const VerticalDivider(),
        Expanded(
          child: contentFooter == null
              ? child
              : Column(
                  children: [
                    Expanded(child: child),
                    contentFooter!,
                  ],
                ),
        ),
      ],
    );
  }
}

/// Compact drag ghost shown under the pointer while a sidebar row is being
/// moved. Overlay-only (never laid out in the sidebar), so it can use padding
/// freely — unlike the row itself, which must stay intrinsic-safe.
Widget _sidebarDragGhost({
  required BuildContext context,
  required Widget leading,
  required String title,
}) {
  final theme = Theme.of(context);
  final scaling = theme.scaling;
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 200 * scaling),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8 * scaling),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scaling,
          vertical: 8 * scaling,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8 * scaling,
          children: [
            leading,
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
///
/// [dock] is the exception: a docked player never overlaps the sidebar at
/// all, so the reservation collapses to a small bottom pad.
/// Pure clearance math for [sidebarBottomClearanceOf], kept free of
/// [BuildContext] so the variant matrix is unit-testable.
double sidebarClearance({
  required bool lgAndUp,
  required bool playerVisible,
  required bool progressBelow,
  required PlayerDock dock,
  required double scaling,
}) {
  // The docked player lays out under the content only and never overlaps the
  // sidebar, so the nav column runs to the window bottom with a small pad.
  if (dock == PlayerDock.docked) return 12 * scaling;
  final clearance = (lgAndUp ? 130 : 65) * scaling;
  if (!playerVisible || !progressBelow) return clearance;
  // `progress: below` adds the seek line under the transport controls.
  return clearance + 12 * scaling;
}

double sidebarBottomClearanceOf(
  BuildContext context, {
  required bool playerVisible,
  required PlayerDock dock,
}) {
  return sidebarClearance(
    lgAndUp: MediaQuery.sizeOf(context).lgAndUp,
    playerVisible: playerVisible,
    progressBelow: context.progressBelow,
    dock: dock,
    scaling: Theme.of(context).scaling,
  );
}
