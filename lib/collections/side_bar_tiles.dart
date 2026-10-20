import 'package:auto_route/auto_route.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/l10n/l10n.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';

class SideBarTiles {
  final IconData icon;
  final String title;
  final String id;
  final String pathPrefix;
  final PageRouteInfo route;

  /// Optional small cover art. Null for the static tiles; set for pinned
  /// playlist tiles, which render the cover in the icon slot so the
  /// sidebar width never changes.
  final String? imageUrl;

  /// The backing playlist for pinned playlist tiles; null for static tiles.
  /// Carried so the pin row can play the collection without re-resolving it.
  final SpotubeSimplePlaylistObject? playlist;

  SideBarTiles({
    required this.icon,
    required this.title,
    required this.id,
    required this.route,
    required this.pathPrefix,
    this.imageUrl,
    this.playlist,
  });
}

List<SideBarTiles> getSidebarTileList(AppLocalizations l10n) => [
      SideBarTiles(
        id: "home",
        pathPrefix: "/home",
        route: const HomeRoute(),
        icon: SpotubeIcons.home,
        title: l10n.browse,
      ),
      SideBarTiles(
        id: "radio",
        pathPrefix: "/radio",
        route: const RadioRoute(),
        icon: SpotubeIcons.radio,
        title: "Radio",
      ),
      SideBarTiles(
        id: "stats",
        pathPrefix: "/stats",
        route: const StatsRoute(),
        icon: SpotubeIcons.chart,
        title: l10n.stats,
      ),
    ];

List<SideBarTiles> getSidebarLibraryTileList(AppLocalizations l10n) => [
      SideBarTiles(
        id: "playlists",
        pathPrefix: "/library/playlists",
        title: l10n.playlists,
        route: const UserPlaylistsRoute(),
        icon: SpotubeIcons.playlist,
      ),
      SideBarTiles(
        id: "artists",
        pathPrefix: "/library/artists",
        title: l10n.artists,
        route: const UserArtistsRoute(),
        icon: SpotubeIcons.artist,
      ),
      SideBarTiles(
        id: "albums",
        pathPrefix: "/library/albums",
        title: l10n.albums,
        route: const UserAlbumsRoute(),
        icon: SpotubeIcons.album,
      ),
      SideBarTiles(
        id: "local_library",
        pathPrefix: "/library/local",
        title: l10n.local_library,
        route: const UserLocalLibraryRoute(),
        icon: SpotubeIcons.device,
      ),
    ];

List<SideBarTiles> getNavbarTileList(AppLocalizations l10n) => [
      SideBarTiles(
        id: "home",
        pathPrefix: "/home",
        route: const HomeRoute(),
        icon: SpotubeIcons.home,
        title: l10n.browse,
      ),
      SideBarTiles(
        id: "search",
        pathPrefix: "/search",
        route: const SearchRoute(),
        icon: SpotubeIcons.search,
        title: l10n.search,
      ),
      SideBarTiles(
        id: "radio",
        pathPrefix: "/radio",
        route: const RadioRoute(),
        icon: SpotubeIcons.radio,
        title: "Radio",
      ),
      SideBarTiles(
        id: "library",
        pathPrefix: "/library",
        route: const UserPlaylistsRoute(),
        icon: SpotubeIcons.library,
        title: l10n.library,
      ),
      SideBarTiles(
        id: "stats",
        pathPrefix: "/stats",
        route: const StatsRoute(),
        icon: SpotubeIcons.chart,
        title: l10n.stats,
      ),
    ];

/// Whether the mobile bottom navigation bar is visible for the given window
/// and layout mode. Mirrors `SpotubeNavigationBar`'s own gate, so pages that
/// hide their inline search rows (Home, Radio) stay in sync with it: the
/// Search tab is the only mobile entry, the rows are the desktop entry.
bool isBottomNavVisible(Size size, LayoutMode layoutMode) =>
    !(layoutMode == LayoutMode.extended ||
        (size.mdAndUp && layoutMode == LayoutMode.adaptive));
