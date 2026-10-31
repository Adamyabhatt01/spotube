import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';

/// The host sections a theme page may hang under.
///
/// An unknown (or missing) `parent` is a rejected page: it is never routed and
/// never injected into navigation. This is the host half of the contract the
/// theme-side validator cannot check — it has no idea which sections exist.
const themePageParents = <String>{
  'sidebar',
  'library',
  'library.local',
  'settings',
};

/// The display title of a theme page: trimmed, capped, with the id as
/// fallback so a page is never an unnamed hole in a nav list.
String themePageTitle(ThemeUiPage page) {
  final title = page.title?.trim();
  if (title == null || title.isEmpty) return page.id;
  return title.length > 60 ? title.substring(0, 60) : title;
}

/// The page named [id], when the active document declares it, it is visible,
/// and its parent is a host section.
ThemeUiPage? routableThemePage(ThemeUiDocument? ui, String id) {
  if (ui == null) return null;
  for (final page in ui.pages) {
    if (page.id != id) continue;
    if (!page.visible || !themePageParents.contains(page.parent)) return null;
    return page;
  }
  return null;
}

/// The pages injected into one host section, in declaration order.
List<SideBarTiles> themePageTiles(ThemeUiDocument? ui, {required String parent}) {
  if (ui == null || !themePageParents.contains(parent)) return const [];
  final tiles = <SideBarTiles>[];
  for (final page in ui.pages) {
    if (page.parent != parent || !page.visible) continue;
    tiles.add(
      SideBarTiles(
        id: 'page:${page.id}',
        title: themePageTitle(page),
        pathPrefix: '/theme-page/${page.id}',
        route: ThemeRoute(pageId: page.id),
        icon: _themePageIcon(page.icon),
      ),
    );
  }
  return tiles;
}

IconData _themePageIcon(String? name) {
  return switch (name) {
    'equalizer' => SpotubeIcons.equalizer,
    'list' => SpotubeIcons.list,
    'playlist' => SpotubeIcons.playlist,
    'download' => SpotubeIcons.download,
    'settings' => SpotubeIcons.settings,
    'search' => SpotubeIcons.search,
    'library' => SpotubeIcons.library,
    'home' => SpotubeIcons.home,
    'radio' => SpotubeIcons.radio,
    'device' => SpotubeIcons.device,
    _ => SpotubeIcons.magic,
  };
}

/// The theme's own screens as navigation destinations.
///
/// A theme that names `screen:<id>` in `navItems`, `navbarItems` or
/// `libraryItems` gets an entry that opens that screen through the theme
/// overlay stack, so the shell can gain destinations the host never shipped.
Map<String, SideBarTiles> themeScreenTiles(ThemeUiDocument? ui) {
  if (ui == null) return const {};
  final tiles = <String, SideBarTiles>{};
  for (final entry in ui.screens.entries) {
    final title = entry.value.title?.trim();
    tiles['screen:${entry.key}'] = SideBarTiles.screen(
      id: entry.key,
      title: title == null || title.isEmpty
          ? entry.key
          : (title.length > 40 ? title.substring(0, 40) : title),
    );
  }
  return tiles;
}

/// Applies a theme's entry list to a host-ordered navigation surface.
///
/// [host] is the complete set the surface implements. A non-empty [themeIds]
/// list replaces the surface, in the theme's order: entries it names are
/// pulled out of [host] or resolved from [screens], and everything else is
/// left out. An empty list keeps the user's own order untouched.
List<SideBarTiles> themeEntriesFor({
  required List<SideBarTiles> host,
  required List<String> themeIds,
  required Map<String, SideBarTiles> screens,
}) {
  if (themeIds.isEmpty) return host;

  final byId = {for (final tile in host) tile.id: tile};
  // The resolver matches bare ids; this map is keyed by the prefixed
  // (`screen:<id>`, `page:<id>`) destinations the navigation surface uses.
  final screenIds = {
    for (final key in screens.keys)
      key.contains(':') ? key.substring(key.indexOf(':') + 1) : key,
  };
  final ids = resolveThemeItems(
    hostIds: [for (final tile in host) tile.id],
    themeIds: themeIds,
    screens: screenIds,
  );

  final result = <SideBarTiles>[];
  for (final id in ids) {
    final tile = byId[id] ?? screens[id];
    if (tile != null) result.add(tile);
  }
  return result;
}

/// Opens a navigation entry, whether it is a host route or a theme screen.
void openSideBarTile(
  BuildContext context,
  WidgetRef ref,
  SideBarTiles tile,
) {
  final screen = tile.screenId;
  if (screen != null) {
    pushThemeUiScreen(ref, screen);
    return;
  }
  final route = tile.route;
  if (route != null) context.navigateTo(route);
}
