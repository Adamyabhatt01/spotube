part of 'metadata_plugin_provider.dart';

bool pluginShouldUpdate({
  required String oldVersion,
  required String oldPluginApiVersion,
  required String newVersion,
  required String newPluginApiVersion,
}) {
  final oldParsed = tryParsePluginVersion(oldVersion);
  final newParsed = tryParsePluginVersion(newVersion);
  if (oldParsed != null && newParsed != null) {
    if (newParsed > oldParsed) return true;
    if (newParsed < oldParsed) return false;
    // Same precedence but a different string (e.g. build metadata
    // `1.0.0+1`): the archive is still a distinct release to install.
    if (oldVersion != newVersion) return true;
  } else if (oldVersion != newVersion) {
    // Non-semver versions cannot be ordered; any change is an update.
    return true;
  }

  final oldApi = tryParsePluginVersion(oldPluginApiVersion);
  final newApi = tryParsePluginVersion(newPluginApiVersion);
  if (oldApi == null || newApi == null) return false;
  return newApi > oldApi;
}

Version? tryParsePluginVersion(String value) {
  try {
    return Version.parse(value);
  } catch (_) {
    return null;
  }
}

extension MetadataPluginUpdateChecks on MetadataPluginNotifier {
  Future<bool> isPluginUpdate(PluginConfiguration newPlugin) async {
    final pluginRes = await (database.pluginsTable.select()
          ..where(
            (tbl) =>
                tbl.name.equals(newPlugin.name) &
                tbl.author.equals(newPlugin.author),
          )
          ..limit(1))
        .get();

    if (pluginRes.isEmpty) {
      return false;
    }

    final oldPlugin = pluginRes.first;
    return pluginShouldUpdate(
      oldVersion: oldPlugin.version,
      oldPluginApiVersion: oldPlugin.pluginApiVersion,
      newVersion: newPlugin.version,
      newPluginApiVersion: newPlugin.pluginApiVersion,
    );
  }
}

@visibleForTesting
Future<PluginsTableData?> replacePluginRowInDatabase({
  required AppDatabase database,
  required PluginConfiguration plugin,
}) {
  return database.transaction(() async {
    final rows = await (database.pluginsTable.select()
          ..where(
            (tbl) =>
                tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author),
          )
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;

    await (database.pluginsTable.update()
          ..where(
            (tbl) =>
                tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author),
          ))
        .write(
      PluginsTableCompanion(
        description: Value(plugin.description),
        version: Value(plugin.version),
        entryPoint: Value(plugin.entryPoint),
        apis: Value(plugin.apis.map((e) => e.name).toList()),
        abilities: Value(plugin.abilities.map((e) => e.name).toList()),
        repository: Value(plugin.repository),
        pluginApiVersion: Value(plugin.pluginApiVersion),
      ),
    );

    return rows.first;
  });
}
