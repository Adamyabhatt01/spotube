import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';

/// Small rounded playlist cover shared by the sidebar pinned tiles and the
/// sidebar reorder dialog. Fixed edge in the button's existing icon slot —
/// it never changes the sidebar width.
class SidebarPinCover extends StatelessWidget {
  final String? imageUrl;
  final double side;

  const SidebarPinCover({
    required this.imageUrl,
    required this.side,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) return const Icon(SpotubeIcons.playlist);

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
