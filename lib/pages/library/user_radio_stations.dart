import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/inter_scrollbar/inter_scrollbar.dart';
import 'package:spotube/components/playbutton_view/playbutton_view.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/utils/use_debounced_filter.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/provider/radio/favorites.dart';

/// The stations the user bookmarked with the heart on a station card.
///
/// The heart already saved these - they were only reachable from the Radio
/// page's own rail, which meant there was nowhere to review the list or drop
/// one. This is that place, next to the playlists in the library.
///
/// The list is served from the local snapshot table, so it renders offline and
/// the stream URL is re-resolved through the directory when a station plays.
@RoutePage()
class UserRadioStationsPage extends HookConsumerWidget {
  static const name = 'user_radio_stations';

  const UserRadioStationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useDebouncedFilter();
    final favorites = ref.watch(radioFavoritesProvider);

    final stations = useMemoized(
      () {
        final all = favorites.asData?.value ?? const <RadioStation>[];
        final needle = search.query.trim().toLowerCase();
        if (needle.isEmpty) return all;
        return all
            .where(
              (station) =>
                  station.name.toLowerCase().contains(needle) ||
                  (station.subtitle ?? '').toLowerCase().contains(needle),
            )
            .toList();
      },
      [favorites.asData?.value, search.query],
    );

    final controller = useScrollController();

    return SafeArea(
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
                  onChanged: search.onChange,
                  placeholder: Text(context.l10n.filter_stations),
                  features: const [
                    InputFeature.leading(Icon(SpotubeIcons.filter)),
                  ],
                ),
              ),
            ),
            const SliverGap(10),
            // Only the "nothing saved yet" case gets its own message: a
            // filter that matched nothing falls through to the grid, which
            // says so itself.
            if (!favorites.isLoading &&
                (favorites.asData?.value ?? const <RadioStation>[]).isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        Icon(
                          SpotubeIcons.radio,
                          size: 40 * context.theme.scaling,
                          color: context.theme.colorScheme.mutedForeground,
                        ),
                        Text(
                          context.l10n.no_saved_stations,
                          textAlign: TextAlign.center,
                        ).muted().small(),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: PlaybuttonView(
                  controller: controller,
                  hasMore: false,
                  isLoading: favorites.isLoading,
                  onRequestMore: () {},
                  itemCount: stations.length,
                  gridItemBuilder: (context, index) =>
                      RadioStationCard(station: stations[index]),
                  listItemBuilder: (context, index) =>
                      RadioStationTile(station: stations[index]),
                ),
              ),
            const SliverSafeArea(sliver: SliverGap(10)),
          ],
        ),
      ),
    );
  }
}
