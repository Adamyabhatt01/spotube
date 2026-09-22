part of 'metadata.dart';

@freezed
class ThemeDefinition with _$ThemeDefinition {
  const factory ThemeDefinition({
    required ThemeColors light,
    required ThemeColors dark,
    @Default(ThemeSurfaces()) ThemeSurfaces surfaces,
    @Default(ThemeBackground()) ThemeBackground background,
    @Default(ThemeRadius()) ThemeRadius radius,
    @Default(1.0) double density,
    @Default(ThemeTokens()) ThemeTokens tokens,
    @Default(ThemeLayout()) ThemeLayout layout,
    @JsonKey(name: 'dynamic') DynamicTheme? dynamicTheme,
  }) = _ThemeDefinition;

  factory ThemeDefinition.fromJson(Map<String, dynamic> json) =>
      _$ThemeDefinitionFromJson(json);
}

/// Which shell the app draws, as opposed to what it is painted with.
///
/// [ThemeTokens] and [ThemeRadius] resize widgets that already exist. This
/// block picks between layouts the host ships: a theme that wants to read as a
/// different application can inset its content into a floating panel, collapse
/// the navigation to icons and move the seek bar out of the player, without
/// Spotube growing a hardcoded skin for it.
///
/// Every field defaults to what the app did before this existed, and
/// `unknownEnumValue` keeps a typo in a plugin from taking down the whole
/// theme: `fromJson` would otherwise throw and the caller falls back to the
/// built-in palette.
@freezed
class ThemeLayout with _$ThemeLayout {
  const factory ThemeLayout({
    /// `inset` floats the page content in a rounded panel over a darkened
    /// backdrop, leaving the player bar full width on the backdrop.
    @JsonKey(unknownEnumValue: ThemeChrome.flat)
    @Default(ThemeChrome.flat)
    ThemeChrome chrome,

    /// `rail` keeps the navigation icon-only at every width instead of
    /// trading width for labels.
    @JsonKey(unknownEnumValue: ThemeNav.labels)
    @Default(ThemeNav.labels)
    ThemeNav nav,

    /// `below` spans the seek bar across the full player width instead of
    /// docking it above the transport controls.
    @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
    @Default(ThemeProgress.inlinePlacement)
    ThemeProgress progress,
  }) = _ThemeLayout;

  factory ThemeLayout.fromJson(Map<String, dynamic> json) =>
      _$ThemeLayoutFromJson(json);
}

enum ThemeChrome {
  flat,
  inset,
}

enum ThemeNav {
  labels,
  rail,
}

enum ThemeProgress {
  @JsonValue('inline')
  inlinePlacement,
  below,
}

/// Plugin-controlled geometry for the parts of the UI a theme is allowed to
/// resize: the media cards and the space around them.
///
/// Values are logical pixels at density 1 and scaling 1, before the host
/// clamps them ([sanitizeThemeDefinition]) and before `density`/`scaling` are
/// applied (`AppLayoutX`, in `modules/app_layout/app_layout.dart`). Widths and
/// heights are independent on purpose — a
/// theme that wants wider artist tiles (the usual request) sets
/// [artistCardWidth] without having to also grow the row.
@freezed
class ThemeTokens with _$ThemeTokens {
  const factory ThemeTokens({
    /// Width of an album/playlist card, and edge of its square cover.
    @Default(150.0) double cardWidth,

    /// Height of an album/playlist card row or grid cell.
    @Default(225.0) double cardHeight,

    /// Width of an artist card. Always at least as wide as its avatar.
    @Default(180.0) double artistCardWidth,

    /// Height of an artist card row or grid cell.
    @Default(250.0) double artistCardHeight,

    /// Space between cards, and between a card row's blocks.
    @Default(12.0) double gutter,

    /// Font family to render text with. Resolved against the platform's
    /// font fallbacks, never loaded from the plugin.
    String? fontFamily,
  }) = _ThemeTokens;

  factory ThemeTokens.fromJson(Map<String, dynamic> json) =>
      _$ThemeTokensFromJson(json);
}

@freezed
class ThemeColors with _$ThemeColors {
  const factory ThemeColors({
    required String background,
    required String foreground,
    required String card,
    required String cardForeground,
    required String primary,
    required String primaryForeground,
    required String secondary,
    required String secondaryForeground,
    required String muted,
    required String mutedForeground,
    required String accent,
    required String accentForeground,
    required String destructive,
    required String destructiveForeground,
    required String border,
    required String input,
    required String ring,
  }) = _ThemeColors;

  factory ThemeColors.fromJson(Map<String, dynamic> json) =>
      _$ThemeColorsFromJson(json);
}

@freezed
class ThemeSurfaces with _$ThemeSurfaces {
  const factory ThemeSurfaces({
    @Default(0.8) double opacity,
    @Default(10.0) double blur,

    /// Optional surface tint as `#RRGGBB` or Flutter-native `#AARRGGBB`.
    String? tint,
  }) = _ThemeSurfaces;

  factory ThemeSurfaces.fromJson(Map<String, dynamic> json) =>
      _$ThemeSurfacesFromJson(json);
}

@freezed
class ThemeBackground with _$ThemeBackground {
  const factory ThemeBackground({
    @Default(ThemeBackgroundSource.none) ThemeBackgroundSource source,
    @Default(0.0) double opacity,
    @Default(0.0) double blur,

    /// Optional veil over the background image as `#RRGGBB` or
    /// Flutter-native `#AARRGGBB` (alpha honored, e.g. `#80000000`
    /// is 50% black). Brightness-adapted by the host layer.
    String? overlay,
  }) = _ThemeBackground;

  factory ThemeBackground.fromJson(Map<String, dynamic> json) =>
      _$ThemeBackgroundFromJson(json);
}

enum ThemeBackgroundSource {
  none,
  albumArt,
  shell,
}

@freezed
class ThemeRadius with _$ThemeRadius {
  const factory ThemeRadius({
    @Default(6.0) double small,
    @Default(10.0) double medium,
    @Default(16.0) double large,
    @Default(999.0) double pill,
  }) = _ThemeRadius;

  factory ThemeRadius.fromJson(Map<String, dynamic> json) =>
      _$ThemeRadiusFromJson(json);
}

@freezed
class DynamicTheme with _$DynamicTheme {
  const factory DynamicTheme({
    required DynamicThemeSource source,
    @Default(DynamicThemeAlgorithm.material) DynamicThemeAlgorithm algorithm,
  }) = _DynamicTheme;

  factory DynamicTheme.fromJson(Map<String, dynamic> json) =>
      _$DynamicThemeFromJson(json);
}

enum DynamicThemeSource {
  albumArt,
  shell,
}

enum DynamicThemeAlgorithm {
  material,
}
