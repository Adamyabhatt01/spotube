import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// The format version of the `theme.json` entry written by the theme
/// toolchain. Must match `staticThemeFormatVersion` in `themes/lib/compile.dart`.
///
/// Anything else is refused and the caller falls back to booting the VM:
/// a static file is an optimization, never a contract the live path cannot
/// outrank.
const staticThemeFormatVersion = 1;

/// A build-time theme payload the host can use without booting Hetu.
///
/// Written into the `.smplug` archive as `theme.json` by `themes/tools/build.dart`
/// after evaluating `getTheme()`/`getUi()` once at build time. The host reads
/// it off the extraction directory and only boots the VM for the optional
/// methods the payload says exist (`showSettings()`/`onUiAction()`, or a
/// `getUi()` that returned nothing at build time).
class StaticThemePayload {
  const StaticThemePayload({
    required this.definition,
    required this.optionalMethods,
  });

  /// The `getTheme()` payload, sanitized the same way the live endpoint
  /// sanitizes it and with its capabilities merged onto the UI document.
  final ThemeDefinition definition;

  /// The optional methods the theme implements (`getUi`, `showSettings`,
  /// `onUiAction`). Known at build time, so the host never has to boot the
  /// VM to discover that a method does not exist.
  final Set<String> optionalMethods;

  /// Whether the VM must still boot to answer `getUi()`.
  ///
  /// A payload that already carries a `ui` tree never needs it; a palette-only
  /// payload that declares `getUi()` but answered nothing at build time still
  /// gets its chance (the build result may have been a transient zero).
  bool get needsVmForUi =>
      optionalMethods.contains('getUi') && definition.ui == null;

  /// Whether the VM must boot to open the theme's settings dialog.
  bool get needsVmForSettings => optionalMethods.contains('showSettings');

  /// Whether the VM must boot to answer a `plugin` UI action.
  bool get needsVmForActions => optionalMethods.contains('onUiAction');
}

/// Parses a decoded `theme.json` envelope.
///
/// Returns null for anything unusable (wrong version, missing theme map, a
/// theme that does not decode). The caller falls back to the live
/// `getTheme()` path, so a broken or future static file costs nothing but
/// the boot it was trying to avoid.
StaticThemePayload? parseStaticThemeJson(Object? decoded) {
  if (decoded is! Map) return null;
  final envelope = decoded.cast<String, dynamic>();
  if (envelope['formatVersion'] != staticThemeFormatVersion) return null;

  final themeRaw = envelope['theme'];
  if (themeRaw is! Map) return null;

  final optionalRaw = envelope['optionalMethods'];
  if (optionalRaw is! List) return null;
  final optionalMethods = <String>{
    for (final method in optionalRaw)
      if (method is String) method,
  };

  try {
    final definition = sanitizeThemeDefinition(
      ThemeDefinition.fromJson(themeRaw.cast<String, dynamic>()),
    );
    return StaticThemePayload(
      definition: withUiCapabilities(definition, definition.capabilities),
      optionalMethods: optionalMethods,
    );
  } catch (_) {
    return null;
  }
}
