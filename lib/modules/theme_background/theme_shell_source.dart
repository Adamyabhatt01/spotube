import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/caelestia_shell_source.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// Host-side source for external shell integrations.
///
/// The plugin protocol only ever says `"source": "shell"`. The host
/// decides which shell integration serves that source, leaving room for
/// future implementations (KDE, GNOME, Hyprland, ...) without changing
/// the renderer or the plugin API.
abstract class ThemeShellSource {
  /// Resolves the current shell background to a local image path.
  ///
  /// Returns null when no shell background is available. Never reads
  /// image bytes — the caller feeds the path into an image provider.
  String? getBackgroundPath();

  /// Resolves the shell-provided theme, if any.
  ///
  /// Returns null when the shell has no theme state to offer. The
  /// caller (eventually `themeDefinitionProvider`) fills shell-owned
  /// pieces of the plugin's declarative [ThemeDefinition] from this.
  /// Async: shell state lives on disk and must not block the event loop.
  Future<ThemeDefinition?> getTheme();

  /// Opaque key identifying current shell theme state for cache
  /// validation (e.g. a scheme file mtime). Null means "no signal":
  /// the cache is then validated by plugin identity alone.
  String? get cacheKey => null;

  /// Emits whenever shell theme state may have changed.
  ///
  /// Drives theme recomputation without polling. Defaults to never;
  /// shells with observable state override this.
  Stream<void> watchTheme() => const Stream.empty();

  /// Emits whenever the shell background may have changed.
  ///
  /// Separate from [watchTheme] so wallpaper swaps rebuild only the
  /// background layer, not the whole theme. Defaults to never.
  Stream<void> watchBackground() => const Stream.empty();
}

/// Merges shell-owned palette data into a plugin [ThemeDefinition].
///
/// Only the color sides come from [shell]; every rendering behavior
/// (surfaces, background attributes, radius, density, dynamic markers)
/// stays plugin-owned so a shell can never override glass settings.
ThemeDefinition mergeShellPalette({
  required ThemeDefinition plugin,
  required ThemeDefinition shell,
}) {
  // Re-sanitize: the shell payload is a second untrusted input, and
  // `fromJson` on the shell side never went through the plugin endpoint's
  // clamps. Cheap, and it keeps geometry provably in range on every path
  // that can produce a ThemeDefinition.
  return sanitizeThemeDefinition(
    plugin.copyWith(light: shell.light, dark: shell.dark),
  );
}

/// Resolves the effective theme for a plugin definition.
///
/// Non-shell plugins pass through untouched (identical instance, no
/// shell lookup). When the plugin declares `dynamic.source == shell`,
/// the shell palette is merged in; an unavailable shell falls back to
/// the plugin definition.
Future<ThemeDefinition?> resolveThemeDefinition(
  ThemeDefinition? plugin, {
  required Future<ThemeDefinition?> Function() readShellTheme,
}) async {
  if (plugin == null) return null;
  if (plugin.dynamicTheme?.source != DynamicThemeSource.shell) return plugin;
  final shell = await readShellTheme();
  if (shell == null) return plugin;
  return mergeShellPalette(plugin: plugin, shell: shell);
}

/// Serves [ThemeShellSource]. Currently Caelestia-only; extend with
/// platform selection when more shell integrations land.
final themeShellSourceProvider = Provider<ThemeShellSource>(
  (ref) => const CaelestiaShellSource(),
);

/// Rebuild signal for shell theme state.
///
/// `themeDefinitionProvider` watches this and recomputes when the shell
/// reports a possible palette change. Stays silent for shells without
/// observable state.
final shellThemeSignalProvider = StreamProvider<void>((ref) {
  return ref.watch(themeShellSourceProvider).watchTheme();
});

/// Rebuild signal for the shell background.
///
/// `themeBackgroundImageProvider` watches this and re-resolves the path
/// when the shell reports a possible wallpaper change, without touching
/// the rest of the theme.
final shellBackgroundSignalProvider = StreamProvider<void>((ref) {
  return ref.watch(themeShellSourceProvider).watchBackground();
});
