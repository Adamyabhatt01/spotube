import 'dart:async';
import 'dart:typed_data';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:spotube/services/theme_ui/artwork_palette.dart';
import 'package:spotube/services/theme_ui/artwork_palette_provider.dart';

/// Kept as the hook module's public sample seam.
///
/// The implementation moved next to the cache so the palette hook and the
/// theme bindings share one extractor; the test that pins the 50 px decode
/// still imports it from here.
ImageProvider paletteSampleProvider(Uint8List bytes) =>
    themeUiPaletteSampleProvider(bytes);

/// The colour the lyrics page tints its backdrop with.
///
/// Reads the URL-keyed cache instead of a single shared slot. The old slot
/// let a stale fetch for the previous track overwrite the current track's
/// colour; keying by URL makes that impossible, and an entry the user has
/// already visited is served without another decode.
PaletteColor usePaletteColor(String imageUrl, WidgetRef ref) {
  final context = useContext();
  final brightness = Theme.of(context).brightness;
  final cache = ref.watch(themeUiPaletteCacheProvider);
  // Rebuilds once per stored palette without polling the cache.
  ref.watch(themeUiPaletteRevisionProvider);
  final palette = cache[imageUrl];

  useEffect(() {
    var cancelled = false;
    if (cache[imageUrl] != null) return null;
    final future = cache.load(imageUrl, isCancelled: () => cancelled);
    // The future only carries the value to this caller; the cache publishes
    // it through [themeUiPaletteRevisionProvider] for the rebuild.
    unawaited(future);
    return () => cancelled = true;
  }, [imageUrl, cache]);

  if (palette == null) return PaletteColor(Colors.gray[300], 0);
  final color =
      brightness == Brightness.light ? palette.lightMuted : palette.darkMuted;
  return PaletteColor(color, 0);
}
