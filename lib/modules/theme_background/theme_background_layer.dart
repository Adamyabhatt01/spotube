import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/utils/theme_converter.dart';

/// Pure presentational background layer for the active [ThemeBackground].
///
/// Renders nothing unless a plugin theme declares a non-none source AND
/// image data is available. Layer order: image, blur, overlay.
/// Intended to sit [Positioned.fill] behind the app content.
class ThemeBackgroundLayer extends ConsumerWidget {
  const ThemeBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(
      themeDefinitionProvider.select((s) => s.asData?.value?.background),
    );
    // Same quantization rule as the lyrics backdrop: one shared decode per
    // 256px window band instead of a re-decode per pixel of resizing.
    final side = quantizeBackdropSide(MediaQuery.sizeOf(context).longestSide);
    final image = ref.watch(themeBackgroundImageProvider(side));
    // A BackdropFilter re-blurs everything behind it on every frame the
    // content moves; while scrolling the frost is skipped and restored when
    // the content settles. Sigma, overlay and opacity at rest are unchanged.
    final blurFrozen = ref.watch(chromeBlurFrozen);

    if (background == null ||
        background.source == ThemeBackgroundSource.none ||
        image == null) {
      return const SizedBox.shrink();
    }

    Color? overlay;
    if (background.overlay != null) {
      try {
        final parsed = ThemeConverter.parseColor(background.overlay!);
        // Material theme brightness mirrors the app theme mode (both
        // derive from the same setting in main), so this stays in sync
        // with the shadcn scheme without mixing Theme imports.
        overlay = ThemeConverter.adaptOverlayForBrightness(
          parsed,
          Theme.of(context).colorScheme.brightness,
        );
      } catch (_) {
        overlay = null;
      }
    }

    return Opacity(
      opacity: background.opacity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image(
              image: image,
              fit: BoxFit.cover,
              // The file can vanish between the source stat and the
              // async decode (wallpaper rotation). Degrade to empty.
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          if (background.blur > 0)
            Positioned.fill(
              child: BackdropFilter(
                // Frozen while scrolling: sigma 0 draws plain until the
                // content settles, instead of re-blurring every frame.
                // Same convention as the nav-bar/chrome frost.
                filter: ImageFilter.blur(
                  sigmaX: blurFrozen ? 0 : background.blur,
                  sigmaY: blurFrozen ? 0 : background.blur,
                ),
                // Sized-expand only sizes the filter region; using a
                // Container(color:) here would add a ColoredBox that the
                // overlay check below could mistake for an overlay.
                child: const SizedBox.expand(),
              ),
            ),
          if (overlay != null)
            Positioned.fill(child: ColoredBox(color: overlay)),
        ],
      ),
    );
  }
}
