import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Canonical built-in palettes as [ThemeColors], matching the ultimate
/// fallbacks in main (Legacy slate schemes).
///
/// Used wherever a full [ThemeDefinition] is needed but only one side
/// comes from an external source (e.g. the Caelestia adapter fills the
/// active mode and falls back to these for the opposite mode).

String _hex(Color color) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${argb.startsWith('ff') ? argb.substring(2) : argb}';
}

ThemeColors _fromScheme(ColorScheme scheme) => ThemeColors(
      background: _hex(scheme.background),
      foreground: _hex(scheme.foreground),
      card: _hex(scheme.card),
      cardForeground: _hex(scheme.cardForeground),
      primary: _hex(scheme.primary),
      primaryForeground: _hex(scheme.primaryForeground),
      secondary: _hex(scheme.secondary),
      secondaryForeground: _hex(scheme.secondaryForeground),
      muted: _hex(scheme.muted),
      mutedForeground: _hex(scheme.mutedForeground),
      accent: _hex(scheme.accent),
      accentForeground: _hex(scheme.accentForeground),
      destructive: _hex(scheme.destructive),
      // shadcn keeps the value and our 17-color contract requires it.
      // ignore: deprecated_member_use
      destructiveForeground: _hex(scheme.destructiveForeground),
      border: _hex(scheme.border),
      input: _hex(scheme.input),
      ring: _hex(scheme.ring),
    );

ThemeColors builtInLightThemeColors() =>
    _fromScheme(LegacyColorSchemes.lightSlate());

ThemeColors builtInDarkThemeColors() =>
    _fromScheme(LegacyColorSchemes.darkSlate());
