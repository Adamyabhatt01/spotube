import 'package:flutter/material.dart' as material;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:spotube/components/button/back_button.dart';

import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/artist/artist_album_list.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';

import 'package:spotube/pages/artist/section/footer.dart';
import 'package:spotube/pages/artist/section/header.dart';
import 'package:spotube/pages/artist/section/related_artists.dart';
import 'package:spotube/pages/artist/section/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/artist/albums.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/provider/metadata_plugin/artist/related.dart';
import 'package:spotube/provider/metadata_plugin/artist/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/artist/wikipedia.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';

@RoutePage()
class ArtistPage extends HookConsumerWidget {
  static const name = "artist";

  final String artistId;
  const ArtistPage(
    @PathParam("id") this.artistId, {
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final scrollController = useScrollController();

    final artistQuery = ref.watch(metadataPluginArtistProvider(artistId));

    // The three collections are only requested when a theme actually owns the
    // page body; the host tree fetches them section by section instead.
    final hasContent = themeUiSlotExists(ref, 'artist.content');
    final topTracks = hasContent
        ? ref
                .watch(metadataPluginArtistTopTracksProvider(artistId))
                .asData
                ?.value
                .items ??
            const <SpotubeFullTrackObject>[]
        : const <SpotubeFullTrackObject>[];
    final albums = hasContent
        ? ref
                .watch(metadataPluginArtistAlbumsProvider(artistId))
                .asData
                ?.value
                .items ??
            const <SpotubeSimpleAlbumObject>[]
        : const <SpotubeSimpleAlbumObject>[];
    final related = hasContent
        ? ref
                .watch(metadataPluginArtistRelatedArtistsProvider(artistId))
                .asData
                ?.value
                .items ??
            const <SpotubeFullArtistObject>[]
        : const <SpotubeFullArtistObject>[];
    final artist = artistQuery.asData?.value;
    final pageBindings = <String, Object?>{
      'artist.id': artistId,
      'artist.name': artist?.name ?? '',
      'artist.artwork': artist?.images.asUrlString(
            placeholder: ImagePlaceholder.artist,
          ) ??
          '',
      'artist.followers': artist?.followers ?? 0,
      'artist.genres': (artist?.genres ?? const []).join(', '),
      'artist.topTracks': topTracks,
      'artist.albums': albums,
      'artist.related': related,
    };
    final hasHeader = themeUiSlotExists(ref, 'artist.header');

    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: const [
          TitleBar(
            leading: [BackButton()],
            backgroundColor: Colors.transparent,
          )
        ],
        floatingHeader: true,
        child: material.RefreshIndicator.adaptive(
          onRefresh: () async {
            ref.invalidate(metadataPluginArtistProvider(artistId));
            ref.invalidate(
              metadataPluginArtistRelatedArtistsProvider(artistId),
            );
            ref.invalidate(metadataPluginArtistAlbumsProvider(artistId));
            ref.invalidate(metadataPluginIsSavedArtistProvider(artistId));
            ref.invalidate(metadataPluginArtistTopTracksProvider(artistId));
            if (artistQuery.hasValue) {
              final artist = artistQuery.asData!.value;
              ref.invalidate(
                artistWikipediaSummaryProvider(
                    (id: artist.id, name: artist.name)),
              );
            }
          },
          child: Builder(builder: (context) {
            if (artistQuery.hasError && artistQuery.asData?.value == null) {
              return Center(child: Text(artistQuery.error.toString()));
            }
            return Skeletonizer(
              enabled: artistQuery.isLoading,
              child: ThemePageContent(
                slot: 'artist.content',
                bindings: pageBindings,
                fallback: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    const SliverGap(material.kToolbarHeight),
                    SliverToBoxAdapter(
                      child: SafeArea(
                        bottom: false,
                        child: hasHeader
                            ? const ThemeSlot('artist.header')
                            : ArtistPageHeader(artistId: artistId),
                      ),
                    ),
                    const SliverGap(20),
                    ArtistPageTopTracks(artistId: artistId),
                    const SliverGap(20),
                    SliverToBoxAdapter(child: ArtistAlbumList(artistId)),
                    SliverPadding(
                      padding: const EdgeInsets.all(8.0),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          context.l10n.fans_also_like,
                          style: context.theme.typography.h4,
                        ),
                      ),
                    ),
                    ArtistPageRelatedArtists(artistId: artistId),
                    const SliverGap(20),
                    if (artistQuery.asData?.value != null)
                      SliverToBoxAdapter(
                        child:
                            ArtistPageFooter(artist: artistQuery.asData!.value),
                      ),
                    const SliverSafeArea(sliver: SliverGap(10)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
