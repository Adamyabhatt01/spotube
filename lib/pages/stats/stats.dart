import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/modules/stats/summary/summary.dart';
import 'package:spotube/modules/stats/top/top.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/history/summary.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/top/albums.dart';
import 'package:spotube/provider/history/top/playlists.dart';
import 'package:spotube/provider/history/top/tracks.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class StatsPage extends HookConsumerWidget {
  static const name = "stats";

  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final hasContent = themeUiSlotExists(ref, 'stats.content');
    final period = ref.watch(playbackHistoryTopDurationProvider);
    final summary = hasContent
        ? ref.watch(playbackHistorySummaryProvider).asData?.value
        : null;
    final topTracks = hasContent
        ? (ref.watch(historyTopTracksProvider(period)).asData?.value.items ??
                const [])
            .map((entry) => entry.track)
            .toList()
        : const [];
    final topAlbums = hasContent
        ? (ref.watch(historyTopAlbumsProvider(period)).asData?.value.items ??
                const [])
            .map((entry) => entry.album)
            .toList()
        : const [];
    final topPlaylists = hasContent
        ? (ref.watch(historyTopPlaylistsProvider(period)).asData?.value.items ??
                const [])
            .map((entry) => entry.playlist)
            .toList()
        : const [];

    return PopScope(
      canPop: false,
      // `didPop == true` means the router deleted this page out of its stack,
      // not that the user asked to leave; see library.dart's handler.
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.navigateTo(const HomeRoute());
      },
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          headers: [
            if (kTitlebarVisible)
              const TitleBar(automaticallyImplyLeading: false),
          ],
          child: ThemePageContent(
            slot: 'stats.content',
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            bindings: {
              'stats.period': period.name,
              'stats.minutes': summary?.duration.inMinutes ?? 0,
              'stats.tracks': summary?.tracks ?? 0,
              'stats.artists': summary?.artists ?? 0,
              'stats.albums': summary?.albums ?? 0,
              'stats.playlists': summary?.playlists ?? 0,
              'stats.fees': summary?.fees ?? 0,
              'stats.topTracks': topTracks,
              'stats.topAlbums': topAlbums,
              'stats.topPlaylists': topPlaylists,
            },
            fallback: CustomScrollView(
              slivers: [
                if (kIsMacOS) const SliverGap(20),
                const StatsPageSummarySection(),
                const StatsPageTopSection(),
                const SliverToBoxAdapter(
                  child: SafeArea(
                    child: SizedBox(),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
