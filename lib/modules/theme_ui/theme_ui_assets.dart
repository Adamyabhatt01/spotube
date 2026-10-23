import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';

/// Resolves a theme's `asset://` paths inside the theme plugin's own,
/// versioned extraction directory.
///
/// The theme never gets a filesystem binding and never chooses an absolute
/// path: it names a relative path, the host validates it with the same
/// predicate it uses for archive entries, then joins it to the directory the
/// plugin was extracted into. An absolute path, a `..` segment, or a Windows
/// drive letter is rejected before any file is touched.
class ThemeUiAssets {
  final String? pluginDirectory;

  const ThemeUiAssets({this.pluginDirectory});

  File? resolve(String? source) {
    if (source == null || !source.startsWith('asset://')) return null;
    final directory = pluginDirectory;
    if (directory == null) return null;

    final relative = source.substring('asset://'.length);
    if (relative.isEmpty) return null;
    // Accept the same shapes the archive extractor accepts, but never a path
    // that normalizes back out of the plugin directory.
    if (!MetadataPluginNotifier.isSafePluginEntryPath(relative)) return null;
    final normalized = normalize(relative);
    if (normalized == '..' || normalized.startsWith('../')) return null;

    // Theme archives keep their declared assets below `assets/`, while the
    // contract (and every `asset://` path a theme writes) is relative to that
    // root. Prefer the canonical location, then fall back to the plugin root
    // for archives built before the convention was enforced.
    final canonical = File(join(directory, 'assets', normalized));
    if (canonical.existsSync()) return canonical;
    final legacy = File(join(directory, normalized));
    if (legacy.existsSync()) return legacy;
    return canonical;
  }
}

/// The active theme plugin's asset root, or an inert resolver before one is
/// installed. Keeping the provider success-shaped means a missing theme is
/// "no assets", not a widget-tree error.
final themeUiAssetsProvider = FutureProvider<ThemeUiAssets>((ref) async {
  final plugin = await ref.watch(
    metadataPluginsProvider.selectAsync(
      (data) => data.defaultThemePluginConfig,
    ),
  );
  if (plugin == null) return const ThemeUiAssets();

  try {
    final directory = await ref
        .read(metadataPluginsProvider.notifier)
        .getPluginDirectory(plugin);
    return ThemeUiAssets(pluginDirectory: directory.path);
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'themeUiAssetsProvider');
    return const ThemeUiAssets();
  }
});
