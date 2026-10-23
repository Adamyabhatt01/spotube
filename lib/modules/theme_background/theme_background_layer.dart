import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/utils/theme_converter.dart';

/// Pure presentational background layer for the active [ThemeBackground].
///
/// Renders nothing unless a plugin theme names the shell as its background
/// source AND the shell has a wallpaper to show. Layer order: image, blur,
/// overlay. Intended to sit [Positioned.fill] behind the app content.
///
/// Under real window transparency the image and blur stay off (painting them
/// would cover the desktop; blur would sample nothing) but the veil still
/// paints: it is translucent, so the live desktop shows through tinted with
/// the theme's background colour instead of losing it. No veil declared
/// stays fully clear.
class ThemeBackgroundLayer extends ConsumerWidget {
  const ThemeBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stale-while-revalidate across theme reloads (same rationale as the
    // url provider below and the palette fallback in main): while the live
    // definition is loading, `asData` is null and the background alone would
    // read "nothing to paint" — blanking the wallpaper for the reload
    // duration. The last-good cached theme holds the previous frame.
    final background = ref.watch(
          themeDefinitionProvider.select((s) => s.asData?.value?.background),
        ) ??
        ref.watch(
          cachedThemeDefinitionProvider.select(
            (s) => s.asData?.value?.background,
          ),
        );
    // Same quantization rule as the lyrics backdrop: one shared decode per
    // 256px window band instead of a re-decode per pixel of resizing.
    final side = quantizeBackdropSide(MediaQuery.sizeOf(context).longestSide);
    final image = ref.watch(themeBackgroundImageProvider(side));
    final assetFile = ref.watch(themeBackgroundAssetFileProvider);
    // A BackdropFilter re-blurs everything behind it on every frame the
    // content moves; while scrolling the frost is skipped and restored when
    // the content settles. Sigma, overlay and opacity at rest are unchanged.
    final blurFrozen = ref.watch(chromeBlurFrozen);

    // Shared veil resolution: the overlay hex (plugin-declared or
    // shell-derived), brightness-adapted — or null when absent/malformed.
    // Resolved before either branch so real and painted modes share it.
    // Material theme brightness mirrors the app theme mode (both derive
    // from the same setting in main), so this stays in sync with the
    // shadcn scheme without mixing Theme imports.
    Color? overlay;
    if (background?.overlay != null) {
      try {
        overlay = ThemeConverter.adaptOverlayForBrightness(
          ThemeConverter.parseColor(background!.overlay!),
          Theme.of(context).colorScheme.brightness,
        );
      } catch (_) {
        overlay = null;
      }
    }

    // Real transparency owns the ground: the compositor shows through, so
    // the wallpaper image (and its blur) would cover the desktop again and
    // stay off. The veil is translucent, so alpha composes and the theme
    // keeps its background colour over the live desktop.
    if (ref.watch(realTransparencyActiveProvider)) {
      if (overlay == null) return const SizedBox.shrink();
      return ColoredBox(color: overlay);
    }

    if (background == null) return const SizedBox.shrink();
    final isAsset = background.source == ThemeBackgroundSource.asset;

    if (isAsset) {
      if (assetFile == null) return const SizedBox.shrink();
    } else if (background.source == ThemeBackgroundSource.none ||
        image == null) {
      return const SizedBox.shrink();
    }

    final Widget ground;
    if (isAsset) {
      final provider = FileImage(assetFile!);
      final scale = background.scale.clamp(1, 8);
      if (background.tile) {
        // Pixel-art tiles are magnified by whole integers and repeated, not
        // stretched: a 32px shard stays a 32px shard at 4x instead of
        // becoming a blurry crop. `DecorationImage.scale` is a divisor, so
        // 1/4 turns each source pixel into four logical pixels.
        ground = DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: provider,
              repeat: ImageRepeat.repeat,
              fit: BoxFit.none,
              scale: 1 / scale,
              filterQuality: FilterQuality.none,
            ),
          ),
        );
      } else {
        ground = Image(
          image: provider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      }
    } else {
      ground = Image(
        image: image!,
        fit: BoxFit.cover,
        // Keep the previous wallpaper until the new one decodes: a
        // wallpaper switch would otherwise blank the ground for the
        // decode duration (raw desktop flashing through unveiled).
        gaplessPlayback: true,
        // The file can vanish between the source stat and the async decode
        // (wallpaper rotation). Degrade to empty.
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }

    return Stack(
      children: [
        // A theme asset can be a transparent pixel overlay (the obsidian
        // shard is mostly alpha). Paint the theme's ground beneath it: the
        // Linux window itself has an alpha channel, so leaving this empty
        // would show the desktop wallpaper rather than the theme's black.
        // Real transparency already returned above, where the compositor is
        // the intended ground.
        if (isAsset)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
            ),
          ),
        Positioned.fill(
          child: Opacity(
            opacity: background.opacity,
            child: Stack(
              children: [
                Positioned.fill(child: ground),
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
          ),
        ),
      ],
    );
  }
}
