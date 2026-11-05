import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/shared/jsonify.dart';
import 'package:hetu_script/values.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_vm_metrics.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

class MetadataPluginThemeEndpoint {
  final Hetu hetu;

  MetadataPluginThemeEndpoint(this.hetu);

  /// Capabilities declared by the last `getTheme()` call.
  ///
  /// A UI document can also come from `getUi()`/`getSettings()`/`onUiAction()`
  /// with no payload around it. Remembering the grant lets those documents
  /// keep the same host-widget/account permissions instead of silently
  /// losing them at the second call.
  List<String> _payloadCapabilities = const <String>[];

  HTInstance? get _theme {
    try {
      final plugin = hetu.fetch("metadataPlugin") as HTInstance;
      return plugin.memberGet("theme") as HTInstance;
    } catch (_) {
      return null;
    }
  }

  Future<ThemeDefinition?> getTheme() async {
    // Grants belong to the latest payload: a null return or a plugin switch
    // must not let a later getUi()/showSettings() document inherit them.
    _payloadCapabilities = const <String>[];
    final theme = _theme;
    if (theme == null) {
      return null;
    }

    final result = await theme.invoke("getTheme");
    final json = _jsonMap(result);
    if (json == null) {
      return null;
    }

    final declared = json['capabilities'];
    _payloadCapabilities = declared is List
        ? declared.whereType<String>().toList(growable: false)
        : const <String>[];

    return withUiCapabilities(
      sanitizeThemeDefinition(ThemeDefinition.fromJson(json)),
      _payloadCapabilities,
    );
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
      ThemeUiVmMetrics.recordGetUi();
      final result = await theme.invoke("getUi");
      final json = _jsonMap(result);
      if (json == null) return null;
      return _withPayloadCapabilities(parseThemeUiDocument(json));
    } catch (_) {
      return null;
    }
  }

  /// The theme's optional settings UI, or null when it carries no
  /// `showSettings()` method.
  ///
  /// The document has the same shape as `getUi()`; the host renders its
  /// `settings.content` slot in a standard dialog. A missing method is a
  /// normal "no settings", never a plugin failure.
  Future<ThemeUiDocument?> getSettings() async {
    final theme = _theme;
    if (theme == null) return null;

    try {
      final result = await theme.invoke("showSettings");
      final json = _jsonMap(result);
      if (json == null) return null;
      return _withPayloadCapabilities(parseThemeUiDocument(json));
    } catch (_) {
      return null;
    }
  }

  /// The theme's optional answer to a UI action.
  ///
  /// A `plugin` action hands an id and a payload to the theme; the theme may
  /// answer with a replacement UI document. A missing method or a throw is
  /// an ordinary "nothing to change" and never takes the current UI down.
  Future<ThemeUiDocument?> onUiAction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final theme = _theme;
    if (theme == null) return null;

    try {
      ThemeUiVmMetrics.recordOnUiAction();
      final result = await theme.invoke(
        "onUiAction",
        positionalArgs: [id, payload],
      );
      final json = _jsonMap(result);
      if (json == null) return null;
      return _withPayloadCapabilities(parseThemeUiDocument(json));
    } catch (_) {
      return null;
    }
  }

  /// Gives a standalone UI document the payload's capability grant.
  ThemeUiDocument? _withPayloadCapabilities(ThemeUiDocument? ui) {
    if (ui == null || _payloadCapabilities.isEmpty) return ui;

    final merged = <String>{
      ...ui.capabilities,
      ..._payloadCapabilities,
    }.toList(growable: false);
    if (merged.length == ui.capabilities.length) return ui;

    return ui.copyWith(capabilities: merged);
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
