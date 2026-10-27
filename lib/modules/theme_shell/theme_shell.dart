import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// The shell fields a theme may take ownership of.
///
/// These are the keys the contract accepts in `layout.enforce`. A field that
/// conflicts with an explicit user choice only takes effect when its key is
/// listed; fields with no user-facing counterpart (section order, window
/// title-bar geometry) apply whenever the theme sends them.
abstract final class ThemeShellKeys {
  static const nav = 'nav';
  static const navItems = 'navItems';
  static const navbarItems = 'navbarItems';
  static const libraryItems = 'libraryItems';
  static const navOrder = 'navOrder';
  static const player = 'player';
  static const playerDock = 'playerDock';
  static const volume = 'volume';
  static const home = 'home';
  static const settings = 'settings';
  static const titlebar = 'titlebar';
  static const splash = 'splash';
}

/// The breakpoint a responsive variant targets.
enum ThemeBreakpoint { compact, medium, expanded }

/// Which tier the window width falls into.
///
/// The thresholds are the host's own: `compact` ends where the sidebar stops
/// labelling itself (md, 820), `medium` where it becomes a labelled rail
/// (lg, 1024), and everything wider is expanded. A theme's `compact` override
/// therefore means the same shape the host calls compact.
ThemeBreakpoint themeBreakpointForWidth(double width) {
  if (width <= 820) return ThemeBreakpoint.compact;
  if (width <= 1024) return ThemeBreakpoint.medium;
  return ThemeBreakpoint.expanded;
}

const _variantNames = <String, ThemeBreakpoint>{
  'compact': ThemeBreakpoint.compact,
  'xs': ThemeBreakpoint.compact,
  'sm': ThemeBreakpoint.compact,
  'medium': ThemeBreakpoint.medium,
  'md': ThemeBreakpoint.medium,
  'expanded': ThemeBreakpoint.expanded,
  'lg': ThemeBreakpoint.expanded,
  'xl': ThemeBreakpoint.expanded,
  '2xl': ThemeBreakpoint.expanded,
};

/// Applies the responsive variant that matches [width] on top of [base].
///
/// Only the fields a variant actually carries are replaced; everything else
/// keeps the base value, which is what lets a theme override just the volume
/// control at one width. Variants with an unknown name are ignored rather than
/// guessed at, so a typo cannot reshape the app on one machine only.
ThemeLayout applyResponsiveLayout(ThemeLayout base, double width) {
  final variant = _variantFor(base.responsive, width);
  if (variant == null) return base;

  return base.copyWith(
    chrome: _chrome(variant['chrome']) ?? base.chrome,
    nav: _nav(variant['nav']) ?? base.nav,
    progress: _progress(variant['progress']) ?? base.progress,
    player: _player(base.player, variant['player']),
    navItems: _strings(variant['navItems']) ?? base.navItems,
    navbarItems: _strings(variant['navbarItems']) ?? base.navbarItems,
    libraryItems: _strings(variant['libraryItems']) ?? base.libraryItems,
    home: _mapMerge(base.home, variant['home']),
    settings: _mapMerge(base.settings, variant['settings']),
    titlebar: _mapMerge(base.titlebar, variant['titlebar']),
    splash: _mapMerge(base.splash, variant['splash']),
  );
}

Map<String, dynamic>? _variantFor(
  Map<String, dynamic> responsive,
  double width,
) {
  if (responsive.isEmpty) return null;
  final wanted = themeBreakpointForWidth(width);
  for (final entry in responsive.entries) {
    if (_variantNames[entry.key] != wanted) continue;
    final raw = entry.value;
    if (raw is Map) return raw.cast<String, dynamic>();
  }
  return null;
}

bool themeEnforces(ThemeLayout layout, String key) =>
    layout.enforce.contains(key);

/// The bar shape after the theme's claim, if any.
///
/// The host has two footer shapes, so the theme's four names collapse onto
/// them: `compact` is the bar tucked under the content, everything else keeps
/// the full-width footer. Without the `playerDock` claim the user's own choice
/// stands.
PlayerDock resolvePlayerDock(ThemeLayout layout, PlayerDock userDock) {
  if (!themeEnforces(layout, ThemeShellKeys.playerDock)) return userDock;
  return layout.player.dock == ThemePlayerDock.compact
      ? PlayerDock.docked
      : PlayerDock.fullWidth;
}

/// Resolves the ids a navigation surface should show, in order.
///
/// [hostIds] is the complete set the host implements, [themeIds] the theme's
/// requested list (which may be empty), and [screens] the theme-screen ids that
/// a `screen:<id>` entry may point at.
///
/// With membership enforced the theme's list is the surface: valid entries in
/// the theme's order, falling back to the host's list when the filter leaves
/// nothing (a theme that names only unknown ids must not blank the nav). With
/// only order enforced the theme's entries come first and the rest follow, so
/// a theme can move an entry without hiding the ones it did not mention.
List<String> resolveThemeItems({
  required List<String> hostIds,
  required List<String> themeIds,
  required Set<String> screens,
  required bool enforceMembership,
  required bool enforceOrder,
}) {
  final known = hostIds.toSet();
  final chosen = <String>[];
  for (final id in themeIds) {
    final valid = known.contains(id) ||
        (id.startsWith('screen:') &&
            screens.contains(id.substring('screen:'.length)));
    if (valid && !chosen.contains(id)) chosen.add(id);
  }

  if (enforceMembership) {
    return chosen.isEmpty ? hostIds : chosen;
  }
  if (enforceOrder && chosen.isNotEmpty) {
    return [...chosen, ...hostIds.where((id) => !chosen.contains(id))];
  }
  return hostIds;
}

/// Resolves a `home`/`settings` section list.
///
/// Section membership is opt-in through `enforce`: a theme that carries a
/// partial list without claiming it must not silently delete the sections it
/// did not mention. Unknown ids are dropped and duplicates collapse.
List<String> resolveThemeSections({
  required List<String> defaults,
  required Map<String, dynamic> block,
  required bool enforced,
}) {
  if (!enforced) return defaults;
  final raw = block['sections'];
  if (raw is! List) return defaults;

  final known = defaults.toSet();
  final ids = <String>[];
  for (final value in raw) {
    if (value is! String || !known.contains(value) || ids.contains(value)) {
      continue;
    }
    ids.add(value);
  }
  return ids.isEmpty ? defaults : ids;
}

ThemePlayerLayout _player(ThemePlayerLayout base, Object? raw) {
  if (raw is! Map) return base;
  final map = raw.cast<String, dynamic>();
  return base.copyWith(
    dock: _dock(map['dock']) ?? base.dock,
    showTrackDetails:
        _bool(map['showTrackDetails']) ?? base.showTrackDetails,
    showActions: _bool(map['showActions']) ?? base.showActions,
    showVolume: _bool(map['showVolume']) ?? base.showVolume,
    showLyrics: _bool(map['showLyrics']) ?? base.showLyrics,
    showProgress: _bool(map['showProgress']) ?? base.showProgress,
  );
}

Map<String, dynamic> _mapMerge(
  Map<String, dynamic> base,
  Object? override,
) {
  if (override is! Map) return base;
  return {...base, ...override.cast<String, dynamic>()};
}

List<String>? _strings(Object? raw) {
  if (raw is! List) return null;
  return [for (final value in raw) if (value is String) value];
}

bool? _bool(Object? raw) => raw is bool ? raw : null;

ThemeChrome? _chrome(Object? raw) => switch (raw) {
      'flat' => ThemeChrome.flat,
      'inset' => ThemeChrome.inset,
      _ => null,
    };

ThemeNav? _nav(Object? raw) => switch (raw) {
      'labels' => ThemeNav.labels,
      'rail' => ThemeNav.rail,
      _ => null,
    };

ThemeProgress? _progress(Object? raw) => switch (raw) {
      'inline' => ThemeProgress.inlinePlacement,
      'below' => ThemeProgress.below,
      _ => null,
    };

ThemePlayerDock? _dock(Object? raw) => switch (raw) {
      'full' => ThemePlayerDock.full,
      'compact' => ThemePlayerDock.compact,
      'floating' => ThemePlayerDock.floating,
      'stage' => ThemePlayerDock.stage,
      _ => null,
    };

/// Title-bar height in logical pixels, or null when the theme did not set it.
double? themeTitlebarHeight(ThemeLayout layout) =>
    _number(layout.titlebar['height'], min: 0, max: 200);

/// Title-bar horizontal padding in logical pixels.
double? themeTitlebarPadding(ThemeLayout layout) =>
    _number(layout.titlebar['padding'], min: 0, max: 48);

/// Whether the host's back control should appear, when the theme says.
bool? themeTitlebarShowBack(ThemeLayout layout) {
  final value = layout.titlebar['showBack'];
  return value is bool ? value : null;
}

double? _number(Object? raw, {required double min, required double max}) {
  if (raw is! num) return null;
  final value = raw.toDouble();
  if (!value.isFinite) return null;
  return value.clamp(min, max).toDouble();
}
