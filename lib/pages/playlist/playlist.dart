import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' hide Page;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/components/dialogs/prompt_dialog.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/track_presentation.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
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
    // Use the object the route was opened with. Watching the saved-playlists
    // collection here built (and background-revalidated) the entire library on
    // every playlist open, just to refresh one name/cover. Live edits are rare
    // and the next open (or a pull-to-refresh of the list) picks them up.
    final playlist = _playlist;

    final tracks = ref.watch(metadataPluginPlaylistTracksProvider(playlist.id));
    final tracksNotifier =
        ref.watch(metadataPluginPlaylistTracksProvider(playlist.id).notifier);
    final isFavoritePlaylist =
        ref.watch(metadataPluginIsSavedPlaylistProvider(playlist.id));

    // Ownership comes from the playlist and the already-cached current user,
    // not from membership in the saved-playlists list. The old provider walked
    // that whole list on page open.
    final currentUserId = ref.watch(
      metadataPluginUserProvider.select((value) => value.asData?.value?.id),
    );
    final isUserPlaylist =
        currentUserId != null && playlist.owner.id == currentUserId;

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
    // Watched only in that case: while the network has answered this page would
    // rebuild on every download-progress tick of the mirror stream just to throw
    // the result away. The presentation state keeps its own subscription for the
    // offline list, so nothing here stops the mirror from being ready to show.
    final hasFreshTracks = tracks.asData != null;
    final cachedTracks = hasFreshTracks
        ? const <SpotubeFullTrackObject>[]
        : ref
                .watch(mirroredPlaylistTracksProvider(playlist.id))
                .asData
                ?.value ??
            const [];
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
          owner: playlist.owner.name.isEmpty ? null : playlist.owner.name,
          ownerImage: playlist.owner.images.lastOrNull?.url,
          tracks: visibleTracks,
          error: hasFreshTracks || cachedTracks.isEmpty ? tracks.error : null,
          routePath: '/playlist/${playlist.id}',
          isLiked: isFavoritePlaylist.asData?.value ?? false,
          isUserPlaylist: isUserPlaylist,
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

                  // Read on demand: watching the notifier in build used to
                  // construct the saved-playlists library on every page open.
                  final favoritePlaylistsNotifier =
                      ref.read(metadataPluginSavedPlaylistsProvider.notifier);

                  if (isFavoritePlaylist.asData!.value) {
                    if (isUserPlaylist) {
                      await favoritePlaylistsNotifier.delete(playlist.id);
                      // The playlist is gone: remove its mirror metadata and
                      // both order entries, but never its downloaded files.
                      await ref
                          .read(playlistMirrorServiceProvider)
                          .forget(playlist.id);
                      ref
                          .read(userPreferencesProvider.notifier)
                          .removePlaylistFromOrders(playlist.id);
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
