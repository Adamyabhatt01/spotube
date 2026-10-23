import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/utils/service_utils.dart';
import 'package:archive/archive.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

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
      final validationKey = _validationKey(pluginConfig);
      if (!_validatedPlugins.contains(validationKey)) {
        final pluginExtractionDir = await _getPluginExtractionDir(pluginConfig);
        await _recoverInterruptedExtraction(pluginExtractionDir);
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
        _validatedPlugins.add(validationKey);
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

  Future<void> _loadDefaultPlugins(MetadataPluginState pluginState) async {
    final seedConfigs = <PluginConfiguration>[];
    // Identity is (name, author), not slug — same rule as the duplicate check.
    final installedNow = <String>{};

    for (final plugin in bundledPlugins) {
      final byteData = await rootBundle.load(
        "assets/plugins/$plugin/plugin.smplug",
      );
      // Only the central directory is read here; inflating `plugin.json` is a
      // few hundred bytes. Writing the archive out again is what used to sit
      // on the startup path for every launch of an up-to-date install.
      final archive = ZipDecoder().decodeBytes(byteData.buffer.asUint8List());
      final pluginConfig = readPluginArchiveConfig(archive);
      seedConfigs.add(pluginConfig);

      if (!await isBundledPluginUpToDate(
        pluginConfig,
        archive
            .firstWhereOrNull(
              (file) => file.isFile && file.name == "plugin.out",
            )
            ?.size,
        pluginState,
      )) {
        await extractPluginArchiveFrom(archive);
      }

      try {
        await addPlugin(pluginConfig);
        installedNow.add('${pluginConfig.name}|${pluginConfig.author}');
      } on MetadataPluginException catch (e) {
        if (e.errorCode != MetadataPluginErrorCode.duplicatePlugin) {
          continue;
        }
        if (!await isPluginUpdate(pluginConfig)) continue;

        // Identity is (name, author), not slug: two differently-authored
        // plugins may slugify to the same string.
        final oldConfig = pluginState.plugins.firstWhereOrNull(
          (p) => p.name == pluginConfig.name && p.author == pluginConfig.author,
        );
        if (oldConfig == null) continue;

        final replaced = await _replacePlugin(oldConfig, pluginConfig);
        if (!replaced) {
          // The row disappeared between the duplicate check and the update.
          // The staged files are already valid; register them as a fresh
          // install rather than failing startup.
          try {
            await addPlugin(pluginConfig);
            installedNow.add('${pluginConfig.name}|${pluginConfig.author}');
          } on MetadataPluginException {
            // Another writer won the race; its row is authoritative.
          }
        }
      }
    }

    await handOverDefaultMetadata(
      recommended: seedConfigs.firstWhereOrNull(
        (config) =>
            config.abilities.contains(PluginAbilities.metadata) &&
            installedNow.contains('${config.name}|${config.author}'),
      ),
      seedConfigs: seedConfigs,
    );
  }

  /// Makes the newly bundled metadata seed the default on installs that
  /// predate it.
  ///
  /// [addPlugin] claims a default slot only when nothing else holds one, so on
  /// an existing install the bundled plugin would land as merely available and
  /// the previous seed would keep the recommendation. Two guards keep this
  /// from stomping a deliberate choice: it runs only for a row this very pass
  /// created (so it fires once per install, never again), and only while the
  /// current default is one of the *other bundled seeds* — a default the user
  /// picked from the plugin index is left alone.
  @visibleForTesting
  Future<void> handOverDefaultMetadata({
    required PluginConfiguration? recommended,
    required List<PluginConfiguration> seedConfigs,
  }) async {
    if (recommended == null) return;

    final current = (await (database.pluginsTable.select()
              ..where((tbl) => tbl.selectedForMetadata.equals(true))
              ..limit(1))
            .get())
        .firstOrNull;
    if (current == null) return;
    if (current.name == recommended.name &&
        current.author == recommended.author) {
      return;
    }

    final isBundledSeed = seedConfigs.any(
      (config) =>
          config.name == current.name && config.author == current.author,
    );
    if (!isBundledSeed) return;

    await setDefaultMetadataPlugin(recommended);
  }

  /// Whether the bundled [config] is already registered and complete on disk,
  /// in which case startup has nothing to do.
  ///
  /// Completeness is the declared bytecode size rather than a content hash: a
  /// write interrupted by a crash leaves a short `plugin.out` behind, and the
  /// unconditional re-extraction this replaces used to repair that.
  Future<bool> isBundledPluginUpToDate(
    PluginConfiguration config,
    int? byteCodeLength,
    MetadataPluginState installed,
  ) async {
    if (byteCodeLength == null) return false;

    final row = installed.plugins.firstWhereOrNull(
      (plugin) => plugin.name == config.name && plugin.author == config.author,
    );
    if (row == null || row.version != config.version) return false;

    final extractionDir = await _getPluginExtractionDir(config);
    if (!await File(join(extractionDir.path, "plugin.json")).exists()) {
      return false;
    }
    final binary = File(join(extractionDir.path, "plugin.out"));
    if (!await binary.exists()) return false;

    return await binary.length() == byteCodeLength;
  }

  Uri _getGithubReleasesUrl(String repoUrl) {
    final parsedUri = Uri.parse(repoUrl);
    final uri = parsedUri.replace(
      host: "api.github.com",
      pathSegments: [
        "repos",
        ...parsedUri.pathSegments,
        "releases",
      ],
      queryParameters: {
        "per_page": "1",
        "page": "1",
      },
    );

    return uri;
  }

  Uri _getCodebergeReleasesUrl(String repoUrl) {
    final parsedUri = Uri.parse(repoUrl);
    final uri = parsedUri.replace(
      pathSegments: [
        "api",
        "v1",
        "repos",
        ...parsedUri.pathSegments,
        "releases",
      ],
      queryParameters: {
        "limit": "1",
        "page": "1",
      },
    );

    return uri;
  }

  Future<String> _getPluginDownloadUrl(Uri uri) async {
    AppLogger.log.i("Getting plugin download URL from: $uri");
    final res = await globalDio.getUri(
      uri,
      options: Options(responseType: ResponseType.json),
    );

    if (res.statusCode != 200) {
      throw MetadataPluginException.failedToGetRelease();
    }
    final releases = res.data as List;
    if (releases.isEmpty) {
      throw MetadataPluginException.noReleasesFound();
    }
    final latestRelease = releases.first;
    final downloadUrl = (latestRelease["assets"] as List).firstWhere(
      (asset) => (asset["name"] as String).endsWith(".smplug"),
    )["browser_download_url"];
    if (downloadUrl == null) {
      throw MetadataPluginException.assetUrlNotFound();
    }
    return downloadUrl;
  }

  /// Root directory where all metadata plugins are stored.
  ///
  /// Memoized: every `pluginsTable` watch event re-validates the plugin list,
  /// and the support directory cannot move within a session.
  Future<Directory> _getPluginRootDir() async {
    if (_pluginRootDirPath case final path?) return Directory(path);
    final root = Directory(
      join(
        (await getApplicationSupportDirectory()).path,
        "metadata-plugins",
      ),
    );
    _pluginRootDirPath = root.path;
    return root;
  }

  String? _pluginRootDirPath;

  /// `author::name@version` triples whose extraction directory was validated
  /// this session. Directories are version-suffixed and immutable once
  /// extracted, so the three existence checks per plugin do not need to
  /// re-run on every watch event; install/remove paths below evict stale
  /// entries.
  final Set<String> _validatedPlugins = {};

  static String _validationKey(PluginConfiguration plugin) =>
      '${plugin.author}::${plugin.name}@${plugin.version}';

  static String _validationPrefix(PluginConfiguration plugin) =>
      '${plugin.author}::${plugin.name}@';

  /// Directory where the plugin will be extracted.
  /// This is a unique directory for each plugin version.
  /// It is used to avoid conflicts when multiple versions of the same plugin are installed
  ///
  /// `author` and `name` go through [ServiceUtils.sanitizeFilename]; `version`
  /// used to be interpolated raw. It is free text from the archive's own
  /// `plugin.json`, so a crafted value decided where every entry of the archive
  /// landed: `join` does not normalize, so `..` segments survive and the kernel
  /// resolves them at open(). The entry names themselves are already rejected
  /// by [isSafePluginEntryPath] before anything is written; the directory they
  /// land in has to pass the same predicate. Thrown here — the single choke
  /// point every caller (extraction, bytecode read, logo, validation, removal)
  /// funnels through — so no path can write outside the plugin root.
  Future<Directory> _getPluginExtractionDir(PluginConfiguration plugin) async {
    if (!isSafePluginEntryPath(plugin.version)) {
      throw MetadataPluginException.invalidPluginConfiguration();
    }
    final pluginDir = await _getPluginRootDir();
    final pluginExtractionDirPath = join(
      pluginDir.path,
      "${ServiceUtils.sanitizeFilename(plugin.author)}-${ServiceUtils.sanitizeFilename(plugin.name)}-${plugin.version}",
    );
    return Directory(pluginExtractionDirPath);
  }

  Future<PluginConfiguration> extractPluginArchive(List<int> bytes) async {
    return extractPluginArchiveFrom(ZipDecoder().decodeBytes(bytes));
  }

  /// `plugin.json` of an already decoded archive, without touching the disk.
  static PluginConfiguration readPluginArchiveConfig(Archive archive) {
    final pluginJson = archive.firstWhereOrNull(
      (file) => file.isFile && file.name == "plugin.json",
    );
    if (pluginJson == null) {
      throw MetadataPluginException.pluginConfigJsonNotFound();
    }
    return PluginConfiguration.fromJson(
      jsonDecode(
        utf8.decode(pluginJson.content as List<int>),
      ) as Map<String, dynamic>,
    );
  }

  Future<PluginConfiguration> extractPluginArchiveFrom(Archive archive) async {
    final pluginConfig = readPluginArchiveConfig(archive);

    // Validate before anything is written to disk: the bytecode file
    // [getPluginByteCode] will later require must be present, and every
    // entry path must stay inside the extraction directory. A partially
    // extracted plugin would otherwise linger on disk even though the
    // install itself fails.
    final hasByteCode =
        archive.any((file) => file.isFile && file.name == "plugin.out");
    if (!hasByteCode) {
      throw MetadataPluginException.pluginByteCodeFileNotFound();
    }

    final pluginDir = await _getPluginRootDir();
    await pluginDir.create(recursive: true);

    final pluginExtractionDir = await _getPluginExtractionDir(pluginConfig);
    await _recoverInterruptedExtraction(pluginExtractionDir);

    for (final file in archive) {
      if (file.isFile && !isSafePluginEntryPath(file.name)) {
        throw MetadataPluginException.invalidPluginConfiguration();
      }
    }

    // Never write over the live plugin directory. A failed extraction must
    // leave the previous working version byte-for-byte intact, and readers
    // must never observe a half-written plugin.
    final stagingDir = Directory(
      join(pluginDir.path, '.staging-$pid-${_stagingSequence++}'),
    );
    try {
      await stagingDir.create(recursive: true);
      for (final file in archive) {
        if (file.isFile) {
          final extractedFile = File(join(stagingDir.path, file.name));
          await extractedFile.create(recursive: true);
          await extractedFile.writeAsBytes(file.content as List<int>);
        }
      }
      await _promoteStagedPlugin(stagingDir, pluginExtractionDir);
    } catch (_) {
      // Only the staging directory is ours to remove; the target is either
      // untouched (failure before promotion) or was restored by promotion.
      await _deleteDirectoryQuietly(stagingDir);
      rethrow;
    }

    return pluginConfig;
  }

  static int _stagingSequence = 0;

  /// Replaces [target] with [staging] as close to atomically as the
  /// filesystem allows. The target is moved aside first because a directory
  /// rename cannot replace a non-empty directory on every platform.
  Future<void> _promoteStagedPlugin(
    Directory staging,
    Directory target,
  ) async {
    final backup = Directory('${target.path}.backup');

    if (await backup.exists()) {
      await _deleteDirectoryQuietly(backup);
    }

    final hadTarget = await target.exists();
    if (hadTarget) {
      await target.rename(backup.path);
    }

    try {
      await staging.rename(target.path);
    } catch (_) {
      // Put the old version back so a failed promotion is a no-op for the
      // caller. If this restore also fails, a later startup recovery can
      // still restore `${target}.backup`.
      if (hadTarget && !await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }

    if (hadTarget) {
      await _deleteDirectoryQuietly(backup);
    }
  }

  /// Completes or rolls back a swap interrupted between the two directory
  /// renames. Called before validation and before the next extraction.
  Future<void> _recoverInterruptedExtraction(Directory target) async {
    final backup = Directory('${target.path}.backup');
    if (!await backup.exists()) return;

    if (await target.exists()) {
      // The new target was promoted but the backup was not cleaned up.
      await _deleteDirectoryQuietly(backup);
      return;
    }

    // The old target was moved aside but the new one was never promoted.
    await backup.rename(target.path);
  }

  Future<void> _deleteDirectoryQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; an orphaned staging/backup directory is never
      // registered and cannot be served as a plugin.
    }
  }

  /// True when [name] cannot escape the plugin extraction directory.
  ///
  /// Both separator styles are normalized first: a Windows-style
  /// `..\evil` entry only traverses on Windows, so a substring check
  /// for `..` alone would miss platform differences, and `a/../../b`
  /// only escapes after normalization. Drive-letter prefixes are also
  /// rejected on every platform: a zip built on one OS is extracted on
  /// whatever OS the installer runs.
  /// Static and side-effect free so the traversal rules stay unit-testable.
  static bool isSafePluginEntryPath(String name) {
    final normalized = normalize(name.replaceAll('\\', '/'));
    if (isAbsolute(normalized)) return false;
    if (normalized == '..' || normalized.startsWith('../')) return false;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) return false;
    return true;
  }

  /// Downloads, extracts & caches the plugin from the given URL and returns the plugin config.
  /// If only a text/html URL is provided, it will try to get the latest release from
  /// the URL for supported websites (github.com, codeberg.org).
  Future<PluginConfiguration> downloadAndCachePlugin(String url) async {
    final res = await globalDio.head(url);
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
    final pluginDir = await _getPluginRootDir();
    await pluginDir.create(recursive: true);

    final pluginRes = await globalDio.get(
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

    return await extractPluginArchive(pluginRes.data);
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
    _validatedPlugins
        .removeWhere((key) => key.startsWith(_validationPrefix(plugin)));
  }

  Future<void> removePlugin(PluginConfiguration plugin) async {
    final pluginExtractionDir = await _getPluginExtractionDir(plugin);

    // A previous interrupted swap may have left the real files in the backup.
    await _deleteDirectoryQuietly(
      Directory('${pluginExtractionDir.path}.backup'),
    );
    if (await pluginExtractionDir.exists()) {
      await pluginExtractionDir.delete(recursive: true);
    }
    await database.pluginsTable.deleteWhere((tbl) =>
        tbl.name.equals(plugin.name) & tbl.author.equals(plugin.author));

    // Cached VMs of a removed plugin must not resolve anymore.
    ref.read(pluginCacheProvider).evictPlugin(plugin.slug);
    _validatedPlugins
        .removeWhere((key) => key.startsWith(_validationPrefix(plugin)));

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
  }) {
    final oldParsed = _tryParseVersion(oldVersion);
    final newParsed = _tryParseVersion(newVersion);
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

    final oldApi = _tryParseVersion(oldPluginApiVersion);
    final newApi = _tryParseVersion(newPluginApiVersion);
    if (oldApi == null || newApi == null) return false;
    return newApi > oldApi;
  }

  static Version? _tryParseVersion(String value) {
    try {
      return Version.parse(value);
    } catch (_) {
      return null;
    }
  }

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
    return shouldUpdatePlugin(
      oldVersion: oldPlugin.version,
      oldPluginApiVersion: oldPlugin.pluginApiVersion,
      newVersion: newPlugin.version,
      newPluginApiVersion: newPlugin.pluginApiVersion,
    );
  }

  /// Updates the existing row in place.
  ///
  /// This is deliberately not remove-then-add: the row is the only thing that
  /// makes the extracted files discoverable, so deleting it before the new
  /// insert (or crashing between the two) leaves the plugin unreachable. A
  /// single UPDATE also preserves the selected/default flags, which the old
  /// remove/add dance had to capture and restore manually.
  ///
  /// Returns the previous row, or null when no row with the same identity
  /// exists. Exposed for the atomicity regression test.
  @visibleForTesting
  static Future<PluginsTableData?> replacePluginRow({
    required AppDatabase database,
    required PluginConfiguration plugin,
  }) {
    return database.transaction(() async {
      final rows = await (database.pluginsTable.select()
            ..where(
              (tbl) =>
                  tbl.name.equals(plugin.name) &
                  tbl.author.equals(plugin.author),
            )
            ..limit(1))
          .get();
      if (rows.isEmpty) return null;

      await (database.pluginsTable.update()
            ..where(
              (tbl) =>
                  tbl.name.equals(plugin.name) &
                  tbl.author.equals(plugin.author),
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

  /// Replaces the installed plugin's metadata row and then removes the old
  /// version directory. The new files must already be extracted.
  Future<bool> _replacePlugin(
    PluginConfiguration oldPlugin,
    PluginConfiguration newPlugin,
  ) async {
    final oldDir = await _getPluginExtractionDir(oldPlugin);
    final newDir = await _getPluginExtractionDir(newPlugin);
    final sameDirectory = oldDir.path == newDir.path;

    final PluginsTableData? oldRow;
    try {
      oldRow = await replacePluginRow(database: database, plugin: newPlugin);
    } catch (_) {
      // The row is still the old one. Only discard files that are not the
      // old installation's directory.
      if (!sameDirectory) await _deleteDirectoryQuietly(newDir);
      rethrow;
    }

    if (oldRow == null) {
      if (!sameDirectory) await _deleteDirectoryQuietly(newDir);
      return false;
    }

    ref.read(pluginCacheProvider).evictPlugin(newPlugin.slug);
    _validatedPlugins
        .removeWhere((key) => key.startsWith(_validationPrefix(newPlugin)));

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
    if (!sameDirectory) await _deleteDirectoryQuietly(oldDir);
    return true;
  }

  Future<void> _discardExtractionIfDistinct(
    PluginConfiguration oldPlugin,
    PluginConfiguration newPlugin,
  ) async {
    final oldDir = await _getPluginExtractionDir(oldPlugin);
    final newDir = await _getPluginExtractionDir(newPlugin);
    if (oldDir.path == newDir.path) return;
    await _deleteDirectoryQuietly(newDir);
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

  Future<Uint8List> getPluginByteCode(PluginConfiguration plugin) async {
    final pluginExtractionDirPath = await _getPluginExtractionDir(plugin);

    final libraryFile = File(join(pluginExtractionDirPath.path, "plugin.out"));

    if (!await libraryFile.exists()) {
      throw MetadataPluginException.pluginByteCodeFileNotFound();
    }

    return await libraryFile.readAsBytes();
  }

  Future<File?> getLogoPath(PluginConfiguration plugin) async {
    final pluginExtractionDirPath = await _getPluginExtractionDir(plugin);

    final logoFile = File(join(pluginExtractionDirPath.path, "logo.png"));

    if (!await logoFile.exists()) {
      return null;
    }

    return logoFile;
  }

  /// The root a theme's `asset://` paths are resolved against.
  ///
  /// The directory is versioned and immutable once promoted; callers must
  /// still validate each relative path with [isSafePluginEntryPath] before
  /// joining, which is what `ThemeUiAssets` does.
  Future<Directory> getPluginDirectory(PluginConfiguration plugin) =>
      _getPluginExtractionDir(plugin);

  /// Re-evaluates the active theme (e.g. after shell scheme changes).
  ///
  /// Manual v1 refresh path alongside the automatic file-watch signals:
  /// `themeDefinitionProvider` recomputes, `ThemeData` rebuilds.
  void refreshThemeDefinition() {
    ref.read(themeUiOverrideProvider.notifier).state = null;
    ref.invalidate(themeDefinitionProvider);
  }
}

final metadataPluginsProvider =
    AsyncNotifierProvider<MetadataPluginNotifier, MetadataPluginState>(
  MetadataPluginNotifier.new,
);

final metadataPluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultMetadataPluginConfig),
    );
    final youtubeEngine = ref.read(youtubeEngineProvider);

    if (defaultPlugin == null) {
      return null;
    }

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);

    return await MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
  },
);

final audioSourcePluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultAudioSourcePluginConfig),
    );
    final youtubeEngine = ref.watch(youtubeEngineProvider);

    if (defaultPlugin == null) {
      return null;
    }

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);

    return await MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
  },
);

final themeDefinitionProvider = FutureProvider<ThemeDefinition?>(
  (ref) async {
    try {
      // Recomputes when the shell reports a possible palette change.
      // Unconditional by design: shell involvement is only known after
      // the plugin theme loads, and scheme changes are rare.
      ref.watch(shellThemeSignalProvider);

      // Reuses a memoized plugin instance instead of spinning a fresh Hetu
      // VM on every recompute (the previous code created one per signal,
      // and Hetu VMs are never released). The instance only rebuilds when
      // the default theme plugin changes.
      final plugin = await ref.watch(themePluginProvider.future);
      if (plugin == null) return null;

      final defaultPlugin = await ref.watch(
        metadataPluginsProvider
            .selectAsync((data) => data.defaultThemePluginConfig),
      );
      if (defaultPlugin == null) return null;

      final definition = await plugin.theme.getTheme();

      // Generic shell handoff: no shell names or paths here. When the
      // plugin declares `dynamic.source == shell`, the host shell source
      // supplies the palette and, if it renders through user config, the
      // glass the desktop actually draws with. Geometry stays plugin-owned.
      // NOTE: ref.read (not watch) is required here — this runs after
      // awaits. Reactivity comes from shellThemeSignalProvider above.
      final resolved = await resolveThemeDefinition(
        definition,
        readShellTheme: () => ref.read(themeShellSourceProvider).getTheme(),
        readShellGlass: () => ref.read(themeShellSourceProvider).getGlass(),
      );

      // Cache only successful resolutions for instant warm startup.
      // Null (failure) outcomes never touch the cache.
      if (resolved != null) {
        unawaited(
          writeThemeCache(
            pluginKey: themePluginKey(defaultPlugin),
            shellKey: ref.read(themeShellSourceProvider).cacheKey,
            definition: resolved,
          ),
        );
      }
      return resolved;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace, 'themeDefinitionProvider');
      return null;
    }
  },
);

/// Memoized theme plugin instance. Rebuilds only when the default theme
/// plugin changes, so theme recomputes reuse the same Hetu VM instead of
/// creating a new one each time (Hetu VMs are never disposed).
final themePluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultThemePluginConfig),
    );
    if (defaultPlugin == null) return null;

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);
    final youtubeEngine = ref.read(youtubeEngineProvider);

    return MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
  },
);

/// UI a theme answers from its optional `getUi()` method.
///
/// Kept separate from [themeUiProvider] so a shell palette refresh does not
/// re-invoke the plugin: this future only rebuilds when the plugin VM does.
final pluginThemeUiProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  final plugin = await ref.watch(themePluginProvider.future);
  if (plugin == null) return null;
  return plugin.theme.getUi();
});

/// A UI document returned by a theme's `onUiAction()`.
///
/// It wins over the current inline/`getUi()` document for the rest of the
/// session, which is what makes a plugin-driven screen change feel like a
/// live theme rather than a one-shot re-render. Selecting another theme
/// clears it through [MetadataPluginNotifier.refreshThemeDefinition].
final themeUiOverrideProvider = StateProvider<ThemeUiDocument?>((ref) => null);

/// The declarative UI the app should draw.
///
/// A theme may carry it inline in `getTheme()` (and then it rides the theme
/// definition cache) or answer from `getUi()`. Inline wins, because it
/// arrived with the same payload the colours did.
final themeUiProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  final override = ref.watch(themeUiOverrideProvider);
  if (override != null) return override;

  final definition = await ref.watch(themeDefinitionProvider.future);
  if (definition == null) return null;
  if (definition.ui != null) return definition.ui;
  return ref.watch(pluginThemeUiProvider.future);
});

/// In-memory cache for MetadataPlugin instances (Hetu VMs).
/// Scoped to provider lifecycle with explicit disposal. Generic so the
/// failure-recovery and eviction semantics are unit-testable without a
/// real Hetu VM.
class PluginVmCache<T> {
  final Map<String, Future<T>> _cache = {};

  /// Caches the creation [Future] (so concurrent attempts share one VM), but
  /// a FAILED future must not linger: without the removal below, one transient
  /// error would permanently disable this (plugin, engine) candidate.
  Future<T> getOrCreate(String key, Future<T> Function() factory) {
    final existing = _cache[key];
    if (existing != null) return existing;

    late final Future<T> tracked;
    tracked = factory().catchError((Object error, StackTrace stack) {
      if (identical(_cache[key], tracked)) _cache.remove(key);
      return Future<T>.error(error, stack);
    });
    _cache[key] = tracked;
    return tracked;
  }

  void evictPlugin(String pluginSlug) {
    // Keys look like "<slug>@<version>:<engine>" (see SourceCandidate.key).
    _cache.keys
        .where(
            (k) => k.startsWith('$pluginSlug:') || k.startsWith('$pluginSlug@'))
        .toList()
        .forEach(_cache.remove);
  }

  void clear() => _cache.clear();

  @visibleForTesting
  int get length => _cache.length;
}

/// Provider for the plugin cache. Drops cached VM references when the
/// provider is disposed; hetu_script exposes no VM disposal API, so the
/// VMs themselves become garbage-collectable but are not force-released.
final pluginCacheProvider = Provider<PluginVmCache<MetadataPlugin>>((ref) {
  final cache = PluginVmCache<MetadataPlugin>();
  ref.onDispose(() => cache.clear());
  return cache;
});
