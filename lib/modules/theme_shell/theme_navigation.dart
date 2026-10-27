import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';

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
  // The resolver matches bare screen ids; this map is keyed by the
  // `screen:<id>` destinations the navigation surface uses.
  final screenIds = {
    for (final key in screens.keys)
      key.startsWith('screen:') ? key.substring('screen:'.length) : key,
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
