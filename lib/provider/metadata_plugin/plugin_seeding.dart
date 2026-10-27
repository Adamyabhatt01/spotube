part of 'metadata_plugin_provider.dart';

extension MetadataPluginSeeding on MetadataPluginNotifier {
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
      final pluginConfig = PluginStorage.readArchiveConfig(archive);
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
        await _storage.extractArchiveFrom(archive);
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

    final extractionDir = await _storage.extractionDir(config);
    if (!await File(join(extractionDir.path, "plugin.json")).exists()) {
      return false;
    }
    final binary = File(join(extractionDir.path, "plugin.out"));
    if (!await binary.exists()) return false;

    return await binary.length() == byteCodeLength;
  }
}
