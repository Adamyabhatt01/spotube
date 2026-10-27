import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// The spacing scale a v3 theme declares, in logical pixels at scaling 1.
///
/// The defaults mirror what the app drew before the block existed, so a theme
/// that does not set `spacing` keeps the current page padding.
class ThemeSpacing {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double page;
  final double section;
  final double cardGap;
  final double pageHorizontal;
  final Map<String, double> custom;

  const ThemeSpacing({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.xxl = 32,
    this.page = 24,
    this.section = 32,
    this.cardGap = 12,
    this.pageHorizontal = 24,
    this.custom = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is ThemeSpacing &&
      other.xs == xs &&
      other.sm == sm &&
      other.md == md &&
      other.lg == lg &&
      other.xl == xl &&
      other.xxl == xxl &&
      other.page == page &&
      other.section == section &&
      other.cardGap == cardGap &&
      other.pageHorizontal == pageHorizontal &&
      mapEquals(other.custom, custom);

  @override
  int get hashCode => Object.hash(
        xs,
        sm,
        md,
        lg,
        xl,
        xxl,
        page,
        section,
        cardGap,
        pageHorizontal,
        Object.hashAllUnordered(custom.entries),
      );
}

/// The motion scale a v3 theme declares, in milliseconds.
class ThemeMotion {
  final double fast;
  final double normal;
  final double slow;
  final double pageTransition;
  final double sheet;
  final String easing;
  final Map<String, double> custom;

  const ThemeMotion({
    this.fast = 120,
    this.normal = 200,
    this.slow = 320,
    this.pageTransition = 220,
    this.sheet = 300,
    this.easing = 'easeOutCubic',
    this.custom = const {},
  });

  Duration get fastDuration => _duration(fast);
  Duration get normalDuration => _duration(normal);
  Duration get slowDuration => _duration(slow);
  Duration get pageTransitionDuration => _duration(pageTransition);
  Duration get sheetDuration => _duration(sheet);

  Curve get curve => switch (easing) {
        'linear' => Curves.linear,
        'ease' => Curves.ease,
        'easeIn' => Curves.easeIn,
        'easeOut' => Curves.easeOut,
        'easeInOut' => Curves.easeInOut,
        'easeInOutCubic' => Curves.easeInOutCubic,
        _ => Curves.easeOutCubic,
      };

  static Duration _duration(double millis) => Duration(
        milliseconds: millis.clamp(0, 1000).round(),
      );

  @override
  bool operator ==(Object other) =>
      other is ThemeMotion &&
      other.fast == fast &&
      other.normal == normal &&
      other.slow == slow &&
      other.pageTransition == pageTransition &&
      other.sheet == sheet &&
      other.easing == easing &&
      mapEquals(other.custom, custom);

  @override
  int get hashCode => Object.hash(
        fast,
        normal,
        slow,
        pageTransition,
        sheet,
        easing,
        Object.hashAllUnordered(custom.entries),
      );
}

/// Everything the v3 presentation blocks contribute that the host can apply.
class ThemePresentation {
  final Typography typography;
  final IconThemeProperties iconTheme;
  final ThemeSpacing spacing;
  final ThemeMotion motion;
  final double sizeScale;
  final double textScale;
  final double radiusScale;
  final double iconScale;
  final double spacingScale;

  const ThemePresentation({
    required this.typography,
    required this.iconTheme,
    required this.spacing,
    required this.motion,
    this.sizeScale = 1,
    this.textScale = 1,
    this.radiusScale = 1,
    this.iconScale = 1,
    this.spacingScale = 1,
  });

  static const empty = ThemePresentation(
    typography: Typography.geist(),
    iconTheme: IconThemeProperties(),
    spacing: ThemeSpacing(),
    motion: ThemeMotion(),
  );
}

/// Resolves a theme's presentation blocks into shadcn types.
///
/// Every number is clamped here, the same way the UI renderer clamps node
/// props: the block arrives from a plugin, its schema is not enforced by this
/// checkout, and a bad value must degrade to the built-in look rather than
/// poison a text style or an icon size. A null theme resolves to the app's
/// defaults.
ThemePresentation resolveThemePresentation(
  ThemeDefinition? theme, {
  required ColorScheme scheme,
}) {
  if (theme == null) return ThemePresentation.empty;

  final scale = _scale(theme.scale);
  return ThemePresentation(
    typography: _typography(theme, scheme: scheme),
    iconTheme: _icons(theme.icons, scale: scale['icon']!),
    spacing: themeSpacing(theme),
    motion: themeMotion(theme),
    sizeScale: scale['size']!,
    textScale: scale['text']!,
    radiusScale: scale['radius']!,
    iconScale: scale['icon']!,
    spacingScale: scale['spacing']!,
  );
}

/// The theme's spacing scale, clamped to values layout can survive.
ThemeSpacing themeSpacing(ThemeDefinition? theme) {
  final raw = _map(theme?.spacing);

  double px(String key, double fallback) => _number(raw[key], 0, 96, fallback);

  return ThemeSpacing(
    xs: px('xs', 4),
    sm: px('sm', 8),
    md: px('md', 12),
    lg: px('lg', 16),
    xl: px('xl', 24),
    xxl: px('xxl', 32),
    page: px('page', 24),
    section: px('section', 32),
    // The v2 token is the fallback: a theme that sets `tokens.gutter` but no
    // spacing block keeps the grid it shipped with.
    cardGap: px('cardGap', theme?.tokens.gutter ?? 12),
    pageHorizontal: px('pageHorizontal', 24),
    custom: _custom(raw['custom'], max: 1000),
  );
}

/// The theme's motion scale, clamped to durations a transition can use.
ThemeMotion themeMotion(ThemeDefinition? theme) {
  final raw = _map(theme?.motion);
  if (raw.isEmpty) return const ThemeMotion();

  double ms(String key, double fallback) => _number(raw[key], 0, 1000, fallback);

  return ThemeMotion(
    fast: ms('fast', 120),
    normal: ms('normal', 200),
    slow: ms('slow', 320),
    pageTransition: ms('pageTransition', 220),
    sheet: ms('sheet', 300),
    easing: switch (raw['easing']) {
      'linear' || 'ease' || 'easeIn' || 'easeOut' || 'easeInOut' ||
      'easeOutCubic' || 'easeInOutCubic' =>
        raw['easing'] as String,
      _ => 'easeOutCubic',
    },
    custom: _custom(raw['custom'], max: 1000),
  );
}

// ---------------------------------------------------------------------------
// typography

const _styleFields = <String, String>{
  'h1': 'h1',
  'h2': 'h2',
  'h3': 'h3',
  'h4': 'h4',
  'p': 'p',
  'lead': 'lead',
  'base': 'base',
  'large': 'large',
  'small': 'small',
  'xSmall': 'xSmall',
  'xLarge': 'xLarge',
  'x2Large': 'x2Large',
  'x3Large': 'x3Large',
  'x4Large': 'x4Large',
  'x5Large': 'x5Large',
  'x6Large': 'x6Large',
  'x7Large': 'x7Large',
  'x8Large': 'x8Large',
  'x9Large': 'x9Large',
  'muted': 'textMuted',
  'textMuted': 'textMuted',
  'textLarge': 'textLarge',
  'textSmall': 'textSmall',
};

Typography _typography(ThemeDefinition theme, {required ColorScheme scheme}) {
  const base = Typography.geist();
  final block = _map(theme.typography);
  final family = _family(block['family']) ?? _family(theme.tokens.fontFamily);
  final mono = _family(block['monoFamily']);
  final styles = _map(block['styles']);

  Typography result = base;
  // The family is the ladder's default, not just its `sans` entry: a theme
  // that names Inter and declares only a few styles expects every role it did
  // not spell out to be Inter too. Mono roles stay monospace.
  if (family != null) result = _withFamily(result, family);
  if (mono != null) {
    result = result.copyWith(
      // A fresh style, because the package font keeps its `package` prefix
      // through `copyWith(fontFamily:)`.
      mono: () => TextStyle(fontFamily: mono),
      inlineCode: () => result.inlineCode.copyWith(fontFamily: mono),
    );
  }

  for (final entry in styles.entries) {
    final field = _styleFields[entry.key];
    final spec = _map(entry.value);
    if (field == null || spec.isEmpty) continue;
    result = _withStyle(
      result,
      field,
      (current) => _style(current, spec, family: family, scheme: scheme),
    );
  }

  return result;
}

Typography _withFamily(Typography typography, String family) {
  TextStyle withFamily(TextStyle style) => style.copyWith(fontFamily: family);
  return typography.copyWith(
    // `sans` is the only ladder entry that carries `package: shadcn_flutter`;
    // copying it would resolve the theme family as a package-relative font.
    sans: () => TextStyle(fontFamily: family),
    xSmall: () => withFamily(typography.xSmall),
    small: () => withFamily(typography.small),
    base: () => withFamily(typography.base),
    large: () => withFamily(typography.large),
    xLarge: () => withFamily(typography.xLarge),
    x2Large: () => withFamily(typography.x2Large),
    x3Large: () => withFamily(typography.x3Large),
    x4Large: () => withFamily(typography.x4Large),
    x5Large: () => withFamily(typography.x5Large),
    x6Large: () => withFamily(typography.x6Large),
    x7Large: () => withFamily(typography.x7Large),
    x8Large: () => withFamily(typography.x8Large),
    x9Large: () => withFamily(typography.x9Large),
    thin: () => withFamily(typography.thin),
    light: () => withFamily(typography.light),
    extraLight: () => withFamily(typography.extraLight),
    normal: () => withFamily(typography.normal),
    medium: () => withFamily(typography.medium),
    semiBold: () => withFamily(typography.semiBold),
    bold: () => withFamily(typography.bold),
    extraBold: () => withFamily(typography.extraBold),
    black: () => withFamily(typography.black),
    italic: () => withFamily(typography.italic),
    h1: () => withFamily(typography.h1),
    h2: () => withFamily(typography.h2),
    h3: () => withFamily(typography.h3),
    h4: () => withFamily(typography.h4),
    p: () => withFamily(typography.p),
    blockQuote: () => withFamily(typography.blockQuote),
    lead: () => withFamily(typography.lead),
    textLarge: () => withFamily(typography.textLarge),
    textSmall: () => withFamily(typography.textSmall),
    textMuted: () => withFamily(typography.textMuted),
  );
}

TextStyle _style(
  TextStyle current,
  Map<String, dynamic> spec, {
  required String? family,
  required ColorScheme scheme,
}) {
  final size = spec['fontSize'];
  final weight = spec['fontWeight'];
  final height = spec['height'];
  final letterSpacing = spec['letterSpacing'];
  final color = spec['color'];
  final styleFamily = _family(spec['fontFamily']) ?? family;
  final italic = spec['fontStyle'] == 'italic';

  return current.copyWith(
    fontSize: size is num && size.isFinite
        ? size.toDouble().clamp(8.0, 96.0).toDouble()
        : null,
    fontWeight: weight is num && weight.isFinite
        ? _weight(weight.round())
        : null,
    height: height is num && height.isFinite
        ? height.toDouble().clamp(0.8, 2.4).toDouble()
        : null,
    letterSpacing: letterSpacing is num && letterSpacing.isFinite
        ? letterSpacing.toDouble().clamp(-2.0, 8.0).toDouble()
        : null,
    color: color is String ? _roleColor(color, scheme) : null,
    fontFamily: styleFamily,
    fontStyle: italic ? FontStyle.italic : null,
  );
}

FontWeight _weight(int value) {
  final index = ((value ~/ 100) - 1).clamp(0, 8);
  return FontWeight.values[index];
}

Color? _roleColor(String raw, ColorScheme scheme) {
  if (!raw.startsWith('@')) return null;
  return switch (raw.substring(1)) {
    'primary' => scheme.primary,
    'primaryForeground' => scheme.primaryForeground,
    'secondary' => scheme.secondary,
    'secondaryForeground' => scheme.secondaryForeground,
    'accent' => scheme.accent,
    'accentForeground' => scheme.accentForeground,
    'muted' => scheme.muted,
    'mutedForeground' => scheme.mutedForeground,
    'destructive' => scheme.destructive,
    'background' => scheme.background,
    'foreground' => scheme.foreground,
    'card' => scheme.card,
    'cardForeground' => scheme.cardForeground,
    'popover' => scheme.popover,
    'popoverForeground' => scheme.popoverForeground,
    'border' => scheme.border,
    'input' => scheme.input,
    'ring' => scheme.ring,
    'sidebar' => scheme.sidebar,
    'sidebarForeground' => scheme.sidebarForeground,
    'sidebarPrimary' => scheme.sidebarPrimary,
    'sidebarPrimaryForeground' => scheme.sidebarPrimaryForeground,
    'sidebarAccent' => scheme.sidebarAccent,
    'sidebarAccentForeground' => scheme.sidebarAccentForeground,
    'sidebarBorder' => scheme.sidebarBorder,
    'sidebarRing' => scheme.sidebarRing,
    'chart1' => scheme.chart1,
    'chart2' => scheme.chart2,
    'chart3' => scheme.chart3,
    'chart4' => scheme.chart4,
    'chart5' => scheme.chart5,
    _ => null,
  };
}

Typography _withStyle(
  Typography typography,
  String field,
  TextStyle Function(TextStyle current) build,
) {
  return switch (field) {
    'h1' => typography.copyWith(h1: () => build(typography.h1)),
    'h2' => typography.copyWith(h2: () => build(typography.h2)),
    'h3' => typography.copyWith(h3: () => build(typography.h3)),
    'h4' => typography.copyWith(h4: () => build(typography.h4)),
    'p' => typography.copyWith(p: () => build(typography.p)),
    'lead' => typography.copyWith(lead: () => build(typography.lead)),
    'base' => typography.copyWith(base: () => build(typography.base)),
    'large' => typography.copyWith(large: () => build(typography.large)),
    'small' => typography.copyWith(small: () => build(typography.small)),
    'xSmall' => typography.copyWith(xSmall: () => build(typography.xSmall)),
    'xLarge' => typography.copyWith(xLarge: () => build(typography.xLarge)),
    'x2Large' => typography.copyWith(x2Large: () => build(typography.x2Large)),
    'x3Large' => typography.copyWith(x3Large: () => build(typography.x3Large)),
    'x4Large' => typography.copyWith(x4Large: () => build(typography.x4Large)),
    'x5Large' => typography.copyWith(x5Large: () => build(typography.x5Large)),
    'x6Large' => typography.copyWith(x6Large: () => build(typography.x6Large)),
    'x7Large' => typography.copyWith(x7Large: () => build(typography.x7Large)),
    'x8Large' => typography.copyWith(x8Large: () => build(typography.x8Large)),
    'x9Large' => typography.copyWith(x9Large: () => build(typography.x9Large)),
    'textMuted' =>
      typography.copyWith(textMuted: () => build(typography.textMuted)),
    'textLarge' =>
      typography.copyWith(textLarge: () => build(typography.textLarge)),
    'textSmall' =>
      typography.copyWith(textSmall: () => build(typography.textSmall)),
    _ => typography,
  };
}

// ---------------------------------------------------------------------------
// icons and scale

IconThemeProperties _icons(Map<String, dynamic> raw, {required double scale}) {
  // Scaling is applied here rather than through `IconThemeProperties.scale`
  // so the result stays inside the render-safe range: half of an 8px icon is
  // not an icon.
  double? size(String key, double fallback) {
    final value = raw[key];
    final base = value is num && value.isFinite
        ? value.toDouble().clamp(8.0, 64.0)
        : fallback;
    return (base * scale).clamp(8.0, 64.0).toDouble();
  }

  final sm = size('sm', 16);
  final md = size('md', 20);
  final lg = size('lg', 24);
  final xl = size('xl', 32);

  return IconThemeProperties(
    small: IconThemeData(size: sm),
    medium: IconThemeData(size: md),
    large: IconThemeData(size: lg),
    xLarge: IconThemeData(size: xl),
  );
}

Map<String, double> _scale(Map<String, dynamic> raw) {
  double value(String key) => _number(raw[key], 0.5, 2.0, 1.0);
  return {
    'size': value('size'),
    'text': value('text'),
    'radius': value('radius'),
    'icon': value('icon'),
    'spacing': value('spacing'),
  };
}

// ---------------------------------------------------------------------------
// primitives

double _number(Object? raw, double min, double max, double fallback) {
  if (raw is! num || !raw.isFinite) return fallback;
  return raw.toDouble().clamp(min, max).toDouble();
}

Map<String, double> _custom(Object? raw, {required double max}) {
  final map = _map(raw);
  if (map.isEmpty) return const {};
  return {
    for (final entry in map.entries)
      if (entry.value is num && (entry.value as num).isFinite)
        entry.key: (entry.value as num).toDouble().clamp(0, max).toDouble(),
  };
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is! Map) return const {};
  return raw.cast<String, dynamic>();
}

final _fontFamilyPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$');

String? _family(Object? raw) {
  if (raw is! String) return null;
  final family = raw.trim();
  if (family.isEmpty || family.length > 64) return null;
  if (!_fontFamilyPattern.hasMatch(family)) return null;
  return family;
}
