import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';

/// Hyprland's `decoration.blur` (`size 8, passes 2`) expressed as a Flutter sigma.
///
/// Calibrated against a live screenshot of the user's foot window: fitting
/// `observed = α·surface + (1−α)·blur(wallpaper)` over 1435 background-only
/// patches gave α = 0.80 (foot.ini declares 0.78) at σ ≈ 16px, RMSE 1.11/255.
/// A constant rather than a formula read off `variables.lua`, because the fit
/// is a one-point calibration of Hyprland's multi-pass box approximation, which
/// has no invertible sigma.
const double kShellBlurSigma = 16.0;

/// Foot's own default: no `[colors-*] alpha` key means an opaque background.
const double _opaqueAlpha = 1.0;

final _surfaceHex = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// `$XDG_CONFIG_HOME` (falling back to `$HOME/.config`), overrideable for tests.
///
/// Mirrors `caelestiaStateDir`: null means "no usable base" and callers treat
/// that as "no shell config to read" rather than building a relative path.
String? xdgConfigDir([String? override]) {
  if (override != null) return override;
  final env = Platform.environment;
  final configHome = env['XDG_CONFIG_HOME'] ??
      (env['HOME'] == null ? null : p.join(env['HOME']!, '.config'));
  if (configHome == null) return null;
  return configHome;
}

/// Foot's background treatment, as configured for [mode] (`dark` or `light`).
typedef FootTreatment = ({double alpha, bool blur});

/// Caelestia shell transparency, as configured in `shell.json`.
typedef ShellTransparency = ({bool enabled, double base});

/// Parse `foot.ini` for the translucency the terminal actually draws with.
///
/// Section resolution walks `[colors-<mode>]` → `[colors-dark]` → `[colors]` →
/// the prelude, which is foot's own precedence for a key it never saw set:
/// caelestia-dots declares `alpha` only under `[colors-dark]`, so a light-mode
/// scheme keeps the dark alpha instead of silently going solid. `[colors]` is
/// the pre-1.28 section name and stays in the chain for older configs.
FootTreatment parseFootIniTreatment(String contents, {String mode = 'dark'}) {
  final sections = <String, Map<String, String>>{
    'main': <String, String>{},
  };
  var current = 'main';

  for (final rawLine in const LineSplitter().convert(contents)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;

    if (line.startsWith('[') && line.endsWith(']')) {
      current = line.substring(1, line.length - 1).trim();
      sections.putIfAbsent(current, () => <String, String>{});
      continue;
    }

    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    sections[current]?[line.substring(0, separator).trim()] =
        line.substring(separator + 1).trim();
  }

  String? lookup(String key) {
    final chain = mode == 'light'
        ? const ['colors-light', 'colors-dark', 'colors', 'main']
        : const ['colors-dark', 'colors', 'main'];
    for (final section in chain) {
      final value = sections[section]?[key];
      if (value != null) return value;
    }
    return null;
  }

  return (
    alpha: _parseAlpha(lookup('alpha')),
    blur: _parseBool(lookup('blur')),
  );
}

double _parseAlpha(String? value) {
  final parsed = value == null ? null : double.tryParse(value);
  if (parsed == null) return _opaqueAlpha;
  return parsed.clamp(0.0, 1.0);
}

bool _parseBool(String? value) {
  if (value == null) return false;
  final normalized = value.toLowerCase();
  return normalized == 'yes' || normalized == 'true' || normalized == '1';
}

/// Parse `~/.config/caelestia/shell.json`.
///
/// Missing or malformed input yields the shell's compiled-in defaults
/// (`appearanceconfig.hpp`: `enabled=false`, `base=0.85`), i.e. solid panels.
ShellTransparency parseShellTransparency(String? contents) {
  const fallback = (enabled: false, base: 0.85);
  if (contents == null) return fallback;

  try {
    final json = jsonDecode(contents);
    if (json is! Map) return fallback;
    final appearance = json['appearance'];
    if (appearance is! Map) return fallback;
    final transparency = appearance['transparency'];
    if (transparency is! Map) return fallback;

    final base = transparency['base'];
    return (
      enabled: transparency['enabled'] == true,
      base: base is num ? base.toDouble().clamp(0.0, 1.0) : fallback.base,
    );
  } catch (_) {
    return fallback;
  }
}

/// Derive the app's glass from the same config the desktop reads.
///
/// Returns null when there is nothing to match (no foot config), so the
/// caller keeps the plugin's authored numbers instead of a half-informed guess.
ThemeGlass? deriveGlass({
  required String? footIni,
  required String? shellJson,
  required String surfaceHex,
  String mode = 'dark',
}) {
  if (footIni == null) return null;

  final foot = parseFootIniTreatment(footIni, mode: mode);
  final overlay = veilOverlay(surfaceHex: surfaceHex, alpha: foot.alpha);
  if (overlay == null) return null;

  final transparency = parseShellTransparency(shellJson);

  return (
    // Cards track the desktop panels, not the terminal: the shell paints every
    // panel at `base`, and foot's alpha describes a window over a wallpaper.
    surfacesOpacity: transparency.enabled ? transparency.base : 1.0,
    // The group draws the wallpaper at full strength and the veil carries the
    // alpha, which is exactly foot's composite and independent of whatever is
    // painted underneath. Scaling the whole group (the old `opacity: 0.55`)
    // blended it against the palette background a second time.
    background: ThemeBackground(
      source: ThemeBackgroundSource.shell,
      opacity: 1.0,
      blur: foot.blur ? kShellBlurSigma : 0.0,
      overlay: overlay,
    ),
  );
}

/// The terminal's veil: scheme `surface` at the terminal's own alpha.
///
/// Emitted as `#AARRGGBB`, which is what `ThemeConverter.parseColor` reads an
/// 8-digit string as. Appending the alpha byte (CSS order) would swap alpha for
/// the red channel and shift the hue.
String? veilOverlay({required String surfaceHex, required double alpha}) {
  if (!_surfaceHex.hasMatch(surfaceHex)) return null;
  final rgb = surfaceHex.replaceFirst('#', '').toLowerCase();
  final byte =
      (alpha.clamp(0.0, 1.0) * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$byte$rgb';
}

/// Read the terminal + shell config and derive the glass. Null on any gap.
Future<ThemeGlass?> readDerivedGlass({
  required String surfaceHex,
  required String mode,
  String? configDir,
}) async {
  final root = xdgConfigDir(configDir);
  if (root == null) return null;

  return deriveGlass(
    footIni: await _readOrNull(File(p.join(root, 'foot', 'foot.ini'))),
    shellJson: await _readOrNull(File(p.join(root, 'caelestia', 'shell.json'))),
    surfaceHex: surfaceHex,
    mode: mode,
  );
}

Future<String?> _readOrNull(File file) async {
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}
