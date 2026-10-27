import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/utils/theme_converter.dart';

/// Publishes the theme plugin's layout decisions to the widget tree.
///
/// Sits below the app theme so [Theme.of] is already scaled, and above every
/// page. Layout is the one thing a theme plugin may rewrite wholesale: card
/// sizes, gutters and corner radii come from here instead of the literals each
/// widget used to carry, and [ThemeLayout] picks between the shell shapes the
/// host ships.
///
/// The values themselves stay unscaled — multiplying by the active scaling
/// happens at read time in [AppLayoutX], so a nested theme override or a theme
/// transition animation resizes the UI without republishing this widget.
class AppLayout extends InheritedWidget {
  final ThemeTokens tokens;
  final ThemeRadius radii;
  final ThemeLayout layout;

  /// The footer shape the shell resolved for this window and user.
  ///
  /// Published here so the router shell and the sidebar share one answer
  /// instead of each combining the theme's claim with the user preference.
  final PlayerDock playerDock;

  /// `false` when the theme removed the volume control; null defers to the
  /// user's own visibility setting.
  final bool? volumeOverride;

  /// The theme's v3 spacing scale, in logical pixels at scaling 1.
  ///
  /// Null means the caller did not resolve one, in which case [AppLayoutX]
  /// derives the card gap from the v2 `tokens.gutter`.
  final ThemeSpacing? spacing;

  /// The theme's v3 motion scale.
  final ThemeMotion motion;

  /// `scale.spacing`, applied on top of `theme.scaling`.
  final double spacingScale;

  /// The status colours, which shadcn's `ColorScheme` has no slot for.
  final ThemeSemanticColors semanticColors;

  const AppLayout({
    super.key,
    required super.child,
    this.tokens = const ThemeTokens(),
    this.radii = const ThemeRadius(),
    this.layout = const ThemeLayout(),
    this.playerDock = PlayerDock.fullWidth,
    this.volumeOverride,
    this.spacing,
    this.motion = const ThemeMotion(),
    this.spacingScale = 1,
    this.semanticColors = const ThemeSemanticColors(),
  });

  @override
  bool updateShouldNotify(AppLayout oldWidget) {
    return oldWidget.tokens != tokens ||
        oldWidget.radii != radii ||
        oldWidget.layout != layout ||
        oldWidget.playerDock != playerDock ||
        oldWidget.volumeOverride != volumeOverride ||
        oldWidget.spacing != spacing ||
        oldWidget.motion != motion ||
        oldWidget.spacingScale != spacingScale ||
        oldWidget.semanticColors != semanticColors;
  }
}

/// Layout values for the nearest [AppLayout], in logical pixels.
///
/// Every getter folds in `theme.scaling`, which the app root already multiplies
/// by the theme's `density` (see `main.dart`), so density needs no handling
/// here. The min() / max() guards are what keep a plugin that asks for a
/// 400px-wide artist tile from having its badge row pushed out of the cell.
extension AppLayoutX on BuildContext {
  AppLayout? get _appLayout => getInheritedWidgetOfExactType<AppLayout>();

  ThemeTokens get _tokens => _appLayout?.tokens ?? const ThemeTokens();

  ThemeRadius get _radii => _appLayout?.radii ?? const ThemeRadius();

  ThemeLayout get _layout => _appLayout?.layout ?? const ThemeLayout();

  /// The theme's layout decisions, already resolved for the current window
  /// width (see `resolveLayout` in `theme_shell/resolved_layout.dart`).
  ThemeLayout get layout => _layout;

  /// The footer shape resolved once by the app root.
  PlayerDock get playerDock =>
      _appLayout?.playerDock ?? PlayerDock.fullWidth;

  /// The theme's volume-control override, if it declared one.
  bool? get volumeOverride => _appLayout?.volumeOverride;

  ThemeSemanticColors get _semanticColors =>
      _appLayout?.semanticColors ?? const ThemeSemanticColors();

  /// The success colour: a checkmark, a healthy state.
  Color get successColor =>
      ThemeConverter.parseColor(_semanticColors.success);

  /// Text on [successColor].
  Color get successForegroundColor =>
      ThemeConverter.parseColor(_semanticColors.successForeground);

  /// The warning colour: something the user should look at.
  Color get warningColor =>
      ThemeConverter.parseColor(_semanticColors.warning);

  /// Text on [warningColor].
  Color get warningForegroundColor =>
      ThemeConverter.parseColor(_semanticColors.warningForeground);

  /// The information colour.
  Color get infoColor => ThemeConverter.parseColor(_semanticColors.info);

  /// Text on [infoColor].
  Color get infoForegroundColor =>
      ThemeConverter.parseColor(_semanticColors.infoForeground);

  /// The sixth categorical colour, for the charts that need one more.
  Color get chart6Color => ThemeConverter.parseColor(_semanticColors.chart6);

  double get _scale => theme.scaling;

  /// Width of an album/playlist card, and edge length of its square cover.
  double get gridCardWidth => _tokens.cardWidth * _scale;

  /// Height of a grid cell or horizontal row holding album/playlist cards.
  ///
  /// Never shorter than the cover plus the title/badge block under it, which
  /// is where the 225 default came from.
  double get gridCardHeight {
    final content = gridCardWidth + 70 * _scale;
    return math.max(content, _tokens.cardHeight * _scale);
  }

  double get artistCardWidth => _tokens.artistCardWidth * _scale;

  /// Height of a cell holding artist cards.
  ///
  /// A mixed row has to reserve this much even for one artist, which is what
  /// `playbuttonCardExtent`'s `hasArtist` flag is for.
  double get _artistCardHeight {
    final content = artistAvatarSize + 80 * _scale;
    return math.max(content, _tokens.artistCardHeight * _scale);
  }

  /// The round avatar inside an artist card, sized from the card's width so it
  /// cannot outgrow the cell a theme widened only the height of.
  double get artistAvatarSize => artistCardWidth * 0.72;

  /// The gap between cards in a shelf or grid: the v3 `spacing.cardGap` when
  /// the theme declares it, otherwise the v2 `tokens.gutter`.
  double get layoutGutter => _spacing.cardGap * _spacingUnit;

  /// Cover-art corner radius. Small because artwork is the smallest surface
  /// the radius scale reaches.
  double get cardCornerRadius => _radii.small * _scale;

  /// Radius of the panel [insetChrome] floats the content in — the largest
  /// surface the radius scale reaches.
  double get surfaceCornerRadius => _radii.large * _scale;

  /// A radius that reads as "fully round" at any size. Flutter folds overlapping
  /// corner radii down, so a huge pill is safe on a short chip.
  double get pillCornerRadius => _radii.pill * _scale;

  ThemeSpacing get _spacing =>
      _appLayout?.spacing ?? ThemeSpacing(cardGap: _tokens.gutter);

  /// The theme's motion scale, for the transitions the app owns.
  ThemeMotion get motion => _appLayout?.motion ?? const ThemeMotion();

  double get _spacingUnit => _scale * (_appLayout?.spacingScale ?? 1);

  /// Padding inside a page's own surface.
  double get pagePadding => _spacing.page * _spacingUnit;

  /// The horizontal gutter between a page's content and the window edge.
  double get pageHorizontalPadding => _spacing.pageHorizontal * _spacingUnit;

  /// Vertical space between two sections of a page.
  double get sectionGap => _spacing.section * _spacingUnit;

  /// Space between two cards in a shelf or grid.
  double get cardGap => _spacing.cardGap * _spacingUnit;

  /// Whether the content floats in a rounded panel instead of filling the
  /// window edge to edge.
  bool get insetChrome => _layout.chrome == ThemeChrome.inset;

  /// Whether navigation stays icon-only at every width.
  bool get iconOnlyNav => _layout.nav == ThemeNav.rail;

  /// Whether the seek bar spans the player below the transport controls
  /// instead of docking above them.
  bool get progressBelow => _layout.progress == ThemeProgress.below;

  /// Gap an [insetChrome] panel leaves to the window edge.
  double get chromeInsetGap => 8 * _scale;

  /// The backdrop an [insetChrome] panel floats on.
  ///
  /// Derived from the theme's own background rather than a contract field: the
  /// panel paints `background`, so the ring has to be a deterministic shade of
  /// it — otherwise a theme could ask for a backdrop its palette never
  /// accounted for. Light takes only a hint of black, since a dark deepen
  /// would frame a white UI in charcoal.
  Color get chromeInkColor {
    final depth = theme.brightness == Brightness.dark ? 0.55 : 0.12;
    return Color.lerp(
        theme.colorScheme.background, const Color(0xFF000000), depth)!;
  }
}

/// Height a card row or grid cell needs, padding included.
///
/// The artist card is taller than the album/playlist one — round avatar, name
/// and a badge row pinned to the bottom — so a mixed row has to reserve the
/// artist extent for even a single artist in it. Both numbers follow the
/// active theme plugin and the theme's scaling, which the cards' own avatars
/// and text already do; a fixed cell height clips the badge row instead.
double playbuttonCardExtent(
  BuildContext context, {
  required bool hasArtist,
}) {
  return hasArtist ? context._artistCardHeight : context.gridCardHeight;
}
