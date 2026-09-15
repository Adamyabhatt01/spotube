import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/shared/jsonify.dart';
import 'package:hetu_script/values.dart';
import 'package:spotube/models/metadata/metadata.dart';

class MetadataPluginThemeEndpoint {
  final Hetu hetu;

  MetadataPluginThemeEndpoint(this.hetu);

  HTInstance? get _theme {
    try {
      final plugin = hetu.fetch("metadataPlugin") as HTInstance;
      return plugin.memberGet("theme") as HTInstance;
    } catch (_) {
      return null;
    }
  }

  Future<ThemeDefinition?> getTheme() async {
    final theme = _theme;
    if (theme == null) {
      return null;
    }

    final result = await theme.invoke("getTheme");

    if (result == null) {
      return null;
    }

    // Hetu struct literals cross the boundary as HTStruct, while values
    // produced by bindings arrive as plain Dart maps. Accept both so
    // hand-written static themes work the same as computed ones.
    final Map<String, dynamic> json;
    if (result is HTStruct) {
      json = jsonifyStruct(result);
    } else if (result is Map<String, dynamic>) {
      json = result;
    } else if (result is Map) {
      json = result.cast<String, dynamic>();
    } else {
      return null;
    }

    return sanitizeThemeDefinition(ThemeDefinition.fromJson(json));
  }
}

/// Clamps untrusted plugin numerics to render-safe ranges.
///
/// Only clamps: out-of-range numbers keep their intent (0.85 stays
/// 0.85). Structurally invalid data (missing keys, wrong types) still
/// throws from `fromJson` and falls back to null upstream.
ThemeDefinition sanitizeThemeDefinition(ThemeDefinition definition) {
  double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
  double nonNegative(double value) => value < 0 ? 0.0 : value;

  return definition.copyWith(
    surfaces: definition.surfaces.copyWith(
      opacity: clamp01(definition.surfaces.opacity),
      blur: nonNegative(definition.surfaces.blur),
    ),
    background: definition.background.copyWith(
      opacity: clamp01(definition.background.opacity),
      blur: nonNegative(definition.background.blur),
    ),
    radius: definition.radius.copyWith(
      small: nonNegative(definition.radius.small),
      medium: nonNegative(definition.radius.medium),
      large: nonNegative(definition.radius.large),
      pill: nonNegative(definition.radius.pill),
    ),
    density: definition.density < 0 ? 1.0 : definition.density,
  );
}
