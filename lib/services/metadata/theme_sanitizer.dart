import 'package:spotube/models/metadata/metadata.dart';

/// Clamps untrusted plugin numerics to render-safe ranges.
///
/// Only clamps: out-of-range numbers keep their intent (0.85 stays 0.85), and
/// a value that is merely large still gets the largest render-safe version.
/// Structurally invalid data (missing keys, wrong types) throws from
/// `fromJson` and falls back to the built-in theme upstream.
///
/// Ranges exist because these numbers reach layout constraints directly: one
/// `density: 500` in a plugin would otherwise produce infinite-size cells, and
/// a non-finite double from the Hetu boundary poisons every constraint it
/// touches. Anything outside a range is a plugin bug, and the honest recovery
/// is the nearest plausible value.
ThemeDefinition sanitizeThemeDefinition(ThemeDefinition definition) {
  final radius = definition.radius;
  final tokens = definition.tokens;

  return definition.copyWith(
    surfaces: definition.surfaces.copyWith(
      opacity: _fraction(definition.surfaces.opacity, 0.8),
      blur: _px(definition.surfaces.blur, max: 100),
    ),
    background: definition.background.copyWith(
      opacity: _fraction(definition.background.opacity, 0.0),
      blur: _px(definition.background.blur, max: 100),
    ),
    radius: radius.copyWith(
      small: _px(radius.small, max: 48),
      medium: _px(radius.medium, max: 48),
      large: _px(radius.large, max: 64),
      // Pill is a sentinel for "fully round"; components clamp it to the
      // shorter side, so a large value is intended rather than a mistake.
      pill: _px(radius.pill, max: 9999, fallback: 999),
    ),
    density: _density(definition.density),
    tokens: tokens.copyWith(
      cardWidth: _between(tokens.cardWidth, min: 80, max: 400, fallback: 150),
      cardHeight:
          _between(tokens.cardHeight, min: 120, max: 600, fallback: 225),
      artistCardWidth: _between(
        tokens.artistCardWidth,
        min: 80,
        max: 480,
        fallback: 180,
      ),
      artistCardHeight: _between(
        tokens.artistCardHeight,
        min: 120,
        max: 640,
        fallback: 250,
      ),
      gutter: _between(tokens.gutter, min: 0, max: 40, fallback: 12),
      fontFamily: _sanitizeFontFamily(tokens.fontFamily),
    ),
  );
}

/// A 0..1 opacity, or [fallback] when the plugin sent something unusable.
double _fraction(double value, double fallback) =>
    _between(value, min: 0, max: 1, fallback: fallback);

/// Density rides the app's size and text scaling, so a wild value resizes
/// every widget at once. Zero or negative means "not a density" and is read as
/// the neutral 1.0 rather than the nearest bound — an unset field arrives as 0
/// through some JSON paths, and 0.7 would shrink the whole UI on their account.
double _density(double value) {
  if (!value.isFinite || value <= 0) return 1.0;
  return _between(value, min: 0.7, max: 1.5, fallback: 1.0);
}

/// A non-negative pixel count capped at [max].
double _px(double value, {required double max, double fallback = 0}) =>
    _between(value, min: 0, max: max, fallback: fallback);

double _between(
  double value, {
  required double min,
  required double max,
  required double fallback,
}) {
  if (!value.isFinite) return fallback;
  return value.clamp(min, max).toDouble();
}

/// Keeps a font family name only if it can plausibly name one.
///
/// The family is looked up in fonts the platform already resolved — a plugin
/// cannot load a font file through it — so the failure mode for a bad name is
/// "silently the default font". Length and character limits are what keeps a
/// hostile or garbled value out of the text style tree.
String? _sanitizeFontFamily(String? family) {
  if (family == null) return null;
  final trimmed = family.trim();
  if (trimmed.isEmpty || trimmed.length > 64) return null;
  if (!_fontFamilyPattern.hasMatch(trimmed)) return null;
  return trimmed;
}

final _fontFamilyPattern = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 ._-]*$");
