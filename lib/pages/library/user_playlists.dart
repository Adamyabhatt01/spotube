import 'package:flutter/material.dart' as material;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Image;
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/assets.gen.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/hooks/utils/use_debounce.dart';
import 'package:spotube/components/playbutton_view/playbutton_view.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/playlist_create_dialog.dart';
import 'package:spotube/components/inter_scrollbar/inter_scrollbar.dart';
import 'package:spotube/components/fallbacks/anonymous_fallback.dart';
import 'package:spotube/modules/playlist/playlist_card.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/sidebar/sidebar_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

@RoutePage()
class UserPlaylistsPage extends HookConsumerWidget {
  static const name = 'user_playlists';
  const UserPlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final searchText = useState('');
    // Collapses a burst of keystrokes into one fuzzy pass; clearing the box
    // still filters instantly via the empty fast path below.
    final searchQuery = useDebounce(
      searchText.value,
      const Duration(milliseconds: 200),
    );
    final effectiveQuery = searchText.value.isEmpty ? '' : searchQuery;

    final authenticated = ref.watch(metadataPluginAuthenticatedProvider);

    final me = ref.watch(metadataPluginUserProvider);
    final playlistsQuery = ref.watch(metadataPluginSavedPlaylistsProvider);
    final playlistsQueryNotifier =
        ref.watch(metadataPluginSavedPlaylistsProvider.notifier);

    final likedTracksPlaylist = useMemoized(
      () => me.asData?.value == null
          ? null
          : SpotubeSimplePlaylistObject(
              id: "user-liked-tracks",
              name: context.l10n.liked_tracks,
              description: context.l10n.liked_tracks_description,
              externalUri: "",
              owner: me.asData!.value!,
              images: [
                  SpotubeImageObject(
                    url: Assets.images.likedTracks.path,
                    width: 300,
                    height: 300,
                  )
                ]),
      [context.l10n, me.asData?.value],
    );

    final mirroredPlaylists =
        ref.watch(mirroredPlaylistsProvider).asData?.value ?? const [];

    // Pins have no sidebar to live in on compact/mobile layouts, so the
    // Playlists page sorts them to the top instead. Watched by id list so
    // pin/unpin/reorder re-sorts live, in pin order.
    final pinnedIds = ref.watch(
      userPreferencesProvider.select((s) => s.pinnedPlaylistIds),
    );

    // Offline the disk snapshot still lists every Spotify playlist the user
    // ever saved, but only the mirrored ones can render their songs. Showing
    // the rest as tappable cards is a promise the page cannot keep.
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;

    final playlists = useMemoized(
      () {
        final online = isOnline
            ? [
                if (likedTracksPlaylist != null) likedTracksPlaylist,
                ...?playlistsQuery.asData?.value.items,
              ]
            : const <SpotubeSimplePlaylistObject>[];
        // A downloaded playlist is usually also in the Spotify list, so the
        // mirror rows only have to supply what the network did not: merged by
        // id, never a second card for one playlist.
        final seen = online.map((playlist) => playlist.id).toSet();
        final combined = [
          ...online,
          for (final mirrored in mirroredPlaylists)
            if (seen.add(mirrored.id)) mirrored,
        ];
        if (effectiveQuery.isEmpty) {
          // Pinned first in pin order; search ranking bypasses this entirely.
          return pinnedFirstPlaylists(combined, pinnedIds);
        }
        return combined
            .map((e) => (weightedRatio(e.name, effectiveQuery), e))
            .sorted((a, b) => b.$1.compareTo(a.$1))
            .where((e) => e.$1 > 50)
            .map((e) => e.$2)
            .toList();
      },
      [
        playlistsQuery,
        effectiveQuery,
        searchText.value.isEmpty,
        mirroredPlaylists,
        isOnline,
        pinnedIds,
      ],
    );

    final controller = useScrollController();

    if (playlistsQuery.error
        case MetadataPluginException(
          errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
          message: _,
        )) {
      return const Center(child: NoDefaultMetadataPlugin());
    }

    // A mirrored playlist is entirely local; nothing about it depends on
    // Spotify answering. When the auth gate cannot be reached — offline, or
    // a token refresh still in flight — the mirror still has to render.
    if (authenticated.asData?.value != true && mirroredPlaylists.isEmpty) {
      return const AnonymousFallback();
    }

    // The failure still hides the page for anyone with nothing cached, but a
    // mirrored playlist lives in the database and is exactly what an offline
    // visit came to find.
    if (playlistsQuery.hasError && mirroredPlaylists.isEmpty) {
      return ErrorBox(
        error: playlistsQuery.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSavedPlaylistsProvider);
        },
      );
    }

    return material.RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(metadataPluginSavedPlaylistsProvider);
      },
      child: SafeArea(
        bottom: false,
        child: InterScrollbar(
          controller: controller,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              SliverAppBar(
                automaticallyImplyLeading: false,
                floating: true,
                backgroundColor: context.theme.colorScheme.background,
                flexibleSpace: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  height: 48,
                  child: TextField(
                    onChanged: (value) => searchText.value = value,
                    placeholder: Text(context.l10n.filter_playlists),
                    features: const [
                      InputFeature.leading(Icon(SpotubeIcons.filter)),
                    ],
                  ),
                ),
              ),
              const SliverGap(10),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: PlaybuttonView(
                  leading: const Expanded(
                    child: Row(
                      children: [
                        PlaylistCreateDialogButton(),
                        // const Gap(10),
                        // Button.primary(
                        //   leading: const Icon(SpotubeIcons.magic),
                        //   child: Text(context.l10n.generate),
                        //   onPressed: () {
                        //     context.navigateTo(const PlaylistGeneratorRoute());
                        //   },
                        // ),
                        // const Gap(10),
                      ],
                    ),
                  ),
                  controller: controller,
                  hasMore: playlistsQuery.asData?.value.hasMore == true,
                  isLoading: isOnline && playlistsQuery.isLoading,
                  onRequestMore: playlistsQueryNotifier.fetchMore,
                  itemCount: playlists.length,
                  gridItemBuilder: (context, index) {
                    return PlaylistCard(playlists[index]);
                  },
                  listItemBuilder: (context, index) {
                    return PlaylistCard.tile(playlists[index]);
                  },
                ),
              ),
              const SliverSafeArea(sliver: SliverGap(10)),
            ],
          ),
        ),
      ),
    );
  }
}
