import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/playbutton_view/playbutton_view.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/controllers/use_shadcn_text_editing_controller.dart';
import 'package:spotube/hooks/utils/use_debounced_filter.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/radio/radio_station_rail.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';
import 'package:spotube/provider/radio/stations.dart';

/// Shared station-search slivers for the Radio page and the Search page's
/// radio scope, so the two can never diverge.
///
/// A custom hook (not a widget) because the result is a sliver list that the
/// owner spreads into its own scroll view. Owns its filter, query and station
/// watches; the owner only supplies the browse selections ([selectedTag] /
/// [selectedCountry] + callbacks), the outer [controller] for pagination, and
/// [showSearchRow] (the Radio page hides the row on mobile where the Search
/// tab owns entry; the Search page always shows it).
///
/// [showMusicShortcut] and [showRecentRail] let the Search page drop the
/// Radio page's leading Music shortcut and history rail without changing the
/// Radio page itself.
///
/// While a text query is typed the browse rails step aside and only the
/// matching grid shows — same rule as music search replacing Browse.
List<Widget> useStationSearchSlivers(
  BuildContext context,
  WidgetRef ref, {
  required ScrollController controller,
  bool showSearchRow = true,
  bool showMusicShortcut = true,
  bool showRecentRail = true,
  String? selectedTag,
  String? selectedCountry,
  required void Function(String? tag) onTag,
  required void Function(String? country) onCountry,
}) {
  final search = useDebouncedFilter();
  final searchController = useShadcnTextEditingController();
  final searchFocusNode = useFocusNode();

  // A typed search outranks a browse selection: the query is what the user
  // most recently asked for, and a lingering tag chip must not silently
  // filter the results they are looking at.
  final query = useMemoized(
    () => search.query.isNotEmpty
        ? (tag: null, country: null, search: search.query)
        : (
            tag: selectedTag,
            country: selectedCountry,
            search: null,
          ),
    [search.query, selectedTag, selectedCountry],
  );

  final stationsQuery = ref.watch(radioStationsProvider(query));
  final stationsNotifier = ref.watch(radioStationsProvider(query).notifier);
  final tags = ref.watch(radioTagsProvider);
  final countries = ref.watch(radioCountriesProvider);

  // Fixed genre rails. Tag choices verified against the live directory
  // (music ~5.3k stations, news ~3.1k — both top-tier tags that never come
  // back empty). Family-keyed like every other station query, so repeat
  // visits reuse the cached page instead of refetching.
  final musicStations = ref.watch(
    radioStationsProvider((tag: 'music', country: null, search: null)),
  );
  final newsStations = ref.watch(
    radioStationsProvider((tag: 'news', country: null, search: null)),
  );

  // Favorites and history feed the rails — both are local Drift `watch()`
  // subscriptions, not network, so keeping them live costs nothing.
  final favorites = ref.watch(radioFavoritesProvider);
  final recent = ref.watch(radioHistoryProvider);

  final scale = context.theme.scaling;

  // Same ceiling as the Browse bar: a fixed cap so the field stops reading
  // as a full-width band on wide windows, clamped to the viewport so a narrow
  // one shrinks it instead of overflowing. Search drops the leading Music
  // shortcut, so it gets the same 16px phone gutters as HomeSearchBar.
  final viewportWidth = MediaQuery.sizeOf(context).width;
  final isNarrow = viewportWidth < 640;
  final compactField = !showMusicShortcut && isNarrow;
  final horizontalGutter = compactField ? 16.0 : 20.0;
  final searchBarWidth = min(
    520.0,
    viewportWidth - (compactField ? 32.0 : 24.0),
  ).toDouble();

  // Anchor for the Popular rail's see-all: the full grid lives further down
  // the same scroll view, so "see all" reveals it instead of routing.
  final allStationsKey = useMemoized(() => GlobalKey());

  void scrollToAllStations() {
    final target = allStationsKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  final typing = search.query.isNotEmpty;
  final stations = stationsQuery.asData?.value;

  return [
    if (showSearchRow)
      // Same host pattern as Browse's HomeSearchBar (Row in a
      // SliverToBoxAdapter, 20x12 padding, 520 cap): the field scrolls
      // with the page instead of floating above it.
      SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showMusicShortcut) ...[
              const Gap(8),
              Button.outline(
                key: const ValueKey('radioMusicShortcut'),
                leading: const Icon(SpotubeIcons.music),
                onPressed: () => context.navigateTo(const HomeRoute()),
                child: const Text('Music'),
              ),
              const Gap(8),
            ],
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalGutter,
                  vertical: 12,
                ),
                // Align, not just ConstrainedBox: Expanded hands down a
                // tight width and only loosening it lets the field stop
                // at searchBarWidth (same as HomeSearchBar).
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: searchBarWidth),
                    child: Focus(
                      // Ancestor of the field, so it sees the keys the
                      // field leaves alone (same as HomeSearchBar).
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          searchFocusNode.unfocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: ListenableBuilder(
                        listenable: searchController,
                        builder: (context, _) {
                          return TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            onChanged: search.onChange,
                            // The filter is already live; submit just
                            // dismisses the keyboard.
                            onSubmitted: (_) => searchFocusNode.unfocus(),
                            placeholder: const Text('Search stations'),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16 * scale,
                              vertical: 12 * scale,
                            ),
                            borderRadius: context.theme.borderRadiusXxl,
                            filled: true,
                            textInputAction: TextInputAction.search,
                            features: [
                              const InputFeature.leading(
                                Icon(SpotubeIcons.search),
                              ),
                              InputFeature.trailing(
                                AnimatedCrossFade(
                                  duration: const Duration(milliseconds: 300),
                                  crossFadeState:
                                      searchController.text.isNotEmpty
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                  firstChild: IconButton.ghost(
                                    size: ButtonSize.small,
                                    icon: const Icon(SpotubeIcons.close),
                                    onPressed: () {
                                      searchController.clear();
                                      search.onChange('');
                                      searchFocusNode.unfocus();
                                    },
                                  ),
                                  secondChild: const SizedBox.square(
                                    dimension: 28,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    if (stationsQuery.hasError && stations == null)
      // A cold failure with no data to show: replace the results area
      // only, so the header, tabs and library stay reachable — a flaky
      // directory should not blank the whole page on a phone.
      SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorBox(
          error: stationsQuery.error!,
          onRetry: () => ref.invalidate(radioStationsProvider(query)),
        ),
      )
    else ...[
      if (!typing) ...[
        if ((favorites.asData?.value ?? const []).isNotEmpty)
          SliverToBoxAdapter(
            child: RadioStationRail(
              title: 'Your favorites',
              stations: favorites.asData?.value ?? const [],
            ),
          ),
        if (showRecentRail && (recent.asData?.value ?? const []).isNotEmpty)
          SliverToBoxAdapter(
            child: RadioStationRail(
              title: 'Recent',
              stations: recent.asData?.value ?? const [],
            ),
          ),
      ],
      // The Popular rail reuses the already-loaded first page — no extra
      // request. It only shows for the default (unfiltered) query: under a
      // tag, country or text filter the grid below already shows exactly
      // that content, so a rail of the same page would just duplicate it.
      if (!typing &&
          query.search == null &&
          query.tag == null &&
          query.country == null &&
          (stations?.items.take(10).toList() ?? const []).isNotEmpty)
        SliverToBoxAdapter(
          child: RadioStationRail(
            title: 'Popular stations',
            stations: stations!.items.take(10).toList(),
            onSeeAll: scrollToAllStations,
          ),
        ),
      if (!typing) ...[
        if ((musicStations.asData?.value.items ?? const []).isNotEmpty)
          SliverToBoxAdapter(
            child: RadioStationRail(
              title: 'Music',
              stations: musicStations.asData?.value.items.take(10).toList() ??
                  const [],
            ),
          ),
        if ((newsStations.asData?.value.items ?? const []).isNotEmpty)
          SliverToBoxAdapter(
            child: RadioStationRail(
              title: 'News',
              stations: newsStations.asData?.value.items.take(10).toList() ??
                  const [],
            ),
          ),
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RadioSectionHeader(title: 'Browse stations'),
              _BrowseRail(
                tags: tags,
                countries: countries,
                selectedTag: selectedTag,
                selectedCountry: selectedCountry,
                onTag: onTag,
                onCountry: onCountry,
              ),
            ],
          ),
        ),
      ],
      const SliverGap(10),
      SliverToBoxAdapter(
        child: RadioSectionHeader(
          key: allStationsKey,
          title: typing ? 'Results' : 'All stations',
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: PlaybuttonView(
          controller: controller,
          hasMore: stations?.hasMore == true,
          isLoading: stationsQuery.isLoading,
          onRequestMore: stationsNotifier.fetchMore,
          itemCount: stations?.items.length ?? 0,
          gridLoadingItem: const Skeletonizer(
            enabled: true,
            child: _RadioCardBone(),
          ),
          listLoadingItem: const Skeletonizer(
            enabled: true,
            child: _RadioTileBone(),
          ),
          gridItemBuilder: (context, index) {
            return RadioStationCard(station: stations!.items[index]);
          },
          listItemBuilder: (context, index) {
            return RadioStationTile(station: stations!.items[index]);
          },
        ),
      ),
    ],
  ];
}

/// Footer crediting the free directory that powers Radio. Radio Browser
/// requires attribution per its usage guidelines.
class RadioAttributionSliver extends StatelessWidget {
  const RadioAttributionSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          'Stations from radio-browser.info — a free, community-maintained '
          'directory of internet radio streams.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11 * context.theme.scaling,
            color: context.theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Horizontal tag chips plus a country dropdown for the browse axes, plus a
/// "Popular" reset that clears both selections.
///
/// Tags stay as chips (the list is short); countries go through a dropdown
/// because the directory can return up to 100 of them while the rail used to
/// truncate both axes to 30 chips. The dropdown writes the same country code
/// the chips used to, so the query/provider contract is unchanged.
class _BrowseRail extends StatelessWidget {
  const _BrowseRail({
    required this.tags,
    required this.countries,
    required this.selectedTag,
    required this.selectedCountry,
    required this.onTag,
    required this.onCountry,
  });

  final AsyncValue<List<RadioTag>> tags;
  final AsyncValue<List<RadioCountry>> countries;
  final String? selectedTag;
  final String? selectedCountry;
  final void Function(String? tag) onTag;
  final void Function(String? country) onCountry;

  @override
  Widget build(BuildContext context) {
    final tagList = tags.asData?.value ?? const [];
    final countryList = countries.asData?.value ?? const [];
    final isDefault = selectedTag == null && selectedCountry == null;
    // Show the rail's skeleton only while both axes are still resolving and
    // neither has produced a chip yet — once either lands, real chips are
    // better than placeholders.
    final loading = (tags.isLoading || countries.isLoading) &&
        tagList.isEmpty &&
        countryList.isEmpty;
    // Sentinel for "no country selected": Select needs a value matching one
    // of its options, and null is not a valid option value.
    const noCountry = '';
    final countryNames = {
      for (final country in countryList) country.code: country.name
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        spacing: 8,
        children: [
          _Chip(
            label: 'Popular',
            selected: isDefault,
            onPressed: () {
              onTag(null);
              onCountry(null);
            },
          ),
          if (loading)
            Skeletonizer(
              enabled: true,
              child: Row(
                spacing: 8,
                children: List.generate(8, (_) => const _ChipPlaceholder()),
              ),
            )
          else ...[
            for (final tag in tagList.take(30))
              _Chip(
                label: tag.name,
                selected: selectedTag == tag.name,
                onPressed: () =>
                    onTag(selectedTag == tag.name ? null : tag.name),
              ),
            if (countryList.isNotEmpty)
              Select<String>(
                value: selectedCountry ?? noCountry,
                onChanged: (value) {
                  if (value == null) return;
                  onCountry(value.isEmpty ? null : value);
                },
                itemBuilder: (context, value) => Text(
                  value.isEmpty
                      ? context.l10n.country
                      : countryNames[value] ?? value,
                ),
                popupConstraints: const BoxConstraints(maxWidth: 240),
                popupWidthConstraint: PopoverConstraint.flexible,
                popup: (context) {
                  return SelectPopup(
                    items: SelectItemBuilder(
                      childCount: countryList.length + 1,
                      builder: (context, index) {
                        if (index == 0) {
                          return SelectItemButton(
                            value: noCountry,
                            child: Text(context.l10n.none),
                          );
                        }
                        final country = countryList[index - 1];
                        return SelectItemButton(
                          value: country.code,
                          child: Text(
                            country.stationCount > 0
                                ? '${country.name} (${country.stationCount})'
                                : country.name,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// A single shimmering chip bar used by [_BrowseRail] while the tag and country
/// lists load. Wrapped in one [Skeletonizer] with the rest of the rail so the
/// group animates off a single controller rather than one per chip.
class _ChipPlaceholder extends StatelessWidget {
  const _ChipPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scale = context.theme.scaling;
    return Container(
      height: 30 * scale,
      width: 84 * scale,
      decoration: BoxDecoration(
        color: context.theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(context.pillCornerRadius),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? Button.secondary(onPressed: onPressed, child: Text(label))
        : Button.outline(onPressed: onPressed, child: Text(label));
  }
}

/// Shimmer bone matching [RadioStationCard]'s footprint: a square cover plus
/// two text bars. Plain containers (no providers, no interaction) so the
/// loading grid reads as incoming radio cards instead of playbutton cards.
class _RadioCardBone extends StatelessWidget {
  const _RadioCardBone();

  @override
  Widget build(BuildContext context) {
    final scale = context.theme.scaling;
    final coverSize = context.gridCardWidth;
    final bone = context.theme.colorScheme.muted;
    return SizedBox(
      width: coverSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              color: bone,
              borderRadius: BorderRadius.circular(context.cardCornerRadius),
            ),
          ),
          Gap(8 * scale),
          Container(
            height: 12 * scale,
            decoration: BoxDecoration(
              color: bone,
              borderRadius: BorderRadius.circular(context.pillCornerRadius),
            ),
          ),
          Gap(4 * scale),
          FractionallySizedBox(
            widthFactor: 0.7,
            child: Container(
              height: 10 * scale,
              decoration: BoxDecoration(
                color: bone,
                borderRadius: BorderRadius.circular(context.pillCornerRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer bone matching [RadioStationTile]'s row: a square cover plus two
/// text bars. Plain containers, like [_RadioCardBone].
class _RadioTileBone extends StatelessWidget {
  const _RadioTileBone();

  @override
  Widget build(BuildContext context) {
    final scale = context.theme.scaling;
    final bone = context.theme.colorScheme.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 50 * scale,
            height: 50 * scale,
            decoration: BoxDecoration(
              color: bone,
              borderRadius: BorderRadius.circular(context.cardCornerRadius),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12 * scale,
                  decoration: BoxDecoration(
                    color: bone,
                    borderRadius:
                        BorderRadius.circular(context.pillCornerRadius),
                  ),
                ),
                Gap(4 * scale),
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: Container(
                    height: 10 * scale,
                    decoration: BoxDecoration(
                      color: bone,
                      borderRadius:
                          BorderRadius.circular(context.pillCornerRadius),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
