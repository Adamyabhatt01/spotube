import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/shared/jsonify.dart';
import 'package:hetu_script/values.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

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
