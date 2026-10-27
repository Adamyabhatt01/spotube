import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/plugin_storage.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/provider/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:archive/archive.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

part 'plugin_providers.dart';
part 'plugin_cache.dart';
part 'plugin_seeding.dart';
part 'plugin_releases.dart';
part 'plugin_assets.dart';
part 'plugin_updates.dart';

final allowedDomainsRegex = RegExp(
  r"^(https?:\/\/)?(www\.)?(github\.com|codeberg\.org)\/.+",
);

/// Plugins shipped inside the APK, in install order.
///
/// Order is the seed policy: [MetadataPluginNotifier.addPlugin] hands the
/// default metadata slot to the first installed plugin carrying `metadata`,
/// the audio slot to the first carrying `audio-source`, and the radio slot to
/// the first carrying `radio`. So the Spotify plugin is listed ahead of
/// Musicbrainz/Listenbrainz to be the recommended default, while it cannot
/// disturb the audio default (it has no `audio-source` ability). Radio Browser
/// precedes SomaFM for the radio slot.
///
/// Each entry must exist at `assets/plugins/<slug>/plugin.smplug` and be
/// declared in `pubspec.yaml` — `test/bundled_plugins_seed_test.dart` holds
/// all three to the same list.
const bundledPlugins = [
  "spotube-plugin-spotify",
  "spotube-plugin-musicbrainz-listenbrainz",
  "spotube-plugin-youtube-audio",
  "spotube-plugin-internet-radio-browser",
  "spotube-plugin-internet-radio-somafm",
];

class MetadataPluginState {
  final List<PluginConfiguration> plugins;
  final int defaultMetadataPlugin;
  final int defaultAudioSourcePlugin;
  final int defaultThemePlugin;
  final int defaultRadioPlugin;

  const MetadataPluginState({
    this.plugins = const [],
    this.defaultMetadataPlugin = -1,
    this.defaultAudioSourcePlugin = -1,
    this.defaultThemePlugin = -1,
    this.defaultRadioPlugin = -1,
  });

  PluginConfiguration? get defaultMetadataPluginConfig {
    if (defaultMetadataPlugin < 0 || defaultMetadataPlugin >= plugins.length) {
      return null;
    }
    return plugins[defaultMetadataPlugin];
  }

  PluginConfiguration? get defaultAudioSourcePluginConfig {
    if (defaultAudioSourcePlugin < 0 ||
        defaultAudioSourcePlugin >= plugins.length) {
      return null;
    }
    return plugins[defaultAudioSourcePlugin];
  }

  PluginConfiguration? get defaultThemePluginConfig {
    if (defaultThemePlugin < 0 || defaultThemePlugin >= plugins.length) {
      return null;
    }
    return plugins[defaultThemePlugin];
  }

  PluginConfiguration? get defaultRadioPluginConfig {
    if (defaultRadioPlugin < 0 || defaultRadioPlugin >= plugins.length) {
      return null;
    }
    return plugins[defaultRadioPlugin];
  }

  factory MetadataPluginState.fromJson(Map<String, dynamic> json) {
    return MetadataPluginState(
      plugins: (json["plugins"] as List<dynamic>)
          .map((e) => PluginConfiguration.fromJson(e))
          .toList(),
      defaultMetadataPlugin: json["default_metadata_plugin"] ?? -1,
      defaultAudioSourcePlugin: json['default_audio_source_plugin'],
      defaultThemePlugin: json["default_theme_plugin"] ?? -1,
      defaultRadioPlugin: json["default_radio_plugin"] ?? -1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "plugins": plugins.map((e) => e.toJson()).toList(),
      "default_metadata_plugin": defaultMetadataPlugin,
      "default_audio_source_plugin": defaultAudioSourcePlugin,
      "default_theme_plugin": defaultThemePlugin,
      "default_radio_plugin": defaultRadioPlugin,
    };
  }

  MetadataPluginState copyWith({
    List<PluginConfiguration>? plugins,
    int? defaultMetadataPlugin,
    int? defaultAudioSourcePlugin,
    int? defaultThemePlugin,
    int? defaultRadioPlugin,
  }) {
    return MetadataPluginState(
      plugins: plugins ?? this.plugins,
      defaultMetadataPlugin:
          defaultMetadataPlugin ?? this.defaultMetadataPlugin,
      defaultAudioSourcePlugin:
          defaultAudioSourcePlugin ?? this.defaultAudioSourcePlugin,
      defaultThemePlugin: defaultThemePlugin ?? this.defaultThemePlugin,
      defaultRadioPlugin: defaultRadioPlugin ?? this.defaultRadioPlugin,
    );
  }
}

class MetadataPluginNotifier extends AsyncNotifier<MetadataPluginState> {
  AppDatabase get database => ref.read(databaseProvider);
  final _storage = PluginStorage();

  @override
  build() async {
    final database = ref.watch(databaseProvider);

    final subscription = database.pluginsTable.select().watch().listen(
      (event) async {
        try {
          state = AsyncValue.data(await toStatePlugins(event));
        } catch (e, stack) {
          // Keep serving the last good state; the failure is reported,
          // never silent.
          AppLogger.reportError(e, stack);
        }
      },
    );

    ref.onDispose(() {
      subscription.cancel();
    });

    final plugins = await database.pluginsTable.select().get();

    final pluginState = await toStatePlugins(plugins);

    await _loadDefaultPlugins(pluginState);

    return pluginState;
  }

  Future<MetadataPluginState> toStatePlugins(
    List<PluginsTableData> plugins,
  ) async {
    int defaultMetadataPlugin = -1;
    int defaultAudioSourcePlugin = -1;
    int defaultThemePlugin = -1;
    int defaultRadioPlugin = -1;
    final pluginConfigs = <PluginConfiguration>[];

    for (int i = 0; i < plugins.length; i++) {
      final plugin = plugins[i];

      final pluginConfig = PluginConfiguration(
        name: plugin.name,
        author: plugin.author,
        description: plugin.description,
        version: plugin.version,
        entryPoint: plugin.entryPoint,
        pluginApiVersion: plugin.pluginApiVersion,
        repository: plugin.repository,
        apis: plugin.apis
            .map(
              (e) => PluginApis.values.firstWhereOrNull(
                (api) => api.name == e,
              ),
            )
            .nonNulls
            .toList(),
        abilities: plugin.abilities
            .map(
              (e) => PluginAbilities.values.firstWhereOrNull(
                (ability) => ability.name == e,
              ),
            )
            .nonNulls
            .toList(),
      );

      // A (re)install path evicts this key, so a hit means the files were
      // there the last time they could have changed.
      final validationKey = PluginStorage.validationKey(pluginConfig);
      if (!_storage.validatedPlugins.contains(validationKey)) {
        final pluginExtractionDir = await _storage.extractionDir(pluginConfig);
        await _storage.recoverInterruptedExtraction(pluginExtractionDir);
        final pluginJsonFile =
            File(join(pluginExtractionDir.path, "plugin.json"));
        final pluginBinaryFile =
            File(join(pluginExtractionDir.path, "plugin.out"));

        if (!await pluginExtractionDir.exists() ||
            !await pluginJsonFile.exists() ||
            !await pluginBinaryFile.exists()) {
          // Delete the plugin entry from DB if the plugin files are not there.
          await database.pluginsTable.deleteOne(plugin);
          continue;
        }
        _storage.validatedPlugins.add(validationKey);
      }

      pluginConfigs.add(pluginConfig);

      if (plugin.selectedForMetadata) {
        defaultMetadataPlugin = pluginConfigs.length - 1;
      }
      if (plugin.selectedForAudioSource) {
        defaultAudioSourcePlugin = pluginConfigs.length - 1;
      }
      if (plugin.selectedForTheme) {
        defaultThemePlugin = pluginConfigs.length - 1;
      }
      if (plugin.selectedForRadio) {
        defaultRadioPlugin = pluginConfigs.length - 1;
      }
    }

    return MetadataPluginState(
      plugins: pluginConfigs,
      defaultMetadataPlugin: defaultMetadataPlugin,
      defaultAudioSourcePlugin: defaultAudioSourcePlugin,
      defaultThemePlugin: defaultThemePlugin,
      defaultRadioPlugin: defaultRadioPlugin,
    );
  }

  /// Downloads, extracts & caches the plugin from the given URL and returns the plugin config.
  /// If only a text/html URL is provided, it will try to get the latest release from
  /// the URL for supported websites (github.com, codeberg.org).
  Future<PluginConfiguration> downloadAndCachePlugin(String url) async {
    final res = await ref.read(appDioProvider).head(url);
    final isSupportedWebsite =
        (res.headers["Content-Type"]?.first)?.startsWith("text/html") == true &&
            allowedDomainsRegex.hasMatch(url);
    String pluginDownloadUrl = url;
    if (isSupportedWebsite) {
      if (url.contains("github.com")) {
        final uri = _getGithubReleasesUrl(url);
        pluginDownloadUrl = await _getPluginDownloadUrl(uri);
      } else if (url.contains("codeberg.org")) {
        final uri = _getCodebergeReleasesUrl(url);
        pluginDownloadUrl = await _getPluginDownloadUrl(uri);
      } else {
        throw MetadataPluginException.unsupportedPluginDownloadWebsite();
      }
    }

    // Now let's download, extract and cache the plugin
    final pluginDir = await _storage.rootDir;
    await pluginDir.create(recursive: true);

    final pluginRes = await ref.read(appDioProvider).get(
          pluginDownloadUrl,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

    if ((pluginRes.statusCode ?? 500) > 299) {
      throw MetadataPluginException.pluginDownloadFailed();
    }

    return await _storage.extractArchive(pluginRes.data);
  }

  bool validatePluginApiCompatibility(PluginConfiguration plugin) {
    final configPluginApiVersion = Version.parse(plugin.pluginApiVersion);
    final appPluginApiVersion = MetadataPlugin.pluginApiVersion;

    // Plugin API's major version must match the app's major version
    if (configPluginApiVersion.major != appPluginApiVersion.major) {
      return false;
    }
    return configPluginApiVersion >= appPluginApiVersion;
  }

  void _assertPluginApiCompatibility(PluginConfiguration plugin) {
    if (!validatePluginApiCompatibility(plugin)) {
      throw MetadataPluginException.pluginApiVersionMismatch();
    }
  }

  /// Whether any plugin row is already the default radio directory.
  ///
  /// Read from the database rather than the in-memory state: on first launch
  /// `_loadDefaultPlugins` seeds the radio directories back-to-back, and the
  /// drift watcher has not necessarily emitted between the two inserts, so
  /// `state` can still look empty for the second one. Using `state` there would
  /// mark both default and `toStatePlugins` would keep the last.
  Future<bool> isAnyRadioPluginSelected() async {
    final rows = await (database.pluginsTable.select()
          ..where((tbl) => tbl.selectedForRadio.equals(true))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<void> addPlugin(PluginConfiguration plugin) async {
    _assertPluginApiCompatibility(plugin);

    final pluginRes = await (database.pluginsTable.select()
          ..where(
            (tbl) =>
                tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author),
          )
          ..limit(1))
        .get();

    if (pluginRes.isNotEmpty) {
      throw MetadataPluginException.duplicatePlugin();
    }

    final seedAsDefaultRadio =
        plugin.abilities.contains(PluginAbilities.radio) &&
            !await isAnyRadioPluginSelected();

    await database.pluginsTable.insertOne(
      PluginsTableCompanion.insert(
        name: plugin.name,
        author: plugin.author,
        description: plugin.description,
        version: plugin.version,
        entryPoint: plugin.entryPoint,
        apis: plugin.apis.map((e) => e.name).toList(),
        abilities: plugin.abilities.map((e) => e.name).toList(),
        pluginApiVersion: Value(plugin.pluginApiVersion),
        repository: Value(plugin.repository),
        // Setting the very first plugin as the default plugin
        selectedForMetadata: Value(
          (state.valueOrNull?.plugins
                      .where(
                          (d) => d.abilities.contains(PluginAbilities.metadata))
                      .isEmpty ??
                  true) &&
              plugin.abilities.contains(PluginAbilities.metadata),
        ),
        selectedForAudioSource: Value(
          (state.valueOrNull?.plugins
                      .where((d) =>
                          d.abilities.contains(PluginAbilities.audioSource))
                      .isEmpty ??
                  true) &&
              plugin.abilities.contains(PluginAbilities.audioSource),
        ),
        selectedForRadio: Value(seedAsDefaultRadio),
      ),
    );

    // A (re)installed plugin's bytecode differs from anything cached under
    // the same slug — drop stale VMs so the next resolution recompiles.
    ref.read(pluginCacheProvider).evictPlugin(plugin.slug);
    _storage.validatedPlugins.removeWhere(
        (key) => key.startsWith(PluginStorage.validationPrefix(plugin)));
  }

  Future<void> removePlugin(PluginConfiguration plugin) async {
    final pluginExtractionDir = await _storage.extractionDir(plugin);

    // A previous interrupted swap may have left the real files in the backup.
    await _storage.deleteDirectoryQuietly(
      Directory('${pluginExtractionDir.path}.backup'),
    );
    if (await pluginExtractionDir.exists()) {
      await pluginExtractionDir.delete(recursive: true);
    }
    await database.pluginsTable.deleteWhere((tbl) =>
        tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author));

    // Cached VMs of a removed plugin must not resolve anymore.
    ref.read(pluginCacheProvider).evictPlugin(plugin.slug);
    _storage.validatedPlugins.removeWhere(
        (key) => key.startsWith(PluginStorage.validationPrefix(plugin)));

    // The removed plugin can no longer seed the startup cache. Clear
    // before the promotion blocks below: a promoted replacement
    // re-records its own identity via setDefaultThemePlugin.
    if (state.valueOrNull?.defaultThemePluginConfig == plugin) {
      await writeThemePluginKey(null);
    }

    // Same here, if the removed plugin is the default plugin
    // set the first available plugin as the default plugin
    // only when there is 1 remaining plugin
    if (state.valueOrNull?.defaultMetadataPluginConfig == plugin) {
      final remainingPlugins = state.valueOrNull?.plugins.where(
            (p) =>
                p != plugin && p.abilities.contains(PluginAbilities.metadata),
          ) ??
          [];
      if (remainingPlugins.length == 1) {
        await setDefaultMetadataPlugin(remainingPlugins.first);
      }
    }

    if (state.valueOrNull?.defaultAudioSourcePluginConfig == plugin) {
      final remainingPlugins = state.valueOrNull?.plugins.where(
            (p) =>
                p != plugin &&
                p.abilities.contains(PluginAbilities.audioSource),
          ) ??
          [];
      if (remainingPlugins.length == 1) {
        await setDefaultAudioSourcePlugin(remainingPlugins.first);
      }
    }

    if (state.valueOrNull?.defaultThemePluginConfig == plugin) {
      final remainingPlugins = state.valueOrNull?.plugins.where(
            (p) => p != plugin && p.abilities.contains(PluginAbilities.theme),
          ) ??
          [];
      if (remainingPlugins.length == 1) {
        await setDefaultThemePlugin(remainingPlugins.first);
      }
    }

    if (state.valueOrNull?.defaultRadioPluginConfig == plugin) {
      final remainingPlugins = state.valueOrNull?.plugins.where(
            (p) => p != plugin && p.abilities.contains(PluginAbilities.radio),
          ) ??
          [];
      if (remainingPlugins.length == 1) {
        await setDefaultRadioPlugin(remainingPlugins.first);
      }
    }
  }

  /// Whether [newPlugin] should replace the installed row for the same
  /// identity. The plugin's own semantic version is the update signal; the
  /// plugin API version is only a secondary signal when both versions match.
  /// Bundled releases routinely bump `version` without changing the API.
  @visibleForTesting
  static bool shouldUpdatePlugin({
    required String oldVersion,
    required String oldPluginApiVersion,
    required String newVersion,
    required String newPluginApiVersion,
  }) =>
      pluginShouldUpdate(
        oldVersion: oldVersion,
        oldPluginApiVersion: oldPluginApiVersion,
        newVersion: newVersion,
        newPluginApiVersion: newPluginApiVersion,
      );

  @visibleForTesting
  static Future<PluginsTableData?> replacePluginRow({
    required AppDatabase database,
    required PluginConfiguration plugin,
  }) =>
      replacePluginRowInDatabase(database: database, plugin: plugin);

  /// Replaces the installed plugin's metadata row and then removes the old
  /// version directory. The new files must already be extracted.
  Future<bool> _replacePlugin(
    PluginConfiguration oldPlugin,
    PluginConfiguration newPlugin,
  ) async {
    final oldDir = await _storage.extractionDir(oldPlugin);
    final newDir = await _storage.extractionDir(newPlugin);
    final sameDirectory = oldDir.path == newDir.path;

    final PluginsTableData? oldRow;
    try {
      oldRow = await replacePluginRow(database: database, plugin: newPlugin);
    } catch (_) {
      // The row is still the old one. Only discard files that are not the
      // old installation's directory.
      if (!sameDirectory) await _storage.deleteDirectoryQuietly(newDir);
      rethrow;
    }

    if (oldRow == null) {
      if (!sameDirectory) await _storage.deleteDirectoryQuietly(newDir);
      return false;
    }

    ref.read(pluginCacheProvider).evictPlugin(newPlugin.slug);
    _storage.validatedPlugins.removeWhere(
        (key) => key.startsWith(PluginStorage.validationPrefix(newPlugin)));

    if (oldRow.selectedForTheme) {
      await writeThemePluginKey(
        newPlugin.abilities.contains(PluginAbilities.theme)
            ? themePluginKey(newPlugin)
            : null,
      );
    }

    // The row now points at the new directory. Only now is it safe to remove
    // the old version; a crash before this point leaves an orphan, never a
    // registered plugin with missing files.
    if (!sameDirectory) await _storage.deleteDirectoryQuietly(oldDir);
    return true;
  }

  Future<void> _discardExtractionIfDistinct(
    PluginConfiguration oldPlugin,
    PluginConfiguration newPlugin,
  ) async {
    final oldDir = await _storage.extractionDir(oldPlugin);
    final newDir = await _storage.extractionDir(newPlugin);
    if (oldDir.path == newDir.path) return;
    await _storage.deleteDirectoryQuietly(newDir);
  }

  Future<void> updatePlugin(
    PluginConfiguration plugin,
    PluginUpdateAvailable update,
  ) async {
    final pluginUpdatedConfig =
        await downloadAndCachePlugin(update.downloadUrl);

    try {
      if (pluginUpdatedConfig.name != plugin.name ||
          pluginUpdatedConfig.author != plugin.author) {
        throw MetadataPluginException.invalidPluginConfiguration();
      }
      _assertPluginApiCompatibility(pluginUpdatedConfig);
    } catch (_) {
      // The archive was already extracted before validation. Do not leave a
      // directory that no row will ever point at.
      await _discardExtractionIfDistinct(plugin, pluginUpdatedConfig);
      rethrow;
    }

    final replaced = await _replacePlugin(plugin, pluginUpdatedConfig);
    if (!replaced) {
      throw StateError('Plugin row disappeared during update');
    }
  }

  Future<void> setDefaultMetadataPlugin(PluginConfiguration plugin) async {
    assert(
      plugin.abilities.contains(PluginAbilities.metadata),
      "Must be a metadata plugin",
    );

    await database.pluginsTable
        .update()
        .write(const PluginsTableCompanion(selectedForMetadata: Value(false)));

    await (database.pluginsTable.update()
          ..where((tbl) =>
              tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author)))
        .write(
      const PluginsTableCompanion(selectedForMetadata: Value(true)),
    );
  }

  Future<void> setDefaultAudioSourcePlugin(PluginConfiguration plugin) async {
    assert(
      plugin.abilities.contains(PluginAbilities.audioSource),
      "Must be an audio-source plugin",
    );

    await database.pluginsTable.update().write(
        const PluginsTableCompanion(selectedForAudioSource: Value(false)));

    await (database.pluginsTable.update()
          ..where((tbl) =>
              tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author)))
        .write(
      const PluginsTableCompanion(selectedForAudioSource: Value(true)),
    );
  }

  Future<void> setDefaultThemePlugin(PluginConfiguration plugin) async {
    assert(
      plugin.abilities.contains(PluginAbilities.theme),
      'Plugin does not have the theme ability',
    );

    await database.pluginsTable.update().write(
          const PluginsTableCompanion(
            selectedForTheme: Value(false),
          ),
        );

    await (database.pluginsTable.update()
          ..where(
            (tbl) =>
                tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author),
          ))
        .write(
      const PluginsTableCompanion(
        selectedForTheme: Value(true),
      ),
    );

    // Identity for the startup theme cache (DB-free validation).
    await writeThemePluginKey(themePluginKey(plugin));
  }

  Future<void> setDefaultRadioPlugin(PluginConfiguration plugin) async {
    assert(
      plugin.abilities.contains(PluginAbilities.radio),
      'Plugin does not have the radio ability',
    );

    await database.pluginsTable.update().write(
          const PluginsTableCompanion(
            selectedForRadio: Value(false),
          ),
        );

    await (database.pluginsTable.update()
          ..where(
            (tbl) =>
                tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author),
          ))
        .write(
      const PluginsTableCompanion(
        selectedForRadio: Value(true),
      ),
    );
  }

  /// Re-evaluates the active theme (e.g. after shell scheme changes).
  ///
  /// Manual v1 refresh path alongside the automatic file-watch signals:
  /// `themeDefinitionProvider` recomputes, `ThemeData` rebuilds.
  void refreshThemeDefinition() {
    ref.read(themeUiOverrideProvider.notifier).state = null;
    ref.invalidate(themeDefinitionProvider);
  }
}
