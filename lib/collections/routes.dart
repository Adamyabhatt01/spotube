import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/services/kv_store/kv_store.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Routes inside the shell swap without ever overlapping.
const _swapNow = CustomRouteType(
  durationInMilliseconds: 0,
  reverseDurationInMilliseconds: 0,
);

/// Gives every route in [routes] a transition that cannot overlap the route it
/// is replacing.
///
/// The shell owns the ground: `ThemeBackgroundLayer` paints behind the router
/// slot and `ThemeBackgroundScope` hands every `Scaffold` a transparent
/// background. Two routes alive at once are therefore *both* visible, and
/// auto_route's default 300ms Material transition keeps the outgoing route
/// mounted and painting for its entire duration — the previous page shows
/// through the new one, which is the after-image on every tab switch. There is
/// no opaque ground to crossfade against, so a real transition cannot be
/// salvaged here; what goes instead is the overlap window.
///
/// Routes outside the shell keep theirs: the queue/sources/lyrics sheets slide
/// up *over* content, and that overlap is the whole point.
List<AutoRoute> swapWithoutOverlap(List<AutoRoute> routes) {
  return [
    for (final route in routes) route.copyWith(type: _swapNow),
  ];
}

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  final WidgetRef ref;

  AppRouter(this.ref) : super(navigatorKey: rootNavigatorKey);

  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: RootAppRoute.page,
          path: "/",
          initial: true,
          children: swapWithoutOverlap([
            AutoRoute(
              path: "home",
              page: HomeRoute.page,
              initial: true,
              guards: [
                AutoRouteGuardCallback(
                  (resolver, router) async {
                    final authenticated = await ref
                        .read(metadataPluginAuthenticatedProvider.future);

                    if (!authenticated && !KVStoreService.doneGettingStarted) {
                      resolver.redirect(const GettingStartedRoute());
                    } else {
                      resolver.next(true);
                    }
                  },
                ),
              ],
            ),
            AutoRoute(
              path: "home/sections/:sectionId",
              page: HomeBrowseSectionItemsRoute.page,
            ),
            AutoRoute(
              path: "search",
              page: SearchRoute.page,
            ),
            AutoRoute(
              path: "library",
              page: LibraryRoute.page,
              children: swapWithoutOverlap([
                AutoRoute(
                  path: "playlists",
                  page: UserPlaylistsRoute.page,
                ),
                AutoRoute(
                  path: "artists",
                  page: UserArtistsRoute.page,
                ),
                AutoRoute(
                  path: "albums",
                  page: UserAlbumsRoute.page,
                ),
                AutoRoute(
                  path: "stations",
                  page: UserRadioStationsRoute.page,
                ),
                AutoRoute(
                  path: "local",
                  page: UserLocalLibraryRoute.page,
                ),
                AutoRoute(
                  path: "downloads",
                  page: UserDownloadsRoute.page,
                ),
              ]),
            ),
            AutoRoute(
              path: "local/folder",
              page: LocalLibraryRoute.page,
              // parentNavigatorKey: shellRouteNavigatorKey,
            ),
            AutoRoute(
              path: "lyrics",
              page: LyricsRoute.page,
            ),
            AutoRoute(
              path: "radio",
              page: RadioRoute.page,
            ),
            AutoRoute(
              path: "settings",
              page: SettingsRoute.page,
            ),
            AutoRoute(
              path: "settings/metadata-provider",
              page: SettingsMetadataProviderRoute.page,
            ),
            AutoRoute(
              path: "settings/metadata-provider/metadata-form",
              page: SettingsMetadataProviderFormRoute.page,
            ),
            AutoRoute(
              path: "settings/blacklist",
              page: BlackListRoute.page,
            ),
            AutoRoute(
              path: "settings/equalizer",
              page: SettingsEqualizerRoute.page,
            ),
            if (!kIsWeb)
              AutoRoute(
                path: "settings/logs",
                page: LogsRoute.page,
              ),
            AutoRoute(
              path: "settings/about",
              page: AboutSpotubeRoute.page,
            ),
            AutoRoute(
              path: "settings/scrobbling",
              page: SettingsScrobblingRoute.page,
            ),
            AutoRoute(
              path: "album/:id",
              page: AlbumRoute.page,
            ),
            AutoRoute(
              path: "artist/:id",
              page: ArtistRoute.page,
            ),
            AutoRoute(
              path: "liked-tracks",
              page: LikedPlaylistRoute.page,
            ),
            AutoRoute(
              path: "playlist/:id",
              page: PlaylistRoute.page,
              guards: [
                AutoRouteGuard.redirect(
                  (resolver) {
                    final PlaylistRouteArgs(:id, :playlist) =
                        resolver.route.args as PlaylistRouteArgs;
                    if (id == "user-liked-tracks") {
                      return LikedPlaylistRoute(playlist: playlist);
                    }

                    return null;
                  },
                ),
              ],
            ),
            AutoRoute(
              path: "track/:id",
              page: TrackRoute.page,
            ),
            AutoRoute(
              path: "connect",
              page: ConnectRoute.page,
            ),
            AutoRoute(
              path: "connect/control",
              page: ConnectControlRoute.page,
            ),
            AutoRoute(
              path: "profile",
              page: ProfileRoute.page,
            ),
            AutoRoute(
              path: "stats",
              page: StatsRoute.page,
            ),
            AutoRoute(
              path: "stats/minutes",
              page: StatsMinutesRoute.page,
            ),
            AutoRoute(
              path: "stats/streams",
              page: StatsStreamsRoute.page,
            ),
            AutoRoute(
              path: "stats/fees",
              page: StatsStreamFeesRoute.page,
            ),
            AutoRoute(
              path: "stats/artists",
              page: StatsArtistsRoute.page,
            ),
            AutoRoute(
              path: "stats/albums",
              page: StatsAlbumsRoute.page,
            ),
            AutoRoute(
              path: "stats/playlists",
              page: StatsPlaylistsRoute.page,
            ),
          ]),
        ),
        CustomRoute(
          transitionsBuilder: TransitionsBuilders.slideBottom,
          durationInMilliseconds: 200,
          reverseDurationInMilliseconds: 200,
          path: "/player/queue",
          page: PlayerQueueRoute.page,
        ),
        CustomRoute(
          transitionsBuilder: TransitionsBuilders.slideBottom,
          durationInMilliseconds: 200,
          reverseDurationInMilliseconds: 200,
          path: "/player/sources",
          page: PlayerTrackSourcesRoute.page,
        ),
        CustomRoute(
          transitionsBuilder: TransitionsBuilders.slideBottom,
          durationInMilliseconds: 200,
          reverseDurationInMilliseconds: 200,
          path: "/player/lyrics",
          page: PlayerLyricsRoute.page,
        ),
        AutoRoute(
          path: "/getting-started",
          page: GettingStartedRoute.page,
          // parentNavigatorKey: rootNavigatorKey,
        ),
        AutoRoute(
          path: "/lastfm-login",
          page: LastFMLoginRoute.page,
          // parentNavigatorKey: rootNavigatorKey,
        ),
      ];
}
