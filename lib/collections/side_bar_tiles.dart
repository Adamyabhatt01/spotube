import 'package:auto_route/auto_route.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/l10n/l10n.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// The ids a theme may name in `layout.navItems` and `libraryItems`.
///
/// These mirror the contract's closed registries. A theme may also name
/// `screen:<id>` to link one of its own `ui.screens`; that entry has no route
/// and opens through the theme screen stack instead.
const sidebarNavIds = <String>['home', 'radio', 'stats', 'search'];
const sidebarLibraryIds = <String>[
  'playlists',
  'artists',
  'albums',
  'stations',
  'local_library',
];
const navbarNavIds = <String>['home', 'search', 'radio', 'library', 'stats'];

class SideBarTiles {
  final IconData icon;
  final String title;
  final String id;
  final String pathPrefix;

  /// The route an entry opens, or null for a theme-screen entry.
  final PageRouteInfo? route;

  /// Set for a `screen:<id>` entry; the sidebar opens the theme screen.
  final String? screenId;

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
    required this.pathPrefix,
    this.route,
    this.screenId,
    this.imageUrl,
    this.playlist,
  });

  /// An entry that links a screen the theme owns.
  factory SideBarTiles.screen({
    required String id,
    required String title,
  }) {
    return SideBarTiles(
      id: 'screen:$id',
      screenId: id,
      title: title,
      pathPrefix: '/theme/$id',
      icon: SpotubeIcons.magic,
    );
  }
}

SideBarTiles _sidebarNavTile(AppLocalizations l10n, String id) {
  return switch (id) {
    'home' => SideBarTiles(
        id: "home",
        pathPrefix: "/home",
        route: const HomeRoute(),
        icon: SpotubeIcons.home,
        title: l10n.browse,
      ),
    'search' => SideBarTiles(
        id: "search",
        pathPrefix: "/search",
        route: const SearchRoute(),
        icon: SpotubeIcons.search,
        title: l10n.search,
      ),
    'radio' => SideBarTiles(
        id: "radio",
        pathPrefix: "/radio",
        route: const RadioRoute(),
        icon: SpotubeIcons.radio,
        title: "Radio",
      ),
    'stats' => SideBarTiles(
        id: "stats",
        pathPrefix: "/stats",
        route: const StatsRoute(),
        icon: SpotubeIcons.chart,
        title: l10n.stats,
      ),
    _ => throw ArgumentError.value(id, 'id', 'unknown sidebar entry'),
  };
}

/// Every top navigation entry the host implements, in the default order.
///
/// Search is part of the registry but not of the default sidebar: a theme may
/// put it there through `navItems`, which is what the contract's `navItems`
/// list has always named.
List<SideBarTiles> getSidebarTileRegistry(AppLocalizations l10n) => [
      for (final id in sidebarNavIds) _sidebarNavTile(l10n, id),
    ];

List<SideBarTiles> getSidebarTileList(AppLocalizations l10n) => [
      for (final id in const ['home', 'radio', 'stats'])
        _sidebarNavTile(l10n, id),
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
      // The stations the user bookmarked with the heart on a station card.
      // They were only reachable from the Radio page's own rail, so there was
      // nowhere to review the list or drop one.
      SideBarTiles(
        id: "stations",
        pathPrefix: "/library/stations",
        title: l10n.stations,
        route: const UserRadioStationsRoute(),
        icon: SpotubeIcons.radio,
      ),
      SideBarTiles(
        id: "local_library",
        pathPrefix: "/library/local",
        title: l10n.local_library,
        route: const UserLocalLibraryRoute(),
        icon: SpotubeIcons.device,
      ),
    ];

SideBarTiles _navbarTile(AppLocalizations l10n, String id) {
  if (id == 'library') {
    return SideBarTiles(
      id: "library",
      pathPrefix: "/library",
      route: const UserPlaylistsRoute(),
      icon: SpotubeIcons.library,
      title: l10n.library,
    );
  }
  return _sidebarNavTile(l10n, id);
}

List<SideBarTiles> getNavbarTileRegistry(AppLocalizations l10n) => [
      for (final id in navbarNavIds) _navbarTile(l10n, id),
    ];

List<SideBarTiles> getNavbarTileList(AppLocalizations l10n) =>
    getNavbarTileRegistry(l10n);

/// Whether the mobile bottom navigation bar is visible for the given window
/// and layout mode. Mirrors `SpotubeNavigationBar`'s own gate, so pages that
/// hide their inline search rows (Home, Radio) stay in sync with it: the
/// Search tab is the only mobile entry, the rows are the desktop entry.
bool isBottomNavVisible(Size size, LayoutMode layoutMode) =>
    !(layoutMode == LayoutMode.extended ||
        (size.mdAndUp && layoutMode == LayoutMode.adaptive));
