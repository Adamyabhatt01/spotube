import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/artist/artist_card.dart';
import 'package:spotube/provider/metadata_plugin/artist/related.dart';

class ArtistPageRelatedArtists extends ConsumerWidget {
  final String artistId;
  const ArtistPageRelatedArtists({
    super.key,
    required this.artistId,
  });

  @override
  Widget build(BuildContext context, ref) {
    final relatedArtists =
        ref.watch(metadataPluginArtistRelatedArtistsProvider(artistId));

    return switch (relatedArtists) {
      AsyncData(value: final artists) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverGrid.builder(
            itemCount: artists.items.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: context.artistCardWidth,
              mainAxisExtent: playbuttonCardExtent(context, hasArtist: true),
              mainAxisSpacing: context.layoutGutter,
              crossAxisSpacing: context.layoutGutter,
            ),
            itemBuilder: (context, index) {
              final artist = artists.items.elementAt(index);
              return ArtistCard(artist);
            },
          ),
        ),
      AsyncError(:final error) => SliverToBoxAdapter(
          child: Center(
            child: Text(error.toString()),
          ),
        ),
      _ => const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}
