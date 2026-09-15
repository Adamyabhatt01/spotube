import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_state.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

/// Host-side adapter: Caelestia `scheme.json` → [ThemeDefinition].
///
/// Caelestia only exposes the currently active scheme, so the adapter is
/// mode-aware: the active side gets Caelestia colors, the opposite side
/// gets Spotube's built-in palette. Missing or malformed state yields
/// null rather than a partially valid theme.
class CaelestiaThemeSource {
  /// Override for tests. Defaults to [caelestiaStateDir].
  final String? stateDir;

  const CaelestiaThemeSource({this.stateDir});

  static final _hexPattern = RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$');

  ThemeDefinition? getTheme() {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return null;
      final raw = File(
        p.join(stateDir, 'scheme.json'),
      ).readAsStringSync();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      final mode = json['mode'];
      if (mode != 'dark' && mode != 'light') return null;

      final colours = json['colours'];
      if (colours is! Map) return null;

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
        // Fixed shell rendering contract (not protocol fields): the
        // shell owns the palette; these backdrop defaults stay constant
        // so glass behavior doesn't shift with every scheme change.
        // The veil relies on host brightness adaptation (white in light
        // mode) rather than a per-mode overlay value.
        surfaces: const ThemeSurfaces(),
        background: const ThemeBackground(
          source: ThemeBackgroundSource.shell,
          opacity: 0.35,
          blur: 30.0,
          overlay: '#000000',
        ),
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
