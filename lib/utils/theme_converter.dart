import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:spotube/models/metadata/metadata.dart';

class ThemeConverter {
  const ThemeConverter._();

  static shadcn.ColorScheme toColorScheme(
    ThemeColors colors, {
    required Brightness brightness,
  }) {
    // Popover/sidebar stay aliased to card-family roles by design: the
    // plugin protocol has no distinct slots for them (see Phase 2 notes).
    final charts = chartPalette(
      primary: _color(colors.primary),
      secondary: _color(colors.secondary),
      accent: _color(colors.accent),
      destructive: _color(colors.destructive),
      brightness: brightness,
    );
    return shadcn.ColorScheme(
      brightness: brightness,
      background: _color(colors.background),
      foreground: _color(colors.foreground),
      card: _color(colors.card),
      cardForeground: _color(colors.cardForeground),
      popover: _color(colors.card),
      popoverForeground: _color(colors.cardForeground),
      primary: _color(colors.primary),
      primaryForeground: _color(colors.primaryForeground),
      secondary: _color(colors.secondary),
      secondaryForeground: _color(colors.secondaryForeground),
      muted: _color(colors.muted),
      mutedForeground: _color(colors.mutedForeground),
      accent: _color(colors.accent),
      accentForeground: _color(colors.accentForeground),
      destructive: _color(colors.destructive),
      destructiveForeground: _color(colors.destructiveForeground),
      border: _color(colors.border),
      input: _color(colors.input),
      ring: _color(colors.ring),
      chart1: charts[0],
      chart2: charts[1],
      chart3: charts[2],
      chart4: charts[3],
      chart5: charts[4],
      sidebar: _color(colors.card),
      sidebarForeground: _color(colors.cardForeground),
      sidebarPrimary: _color(colors.primary),
      sidebarPrimaryForeground: _color(colors.primaryForeground),
      sidebarAccent: _color(colors.secondary),
      sidebarAccentForeground: _color(colors.secondaryForeground),
      sidebarBorder: _color(colors.border),
      sidebarRing: _color(colors.ring),
    );
  }

  static Color parseColor(String value) => _color(value);

  /// Adapts a backdrop veil color to the active brightness.
  ///
  /// Dark keeps the author's overlay as-is. Light maps it to white at
  /// the same alpha: the veil strength stays author-chosen while the
  /// color follows the mode, so light themes read like stock light
  /// instead of sitting under a dark veil.
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

  static Color _color(String value) {
    final hex = value.replaceFirst('#', '');

    if (hex.length != 6 && hex.length != 8) {
      throw FormatException('Invalid theme color: $value');
    }

    final normalized = hex.length == 6 ? 'FF$hex' : hex;

    return Color(int.parse(normalized, radix: 16));
  }
}
