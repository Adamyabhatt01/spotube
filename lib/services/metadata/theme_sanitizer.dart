import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';

/// The contract's migration instruction, worded as `themes/lib/validator.dart`
/// words it so an author sees the same message from the toolchain and the app.
const themeV3Rejection = 'specVersion 3 is not supported; migrate to 4';

/// Whether the v3 rejection has been written to the app log yet.
///
/// Sanitizing runs on every theme recompute, and one theme losing its UI is
/// one fact — a line per repaint would bury the rest of the log.
var _v3RejectionLogged = false;

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
///
/// It also enforces the version gate: v4 is a breaking contract, so a v3
/// payload keeps its colours and loses its UI document. Both the plugin and the
/// warm-start cache paths come through here, which is why the gate is here
/// rather than in the endpoint. A v3 theme's optional `getUi()` answer is
/// refused one level up, in `themeUiProvider`, so it is never even invoked.
ThemeDefinition sanitizeThemeDefinition(ThemeDefinition definition) {
  final radius = definition.radius;
  final tokens = definition.tokens;

  if (definition.specVersion == 3 && !_v3RejectionLogged) {
    _v3RejectionLogged = true;
    AppLogger.logEvent('[theme] $themeV3Rejection');
  }

  return definition.copyWith(
    ui: definition.specVersion == 3 ? null : definition.ui,
    surfaces: definition.surfaces.copyWith(
      opacity: _fraction(definition.surfaces.opacity, 0.8),
      blur: _px(definition.surfaces.blur, max: 100),
    ),
    background: definition.background.copyWith(
      opacity: _fraction(definition.background.opacity, 0.0),
      blur: _px(definition.background.blur, max: 100),
      scale: _intBetween(definition.background.scale, min: 1, max: 8),
      // Tri-state opt-in, intentionally unclamped: a bool cannot poison
      // layout, and the tri-state (true/false/absent) is the contract —
      // normalizing here would collapse "no opinion" into a decision.
      // Non-bool payloads already decode to null in `fromJson`.
      transparent: definition.background.transparent,
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
    layout: definition.layout.copyWith(
      sidebarWidth: _optionalPx(definition.layout.sidebarWidth, max: 1000),
      asideWidth: _optionalPx(definition.layout.asideWidth, max: 1000),
    ),
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

/// Moves the payload's declared capabilities onto its UI document.
///
/// The contract declares capabilities once, at the top level of `getTheme()`:
/// `"capabilities": ["ui.hostWidgets", "library.write"]`. The runtime reads
/// them from [ThemeUiDocument.capabilities], because a UI document can also
/// arrive from `getUi()`/`onUiAction()` without the theme payload around it.
/// Nothing copied the list across, so every opt-in host widget and
/// account-mutating action saw an empty grant and silently disabled itself.
///
/// Anything the document already declares is kept, so both spellings work for
/// a theme built against a host that expected the list inside `ui`.
ThemeDefinition withUiCapabilities(
  ThemeDefinition definition,
  List<String> payloadCapabilities,
) {
  final ui = definition.ui;
  if (ui == null || payloadCapabilities.isEmpty) return definition;

  final merged = <String>{
    ...ui.capabilities,
    ...payloadCapabilities,
  }.toList(growable: false);
  if (merged.length == ui.capabilities.length) return definition;

  return definition.copyWith(ui: ui.copyWith(capabilities: merged));
}

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

/// An optional pixel count: null stays null ("host default") and a non-finite
/// value falls back to that default rather than poisoning a constraint.
double? _optionalPx(double? value, {required double max}) {
  if (value == null || !value.isFinite) return null;
  return value.clamp(0.0, max).toDouble();
}

double _between(
  double value, {
  required double min,
  required double max,
  required double fallback,
}) {
  if (!value.isFinite) return fallback;
  return value.clamp(min, max).toDouble();
}

/// A whole-number pixel multiplier (background tile scale), clamped.
int _intBetween(int value, {required int min, required int max}) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
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
