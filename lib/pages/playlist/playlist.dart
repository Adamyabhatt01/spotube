import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/components/dialogs/prompt_dialog.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/track_presentation.dart';
import 'package:spotube/components/track_presentation/use_is_user_playlist.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/connectivity_adapter.dart';

@RoutePage()
class PlaylistPage extends HookConsumerWidget {
  static const name = "playlist";

  final SpotubeSimplePlaylistObject _playlist;
  final String id;
  const PlaylistPage({
    super.key,
    @PathParam("id") required this.id,
    required SpotubeSimplePlaylistObject playlist,
  }) : _playlist = playlist;

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref
            .watch(
              metadataPluginSavedPlaylistsProvider.select(
                (value) => value.whenData(
                  (value) =>
                      value.items.firstWhereOrNull((s) => s.id == _playlist.id),
                ),
              ),
            )
            .asData
            ?.value ??
        _playlist;

    final tracks = ref.watch(metadataPluginPlaylistTracksProvider(playlist.id));
    final tracksNotifier =
        ref.watch(metadataPluginPlaylistTracksProvider(playlist.id).notifier);
    final isFavoritePlaylist =
        ref.watch(metadataPluginIsSavedPlaylistProvider(playlist.id));

    final favoritePlaylistsNotifier =
        ref.watch(metadataPluginSavedPlaylistsProvider.notifier);

    final isUserPlaylist = useIsUserPlaylist(ref, playlist.id);

    // A mirrored playlist is kept in sync by the page that shows it. Listening
    // instead of watching: this is a side effect on the first page arriving, and
    // must not rebuild the page every time the mirror writes.
    ref.listen(
      metadataPluginPlaylistTracksProvider(playlist.id),
      (previous, next) {
        final page = next.asData?.value;
        // Only the arrival of data, not the pages the user scrolls through —
        // the mirror walks the rest of the collection itself.
        if (page == null || previous is AsyncData) return;
        unawaited(
          ref.read(playlistMirrorServiceProvider).reconcile(
                playlist,
                page,
                (offset, limit) => tracksNotifier.fetch(offset, limit),
              ),
        );
      },
    );

    // What the mirror holds for this playlist: every track it has a payload
    // for — which is every track ever downloaded from it — in Spotify's order.
    // Shown while the network view is not available rather than on top of it, so
    // a playlist that was never mirrored keeps showing exactly what it did.
    final cachedTracks =
        ref.watch(mirroredPlaylistTracksProvider(playlist.id)).asData?.value ??
            const [];
    final hasFreshTracks = tracks.asData != null;
    final visibleTracks =
        hasFreshTracks ? tracks.asData!.value.items : cachedTracks;

    // Offline the network view will never arrive: the auth check that gates
    // it is stuck. Showing its spinner over a mirror that has already
    // loaded would tell the user the page is still working when it isn't.
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;

    return material.RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(metadataPluginPlaylistTracksProvider(playlist.id));
        // The favorite state lives in its own per-id provider; refreshing this
        // page must not rebuild the whole saved-playlists library just to
        // re-check one heart.
        ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlist.id));
      },
      child: TrackPresentation(
        options: TrackPresentationOptions(
          collection: playlist,
          image: playlist.images.asUrlString(
            placeholder: ImagePlaceholder.collection,
          ),
          pagination: PaginationProps(
            hasNextPage: tracks.asData?.value.hasMore ?? false,
            isLoading: isOnline &&
                ((!hasFreshTracks && tracks.isLoading) ||
                    tracks.isLoadingNextPage),
            onFetchMore: tracksNotifier.fetchMore,
            onRefresh: () async {
              ref.invalidate(metadataPluginPlaylistTracksProvider(playlist.id));
            },
            onFetchAll: () async {
              return await tracksNotifier.fetchAll();
            },
          ),
          title: playlist.name,
          description: playlist.description,
          owner: playlist.owner.name,
          ownerImage: playlist.owner.images.lastOrNull?.url,
          tracks: visibleTracks,
          error: hasFreshTracks || cachedTracks.isEmpty ? tracks.error : null,
          routePath: '/playlist/${playlist.id}',
          isLiked: isFavoritePlaylist.asData?.value ?? false,
          shareUrl: playlist.externalUri,
          onHeart: isFavoritePlaylist.asData?.value == null
              ? null
              : () async {
                  final confirmed = isUserPlaylist
                      ? await showPromptDialog(
                          context: context,
                          title: context.l10n.delete_playlist,
                          message: context.l10n.delete_playlist_confirmation,
                        )
                      : true;
                  if (!confirmed) return null;

                  if (isFavoritePlaylist.asData!.value) {
                    if (isUserPlaylist) {
                      await favoritePlaylistsNotifier.delete(playlist.id);
                    } else {
                      await favoritePlaylistsNotifier.removeFavorite(playlist);
                    }
                  } else {
                    await favoritePlaylistsNotifier.addFavorite(playlist);
                  }
                  return isUserPlaylist;
                },
        ),
      ),
    );
  }
}
