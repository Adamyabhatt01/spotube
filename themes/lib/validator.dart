import 'dart:math' as math;

import 'v3_validator.dart';
import 'v4_validator.dart';

/// How loud a finding is.
///
/// [error] means the host throws and the whole theme is discarded. [warning]
/// means the host keeps the theme but quietly changes the value — which is
/// exactly the class of bug a theme author cannot see today.
enum Severity { error, warning }

/// One finding about a payload.
class Issue {
  const Issue(this.severity, this.path, this.message, {this.resolved});

  final Severity severity;

  /// Where the problem is, e.g. `dark.primary`.
  final String path;

  final String message;

  /// The value the host ends up with, when the host changes it.
  final Object? resolved;

  @override
  String toString() {
    final resolvedText = resolved == null ? '' : ' (host uses: $resolved)';
    return '${severity == Severity.error ? 'error' : 'warn '}  '
        '$path: $message$resolvedText';
  }
}

/// The result of validating one payload.
class ValidationReport {
  ValidationReport(this.issues, this.resolved);

  final List<Issue> issues;

  /// The payload as the host will actually use it, after clamping.
  ///
  /// Null when the payload is unusable (the host would throw before it gets
  /// this far).
  final Map<String, dynamic>? resolved;

  bool get hasErrors => issues.any((issue) => issue.severity == Severity.error);

  int get errorCount =>
      issues.where((i) => i.severity == Severity.error).length;

  int get warningCount =>
      issues.where((i) => i.severity == Severity.warning).length;
}

/// The color roles a theme must define, in the host's own spelling.
const colorRoles = <String>[
  'background',
  'foreground',
  'card',
  'cardForeground',
  'primary',
  'primaryForeground',
  'secondary',
  'secondaryForeground',
  'muted',
  'mutedForeground',
  'accent',
  'accentForeground',
  'destructive',
  'destructiveForeground',
  'border',
  'input',
  'ring',
];

/// Top-level keys the host reads today.
///
/// `specVersion` is not among them: the host ignores unknown keys, so a theme
/// that declares it is safe to ship to a host that predates the field. That is
/// reported as a warning, not an error.
const knownTopLevelKeys = <String>[
  'light',
  'dark',
  'surfaces',
  'background',
  'radius',
  'density',
  'tokens',
  'layout',
  'dynamic',
];

/// Validates a theme payload against the current contract.
///
/// v2 (no `specVersion`) is still read. v3 is rejected before any parsing:
/// the message is the migration instruction, not a list of v3 findings.
ValidationReport validateThemePayload(Map<String, dynamic> payload) =>
    _validateThemePayload(payload, allowV3: false);

/// Validates a legacy v3 payload for the build and migration tools.
///
/// The host never calls this: `themes/tools/migrate_v3.dart` and the bundled
/// v3 themes need the old rules until Phase 11 rewrites those themes.
ValidationReport validateLegacyThemePayload(Map<String, dynamic> payload) =>
    _validateThemePayload(payload, allowV3: true);

ValidationReport _validateThemePayload(
  Map<String, dynamic> payload, {
  required bool allowV3,
}) {
  final issues = <Issue>[];

  final specVersion = payload['specVersion'];
  final isV2 = specVersion == null || (specVersion is num && specVersion == 2);
  final isV3 = specVersion is num && specVersion == 3;
  final isV4 = specVersion is num && specVersion == 4;

  if (!isV2 && !isV3 && !isV4) {
    issues.add(
      Issue(
        Severity.error,
        'specVersion',
        specVersion == null
            ? 'must be 4'
            : 'must be 4 — omit it only for a legacy v2 payload',
      ),
    );
    return ValidationReport(issues, null);
  }

  if (isV3 && !allowV3) {
    issues.add(
      const Issue(
        Severity.error,
        'specVersion',
        'specVersion 3 is not supported; migrate to 4',
      ),
    );
    return ValidationReport(issues, null);
  }

  final isV3OrNewer = isV3 || isV4;
  final known = <String>{
    if (isV4) ...v4TopLevelKeys,
    if (!isV4) ...knownTopLevelKeys,
    if (!isV4 && isV3OrNewer) ...v3TopLevelKeys,
  };

  for (final key in payload.keys) {
    if (!known.contains(key)) {
      issues.add(
        Issue(
          isV4 ? Severity.error : Severity.warning,
          key,
          isV4
              ? 'not a v4 top-level key — the host rejects it'
              : 'not read by the app — this field is ignored',
        ),
      );
    }
  }

  final light = _palette(payload, 'light', issues, allowV3Roles: isV3OrNewer);
  final dark = _palette(payload, 'dark', issues, allowV3Roles: isV3OrNewer);

  final surfaces = _map(payload, 'surfaces', issues);
  final background = _map(payload, 'background', issues);
  final radius = _map(payload, 'radius', issues);
  final tokens = _map(payload, 'tokens', issues);
  final layout = _map(payload, 'layout', issues);

  final resolvedSurfaces = _resolveSurfaces(surfaces, issues);
  final resolvedBackground = _resolveBackground(
    background,
    issues,
    allowAsset: isV3OrNewer,
  );
  final resolvedRadius = _resolveRadius(radius, issues);
  final resolvedTokens = _resolveTokens(tokens, issues);
  final resolvedLayout = _resolveLayout(layout, issues);
  final resolvedDensity = _resolveDensity(payload['density'], issues);
  final resolvedDynamic = _resolveDynamic(
    _map(payload, 'dynamic', issues),
    issues,
  );

  if (isV4) {
    issues.addAll(validateV4Blocks(payload));
  } else if (isV3) {
    issues.addAll(validateV3Blocks(payload));
  }

  final hasErrors = issues.any((issue) => issue.severity == Severity.error);
  if (hasErrors) {
    return ValidationReport(issues, null);
  }

  final resolved = <String, dynamic>{
    'light': light,
    'dark': dark,
    'surfaces': resolvedSurfaces,
    'background': resolvedBackground,
    'radius': resolvedRadius,
    'density': resolvedDensity,
    'tokens': resolvedTokens,
    'layout': resolvedLayout,
    if (resolvedDynamic != null) 'dynamic': resolvedDynamic,
  };

  return ValidationReport(issues, resolved);
}

/// The light or dark palette: 17 required roles, each a hex color.
Map<String, dynamic> _palette(
  Map<String, dynamic> payload,
  String key,
  List<Issue> issues, {
  bool allowV3Roles = false,
}) {
  final raw = payload[key];
  if (raw is! Map) {
    issues.add(
      Issue(
        Severity.error,
        key,
        raw == null
            ? 'required — the host throws and falls back to the built-in theme'
            : 'must be an object',
      ),
    );
    return const {};
  }

  final palette = <String, dynamic>{};
  for (final role in colorRoles) {
    final value = raw[role];
    if (value == null) {
      issues.add(
        Issue(
          Severity.error,
          '$key.$role',
          'required — a missing role discards the whole theme',
        ),
      );
      continue;
    }
    if (value is! String) {
      issues.add(
        Issue(
          Severity.error,
          '$key.$role',
          'must be a string, got ${value.runtimeType}',
        ),
      );
      continue;
    }
    if (!_isHexColor(value)) {
      issues.add(
        Issue(
          Severity.error,
          '$key.$role',
          'not a #RRGGBB or #AARRGGBB color — the host throws and discards '
              'the whole palette',
        ),
      );
      continue;
    }
    palette[role] = value;
  }

  final known = allowV3Roles ? {...colorRoles, ...v3PaletteRoles} : colorRoles;
  for (final extra in raw.keys) {
    if (!known.contains(extra)) {
      issues.add(
        Issue(
          Severity.warning,
          '$key.$extra',
          'not a v2 color role — ignored by the host',
        ),
      );
    }
  }

  return palette;
}

/// The `surfaces` block.
Map<String, dynamic> _resolveSurfaces(
  Map<String, dynamic> surfaces,
  List<Issue> issues,
) {
  return {
    'opacity': _fraction(surfaces, 'surfaces.opacity', 0.8, issues),
    'blur': _clamped(
      surfaces,
      'surfaces.blur',
      min: 0,
      max: 100,
      issues: issues,
    ),
    if (surfaces['tint'] != null)
      'tint': _color(surfaces, 'surfaces.tint', issues),
  };
}

/// The `background` block.
Map<String, dynamic> _resolveBackground(
  Map<String, dynamic> background,
  List<Issue> issues, {
  bool allowAsset = false,
}) {
  // `asset` is a v3 source: a v2 host would reject it, which is why a v2
  // payload is not allowed to name it.
  final sources = {'none', 'albumArt', 'shell', if (allowAsset) 'asset'};
  final source = background['source'];
  var resolvedSource = 'none';
  if (source == null) {
    // The host's default is `none`; absent is fine.
  } else if (source is String && sources.contains(source)) {
    resolvedSource = source;
  } else {
    issues.add(
      Issue(
        Severity.error,
        'background.source',
        'must be one of ${sources.join(', ')} — an unknown value makes the host '
            'throw and discard the theme',
      ),
    );
  }

  // A source with no asset is a background the host cannot draw.
  if (resolvedSource == 'asset') {
    final asset = background['asset'];
    if (asset is! String || !asset.startsWith('asset://')) {
      issues.add(
        const Issue(
          Severity.error,
          'background.asset',
          'source is asset but no asset:// path is given',
        ),
      );
    }
  }

  final transparent = background['transparent'];
  Object? resolvedTransparent;
  if (transparent is bool) {
    resolvedTransparent = transparent;
  } else if (transparent != null) {
    issues.add(
      Issue(
        Severity.warning,
        'background.transparent',
        'must be a boolean — the host reads anything else as "no opinion"',
      ),
    );
  }

  // A tiled background is drawn at integer magnification so a pixel texture
  // stays a pixel texture: nearest-neighbour, never a smooth stretch.
  var scale = background['scale'];
  if (scale != null) {
    if (scale is! num || scale < 1 || scale > 8) {
      issues.add(
        Issue(
          Severity.warning,
          'background.scale',
          'must be a number 1..8 — the host uses 1',
          resolved: 1,
        ),
      );
      scale = 1;
    } else if (scale != scale.roundToDouble()) {
      issues.add(
        Issue(
          Severity.warning,
          'background.scale',
          'must be a whole number — the host rounds it',
          resolved: scale.roundToDouble(),
        ),
      );
      scale = scale.roundToDouble();
    }
  }

  final tile = background['tile'];
  if (tile != null && tile is! bool) {
    issues.add(
      const Issue(
        Severity.warning,
        'background.tile',
        'must be a boolean — the host reads anything else as "no"',
      ),
    );
  }

  return {
    'source': resolvedSource,
    'opacity': _fraction(background, 'background.opacity', 0.0, issues),
    'blur': _clamped(
      background,
      'background.blur',
      min: 0,
      max: 100,
      issues: issues,
    ),
    if (background['overlay'] != null)
      'overlay': _color(background, 'background.overlay', issues),
    if (resolvedTransparent != null) 'transparent': resolvedTransparent,
    if (tile is bool) 'tile': tile,
    if (scale is num) 'scale': scale.toInt(),
    if (resolvedSource == 'asset' && background['asset'] is String)
      'asset': background['asset'],
  };
}

/// The `radius` block.
Map<String, dynamic> _resolveRadius(
  Map<String, dynamic> radius,
  List<Issue> issues,
) {
  return {
    'small': _clamped(radius, 'radius.small', min: 0, max: 48, issues: issues),
    'medium': _clamped(
      radius,
      'radius.medium',
      min: 0,
      max: 48,
      issues: issues,
    ),
    'large': _clamped(radius, 'radius.large', min: 0, max: 64, issues: issues),
    'pill': _clamped(
      radius,
      'radius.pill',
      min: 0,
      max: 9999,
      fallback: 999,
      issues: issues,
    ),
  };
}

/// The `density` value.
double _resolveDensity(Object? value, List<Issue> issues) {
  if (value == null) return 1.0;
  if (value is! num) {
    issues.add(const Issue(Severity.error, 'density', 'must be a number'));
    return 1.0;
  }
  final density = value.toDouble();
  if (!density.isFinite || density <= 0) {
    issues.add(
      Issue(
        Severity.warning,
        'density',
        'must be a positive number',
        resolved: 1.0,
      ),
    );
    return 1.0;
  }
  if (density < 0.7 || density > 1.5) {
    issues.add(
      Issue(
        Severity.warning,
        'density',
        'outside 0.7..1.5',
        resolved: density.clamp(0.7, 1.5).toDouble(),
      ),
    );
    return density.clamp(0.7, 1.5).toDouble();
  }
  return density;
}

/// The `tokens` block.
Map<String, dynamic> _resolveTokens(
  Map<String, dynamic> tokens,
  List<Issue> issues,
) {
  final resolved = <String, dynamic>{
    'cardWidth': _clamped(
      tokens,
      'tokens.cardWidth',
      min: 80,
      max: 400,
      fallback: 150,
      issues: issues,
    ),
    'cardHeight': _clamped(
      tokens,
      'tokens.cardHeight',
      min: 120,
      max: 600,
      fallback: 225,
      issues: issues,
    ),
    'artistCardWidth': _clamped(
      tokens,
      'tokens.artistCardWidth',
      min: 80,
      max: 480,
      fallback: 180,
      issues: issues,
    ),
    'artistCardHeight': _clamped(
      tokens,
      'tokens.artistCardHeight',
      min: 120,
      max: 640,
      fallback: 250,
      issues: issues,
    ),
    'gutter': _clamped(
      tokens,
      'tokens.gutter',
      min: 0,
      max: 40,
      fallback: 12,
      issues: issues,
    ),
  };

  final family = tokens['fontFamily'];
  if (family != null) {
    if (family is! String) {
      issues.add(
        const Issue(
          Severity.warning,
          'tokens.fontFamily',
          'must be a string — dropped',
        ),
      );
    } else {
      final trimmed = family.trim();
      if (trimmed.isEmpty || trimmed.length > 64) {
        issues.add(
          const Issue(
            Severity.warning,
            'tokens.fontFamily',
            'empty or longer than 64 characters — dropped',
          ),
        );
      } else if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$').hasMatch(trimmed)) {
        issues.add(
          const Issue(
            Severity.warning,
            'tokens.fontFamily',
            'contains characters no font family can have — dropped',
          ),
        );
      } else {
        resolved['fontFamily'] = trimmed;
      }
    }
  }

  return resolved;
}

/// The `layout` block.
Map<String, dynamic> _resolveLayout(
  Map<String, dynamic> layout,
  List<Issue> issues,
) {
  const chrome = {'flat': 'flat', 'inset': 'inset'};
  const nav = {'labels': 'labels', 'rail': 'rail'};
  const progress = {'inline': 'inline', 'below': 'below'};

  return {
    'chrome': _enumValue(layout, 'layout.chrome', chrome, 'flat', issues),
    'nav': _enumValue(layout, 'layout.nav', nav, 'labels', issues),
    'progress': _enumValue(
      layout,
      'layout.progress',
      progress,
      'inline',
      issues,
    ),
  };
}

/// The `dynamic` block.
Map<String, dynamic>? _resolveDynamic(
  Map<String, dynamic> block,
  List<Issue> issues,
) {
  if (block.isEmpty) return null;

  const sources = {'albumArt', 'shell'};
  const algorithms = {'material'};

  final source = block['source'];
  var resolvedSource = source;
  if (source == null) {
    issues.add(
      const Issue(
        Severity.error,
        'dynamic.source',
        'required when `dynamic` is present — the host throws',
      ),
    );
    resolvedSource = 'albumArt';
  } else if (source is! String || !sources.contains(source)) {
    issues.add(
      Issue(
        Severity.error,
        'dynamic.source',
        'must be one of ${sources.join(', ')} — the host throws',
      ),
    );
    resolvedSource = 'albumArt';
  }

  final algorithm = block['algorithm'];
  var resolvedAlgorithm = 'material';
  if (algorithm == null) {
    // The host's default.
  } else if (algorithm is! String || !algorithms.contains(algorithm)) {
    issues.add(
      Issue(
        Severity.error,
        'dynamic.algorithm',
        'must be one of ${algorithms.join(', ')} — the host throws',
      ),
    );
  } else {
    resolvedAlgorithm = algorithm;
  }

  return {'source': resolvedSource, 'algorithm': resolvedAlgorithm};
}

/// A sub-object of the payload.
Map<String, dynamic> _map(
  Map<String, dynamic> payload,
  String key,
  List<Issue> issues,
) {
  final value = payload[key];
  if (value == null) return const {};
  if (value is! Map) {
    issues.add(Issue(Severity.error, key, 'must be an object'));
    return const {};
  }
  return value.cast<String, dynamic>();
}

/// A number clamped into the host's range.
double _clamped(
  Map<String, dynamic> map,
  String path, {
  required double min,
  required double max,
  double? fallback,
  required List<Issue> issues,
}) {
  final value = map[path.split('.').last];
  if (value == null) {
    if (fallback != null) return fallback;
    // The host's own default for an absent field.
    return _hostDefault(path);
  }
  if (value is! num) {
    issues.add(Issue(Severity.error, path, 'must be a number'));
    return fallback ?? _hostDefault(path);
  }
  final number = value.toDouble();
  if (!number.isFinite) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'is not a finite number',
        resolved: fallback ?? _hostDefault(path),
      ),
    );
    return fallback ?? _hostDefault(path);
  }
  if (number < min || number > max) {
    final clamped = math.max(min, math.min(max, number));
    issues.add(
      Issue(Severity.warning, path, 'outside $min..$max', resolved: clamped),
    );
    return clamped;
  }
  return number;
}

/// The host's default for an absent numeric field.
double _hostDefault(String path) {
  switch (path) {
    case 'surfaces.opacity':
      return 0.8;
    case 'surfaces.blur':
    case 'background.opacity':
    case 'background.blur':
      return 0.0;
    case 'radius.small':
    case 'radius.medium':
    case 'radius.large':
      return 0.0;
    case 'radius.pill':
      return 999.0;
    case 'tokens.cardWidth':
      return 150.0;
    case 'tokens.cardHeight':
      return 225.0;
    case 'tokens.artistCardWidth':
      return 180.0;
    case 'tokens.artistCardHeight':
      return 250.0;
    case 'tokens.gutter':
      return 12.0;
    default:
      return 0.0;
  }
}

/// A 0..1 value.
double _fraction(
  Map<String, dynamic> map,
  String path,
  double fallback,
  List<Issue> issues,
) {
  return _clamped(
    map,
    path,
    min: 0,
    max: 1,
    fallback: fallback,
    issues: issues,
  );
}

/// An enum value with a known fallback.
String _enumValue(
  Map<String, dynamic> map,
  String path,
  Map<String, String> allowed,
  String fallback,
  List<Issue> issues,
) {
  final value = map[path.split('.').last];
  if (value == null) return fallback;
  if (value is String && allowed.containsKey(value)) return value;
  issues.add(
    Issue(
      Severity.warning,
      path,
      'must be one of ${allowed.keys.join(', ')} — the host falls back',
      resolved: fallback,
    ),
  );
  return fallback;
}

/// A hex color that the host can parse.
String _color(Map<String, dynamic> map, String path, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value is! String || !_isHexColor(value)) {
    issues.add(
      Issue(Severity.error, path, 'must be a #RRGGBB or #AARRGGBB color'),
    );
    return '#000000';
  }
  return value;
}

/// Whether a value parses as a color the host accepts.
///
/// The host strips one leading `#` and requires 6 or 8 hex digits; anything
/// else throws, and a throw there discards the entire theme.
bool _isHexColor(String value) {
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return false;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return false;
  return int.tryParse(hex, radix: 16) != null;
}
