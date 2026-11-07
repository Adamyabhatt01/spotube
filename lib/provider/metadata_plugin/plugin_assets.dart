part of 'metadata_plugin_provider.dart';

extension MetadataPluginAssets on MetadataPluginNotifier {
  Future<Uint8List> getPluginByteCode(PluginConfiguration plugin) async {
    final pluginExtractionDirPath = await _storage.extractionDir(plugin);

    final libraryFile = File(join(pluginExtractionDirPath.path, "plugin.out"));

    if (!await libraryFile.exists()) {
      throw MetadataPluginException.pluginByteCodeFileNotFound();
    }

    return await libraryFile.readAsBytes();
  }

  Future<File?> getLogoPath(PluginConfiguration plugin) async {
    final pluginExtractionDirPath = await _storage.extractionDir(plugin);

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
      _storage.extractionDir(plugin);
}

/// Reads the static `theme.json` payload for the plugin named by a
/// `themePluginKey` (`author::name::version`).
///
/// Top-level (not on the notifier) on purpose: the only identity needed is
/// the recorded plugin key, so the static path stays free of the metadata
/// provider and the database behind it. Returns null when there is no
/// payload, it is from another envelope version, or it does not decode —
/// every one of those just costs the live `getTheme()` boot it was trying
/// to avoid.
Future<StaticThemePayload?> readStaticThemePayload(
  String? pluginKey,
) async {
  try {
    if (pluginKey == null) return null;
    final parts = pluginKey.split('::');
    if (parts.length != 3) return null;

    // `entryPoint` does not take part in the directory name; it only needs
    // to satisfy the model because the storage computes the path from
    // author/name/version alone.
    final config = PluginConfiguration(
      name: parts[1],
      description: '',
      version: parts[2],
      author: parts[0],
      entryPoint: 'Theme',
      pluginApiVersion: '2.0.0',
    );
    final storage = PluginStorage();
    final dir = await storage.extractionDir(config);
    final file = File(join(dir.path, 'theme.json'));
    if (!await file.exists()) return null;
    return parseStaticThemeJson(jsonDecode(await file.readAsString()));
  } catch (_) {
    return null;
  }
}
