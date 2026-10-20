import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';

/// Fixed cover edge for pinned playlist tiles, in the button's existing icon
/// slot. The sidebar width (200 * scaling, package-fixed) never changes.
const sidebarPinCoverSide = 28.0;

/// Small rounded playlist cover shared by the sidebar pinned tiles and the
/// sidebar reorder dialog. Fixed edge in the button's existing icon slot —
/// it never changes the sidebar width.
class SidebarPinCover extends StatelessWidget {
  final String? imageUrl;
  final double side;

  /// Icon shown when [imageUrl] is null. Defaults to the playlist glyph for
  /// the playlist pins; station pins pass the radio glyph.
  final IconData fallbackIcon;

  const SidebarPinCover({
    required this.imageUrl,
    required this.side,
    this.fallbackIcon = SpotubeIcons.playlist,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) return Icon(fallbackIcon);

    final scaling = Theme.of(context).scaling;
    final edge = side * scaling;
    return Container(
      width: edge,
      height: edge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6 * scaling),
        image: DecorationImage(
          // Decoded at 2x the display size, like PlaybuttonTile.
          image: UniversalImage.imageProvider(
            imageUrl!,
            width: edge * 2,
            height: edge * 2,
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
