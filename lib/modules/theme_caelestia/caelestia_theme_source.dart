import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_state.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

/// The live scheme's `surface` role, and the mode it is active in.
typedef CaelestiaSurface = ({String hex, String mode});

/// Host-side adapter: Caelestia `scheme.json` → [ThemeDefinition].
///
/// Caelestia only exposes the currently active scheme, so the adapter is
/// mode-aware: the active side gets Caelestia colors, the opposite side
/// gets Spotube's built-in palette. Missing or malformed state yields
/// null rather than a partially valid theme.
///
/// Async by design: file content is read off the event loop instead of
/// blocking it during theme resolution (startup / shell-change path).
class CaelestiaThemeSource {
  /// Override for tests. Defaults to [caelestiaStateDir].
  final String? stateDir;

  const CaelestiaThemeSource({this.stateDir});

  static final _hexPattern = RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$');

  /// Reads and shape-checks `scheme.json`. Null when absent or malformed.
  Future<({String mode, Map colours})?> _readScheme() async {
    final stateDir = caelestiaStateDir(this.stateDir);
    if (stateDir == null) return null;
    final raw = await File(
      p.join(stateDir, 'scheme.json'),
    ).readAsString();
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;

    final mode = json['mode'];
    if (mode != 'dark' && mode != 'light') return null;

    final colours = json['colours'];
    if (colours is! Map) return null;

    return (mode: mode as String, colours: colours);
  }

  /// The live scheme's `surface` role and active mode.
  ///
  /// Glass derivation needs exactly these two: `surface` is what the terminal
  /// paints its background with (caelestia sends it as OSC 11), and the mode
  /// picks which `[colors-*]` alpha applies. [ThemeColors] cannot stand in —
  /// its `card` carries the surface hex but not the mode it came from.
  Future<CaelestiaSurface?> getSurface() async {
    try {
      final scheme = await _readScheme();
      if (scheme == null) return null;
      final surface = scheme.colours['surface'];
      if (surface is! String) return null;
      return (hex: surface, mode: scheme.mode);
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace, 'CaelestiaThemeSource.getSurface');
      return null;
    }
  }

  Future<ThemeDefinition?> getTheme() async {
    try {
      final scheme = await _readScheme();
      if (scheme == null) return null;

      final mode = scheme.mode;
      final colours = scheme.colours;

      String role(String name) {
        final value = colours[name];
        if (value is! String || !_hexPattern.hasMatch(value)) {
          throw FormatException('missing or invalid role: $name');
        }
        return '#$value';
      }

      final active = ThemeColors(
        background: role('background'),
        foreground: role('onBackground'),
        card: role('surface'),
        cardForeground: role('onSurface'),
        primary: role('primary'),
        primaryForeground: role('onPrimary'),
        secondary: role('secondary'),
        secondaryForeground: role('onSecondary'),
        muted: role('surfaceContainer'),
        mutedForeground: role('onSurfaceVariant'),
        accent: role('tertiary'),
        accentForeground: role('onTertiary'),
        destructive: role('error'),
        destructiveForeground: role('onError'),
        border: role('outline'),
        input: role('outlineVariant'),
        ring: role('primary'),
      );

      return ThemeDefinition(
        light: mode == 'light' ? active : builtInLightThemeColors(),
        dark: mode == 'dark' ? active : builtInDarkThemeColors(),
        // Palette only. Glass is never read off this object: the host asks
        // [ThemeShellSource.getGlass] and merges that over the plugin's, so
        // these stay defaults rather than authoring a look that gets discarded.
        surfaces: const ThemeSurfaces(),
        background: const ThemeBackground(),
        radius: const ThemeRadius(),
        density: 1.0,
        dynamicTheme: const DynamicTheme(
          source: DynamicThemeSource.shell,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace, 'CaelestiaThemeSource.getTheme');
      return null;
    }
  }
}
