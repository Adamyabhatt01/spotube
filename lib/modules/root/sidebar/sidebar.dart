import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/root/sidebar/sidebar_footer.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_tile.dart';
import 'package:spotube/modules/root/sidebar/sidebar_reorderable_item.dart';
import 'package:spotube/modules/root/sidebar/sidebar_station_pin_tile.dart';
import 'package:spotube/modules/root/sidebar/sidebar_visibility.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';

import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/theme_shell/theme_branding.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/sidebar/sidebar_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Max pinned playlists shown in icon-only rail mode. The labelled sidebar
/// scrolls natively (shadcn renders it as a vertical `CustomScrollView`), so
/// only the rail — which cannot label rows — needs a cap.
const _maxRailPins = 8;

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
    // Already resolved for the current width (main.dart publishes the
    // breakpoint variant through AppLayout).
    final layout = context.layout;
    // shadcn sizes each navigation label with `IntrinsicWidth`, so the face
    // must be registered before that measurement. Registering a font does not
    // invalidate an existing `RenderParagraph`, and a plain rebuild reuses the
    // same `TextStyle`, so the intrinsic width would stay at the fallback
    // face's value. Recreate the sidebar once the faces land (the key flips
    // from false to true) to force a fresh measure with Inter.
    final fontsLoaded = ref.watch(themeUiFontsProvider).hasValue;
    final themeUi = ref.watch(themeUiProvider).asData?.value;
    final themeDefinition = ref.watch(themeDefinitionProvider).asData?.value;
    final branding = useMemoized(
      () => ThemeBranding.from(themeDefinition),
      [themeDefinition],
    );

    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    final playerDock = context.playerDock;
    final measuredPlayerHeight = ref.watch(bottomPlayerHeightProvider);
    final storedLibraryOrder = ref.watch(
      userPreferencesProvider.select((s) => s.sidebarLibraryOrder),
    );
    final pinnedIds = ref.watch(
      userPreferencesProvider.select((s) => s.pinnedPlaylistIds),
    );
    final stationPinIds = ref.watch(
      userPreferencesProvider.select((s) => s.pinnedStationIds),
    );
    final playlistIndex = ref.watch(sidebarPlaylistIndexProvider);
    final me = ref.watch(metadataPluginUserProvider).asData?.value;
    // Local plugin state, so it stays true offline — unlike [me], whose
    // profile fetch has no snapshot fallback. Gating the fallback on it
    // keeps a pinned Liked entry visible offline without ever showing one
    // while logged out.
    final authenticated =
        ref.watch(metadataPluginAuthenticatedProvider).asData?.value;

    final screens = useMemoized(
      () => themeScreenTiles(themeUi),
      [themeUi],
    );

    final sidebarLibraryTileList = useMemoized(
      () => getSidebarLibraryTileList(context.l10n),
      [context.l10n],
    );

    // Synthetic entry, mirroring UserPlaylistsPage: built in UI because its
    // name needs l10n, which providers cannot reach. Falls back to an
    // anonymous owner while signed in so the pin survives offline — the
    // tracks themselves come from the savedTracks snapshot.
    final likedTracksPlaylist = useMemoized(
      () => resolveLikedTracksPlaylist(
        name: context.l10n.liked_tracks,
        description: context.l10n.liked_tracks_description,
        me: me,
        authenticated: authenticated,
      ),
      [context.l10n, me, authenticated],
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

    // The top entries the theme asked for. A non-empty list is the surface,
    // resolved against the full registry (so `search` becomes available); an
    // empty list keeps the host's own entries and order.
    final sidebarTileList = useMemoized(
      () {
        if (layout.navItems.isEmpty) {
          return getSidebarTileList(context.l10n);
        }
        return themeEntriesFor(
          host: getSidebarTileRegistry(context.l10n),
          themeIds: layout.navItems,
          screens: screens,
        );
      },
      [context.l10n, layout, screens],
    );

    // Library group as the theme asked for it, or in the user's own order.
    final visibleLibraryTiles = useMemoized(
      () {
        if (layout.libraryItems.isEmpty) return orderedLibraryTiles;
        return themeEntriesFor(
          host: sidebarLibraryTileList,
          themeIds: layout.libraryItems,
          screens: screens,
        );
      },
      [
        sidebarLibraryTileList,
        orderedLibraryTiles,
        layout,
        screens,
      ],
    );

    // Pinned playlists in pin order. A pinned id with no playlist behind it
    // (deleted, offline, logged out) is skipped, never a dead tile.
    final pinnedTiles = useMemoized(
      () {
        final tiles = <SideBarTiles>[];
        for (final id in pinnedIds) {
          final playlist = id == likedTracksPlaylistId
              ? likedTracksPlaylist
              : playlistIndex[id];
          if (playlist == null) continue;
          tiles.add(
            SideBarTiles(
              id: "pin:$id",
              title: playlist.name,
              pathPrefix: id == likedTracksPlaylistId
                  ? "/liked-tracks"
                  : "/playlist/$id",
              // The route guard redirects user-liked-tracks to
              // LikedPlaylistRoute, so pins navigate uniformly.
              route: PlaylistRoute(id: id, playlist: playlist),
              icon: SpotubeIcons.playlist,
              imageUrl: playlist.images.from200PxTo300PxOrSmallestImage(
                ImagePlaceholder.collection,
              ),
              playlist: playlist,
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
      ...visibleLibraryTiles,
      ...pinnedTiles,
    ];

    final router = context.watchRouter;

    final selectedIndex = tileList.indexWhere(
      (e) => router.currentPath.startsWith(e.pathPrefix),
    );

    if (!sidebarVisibleOf(context, layoutMode)) return child;

    final scaling = Theme.of(context).scaling;
    final collapsed = ref.watch(
      userPreferencesProvider.select((s) => s.sidebarCollapsed),
    );
    final showLabels = mediaQuery.lgAndUp && !context.iconOnlyNav && !collapsed;
    // A labelled sidebar is a fixed-width rail. Without this bound the
    // enclosing Row hands the column unbounded width; shadcn's
    // NavigationSidebar caps itself at 200, but a theme header that fills
    // the available width would then try to lay out at infinity.
    final labelSidebarWidth = context.sidebarWidth;
    // A theme-owned sidebar draws its own body; the host keeps the width,
    // divider, clearance and the docked player around it.
    final hasThemeSidebar =
        context.sidebarOwned && themeUiSlotExists(ref, 'sidebar.content');
    final hasThemeLibrary = themeUiSlotExists(ref, 'sidebar.library');
    // User collapse narrows even a theme-drawn sidebar, to the rail width
    // the host already uses for icon-only navigation.
    final leftPaneWidth = hasThemeSidebar
        ? (collapsed
            ? math.min(72 * scaling, labelSidebarWidth)
            : labelSidebarWidth)
        : (showLabels ? labelSidebarWidth : null);
    final bottomClearance = sidebarBottomClearanceOf(
      context,
      playerVisible: bottomPlayerVisibleOf(context, layoutMode),
      dock: playerDock,
      playerHeight: measuredPlayerHeight,
    );
    final hasThemeHeader = themeUiSlotExists(ref, 'sidebar.header');
    final hasThemeNavBefore = themeUiSlotExists(ref, 'sidebar.nav.before');
    final hasThemeNavAfter = themeUiSlotExists(ref, 'sidebar.nav.after');
    final hasThemeLibraryBefore =
        themeUiSlotExists(ref, 'sidebar.library.before');
    final hasThemeLibraryAfter =
        themeUiSlotExists(ref, 'sidebar.library.after');
    final hasThemePinsBefore = themeUiSlotExists(ref, 'sidebar.pins.before');
    final hasThemePinsAfter = themeUiSlotExists(ref, 'sidebar.pins.after');
    final hasThemeFooter = themeUiSlotExists(ref, 'sidebar.footer');

    final visiblePins =
        showLabels ? pinnedTiles : pinnedTiles.take(_maxRailPins).toList();
    final hasRailOverflow =
        !showLabels && pinnedTiles.length > visiblePins.length;

    // Pinned stations in pin order. Resolution happens per row inside
    // [SidebarStationPinTile] (favorites, history, then directory), so this
    // only slices keys for the rail cap — an unresolvable pin hides itself.
    // Drag ids are the raw favorite keys: the shared pins group drops
    // cross-type moves as no-ops (unknown id => null drop), so playlist and
    // station pins can never corrupt each other's order.
    final visibleStationKeys =
        showLabels ? stationPinIds : stationPinIds.take(_maxRailPins).toList();
    final hasStationOverflow =
        !showLabels && stationPinIds.length > visibleStationKeys.length;

    // Best-effort names for the drag ghosts below; the tile itself resolves
    // the full object. Favorites cover the common case; anything else drags
    // under its raw key.
    final favoriteStations = ref.watch(radioFavoritesProvider).asData?.value ??
        const <RadioStation>[];
    final stationNames = useMemoized(
      () => {
        for (final station in favoriteStations)
          station.favoriteKey: station.name,
      },
      [favoriteStations],
    );

    final List<NavigationBarItem> navigationButtons = [
      if (!(hasThemeHeader && showLabels))
        NavigationLabel(
          child: showLabels
              ? ThemeBrandMark(
                  branding: branding,
                  fontSize: 30,
                  color: colorScheme.foreground,
                )
              : const Text(""),
        ),
      for (final tile in sidebarTileList)
        NavigationButton(
          style: router.currentPath.startsWith(tile.pathPrefix)
              ? const ButtonStyle.secondary()
              : null,
          label: showLabels ? Text(tile.title) : null,
          // A fixed-width sidebar must not marquee its labels: the default
          // `NavigationOverflow.marquee` starts scrolling the moment the
          // label is a fraction wider than its box, which reads as clipped
          // text that slides sideways. Ellipsis keeps long names still.
          overflow: NavigationOverflow.ellipsis,
          child: Tooltip(
            tooltip: TooltipContainer(child: Text(tile.title)).call,
            child: Icon(tile.icon),
          ),
          onPressed: () {
            openSideBarTile(context, ref, tile);
          },
        ),
      if (showLabels && hasThemeNavAfter)
        const _ThemeSlotNavigationItem('sidebar.nav.after'),
      const NavigationDivider(),
      if (showLabels && hasThemeLibraryBefore)
        const _ThemeSlotNavigationItem('sidebar.library.before')
      else if (showLabels && !hasThemeLibrary)
        NavigationLabel(child: Text(context.l10n.library)),
      // A theme-drawn library group replaces the label, the tiles and the
      // trailing drop zone in one go; the before/after slots and the pins
      // below stay host-owned. Ignored in the rail, which cannot label rows.
      if (showLabels && hasThemeLibrary)
        const _ThemeSlotNavigationItem('sidebar.library')
      else ...[
        for (final tile in visibleLibraryTiles)
          SidebarReorderableItem(
            key: ValueKey('lib:${tile.id}'),
            group: SidebarReorderGroup.library,
            id: tile.id,
            onAcceptInGroup: (draggedId, targetId, {required bool after}) {
              final visible = [for (final t in visibleLibraryTiles) t.id];
              final drop = resolveSidebarDrop(
                visible,
                draggedId,
                targetId,
                after: after,
              );
              if (drop == null) return;
              ref.read(userPreferencesProvider.notifier).setSidebarLibraryOrder(
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
              alignment: showLabels ? AlignmentDirectional.centerStart : null,
              label: showLabels ? Text(tile.title) : null,
              overflow: NavigationOverflow.ellipsis,
              onPressed: () {
                openSideBarTile(context, ref, tile);
              },
              child: Tooltip(
                tooltip: TooltipContainer(child: Text(tile.title)).call,
                child: Icon(tile.icon),
              ),
            ),
          ),
        // Drop zone below the last library tile: dropping onto a row can
        // only move up to that row's index, so the very bottom needs its own
        // target.
        SidebarTrailingDropZone(
          key: const ValueKey('lib-end'),
          group: SidebarReorderGroup.library,
          visibleIds: [for (final t in visibleLibraryTiles) t.id],
          onAccept: (draggedId) {
            final visible = [for (final t in visibleLibraryTiles) t.id];
            final from = visible.indexOf(draggedId);
            if (from == -1) return;
            ref.read(userPreferencesProvider.notifier).setSidebarLibraryOrder(
                  moveSidebarEntry(visible, from, visible.length - 1),
                );
          },
        ),
      ],
      if (showLabels && hasThemeLibraryAfter)
        const _ThemeSlotNavigationItem('sidebar.library.after'),
      if (showLabels && hasThemePinsBefore)
        const _ThemeSlotNavigationItem('sidebar.pins.before'),
      if (pinnedTiles.isNotEmpty) ...[
        const NavigationDivider(),
        if (showLabels) _PinGroupHeading(title: context.l10n.pinned_playlists),
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
                side: sidebarPinCoverSide,
              ),
              title: tile.title,
            ),
            // The label navigates; the cover plays (see SidebarPinTile).
            row: SidebarPinTile(tile: tile, showLabels: showLabels),
          ),
        // Drop zone below the last pin (above the rail overflow tile, which
        // stays fixed): the only way to move a playlist to the very bottom.
        SidebarTrailingDropZone(
          key: const ValueKey('pins-end'),
          group: SidebarReorderGroup.pins,
          visibleIds: [for (final t in visiblePins) t.id.substring(4)],
          onAccept: (draggedId) {
            final stored = ref.read(userPreferencesProvider).pinnedPlaylistIds;
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
            overflow: NavigationOverflow.ellipsis,
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
      if (stationPinIds.isNotEmpty) ...[
        const _PinSectionGap(),
        if (showLabels) _PinGroupHeading(title: context.l10n.pinned_stations),
        for (final key in visibleStationKeys)
          SidebarReorderableItem(
            key: ValueKey('station-pin:$key'),
            group: SidebarReorderGroup.pins,
            id: key,
            onAcceptInGroup: (draggedId, targetId, {required bool after}) {
              final stored = ref.read(userPreferencesProvider).pinnedStationIds;
              final visible = List<String>.of(visibleStationKeys);
              final drop = resolveSidebarDrop(
                visible,
                draggedId,
                targetId,
                after: after,
              );
              if (drop == null) return;
              ref.read(userPreferencesProvider.notifier).setPinnedStationIds(
                    moveSidebarPin(stored, visible, drop.from, drop.to),
                  );
            },
            feedback: _sidebarDragGhost(
              context: context,
              leading: const Icon(SpotubeIcons.radio),
              title: stationNames[key] ?? key,
            ),
            // The whole row plays; there is no station-detail route to
            // navigate to (see SidebarStationPinTile).
            row: SidebarStationPinTile(
              favoriteKey: key,
              showLabels: showLabels,
            ),
          ),
        // Drop zone below the last station pin: the only way to move a
        // station to the very bottom of its block.
        SidebarTrailingDropZone(
          key: const ValueKey('station-pins-end'),
          group: SidebarReorderGroup.pins,
          visibleIds: visibleStationKeys,
          onAccept: (draggedId) {
            final stored = ref.read(userPreferencesProvider).pinnedStationIds;
            final visible = List<String>.of(visibleStationKeys);
            final from = visible.indexOf(draggedId);
            if (from == -1) return;
            ref.read(userPreferencesProvider.notifier).setPinnedStationIds(
                  moveSidebarPin(stored, visible, from, visible.length - 1),
                );
          },
        ),
        if (hasStationOverflow)
          NavigationButton(
            label: null,
            onPressed: () {
              context.navigateTo(const RadioRoute());
            },
            child: Tooltip(
              tooltip: const TooltipContainer(child: Text('Radio')).call,
              child: const Icon(SpotubeIcons.radio),
            ),
          ),
      ],
      if (showLabels && hasThemePinsAfter)
        const _ThemeSlotNavigationItem('sidebar.pins.after'),
    ];

    final backdropActive = ref.watch(themeBackdropActiveProvider);
    // Same rule as the label band below: real transparency also needs the
    // ground gone, even with no painted backdrop behind it.
    final transparentGround =
        backdropActive || ref.watch(realTransparencyActiveProvider);
    final navigationSidebar = NavigationSidebar(
      // Recreate the label subtree when the theme faces finish loading:
      // `IntrinsicWidth` measured the fallback face and registering a font
      // does not invalidate that cached paragraph width.
      key: ValueKey(fontsLoaded),
      index: selectedIndex,
      onSelected: (index) {
        openSideBarTile(context, ref, tileList[index]);
      },
      children: navigationButtons,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: leftPaneWidth,
          child: hasThemeSidebar
              // The theme owns the body; the host keeps the width box, the
              // divider, the bottom clearance and the docked player.
              ? Column(
                  children: [
                    const Expanded(
                      child: ThemeSlot(
                        'sidebar.content',
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                      ),
                    ),
                    Gap(bottomClearance),
                  ],
                )
              : Column(
                  children: [
                    if (showLabels && hasThemeHeader)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
                        child: ThemeSlot(
                          'sidebar.header',
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                        ),
                      ),
                    if (showLabels && hasThemeNavBefore)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: ThemeSlot(
                          'sidebar.nav.before',
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                        ),
                      ),
                    Expanded(
                      child: showLabels
                          // shadcn's pinned sidebar labels (NavigationLabel's
                          // SliverPersistentHeader delegate) paint
                          // `colorScheme.background` behind themselves, which is opaque
                          // and punches a solid band across the backdrop at every group
                          // heading. Transparent in this subtree only, and only while
                          // a backdrop is actually being painted: with no shell glass
                          // underneath, that band is the heading's real background.
                          // The header still hides rows scrolled under it because it is
                          // pinned over the backdrop layer, not over app content.
                          ? transparentGround
                              ? Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: () => colorScheme.copyWith(
                                      background: () => Colors.transparent,
                                    ),
                                  ),
                                  child: navigationSidebar,
                                )
                              : navigationSidebar
                          : NavigationRail(
                              // Opaque `background` by default (shadcn fills
                              // `colorScheme.background`); transparent with the
                              // ground, same as the label band above.
                              backgroundColor:
                                  transparentGround ? Colors.transparent : null,
                              alignment: NavigationRailAlignment.start,
                              index: selectedIndex,
                              onSelected: (index) {
                                openSideBarTile(context, ref, tileList[index]);
                              },
                              children: navigationButtons,
                            ),
                    ),
                    if (showLabels && hasThemeFooter)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: ThemeSlot(
                          'sidebar.footer',
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                        ),
                      )
                    else
                      SidebarFooter(compact: !showLabels),
                    Gap(bottomClearance),
                  ],
                ),
        ),
        const VerticalDivider(),
        Expanded(
          child: contentFooter == null
              ? child
              : Column(
                  children: [
                    Expanded(child: child),
                    LayoutBuilder(
                      builder: (context, constraints) => PlayerSeekWidth(
                        width: constraints.maxWidth,
                        child: contentFooter!,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A theme slot in the sidebar's sliver list. Only used in the labelled
/// sidebar, where [NavigationSidebar] lays every child out as a sliver.
class _ThemeSlotNavigationItem extends StatelessWidget
    implements NavigationBarItem {
  final String name;

  const _ThemeSlotNavigationItem(this.name);

  @override
  bool get selectable => false;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ThemeSlot(
          name,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
      ),
    );
  }
}

/// Compact group heading for the pin sections (pinned playlists, pinned
/// stations): ~22px tall instead of [NavigationLabel]'s fixed 48px
/// (`navigation_bar.dart`), small semibold muted text with tight padding.
///
/// A plain sliver, not a pinned header — the pin blocks are short and the
/// heading scrolls with them. Paints no background, so it never punches a
/// band across the backdrop like the package label delegate does.
class _PinGroupHeading extends StatelessWidget implements NavigationBarItem {
  final String title;

  const _PinGroupHeading({required this.title});

  @override
  bool get selectable => false;

  @override
  Widget build(BuildContext context) {
    final navData = Data.maybeOf<NavigationControlData>(context);
    if (navData?.containerType != NavigationContainerType.sidebar) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scaling = theme.scaling;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 * scaling,
          6 * scaling,
          16 * scaling,
          2 * scaling,
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12 * scaling,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Slim gap between the pinned-playlists and pinned-stations groups (6px),
/// replacing the full [NavigationDivider] (1px line + 2×8px padding ≈ 17px)
/// that used to separate them. Sidebar-only sliver; invisible in the rail.
class _PinSectionGap extends StatelessWidget implements NavigationBarItem {
  const _PinSectionGap();

  @override
  bool get selectable => false;

  @override
  Widget build(BuildContext context) {
    final navData = Data.maybeOf<NavigationControlData>(context);
    if (navData?.containerType != NavigationContainerType.sidebar) {
      return const SizedBox.shrink();
    }
    return SliverToBoxAdapter(
      child: SizedBox(height: 6 * Theme.of(context).scaling),
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
  double? playerHeight,
}) {
  // The docked player lays out under the content only and never overlaps the
  // sidebar, so the nav column runs to the window bottom with a small pad.
  if (dock == PlayerDock.docked) return 12 * scaling;
  // Theme player slots can grow the bar past the host's estimate; when the
  // real height is known, reserve it plus a small pad.
  if (playerVisible && playerHeight != null && playerHeight > 0) {
    return playerHeight + 12 * scaling;
  }
  final clearance = (lgAndUp ? 130 : 65) * scaling;
  if (!playerVisible || !progressBelow) return clearance;
  // `progress: below` adds the seek line under the transport controls.
  return clearance + 12 * scaling;
}

double sidebarBottomClearanceOf(
  BuildContext context, {
  required bool playerVisible,
  required PlayerDock dock,
  double? playerHeight,
}) {
  return sidebarClearance(
    lgAndUp: MediaQuery.sizeOf(context).lgAndUp,
    playerVisible: playerVisible,
    progressBelow: context.progressBelow,
    dock: dock,
    scaling: Theme.of(context).scaling,
    playerHeight: playerHeight,
  );
}
