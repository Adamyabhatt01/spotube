import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/caelestia_shell_source.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// Glass the shell wants the app to draw with.
///
/// Deliberately partial: [surfacesOpacity] is the only card property the
/// shell owns, since `surfaces.blur`/`tint` and all geometry stay
/// plugin-authored. [background] replaces the backdrop wholesale because a
/// derived veil is meaningless alongside a plugin's different veil.
///
/// A record, not a model: it never crosses the plugin protocol boundary and
/// is never serialized, so it has no reason to join [ThemeDefinition].
typedef ThemeGlass = ({
  double? surfacesOpacity,
  ThemeBackground? background,
});

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

  /// Resolves the glass the shell actually draws its windows with.
  ///
  /// Null means "no opinion": the plugin's authored numbers stand. Shells
  /// that render through user config (a terminal's translucency, a
  /// compositor's blur) override this so the app matches the desktop
  /// instead of merely borrowing its colors. Only consulted for a plugin
  /// that names the shell as its own background source — see
  /// [mergeShellPalette].
  Future<ThemeGlass?> getGlass() async => null;

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

/// Merges shell-owned data into a plugin [ThemeDefinition].
///
/// Colors always come from [shell]. [glass] additionally supplies the
/// backdrop and the card alpha, but only to a plugin that paints the desktop
/// itself (`background.source == shell`): the glass describes a wallpaper, so
/// a plugin with a plain background or one frosting its own album art keeps
/// its authored numbers byte-for-byte. Radius, density, tokens, layout and the
/// rest of `surfaces` stay plugin-owned on every path, and a null glass leaves
/// the plugin byte-identical.
ThemeDefinition mergeShellPalette({
  required ThemeDefinition plugin,
  required ThemeDefinition shell,
  ThemeGlass? glass,
}) {
  // One condition for the whole glass, because both halves of it are the same
  // claim about the desktop: borrowing the terminal's panel alpha while
  // painting no wallpaper gives translucent cards over a flat ground, which
  // describes neither the terminal nor the plugin.
  final shellGlass =
      glass != null && plugin.background.source == ThemeBackgroundSource.shell
          ? glass
          : null;
  final surfacesOpacity = shellGlass?.surfacesOpacity;

  // Re-sanitize: the shell payload is a second untrusted input, and
  // `fromJson` on the shell side never went through the plugin endpoint's
  // clamps. Cheap, and it keeps geometry provably in range on every path
  // that can produce a ThemeDefinition.
  return sanitizeThemeDefinition(
    plugin.copyWith(
      light: shell.light,
      dark: shell.dark,
      surfaces: surfacesOpacity == null
          ? plugin.surfaces
          : plugin.surfaces.copyWith(opacity: surfacesOpacity),
      // The transparency opt-in is the *plugin's* voice: shell glass owns
      // colors and veil, but must not silently drop an explicit veto
      // (or grant) by replacing the whole background block. Absent stays
      // absent (defers to the host setting either way).
      background: (shellGlass?.background ?? plugin.background)
          .copyWith(transparent: plugin.background.transparent),
    ),
  );
}

/// Resolves the effective theme for a plugin definition.
///
/// Non-shell plugins pass through untouched (identical instance, no
/// shell lookup). When the plugin declares `dynamic.source == shell`,
/// the shell palette and — when it has one — its terminal-derived glass
/// are merged in; an unavailable shell falls back to the plugin definition.
Future<ThemeDefinition?> resolveThemeDefinition(
  ThemeDefinition? plugin, {
  required Future<ThemeDefinition?> Function() readShellTheme,
  required Future<ThemeGlass?> Function() readShellGlass,
}) async {
  if (plugin == null) return null;
  if (plugin.dynamicTheme?.source != DynamicThemeSource.shell) return plugin;
  final shell = await readShellTheme();
  if (shell == null) return plugin;
  return mergeShellPalette(
    plugin: plugin,
    shell: shell,
    glass: await readShellGlass(),
  );
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
