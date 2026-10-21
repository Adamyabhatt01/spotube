import 'dart:ui' show ImageFilter, TileMode;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/utils/platform.dart';

/// Whether [FrostedArtwork] frosts the artwork itself instead of leaving that
/// to the surface placed on top of it.
///
/// A panel reading this drops its own backdrop blur: with the picture behind it
/// already frosted, sampling the backdrop would blur a blur. Both ends of the
/// arrangement ask this one question so they cannot drift apart.
bool get artworkIsSelfFrosted => kIsAndroid;

/// Cover art behind a panel, frosted without reading the pixels under it.
///
/// The playlist header painted the cover into a `DecoratedBox` and let the
/// panel's `BackdropFilter` blur it, which makes the frost depend on paint
/// order and layer caching. On Android that dependency is visible: on the
/// header's first painted frame the cover has not resolved from its
/// `ImageProvider` yet, so the filter samples an empty backdrop, and nothing
/// re-samples once the image arrives - the frost stays flat until some other
/// repaint (a scroll) forces one. Filtering the picture as it is painted has no
/// order to get wrong.
///
/// Everywhere else this returns the decorated box it replaces, so desktop and
/// iOS keep sampling through the panel's own blur and look exactly as before.
class FrostedArtwork extends StatelessWidget {
  final ImageProvider image;
  final BorderRadiusGeometry borderRadius;

  /// The frost's sigma, so the baked blur matches the one the panel would have
  /// applied. Null or zero means there was no frost to bake, and the artwork is
  /// painted as it is.
  final double? sigma;
  final Widget child;

  const FrostedArtwork({
    required this.image,
    required this.borderRadius,
    required this.sigma,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      image: DecorationImage(image: image, fit: BoxFit.cover),
      borderRadius: borderRadius,
    );

    if (!artworkIsSelfFrosted) {
      return DecoratedBox(decoration: decoration, child: child);
    }

    final backdrop = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(image: image, fit: BoxFit.cover),
      ),
    );
    final sigma = this.sigma;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          Positioned.fill(
            // Mirrored rather than clamped: a filter layer's own edge would
            // otherwise bleed transparency inwards and leave a soft dark seam
            // just inside the panel.
            child: sigma == null || sigma <= 0
                ? backdrop
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.mirror,
                    ),
                    child: backdrop,
                  ),
          ),
          child,
        ],
      ),
    );
  }
}
