import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// Stale-while-revalidate cache for the resolved theme.
///
/// Written only after a successful live resolution — never for
/// null/failure outcomes. Read on startup for an instant themed first
/// paint; the live provider stays authoritative and overwrites silently.
/// Every layer treats cached data as untrusted: any structural problem
/// falls back to null (built-in/live path).
const _cacheKey = 'spotube.theme_definition_cache.v3';
const _pluginKeyKey = 'spotube.theme_default_plugin_key.v1';

/// Identity of the selected theme plugin. Written at selection time so
/// cache validation never waits on the database.
String themePluginKey(PluginConfiguration plugin) =>
    '${plugin.author}::${plugin.name}::${plugin.version}';

/// The recorded default theme plugin identity, or null when no theme was
/// ever selected (or the store is unreachable).
///
/// DB-free by design: it is what lets a later lookup resolve a static
/// `theme.json` payload without pulling the metadata provider (and the
/// database behind it) into the theme-ui path.
final storedThemePluginKeyProvider =
    FutureProvider<String?>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pluginKeyKey);
  } catch (_) {
    // A missing store is a fallback, not a failure: the live plugin path
    // still resolves the theme.
    return null;
  }
});

/// Records which plugin is the theme default. Called from
/// `setDefaultThemePlugin` (covers promotion paths that route through
/// it). Removal of the default clears it (see `removePlugin`).
Future<void> writeThemePluginKey(String? pluginKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (pluginKey == null) {
      await prefs.remove(_pluginKeyKey);
      // No active theme means nothing can legitimately warm-start from the
      // cached definition. Leaving it behind would keep a payload naming a
      // plugin that is no longer selected, and an uninstall would leave files
      // that no longer exist as its only owner.
      await prefs.remove(_cacheKey);
    } else {
      await prefs.setString(_pluginKeyKey, pluginKey);
    }
  } catch (e, stack) {
    // Best-effort by design, but a persistently failing write is otherwise
    // undiscoverable — record it like the read path does.
    AppLogger.reportError(e, stack, 'writeThemePluginKey');
  }
}

/// Drops the warm-start definition when the plugin behind [pluginKey]
/// changed bytes without changing its identity (a same-version reinstall or
/// update). Cache validation checks the plugin key alone, so it cannot tell
/// the previous build's payload from the new one — the next start would
/// warm-start from the old theme until live resolution re-writes the cache.
/// No-op for any other plugin. The live provider re-resolves from the new
/// files and re-writes the cache, so the only cost is one cold start.
Future<void> clearThemeCacheForPlugin(Ref ref, String pluginKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_pluginKeyKey) != pluginKey) return;
    await prefs.remove(_cacheKey);
    ref.invalidate(cachedThemeDefinitionProvider);
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'clearThemeCacheForPlugin');
  }
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
        // v3: the inline UI tree is part of the definition, so a warm start
        // keeps the theme's layout as well as its palette. A v2 entry has no
        // `ui` key and would flash the stock shell until live resolution.
        'v': 3,
        'pluginKey': pluginKey,
        'shellKey': shellKey,
        'definition': definition.toJson(),
      }),
    );
  } catch (e, stack) {
    // Best-effort by design, but a persistently failing write is otherwise
    // undiscoverable — record it like the read path does.
    AppLogger.reportError(e, stack, 'writeThemeCache');
  }
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
    if (json['v'] != 3) return null;
    if (json['pluginKey'] != pluginKey) return null;

    final definition = json['definition'];
    if (definition is! Map) return null;
    // Written after sanitizing, but a cache outlives the ranges the host
    // was built with, so treat the numbers as untrusted again on read.
    return sanitizeThemeDefinition(
      ThemeDefinition.fromJson(definition.cast<String, dynamic>()),
    );
  } catch (e, stack) {
    // Corrupt cache is a warm-start optimization loss, not fatal: fall
    // back to live resolution, but leave a trace instead of silence.
    AppLogger.reportError(e, stack, 'cachedThemeDefinitionProvider');
    return null;
  }
});
