import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';

/// Quantizes a backdrop decode side the way the lyrics backdrop does: the
/// provider's cache key includes the decode size, so rounding the window up
/// in fixed steps keeps a resize from re-decoding for every pixel it moves.
/// Same rule everywhere a full-screen backdrop is decoded.
double quantizeBackdropSide(double longestSide, {double step = 256}) {
  if (longestSide <= 0) return step;
  return (longestSide / step).ceilToDouble() * step;
}

/// Resolves what the backdrop should show, as a URL, or null when there is
/// nothing to render:
/// - no plugin theme, or its background source is not
///   [ThemeBackgroundSource.shell]
/// - the source is shell but the host shell has no wallpaper to show, which is
///   what makes a non-Caelestia desktop inert even if a plugin asked for one
///
/// Size-independent, so it doubles as the one "is a backdrop being painted"
/// predicate every consumer of the shell glass shares — the scaffold ground,
/// the sidebar's label fill, the title bar. Deciding that from the sized
/// provider below would tie it to a window dimension it does not care about.
final themeBackdropUrlProvider = Provider<String?>((ref) {
  // Re-resolves the path when the shell reports a possible wallpaper
  // change, without touching the rest of the theme.
  ref.watch(shellBackgroundSignalProvider);

  // Stale-while-revalidate across theme reloads: while the live definition
  // is loading (theme switch) `asData` is null, so the source alone would
  // read "no backdrop" — dropping the transparent scaffold for an opaque
  // one for the reload duration (the black pop). The last-good cached theme
  // holds the previous source until the live one lands. The palette in main
  // already falls back the same way; the ground must match it.
  final liveSource = ref.watch(
    themeDefinitionProvider.select((s) => s.asData?.value?.background.source),
  );
  final cachedSource = ref.watch(
    cachedThemeDefinitionProvider.select(
      (s) => s.asData?.value?.background.source,
    ),
  );

  if ((liveSource ?? cachedSource) != ThemeBackgroundSource.shell) {
    return null;
  }

  return ref.watch(themeShellSourceProvider).getBackgroundPath();
});

/// Whether [ThemeBackgroundLayer] is actually painting behind the app.
///
/// Chrome that exists only to bend the shell's glass to the terminal must
/// switch off with it: a transparent scaffold ground over nothing is just an
/// unpainted window. So a built-in theme, a plugin with no backdrop, or a
/// shell-sourced plugin on a desktop with no Caelestia state keeps the
/// appearance it had before the shell owned any of it.
final themeBackdropActiveProvider = Provider<bool>(
  (ref) => ref.watch(themeBackdropUrlProvider) != null,
);

/// Resolves the background image for the active [ThemeBackground] spec,
/// decoded at [side] logical pixels.
///
/// Keyed by the quantized side so the layer and the scope share one cached
/// instance (and one decode) whenever they agree on the size — different
/// keys would fragment the image cache the way per-pixel sizes used to.
/// Null exactly when [themeBackdropUrlProvider] is.
final themeBackgroundImageProvider =
    Provider.family<ImageProvider?, double>((ref, side) {
  final url = ref.watch(themeBackdropUrlProvider);
  if (url == null) return null;
  return UniversalImage.imageProvider(url, width: side, height: side);
});
