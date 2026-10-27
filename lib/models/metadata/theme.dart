part of 'metadata.dart';

@freezed
class ThemeDefinition with _$ThemeDefinition {
  const factory ThemeDefinition({
    /// The payload version this theme was written against.
    ///
    /// 2 is the contract the app read until the v3 blocks arrived; 3 adds
    /// the extra colour roles, the tokens, the component styles, the shell's
    /// composition, branding and the UI tree.
    ///
    /// The version describes the *payload*, not what the app can do: a host
    /// reads the fields it knows and ignores the rest, so a v3 theme still
    /// works on a v2 host (it draws as its two colour schemes there).
    @Default(2) int specVersion,
    required ThemeColors light,
    required ThemeColors dark,
    @Default(ThemeSurfaces()) ThemeSurfaces surfaces,
    @Default(ThemeBackground()) ThemeBackground background,
    @Default(ThemeRadius()) ThemeRadius radius,
    @Default(1.0) double density,
    @Default(ThemeTokens()) ThemeTokens tokens,
    @Default(ThemeLayout()) ThemeLayout layout,
    @JsonKey(name: 'dynamic') DynamicTheme? dynamicTheme,

    /// The v3 presentation blocks. They stay as contract-owned maps at this
    /// layer, like UI nodes: the renderer reads the keys it knows and clamps
    /// every number it uses, so a newer theme can add a key without a host
    /// model change, and a malformed key cannot take the palette down.
    @Default({}) Map<String, dynamic> typography,
    @Default({}) Map<String, dynamic> spacing,
    @Default({}) Map<String, dynamic> motion,
    @Default({}) Map<String, dynamic> scale,
    @Default({}) Map<String, dynamic> icons,
    @Default({}) Map<String, dynamic> components,
    @Default({}) Map<String, dynamic> branding,
    @Default({}) Map<String, dynamic> assets,

    /// The declarative UI tree a theme may carry inline in `getTheme()`.
    ///
    /// A theme that answers from its optional `getUi()` method leaves this
    /// null; `themeUiProvider` asks the plugin and caches the result. A
    /// malformed tree is dropped here rather than taking the palette with
    /// it, so a broken screen cannot leave the user on the built-in theme.
    @JsonKey(fromJson: _themeUiFromJson) ThemeUiDocument? ui,
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

    /// The player's own shape. `stage` makes the player the centre of the
    /// app (the theme fills `stage.center`/`stage.below`); the other values
    /// keep the host's footer player.
    @Default(ThemePlayerLayout()) ThemePlayerLayout player,

    /// Deprecated v3 opt-in, retained so v3 payloads still parse.
    ///
    /// The host no longer reads it. A layout field takes effect when the
    /// theme sends a meaningful value: a non-empty entry/section list, a
    /// `compact` dock, or `showVolume: false`. A v3 host still gates on this
    /// list, so a payload shipped to both hosts keeps it.
    @Default([]) List<String> enforce,

    /// The navigation entries and library entries the theme wants the host
    /// to show, in order. Kept raw so a theme can add a future entry without
    /// a model release; the host filters to the ids it implements.
    ///
    /// `navItems` drives the sidebar, `navbarItems` the bottom bar, and
    /// `libraryItems` the library group below the sidebar's top entries. An
    /// entry may also be `screen:<id>`, which links to one of the theme's own
    /// `ui.screens`, so a theme can add a destination the host never shipped.
    @Default([]) List<String> navItems,
    @Default([]) List<String> navbarItems,
    @Default([]) List<String> libraryItems,

    /// Home/settings section order and composition, as contract-owned maps.
    @Default({}) Map<String, dynamic> home,
    @Default({}) Map<String, dynamic> settings,

    /// Window title-bar geometry and back-control preference.
    @Default({}) Map<String, dynamic> titlebar,

    /// Launch splash logo/text, resolved through the theme's own assets.
    @Default({}) Map<String, dynamic> splash,

    /// Breakpoint-specific overrides (`compact`, `medium`, ...).
    @Default({}) Map<String, dynamic> responsive,
  }) = _ThemeLayout;

  factory ThemeLayout.fromJson(Map<String, dynamic> json) =>
      _$ThemeLayoutFromJson(json);
}

@freezed
class ThemePlayerLayout with _$ThemePlayerLayout {
  const factory ThemePlayerLayout({
    @JsonKey(unknownEnumValue: ThemePlayerDock.full)
    @Default(ThemePlayerDock.full)
    ThemePlayerDock dock,
    @Default(true) bool showTrackDetails,
    @Default(true) bool showActions,
    @Default(true) bool showVolume,
    @Default(true) bool showLyrics,
    @Default(true) bool showProgress,
  }) = _ThemePlayerLayout;

  factory ThemePlayerLayout.fromJson(Map<String, dynamic> json) =>
      _$ThemePlayerLayoutFromJson(json);
}

enum ThemePlayerDock {
  full,
  compact,
  floating,
  stage,
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

    // The roles a v2 payload does not have. Each is optional, and each falls
    // back to the role it aliases, so a theme may set only the ones it cares
    // about and the host keeps its own for the rest.

    /// The floating surface: menus, popovers, dropdowns.
    String? popover,

    /// Text on [popover].
    String? popoverForeground,

    /// The sidebar's own surface.
    String? sidebar,

    /// Text on [sidebar].
    String? sidebarForeground,

    /// The sidebar's active accent.
    String? sidebarPrimary,

    /// Text on [sidebarPrimary].
    String? sidebarPrimaryForeground,

    /// The sidebar's secondary accent.
    String? sidebarAccent,

    /// Text on [sidebarAccent].
    String? sidebarAccentForeground,

    /// The sidebar's outlines.
    String? sidebarBorder,

    /// The sidebar's focus ring.
    String? sidebarRing,

    /// The categorical palette, used by charts and summaries.
    String? chart1,
    String? chart2,
    String? chart3,
    String? chart4,
    String? chart5,
    String? chart6,

    /// The status colours: success, warning and information.
    String? success,
    String? successForeground,
    String? warning,
    String? warningForeground,
    String? info,
    String? infoForeground,
  }) = _ThemeColors;

  factory ThemeColors.fromJson(Map<String, dynamic> json) =>
      _$ThemeColorsFromJson(json);
}

/// The status colours and the sixth chart colour, resolved from a palette.
///
/// shadcn's `ColorScheme` has no slot for these — it carries five chart
/// colours and no status colours at all — so they travel beside it, published
/// through `AppLayout` and read as `context.successColor` and friends.
@freezed
class ThemeSemanticColors with _$ThemeSemanticColors {
  const factory ThemeSemanticColors({
    @Default('#16a34a') String success,
    @Default('#ffffff') String successForeground,
    @Default('#b45309') String warning,
    @Default('#ffffff') String warningForeground,
    @Default('#2563eb') String info,
    @Default('#ffffff') String infoForeground,
    @Default('#8b5cf6') String chart6,
  }) = _ThemeSemanticColors;

  factory ThemeSemanticColors.fromJson(Map<String, dynamic> json) =>
      _$ThemeSemanticColorsFromJson(json);
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
    @JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
    @Default(ThemeBackgroundSource.none)
    ThemeBackgroundSource source,
    @Default(0.0) double opacity,
    @Default(0.0) double blur,

    /// A v3 background shipped with the theme (`asset://…`).
    String? asset,

    /// Repeat [asset] instead of stretching it.
    @Default(false) bool tile,

    /// Whole-number magnification for a tiled [asset], 1..8.
    @Default(1) int scale,

    /// Optional veil over the background image as `#RRGGBB` or
    /// Flutter-native `#AARRGGBB` (alpha honored, e.g. `#80000000`
    /// is 50% black). Brightness-adapted by the host layer.
    String? overlay,

    /// Real window transparency opt-in, tri-state by design:
    /// - `true`: theme wants the compositor to show through (still needs
    ///   the host master setting);
    /// - `false`: explicit veto, always opaque even with the setting on;
    /// - absent (`null`): no opinion, the host setting decides alone (this
    ///   is what old themes decode to).
    /// Decoded leniently: anything that is not a JSON bool reads as absent,
    /// so one malformed flag can never nuke the whole theme.
    @JsonKey(fromJson: _transparentFromJson) bool? transparent,
  }) = _ThemeBackground;

  factory ThemeBackground.fromJson(Map<String, dynamic> json) =>
      _$ThemeBackgroundFromJson(json);
}

/// Lenient tri-state decode for [ThemeBackground.transparent]: only a real
/// JSON bool carries an opinion; everything else (absent, null, strings,
/// numbers) defers to the host setting.
bool? _transparentFromJson(dynamic value) => value is bool ? value : null;

enum ThemeBackgroundSource {
  none,
  albumArt,
  shell,
  asset,
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

/// A theme's declarative UI, either inline in `getTheme()` or returned by the
/// optional `getUi()` method.
///
/// Nodes stay as JSON maps at this layer on purpose: the node vocabulary is
/// the theme contract's, not the host model's, so a renderer can accept a new
/// node without a fresh Freezed class. Slots, screens and templates get
/// structure here because the host mounts and navigates them.
@freezed
class ThemeUiDocument with _$ThemeUiDocument {
  const factory ThemeUiDocument({
    @Default(1) int specVersion,
    @Default({}) Map<String, ThemeUiSlot> slots,
    @Default({}) Map<String, ThemeUiScreen> screens,
    @Default(<String, ThemeUiTemplate>{})
    Map<String, ThemeUiTemplate> templates,
  }) = _ThemeUiDocument;

  factory ThemeUiDocument.fromJson(Map<String, dynamic> json) =>
      _$ThemeUiDocumentFromJson(json);
}

/// One host slot, with the children the theme wants mounted there.
@freezed
class ThemeUiSlot with _$ThemeUiSlot {
  const factory ThemeUiSlot({
    @Default([]) List<Map<String, dynamic>> children,

    /// How often the host may refresh data-bound children in this slot.
    /// Zero means "on state changes only".
    double? refreshSeconds,
  }) = _ThemeUiSlot;

  factory ThemeUiSlot.fromJson(Map<String, dynamic> json) =>
      _$ThemeUiSlotFromJson(json);
}

/// A screen the theme owns, reachable from an action's `screen:<id>` target.
@freezed
class ThemeUiScreen with _$ThemeUiScreen {
  const factory ThemeUiScreen({
    String? title,
    @Default(false) bool showBack,
    @Default([]) List<Map<String, dynamic>> children,
  }) = _ThemeUiScreen;

  factory ThemeUiScreen.fromJson(Map<String, dynamic> json) =>
      _$ThemeUiScreenFromJson(json);
}

/// A reusable subtree a text node may expand with `template`/`args`.
@freezed
class ThemeUiTemplate with _$ThemeUiTemplate {
  const factory ThemeUiTemplate({
    @Default([]) List<String> params,
    @Default([]) List<Map<String, dynamic>> children,
  }) = _ThemeUiTemplate;

  factory ThemeUiTemplate.fromJson(Map<String, dynamic> json) =>
      _$ThemeUiTemplateFromJson(json);
}

/// Parses a UI document without letting a malformed tree take the theme down.
///
/// Installed plugins are not built by this checkout, so the host cannot rely
/// on the theme-side validator. A bad UI loses the UI, never the palette.
ThemeUiDocument? parseThemeUiDocument(Map<String, dynamic> json) {
  try {
    return ThemeUiDocument.fromJson(json);
  } catch (_) {
    return null;
  }
}

ThemeUiDocument? _themeUiFromJson(dynamic value) {
  if (value is! Map) return null;
  return parseThemeUiDocument(value.cast<String, dynamic>());
}
