import 'package:auto_route/auto_route.dart';
import 'package:auto_size_text/auto_size_text.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';

import 'package:spotube/provider/blacklist_provider.dart';

class ArtistCard extends HookConsumerWidget {
  final SpotubeFullArtistObject artist;
  const ArtistCard(this.artist, {super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    // Every fixed number here has to scale: the row this card sits in sizes
    // itself off the same factor, and the name/badges below already grow with
    // the theme.
    final scale = context.theme.scaling;
    final avatarSize = context.artistAvatarSize;
    final backgroundImage = UniversalImage.imageProvider(
      // Phase 2 perf (IMG.2): decode at 2x the avatar display size, so a theme
      // that widens artist cards gets sharp art rather than an upscale.
      artist.images.asUrlString(
        placeholder: ImagePlaceholder.artist,
      ),
      height: avatarSize * 2,
      width: avatarSize * 2,
    );
    final isBlackListed = ref.watch(
      blacklistedIdsProvider.select((ids) => ids.contains(artist.id)),
    );

    return SizedBox(
      width: context.artistCardWidth,
      child: Button.card(
        onPressed: () {
          context.navigateTo(ArtistRoute(artistId: artist.id));
        },
        child: Column(
          children: [
            Avatar(
              initials: artist.name.trim()[0].toUpperCase(),
              provider: backgroundImage,
              size: avatarSize,
            ),
            Gap(10 * scale),
            // Takes the slack the badge row used to get from a Spacer: the name
            // shrinks to fit a short cell instead of pushing the badge out of
            // it.
            Expanded(
              child: AutoSizeText(
                artist.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.bold,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isBlackListed == true) ...[
                  DestructiveBadge(
                    child: Text(context.l10n.blacklisted.toUpperCase()),
                  ),
                  const Gap(5),
                ],
                SecondaryBadge(
                  child: Text(context.l10n.artist.toUpperCase()),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
