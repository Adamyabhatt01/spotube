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
    final json = _jsonMap(result);
    if (json == null) {
      return null;
    }

    return sanitizeThemeDefinition(ThemeDefinition.fromJson(json));
  }

  /// The theme's optional declarative UI, or null when it carries no
  /// `getUi()` method.
  ///
  /// The method is optional by contract, so a missing or throwing method is
  /// an ordinary "no UI here", not a theme failure: the palette still loads.
  Future<ThemeUiDocument?> getUi() async {
    final theme = _theme;
    if (theme == null) return null;

    try {
      final result = await theme.invoke("getUi");
      final json = _jsonMap(result);
      if (json == null) return null;
      return parseThemeUiDocument(json);
    } catch (_) {
      return null;
    }
  }

  /// Hetu struct literals cross the boundary as HTStruct, while values
  /// produced by bindings arrive as plain Dart maps. Accept both so
  /// hand-written static themes work the same as computed ones.
  Map<String, dynamic>? _jsonMap(dynamic result) {
    if (result is HTStruct) {
      return jsonifyStruct(result);
    } else if (result is Map<String, dynamic>) {
      return result;
    } else if (result is Map) {
      return result.cast<String, dynamic>();
    }
    return null;
  }
}
