import 'dart:async';
import 'dart:typed_data';

import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/shared/jsonify.dart';
import 'package:hetu_script/values.dart';

/// The bytecode of a compiled theme, plus the payload it produces.
///
/// Both halves matter at build time: the bytecode is what ships, and the
/// payload is what the host will parse. A theme that compiles but produces no
/// payload is broken, and today that only shows up after the user installs it.
class CompiledTheme {
  CompiledTheme({
    required this.byteCode,
    required this.payload,
    required this.warning,
    this.uiSpec,
    this.optionalMethods = const [],
  });

  final Uint8List byteCode;

  /// The map `getTheme()` returned, already converted to plain JSON.
  final Map<String, dynamic> payload;

  /// A non-fatal problem found while evaluating (missing optional methods,
  /// a `getUi()` that threw, …).
  final String? warning;

  /// The UI specification, if the theme answers `getUi()`.
  ///
  /// A theme may put its UI in the payload instead; both are the same
  /// document, and the host accepts either.
  final Map<String, dynamic>? uiSpec;

  /// The optional methods this theme implements.
  final List<String> optionalMethods;
}

/// Compiles theme source to Hetu bytecode.
Uint8List compileThemeSource(String source, {required String sourceName}) {
  // The VM prints per-phase timings by default; a build tool wants the
  // build's own output, not the compiler's.
  final hetu = Hetu(config: HetuConfig(printPerformanceStatistics: false));
  hetu.init();
  final bytes = hetu.compile(source, sourceName: sourceName);
  if (bytes.isEmpty) {
    throw StateError('Hetu produced no bytecode for $sourceName');
  }
  return Uint8List.fromList(bytes);
}

/// Boots the bytecode the way the app does and calls `getTheme()`.
///
/// The three `eval` lines are the app's own (`MetadataPlugin.create`), so a
/// theme that works here works there: same module name, same entry point, same
/// `metadataPlugin` binding.
Future<CompiledTheme> evaluateTheme(
  Uint8List byteCode, {
  required String entryPoint,
}) async {
  final hetu = Hetu(config: HetuConfig(printPerformanceStatistics: false));
  hetu.init();
  hetu.loadBytecode(bytes: byteCode, moduleName: 'plugin');
  hetu.eval('''
import "module:plugin" as plugin

var Plugin = plugin.$entryPoint

var metadataPlugin = Plugin()
''');

  final plugin = hetu.fetch('metadataPlugin') as HTInstance;
  final theme = plugin.memberGet('theme') as HTInstance;
  final result = await theme.invoke('getTheme');

  final payload = _asJsonMap(result);
  if (payload == null) {
    throw StateError('getTheme() did not return a map');
  }

  // The optional methods. A theme that implements them gets more; a theme
  // that does not is not broken, so their absence is not an error.
  final optional = <String>[];
  for (final method in const ['getUi', 'onUiAction', 'showSettings']) {
    if (theme.memberGet(method, throws: false) != null) {
      optional.add(method);
    }
  }

  Map<String, dynamic>? uiSpec;
  String? warning;
  if (optional.contains('getUi')) {
    try {
      uiSpec = await callThemeUi(hetu);
      if (uiSpec == null) {
        warning = 'getUi() returned nothing';
      }
    } catch (error) {
      warning = 'getUi() failed: $error';
    }
  }

  return CompiledTheme(
    byteCode: byteCode,
    payload: payload,
    warning: warning,
    uiSpec: uiSpec,
    optionalMethods: optional,
  );
}

/// The UI specification a theme answers with, or null when it has none.
Future<Map<String, dynamic>?> callThemeUi(Hetu hetu) async {
  final plugin = hetu.fetch('metadataPlugin') as HTInstance;
  final theme = plugin.memberGet('theme') as HTInstance;
  final result = await theme.invoke('getUi');
  return _asJsonMap(result);
}

/// Calls a theme's own action handler.
///
/// The host dispatches a `plugin` action here; a theme may answer with a new
/// UI specification or with nothing.
Future<Map<String, dynamic>?> callThemeAction(
  Hetu hetu, {
  required String id,
  Map<String, dynamic> payload = const {},
}) async {
  final plugin = hetu.fetch('metadataPlugin') as HTInstance;
  final theme = plugin.memberGet('theme') as HTInstance;
  final result = await theme.invoke(
    'onUiAction',
    positionalArgs: [id, payload],
  );
  return _asJsonMap(result);
}

/// Converts whatever the plugin returned into a plain JSON map.
///
/// Hetu struct literals cross the boundary as `HTStruct` while values produced
/// by bindings arrive as plain Dart maps; the host accepts both, so the build
/// accepts both too.
Map<String, dynamic>? _asJsonMap(Object? result) {
  if (result is HTStruct) {
    return jsonifyStruct(result);
  }
  if (result is Map<String, dynamic>) return result;
  if (result is Map) return result.cast<String, dynamic>();
  return null;
}

/// The payload of an optional method, or null when it is missing or failed.
///
/// Optional plugin methods (`getUi`, `onUiAction`) are allowed to be absent:
/// most themes will not implement them, and a missing method is not an error.
Future<Map<String, dynamic>?> callOptional(
  Hetu hetu, {
  required String method,
}) async {
  try {
    final plugin = hetu.fetch('metadataPlugin') as HTInstance;
    final theme = plugin.memberGet('theme') as HTInstance;
    final result = await theme.invoke(method);
    return _asJsonMap(result);
  } catch (_) {
    return null;
  }
}
