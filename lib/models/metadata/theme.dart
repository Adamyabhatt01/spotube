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
    @JsonKey(name: 'dynamic') DynamicTheme? dynamicTheme,
  }) = _ThemeDefinition;

  factory ThemeDefinition.fromJson(Map<String, dynamic> json) =>
      _$ThemeDefinitionFromJson(json);
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
