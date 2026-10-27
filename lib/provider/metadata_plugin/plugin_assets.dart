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
