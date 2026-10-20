import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/home/sections/new_releases.dart';
import 'package:spotube/modules/home/sections/sections.dart';
import 'package:spotube/modules/radio/radio_station_rail.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';

/// Blank-state landing for the music scope: recent searches as tappable
/// chips (tap submits the term) above the personalized Browse sections
/// (new artists based on taste, recommended songs) and new releases.
///
/// Search intentionally skips the home page's Recently Played rail; history
/// is not a recommendation. This is Search-only — Browse keeps its own
/// composition.
class SearchLandingMusic extends ConsumerWidget {
  const SearchLandingMusic({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Skip the Browse widget's "building your timeline" placeholder while
    // the personalized sections load: that branch was designed for the wide
    // Browse page and its single-line status row overflows on a phone.
    // New releases below keeps the landing useful until the rails arrive.
    final browseSections = ref.watch(metadataPluginBrowseSectionsProvider);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _RecentSearches()),
        if (!browseSections.isLoading) const HomePageBrowseSection(),
        const SliverToBoxAdapter(child: HomeNewReleasesSection()),
        const SliverSafeArea(sliver: SliverGap(24)),
      ],
    );
  }
}

/// Blank-state landing for the radio scope: favorites + history rails.
/// Both providers are local Drift watches (no network), and the rail
/// renders nothing on empty — same composition the Radio page uses.
class SearchLandingRadio extends ConsumerWidget {
  const SearchLandingRadio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(radioFavoritesProvider);
    final recent = ref.watch(radioHistoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioStationRail(
          title: 'Your favorites',
          stations: favorites.asData?.value ?? const [],
        ),
        RadioStationRail(
          title: 'Recent',
          stations: recent.asData?.value ?? const [],
        ),
      ],
    );
  }
}

class _RecentSearches extends ConsumerWidget {
  const _RecentSearches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(context.l10n.recent_searches)),
              const Spacer(),
              Button.text(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(context.l10n.clear_all),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in recents)
                Chip(
                  child: Text(term),
                  onPressed: () {
                    ref.read(searchTermStateProvider.notifier).state = term;
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
