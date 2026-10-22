import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:spotube/models/metadata/metadata.dart';

class ThemeConverter {
  const ThemeConverter._();

  /// Builds a colour scheme from a theme's palette.
  ///
  /// Every role is resolved on its own: a role the theme did not send falls
  /// back to the role it aliases, and a role the theme sent but that cannot
  /// be parsed falls back to the host's own scheme. Before, one bad colour
  /// threw and the whole palette was discarded — the app drew its built-in
  /// theme and the user was left wondering why their theme "did not apply".
  ///
  /// The fallback scheme is the built-in palette for this brightness; it is
  /// what the theme is merged onto, role by role.
  static shadcn.ColorScheme toColorScheme(
    ThemeColors colors, {
    required Brightness brightness,
    required shadcn.ColorScheme fallback,
  }) {
    final charts = chartPalette(
      primary: _role(colors.primary, fallback.primary),
      secondary: _role(colors.secondary, fallback.secondary),
      accent: _role(colors.accent, fallback.accent),
      destructive: _role(colors.destructive, fallback.destructive),
      brightness: brightness,
    );

    return shadcn.ColorScheme(
      brightness: brightness,
      background: _role(colors.background, fallback.background),
      foreground: _role(colors.foreground, fallback.foreground),
      card: _role(colors.card, fallback.card),
      cardForeground: _role(colors.cardForeground, fallback.cardForeground),
      // The popover is its own surface when the theme says so, and the card
      // surface otherwise — which is what it was before the role existed.
      popover: _role(colors.popover, _role(colors.card, fallback.popover)),
      popoverForeground: _role(
        colors.popoverForeground,
        _role(colors.cardForeground, fallback.popoverForeground),
      ),
      primary: _role(colors.primary, fallback.primary),
      primaryForeground:
          _role(colors.primaryForeground, fallback.primaryForeground),
      secondary: _role(colors.secondary, fallback.secondary),
      secondaryForeground:
          _role(colors.secondaryForeground, fallback.secondaryForeground),
      muted: _role(colors.muted, fallback.muted),
      mutedForeground: _role(colors.mutedForeground, fallback.mutedForeground),
      accent: _role(colors.accent, fallback.accent),
      accentForeground: _role(colors.accentForeground, fallback.accentForeground),
      destructive: _role(colors.destructive, fallback.destructive),
      destructiveForeground: _role(
        colors.destructiveForeground,
        // ignore: deprecated_member_use
        fallback.destructiveForeground,
      ),
      border: _role(colors.border, fallback.border),
      input: _role(colors.input, fallback.input),
      ring: _role(colors.ring, fallback.ring),
      sidebar: _role(colors.sidebar, _role(colors.card, fallback.sidebar)),
      sidebarForeground: _role(
        colors.sidebarForeground,
        _role(colors.cardForeground, fallback.sidebarForeground),
      ),
      sidebarPrimary: _role(
        colors.sidebarPrimary,
        _role(colors.primary, fallback.sidebarPrimary),
      ),
      sidebarPrimaryForeground: _role(
        colors.sidebarPrimaryForeground,
        _role(colors.primaryForeground, fallback.sidebarPrimaryForeground),
      ),
      sidebarAccent: _role(
        colors.sidebarAccent,
        _role(colors.secondary, fallback.sidebarAccent),
      ),
      sidebarAccentForeground: _role(
        colors.sidebarAccentForeground,
        _role(colors.secondaryForeground, fallback.sidebarAccentForeground),
      ),
      sidebarBorder: _role(
        colors.sidebarBorder,
        _role(colors.border, fallback.sidebarBorder),
      ),
      sidebarRing: _role(colors.sidebarRing, _role(colors.ring, fallback.sidebarRing)),
      chart1: _role(colors.chart1, charts[0]),
      chart2: _role(colors.chart2, charts[1]),
      chart3: _role(colors.chart3, charts[2]),
      chart4: _role(colors.chart4, charts[3]),
      chart5: _role(colors.chart5, charts[4]),
    );
  }

  /// The status colours and the sixth chart colour, resolved from a palette.
  ///
  /// They are not part of shadcn's `ColorScheme`, so they are resolved here
  /// and published beside it.
  static ThemeSemanticColors toSemanticColors(
    ThemeColors colors, {
    required ThemeSemanticColors fallback,
  }) {
    return ThemeSemanticColors(
      success: _hex(colors.success, fallback.success),
      successForeground:
          _hex(colors.successForeground, fallback.successForeground),
      warning: _hex(colors.warning, fallback.warning),
      warningForeground:
          _hex(colors.warningForeground, fallback.warningForeground),
      info: _hex(colors.info, fallback.info),
      infoForeground: _hex(colors.infoForeground, fallback.infoForeground),
      chart6: _hex(colors.chart6, fallback.chart6),
    );
  }

  /// One role: the theme's value when it has one, the fallback otherwise.
  static Color _role(String? value, Color fallback) {
    if (value == null) return fallback;
    final parsed = _tryParseColor(value);
    return parsed ?? fallback;
  }

  /// One role as a hex string, for the values that travel as strings.
  static String _hex(String? value, String fallback) {
    if (value == null) return fallback;
    return _tryParseColor(value) == null ? fallback : value;
  }

  /// Parses a colour, or answers null when the theme sent nonsense.
  static Color? _tryParseColor(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    final normalized = hex.length == 6 ? 'FF$hex' : hex;
    return Color(int.parse(normalized, radix: 16));
  }

  static Color parseColor(String value) =>
      _tryParseColor(value) ??
      (throw FormatException('Invalid theme color: $value'));

  /// Adapts a backdrop veil color to the active brightness.
  ///
  /// Dark keeps the author's overlay as-is. Light maps it to white at the
  /// same alpha: the veil strength stays author-chosen while the color
  /// follows the mode, so light themes read like stock light instead of
  /// sitting under a dark veil.
  static Color adaptOverlayForBrightness(Color overlay, Brightness brightness) {
    if (brightness == Brightness.dark) return overlay;
    final alpha = (overlay.toARGB32() >> 24) & 0xFF;
    return Color.fromARGB(alpha, 255, 255, 255);
  }

  /// Categorical palette derived from theme roles.
  ///
  /// Hues blend theme roles toward classic categorical anchors so
  /// low-saturation themes (e.g. Caelestia neutral grays) still get
  /// separated, vivid categories. Saturation is floored and lightness
  /// is brightness-aware for readability in both modes. Deterministic
  /// for a given input. Six entries: the scheme consumes the first
  /// five, summary cards use all six.
  static List<Color> chartPalette({
    required Color primary,
    required Color secondary,
    required Color accent,
    required Color destructive,
    required Brightness brightness,
  }) {
    const anchors = [217.0, 142.0, 48.0, 0.0, 180.0, 300.0];
    final lightness = brightness == Brightness.dark ? 0.68 : 0.45;
    final bases = [primary, secondary, accent, destructive];
    return List.generate(6, (i) {
      final base = i < 4 ? bases[i] : (i == 4 ? primary : secondary);
      final baseHsl = HSLColor.fromColor(base);
      final saturation = baseHsl.saturation.clamp(0.0, 1.0);
      var hue = baseHsl.hue;
      // 5th/6th complement their base for separation.
      if (i >= 4) hue = (hue + 180.0) % 360.0;
      // Gray bases carry no hue information: snap to the anchor so
      // neutral themes still get separated categories.
      hue = _lerpAngle(hue, anchors[i], saturation < 0.2 ? 1.0 : 0.5);
      return baseHsl
          .withHue(hue)
          .withSaturation(
            saturation < 0.55 ? 0.55 : saturation,
          )
          .withLightness(lightness)
          .toColor();
    });
  }

  /// Pale card fill for a categorical color, both modes.
  static Color chartCardFill(Color color, Brightness brightness) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(
            hsl.saturation.clamp(0.0, 1.0) < 0.35 ? 0.35 : hsl.saturation)
        .withLightness(brightness == Brightness.dark ? 0.85 : 0.93)
        .toColor();
  }

  /// Dark card text for a categorical color, both modes.
  static Color chartCardText(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(
            hsl.saturation.clamp(0.0, 1.0) < 0.45 ? 0.45 : hsl.saturation)
        .withLightness(0.25)
        .toColor();
  }

  static double _lerpAngle(double a, double b, double t) {
    var d = (b - a) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return (a + d * t) % 360.0;
  }
}
