import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';

/// Stale-while-revalidate cache for the resolved theme.
///
/// Written only after a successful live resolution — never for
/// null/failure outcomes. Read on startup for an instant themed first
/// paint; the live provider stays authoritative and overwrites silently.
/// Every layer treats cached data as untrusted: any structural problem
/// falls back to null (built-in/live path).
const _cacheKey = 'spotube.theme_definition_cache.v1';
const _pluginKeyKey = 'spotube.theme_default_plugin_key.v1';

/// Identity of the selected theme plugin. Written at selection time so
/// cache validation never waits on the database.
String themePluginKey(PluginConfiguration plugin) =>
    '${plugin.author}::${plugin.name}::${plugin.version}';

/// Records which plugin is the theme default. Called from
/// `setDefaultThemePlugin` (covers promotion paths that route through
/// it). Removal of the default clears it (see `removePlugin`).
Future<void> writeThemePluginKey(String? pluginKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (pluginKey == null) {
      await prefs.remove(_pluginKeyKey);
    } else {
      await prefs.setString(_pluginKeyKey, pluginKey);
    }
  } catch (_) {}
}

/// Persists a successfully resolved theme. Fire-and-forget from the
/// live provider; failures are swallowed — caching is best-effort.
///
/// Also records the plugin identity: selections made before this
/// cache existed (persisted default in the database, setter never
/// re-run) backfill on first successful resolution.
Future<void> writeThemeCache({
  required String pluginKey,
  required String? shellKey,
  required ThemeDefinition definition,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pluginKeyKey, pluginKey);
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'v': 1,
        'pluginKey': pluginKey,
        'shellKey': shellKey,
        'definition': definition.toJson(),
      }),
    );
  } catch (_) {}
}

/// Last-good theme, or null on any mismatch or malformed data.
///
/// Depends only on SharedPreferences plus the (sync, cheap) shell
/// source — never on the database, Hetu, or plugin bytecode.
///
/// Validation is deliberately plugin-identity only: the shell mtime
/// changes on every Caelestia rewrite (often racing our own read by
/// milliseconds), so gating on it turned every warm start into a
/// cache miss. A stale palette self-heals within seconds — the live
/// provider always re-resolves at startup and overwrites — while a
/// miss costs seconds of splash. The shell key is still stored for
/// diagnostics.
final cachedThemeDefinitionProvider =
    FutureProvider<ThemeDefinition?>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final pluginKey = prefs.getString(_pluginKeyKey);
    final raw = prefs.getString(_cacheKey);
    if (pluginKey == null || raw == null) return null;

    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    if (json['v'] != 1) return null;
    if (json['pluginKey'] != pluginKey) return null;

    final definition = json['definition'];
    if (definition is! Map) return null;
    return ThemeDefinition.fromJson(definition.cast<String, dynamic>());
  } catch (e, stack) {
    // Corrupt cache is a warm-start optimization loss, not fatal: fall
    // back to live resolution, but leave a trace instead of silence.
    AppLogger.reportError(e, stack, 'cachedThemeDefinitionProvider');
    return null;
  }
});
