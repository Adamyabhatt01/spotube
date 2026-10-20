import 'package:auto_route/auto_route.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/ui/button_tile.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/utils/primitive_utils.dart';

class StatsArtistItem extends StatelessWidget {
  final SpotubeSimpleArtistObject artist;
  final Widget info;
  const StatsArtistItem({
    super.key,
    required this.artist,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    return ButtonTile(
      style: ButtonVariance.ghost,
      title: Text(artist.name),
      leading: Avatar(
        initials: PrimitiveUtils.initialOf(artist.name),
        provider: UniversalImage.imageProvider(
          (artist.images).asUrlString(
            placeholder: ImagePlaceholder.artist,
          ),
        ),
      ),
      trailing: info,
      onPressed: () {
        context.navigateTo(ArtistRoute(artistId: artist.id));
      },
    );
  }
}
