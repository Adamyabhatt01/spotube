part of 'metadata.dart';

@freezed
class ThemeDefinition with _$ThemeDefinition {
  const factory ThemeDefinition({
    /// The payload version this theme was written against.
    ///
    /// 2 is the original palette-only contract. 3 added the extra colour
    /// roles, tokens, component styles, shell composition, branding and the
    /// UI tree. 4 is the current contract and adds kits, capabilities, pages
    /// and the expanded semantic node vocabulary.
    ///
    /// The host accepts 2 and 4. A 3 payload is rejected with a migration
    /// message; `themes/tools/migrate_v3.dart` rewrites it. The field stays a
    /// plain int at this layer so an unknown version still decodes and the
    /// validator can report on it instead of failing during JSON parsing.
    @Default(2) int specVersion,

    /// The UI kit semantic nodes render through by default.
    ///
    /// One of `shadcn`, `material` or `cupertino`. The value stays a string at
    /// this layer: an unknown kit is a theme authored for a newer host, and the
    /// runtime falls back to `shadcn` instead of failing to parse the palette.
    @Default('shadcn') String uiKit,
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

    /// `theme` hands the sidebar body to `sidebar.content`, letting a theme
    /// draw its own navigation. The host still owns visibility, width, the
    /// divider, the bottom clearance and the docked player.
    @JsonKey(unknownEnumValue: ThemeSidebar.host)
    @Default(ThemeSidebar.host)
    ThemeSidebar sidebar,

    /// Sidebar width in logical px at scaling 1. Null keeps the host width.
    /// The validator clamps 0–1000.
    double? sidebarWidth,

    /// `theme` shows a right-hand panel fed by `aside.content`. It only
    /// mounts while the user has the aside open and the window is wide enough.
    @JsonKey(unknownEnumValue: ThemeAside.none)
    @Default(ThemeAside.none)
    ThemeAside aside,

    /// Aside width in logical px at scaling 1. Null keeps the host width.
    /// The validator clamps 0–1000.
    double? asideWidth,

    /// A rearranged shell: rows, columns, stacks and grid containers holding
    /// named regions. Null keeps the host's own shell.
    ///
    /// Parsed leniently by [ThemeShellLayout.parse]: a tree that fails the
    /// host's structural rules reads as null and the legacy layout stands, so
    /// a malformed descriptor cannot blank the app. The theme-side validator
    /// reports the same problems as errors.
    @JsonKey(fromJson: _themeShellFromJson, toJson: _themeShellToJson)
    ThemeShellLayout? shell,

    /// Where a theme's pins may be shown. The host validates a pin's `target`
    /// against this list; an empty list keeps the historic sidebar target.
    @JsonKey(fromJson: _themePinTargetsFromJson)
    @Default([])
    List<ThemePinTarget> pinTargets,

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

enum ThemeSidebar {
  host,
  theme,
}

enum ThemeAside {
  none,
  theme,
}

/// One declared pin destination, from `layout.pinTargets`.
///
/// The id names a region (usually a custom bar); the label is what the
/// context menu shows. The host rejects a pin whose `target` is not in the
/// theme's declared list.
class ThemePinTarget {
  final String id;
  final String label;

  const ThemePinTarget({required this.id, required this.label});

  static ThemePinTarget? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.trim().isEmpty || id.length > 64) return null;
    return ThemePinTarget(
      id: id,
      label: label is String && label.trim().isNotEmpty ? label : id,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

List<ThemePinTarget> _themePinTargetsFromJson(dynamic value) {
  if (value is! List) return const [];
  final targets = <ThemePinTarget>[];
  for (final raw in value) {
    final target = ThemePinTarget.parse(raw);
    if (target == null || targets.any((t) => t.id == target.id)) continue;
    targets.add(target);
    if (targets.length >= 16) break;
  }
  return targets;
}

/// A parsed `layout.shell` tree.
///
/// The raw contract is a nested map; the host parses it once into this shape
/// so the renderer never walks untrusted JSON. [parse] enforces the structural
/// rules the app cannot survive without — exactly one `content`, unique ids,
/// one of each non-repeatable host region, depth ≤ 8, leaves ≤ 24 — and
/// returns null when they fail. The theme-side validator reports the same
/// failures as errors with a path.
class ThemeShellLayout {
  final ThemeShellNode root;

  const ThemeShellLayout(this.root);

  factory ThemeShellLayout.fromJson(Map<String, dynamic> json) {
    final parsed = ThemeShellLayout.parse(json);
    if (parsed == null) {
      throw const FormatException('invalid shell layout');
    }
    return parsed;
  }

  Map<String, dynamic> toJson() => root.toJson();

  static ThemeShellLayout? parse(Object? raw) {
    if (raw is! Map) return null;
    final root = ThemeShellNode._parse(raw.cast<String, dynamic>(), 0);
    if (root == null) return null;

    final leaves = <ThemeShellNode>[];
    if (!root._collectLeaves(leaves, 0)) return null;
    if (leaves.length > ThemeShellNode.maxLeaves) return null;

    var contents = 0;
    final ids = <String>{};
    final singles = <ThemeShellRegion>{};
    for (final leaf in leaves) {
      final region = leaf.region;
      if (region == null) return null;
      if (region == ThemeShellRegion.content) contents++;
      if (region != ThemeShellRegion.custom) {
        if (!singles.add(region)) return null;
      }
      final id = leaf.effectiveId;
      if (id == null || !ids.add(id)) return null;
    }
    if (contents != 1) return null;
    return ThemeShellLayout(root);
  }
}

ThemeShellLayout? _themeShellFromJson(dynamic value) =>
    ThemeShellLayout.parse(value);

Object? _themeShellToJson(ThemeShellLayout? shell) => shell?.toJson();

enum ThemeShellNodeType { row, column, stack, grid }

enum ThemeShellRegion {
  content,
  sidebar,
  aside,
  player,
  titlebar,
  navbar,
  custom,
}

/// A length in the shell descriptor: pixels, a percentage of the parent, or
/// `auto` (the widget's intrinsic size).
class ThemeShellSize {
  final double? pixels;
  final double? percent;
  final bool intrinsic;

  const ThemeShellSize._intrinsic()
      : pixels = null,
        percent = null,
        intrinsic = true;

  const ThemeShellSize.px(double value)
      : pixels = value,
        percent = null,
        intrinsic = false;

  const ThemeShellSize.percent(double value)
      : pixels = null,
        percent = value,
        intrinsic = false;

  static const auto = ThemeShellSize._intrinsic();

  static ThemeShellSize? parse(Object? raw) {
    if (raw == 'auto') return auto;
    if (raw is num && raw.isFinite) {
      return ThemeShellSize.px(raw.toDouble().clamp(0.0, 4000.0).toDouble());
    }
    if (raw is String && raw.endsWith('%')) {
      final value = double.tryParse(raw.substring(0, raw.length - 1));
      if (value == null || !value.isFinite) return null;
      return ThemeShellSize.percent(value.clamp(0.0, 100.0).toDouble());
    }
    return null;
  }

  /// The concrete size for a parent extent, or null when intrinsic.
  double? resolve(double parentExtent) {
    if (intrinsic) return null;
    if (pixels != null) return pixels;
    if (percent != null) return parentExtent * percent! / 100;
    return null;
  }

  Map<String, dynamic> toJson() {
    if (intrinsic) return {'auto': true};
    if (percent != null) return {'percent': percent};
    return {'px': pixels};
  }
}

/// `resizable: { edges, storageKey, min, max }` on a region leaf.
class ThemeShellResize {
  final List<String> edges;
  final String? storageKey;
  final double? min;
  final double? max;

  const ThemeShellResize({
    this.edges = const ['end'],
    this.storageKey,
    this.min,
    this.max,
  });

  static ThemeShellResize? parse(Object? raw) {
    if (raw is bool) return raw ? const ThemeShellResize() : null;
    if (raw is! Map) return null;
    final edgesRaw = raw['edges'];
    final edges = <String>[
      if (edgesRaw is List)
        for (final edge in edgesRaw)
          if (edge is String &&
              const {'start', 'end', 'top', 'bottom'}.contains(edge))
            edge,
    ];
    return ThemeShellResize(
      edges: edges.isEmpty ? const ['end'] : edges,
      storageKey: _shellKey(raw['storageKey']),
      min: _shellNumber(raw['min'], 0, 4000),
      max: _shellNumber(raw['max'], 0, 4000),
    );
  }

  Map<String, dynamic> toJson() => {
        'edges': edges,
        if (storageKey != null) 'storageKey': storageKey,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };
}

/// One node of a shell tree: a container (`row`, `column`, `stack`, `grid`) or
/// a region leaf.
class ThemeShellNode {
  static const maxDepth = 8;
  static const maxLeaves = 24;

  final ThemeShellNodeType? type;
  final ThemeShellRegion? region;
  final String? id;
  final String? slot;
  final String? label;
  final ThemeShellSize? width;
  final ThemeShellSize? height;
  final int flex;
  final double? minWidth;
  final double? maxWidth;
  final double? minHeight;
  final double? maxHeight;
  final ThemeShellResize? resizable;
  final bool collapsible;
  final double? collapsedSize;
  final String? overflow;
  final String? hiddenWhen;
  final List<String> safeArea;
  final int zIndex;
  final int? focusOrder;
  final String? storageKey;
  final List<ThemeShellNode> children;

  const ThemeShellNode._({
    required this.type,
    required this.region,
    required this.id,
    required this.slot,
    required this.label,
    required this.width,
    required this.height,
    required this.flex,
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
    required this.resizable,
    required this.collapsible,
    required this.collapsedSize,
    required this.overflow,
    required this.hiddenWhen,
    required this.safeArea,
    required this.zIndex,
    required this.focusOrder,
    required this.storageKey,
    required this.children,
  });

  bool get isRegion => region != null;

  /// Every region leaf in this subtree, depth-first.
  List<ThemeShellNode> get leaves {
    final out = <ThemeShellNode>[];
    _collectLeaves(out, 0);
    return out;
  }

  /// A container with no children left after visibility pruning has nothing to
  /// lay out.
  bool get isEmptyContainer => !isRegion && children.isEmpty;

  /// The id the host uses for persistence and `region.<id>.*` bindings.
  String? get effectiveId {
    if (id != null && id!.isNotEmpty) return id;
    final region = this.region;
    if (region == null || region == ThemeShellRegion.custom) return null;
    return region.name;
  }

  static ThemeShellNode? _parse(Map<String, dynamic> raw, int depth) {
    if (depth > maxDepth) return null;

    final regionRaw = raw['region'];
    if (regionRaw is String) {
      final region = _region(regionRaw);
      if (region == null) return null;
      final slot = raw['slot'] is String && (raw['slot'] as String).isNotEmpty
          ? raw['slot'] as String
          : null;
      final id = raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : null;
      final label =
          raw['label'] is String && (raw['label'] as String).isNotEmpty
              ? raw['label'] as String
              : null;
      // Custom regions have no host default to draw; without a slot the leaf
      // has nothing to show. Drop it rather than reserving blank space.
      if (region == ThemeShellRegion.custom && (slot == null || id == null)) {
        return null;
      }
      return ThemeShellNode._(
        type: null,
        region: region,
        id: id,
        slot: slot,
        label: label,
        width: ThemeShellSize.parse(raw['width']),
        height: ThemeShellSize.parse(raw['height']),
        flex: _shellInt(raw['flex'], 0, 1000),
        minWidth: _shellNumber(raw['minWidth'], 0, 4000),
        maxWidth: _shellNumber(raw['maxWidth'], 0, 4000),
        minHeight: _shellNumber(raw['minHeight'], 0, 4000),
        maxHeight: _shellNumber(raw['maxHeight'], 0, 4000),
        resizable: ThemeShellResize.parse(raw['resizable']),
        collapsible: raw['collapsible'] == true,
        collapsedSize: _shellNumber(raw['collapsedSize'], 0, 4000),
        overflow: _overflow(raw['overflow']),
        hiddenWhen:
            raw['hiddenWhen'] is String ? raw['hiddenWhen'] as String : null,
        safeArea: _safeArea(raw['safeArea']),
        zIndex: _shellInt(raw['zIndex'], 0, 1000),
        focusOrder: raw['focusOrder'] is num
            ? _shellInt(raw['focusOrder'], 0, 1000)
            : null,
        storageKey: _shellKey(raw['storageKey']),
        children: const [],
      );
    }

    final type = _type(raw['type']);
    if (type == null) return null;
    final childrenRaw = raw['children'];
    if (childrenRaw is! List) return null;
    final children = <ThemeShellNode>[];
    for (final child in childrenRaw) {
      if (child is! Map) return null;
      final parsed = _parse(child.cast<String, dynamic>(), depth + 1);
      if (parsed == null) return null;
      children.add(parsed);
      if (children.length >= maxLeaves) break;
    }
    if (children.isEmpty) return null;

    return ThemeShellNode._(
      type: type,
      region: null,
      id: raw['id'] is String ? raw['id'] as String : null,
      slot: null,
      label: null,
      width: ThemeShellSize.parse(raw['width']),
      height: ThemeShellSize.parse(raw['height']),
      flex: _shellInt(raw['flex'], 0, 1000),
      minWidth: _shellNumber(raw['minWidth'], 0, 4000),
      maxWidth: _shellNumber(raw['maxWidth'], 0, 4000),
      minHeight: _shellNumber(raw['minHeight'], 0, 4000),
      maxHeight: _shellNumber(raw['maxHeight'], 0, 4000),
      resizable: null,
      collapsible: false,
      collapsedSize: null,
      overflow: null,
      hiddenWhen: null,
      safeArea: const [],
      zIndex: 0,
      focusOrder: null,
      storageKey: null,
      children: children,
    );
  }

  /// Depth-first leaves, failing when the tree is deeper than [maxDepth].
  bool _collectLeaves(List<ThemeShellNode> out, int depth) {
    if (depth > maxDepth) return false;
    if (isRegion) {
      out.add(this);
      return out.length <= maxLeaves;
    }
    for (final child in children) {
      if (!child._collectLeaves(out, depth + 1)) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() {
    if (isRegion) {
      return {
        'region': region!.name,
        if (id != null) 'id': id,
        if (slot != null) 'slot': slot,
        if (label != null) 'label': label,
        if (width != null) 'width': width!.toJson(),
        if (height != null) 'height': height!.toJson(),
        if (flex > 0) 'flex': flex,
        if (minWidth != null) 'minWidth': minWidth,
        if (maxWidth != null) 'maxWidth': maxWidth,
        if (minHeight != null) 'minHeight': minHeight,
        if (maxHeight != null) 'maxHeight': maxHeight,
        if (resizable != null) 'resizable': resizable!.toJson(),
        if (collapsible) 'collapsible': true,
        if (collapsedSize != null) 'collapsedSize': collapsedSize,
        if (overflow != null) 'overflow': overflow,
        if (hiddenWhen != null) 'hiddenWhen': hiddenWhen,
        if (safeArea.isNotEmpty) 'safeArea': safeArea,
        if (zIndex != 0) 'zIndex': zIndex,
        if (focusOrder != null) 'focusOrder': focusOrder,
        if (storageKey != null) 'storageKey': storageKey,
      };
    }
    return {
      'type': type!.name,
      if (width != null) 'width': width!.toJson(),
      if (height != null) 'height': height!.toJson(),
      if (flex > 0) 'flex': flex,
      if (minWidth != null) 'minWidth': minWidth,
      if (maxWidth != null) 'maxWidth': maxWidth,
      if (minHeight != null) 'minHeight': minHeight,
      if (maxHeight != null) 'maxHeight': maxHeight,
      'children': [for (final child in children) child.toJson()],
    };
  }
}

ThemeShellNodeType? _type(Object? raw) => switch (raw) {
      'row' => ThemeShellNodeType.row,
      'column' => ThemeShellNodeType.column,
      'stack' => ThemeShellNodeType.stack,
      'grid' => ThemeShellNodeType.grid,
      _ => null,
    };

ThemeShellRegion? _region(Object? raw) => switch (raw) {
      'content' => ThemeShellRegion.content,
      'sidebar' => ThemeShellRegion.sidebar,
      'aside' => ThemeShellRegion.aside,
      'player' => ThemeShellRegion.player,
      'titlebar' => ThemeShellRegion.titlebar,
      'navbar' => ThemeShellRegion.navbar,
      'custom' => ThemeShellRegion.custom,
      _ => null,
    };

String? _overflow(Object? raw) =>
    raw is String && const {'clip', 'scroll', 'wrap', 'menu'}.contains(raw)
        ? raw
        : null;

List<String> _safeArea(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final edge in raw)
      if (edge is String &&
          const {'top', 'right', 'bottom', 'left'}.contains(edge))
        edge,
  ];
}

String? _shellKey(Object? raw) {
  if (raw is! String || raw.isEmpty || raw.length > 64) return null;
  return RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(raw) ? raw : null;
}

double? _shellNumber(Object? raw, double min, double max) {
  if (raw is! num || !raw.isFinite) return null;
  return raw.toDouble().clamp(min, max).toDouble();
}

int _shellInt(Object? raw, int min, int max) {
  if (raw is! num || !raw.isFinite) return min;
  return raw.toInt().clamp(min, max);
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

    /// Render point id → template name. The host keeps the behaviour of the
    /// surface (positioning, focus, keyboard, dispatch) and the template
    /// replaces its pixels. Only ids in the closed v4 catalogue are honoured;
    /// an unknown id is ignored at runtime.
    @Default(<String, String>{}) Map<String, String> renderPoints,
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
