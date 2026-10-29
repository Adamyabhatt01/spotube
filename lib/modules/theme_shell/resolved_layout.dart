import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';

/// Every shell decision a theme's `layout` block contributes, resolved once.
///
/// The raw [ThemeLayout] still reaches widgets that only need a value it
/// carries (chrome shape, seek placement, title-bar geometry). This class is
/// for the decisions that also involve the host or the user: which breakpoint
/// variant applies, which footer dock shape wins, and whether the theme hides
/// the volume control. Resolving them once at the app root keeps the sidebar,
/// the router shell and both player bars from re-deriving the same answer from
/// different inputs.
class ResolvedLayout {
  /// The layout with the current breakpoint variant merged in.
  final ThemeLayout layout;

  /// The tier the window width fell into.
  final ThemeBreakpoint breakpoint;

  /// The footer shape after the theme's claim and the user's preference.
  final PlayerDock playerDock;

  /// `false` when the theme removes the volume control, `null` when the
  /// user's own visibility setting stands.
  ///
  /// There is deliberately no `true`: a theme can hide a control it designed
  /// its player without, but it cannot force one back onto a user who chose
  /// to keep it hidden.
  final bool? volumeOverride;

  const ResolvedLayout({
    this.layout = const ThemeLayout(),
    this.breakpoint = ThemeBreakpoint.expanded,
    this.playerDock = PlayerDock.fullWidth,
    this.volumeOverride,
  });

  /// Whether the theme named the sidebar's top navigation surface.
  bool get navItemsDeclared => layout.navItems.isNotEmpty;

  /// Whether the theme named the sidebar's library group.
  bool get libraryItemsDeclared => layout.libraryItems.isNotEmpty;

  /// Whether the theme named the bottom navigation bar.
  bool get navbarItemsDeclared => layout.navbarItems.isNotEmpty;

  /// Whether the theme draws the sidebar body instead of the host.
  bool get sidebarOwned => layout.sidebar == ThemeSidebar.theme;

  /// Whether the theme asked for a right-hand aside.
  bool get asideEnabled => layout.aside == ThemeAside.theme;

  /// The theme's sidebar width in logical px at scaling 1, or null for the
  /// host default.
  double? get sidebarWidth => layout.sidebarWidth;

  /// The theme's aside width in logical px at scaling 1, or null for the host
  /// default.
  double? get asideWidth => layout.asideWidth;
}

/// Resolves a theme's layout for the current window and user choices.
///
/// The only entry point widgets should use: `applyResponsiveLayout` selects
/// the breakpoint variant, and the two user-preference conflicts (footer dock
/// and volume visibility) are settled here rather than at each consumer.
ResolvedLayout resolveLayout(
  ThemeLayout base, {
  required double width,
  required PlayerDock userDock,
}) {
  final layout = applyResponsiveLayout(base, width);
  return ResolvedLayout(
    layout: layout,
    breakpoint: themeBreakpointForWidth(width),
    playerDock: _resolveDock(layout, userDock),
    volumeOverride: layout.player.showVolume ? null : false,
  );
}

/// `compact` is the only dock name that asks for a shape the user did not
/// pick. `full` and `floating` describe the host's default footer, and
/// `stage` changes the content around the player rather than its dock, so all
/// three defer to the user's preference.
PlayerDock _resolveDock(ThemeLayout layout, PlayerDock userDock) {
  if (layout.player.dock != ThemePlayerDock.compact) return userDock;
  return PlayerDock.docked;
}
