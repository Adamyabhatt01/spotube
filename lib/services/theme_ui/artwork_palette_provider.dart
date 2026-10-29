import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/theme_ui/artwork_palette.dart';

/// One palette cache per provider container.
///
/// Container-scoped rather than a top-level singleton so a test's palette
/// cannot leak into the next test, and so the cache is disposed with the
/// app it belongs to.
final themeUiPaletteCacheProvider = Provider<ArtworkPaletteCache>((ref) {
  final cache = ArtworkPaletteCache();
  ref.onDispose(cache.dispose);
  return cache;
});

/// Emits once per stored palette.
///
/// Slots watch this only when the theme actually binds `palette.*`, so a
/// theme that never asks for a palette pays for neither the extraction nor
/// the rebuild.
final themeUiPaletteRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(themeUiPaletteCacheProvider).changes;
});
