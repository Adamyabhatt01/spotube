import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/pages/radio/station_search.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

@RoutePage()
class RadioScreen extends HookConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    // The Search tab is the only mobile entry: hide the search row (Music
    // shortcut + station filter) wherever the bottom bar is visible.
    // Desktop keeps it. Note this also removes mobile station text-filter;
    // tag/country browse still works there — and the Search page's radio
    // scope restores full station search on mobile.
    final showSearchRow = !isBottomNavVisible(
      MediaQuery.sizeOf(context),
      layoutMode,
    );
    final selectedTag = useState<String?>(null);
    final selectedCountry = useState<String?>(null);

    final controller = useScrollController();

    // The page is a single scroll: the shared station search (field, rails,
    // filter and grid) is the whole content above the attribution footer.
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          ...useStationSearchSlivers(
            context,
            ref,
            controller: controller,
            showSearchRow: showSearchRow,
            selectedTag: selectedTag.value,
            selectedCountry: selectedCountry.value,
            onTag: (tag) {
              selectedCountry.value = null;
              selectedTag.value = tag;
            },
            onCountry: (country) {
              selectedTag.value = null;
              selectedCountry.value = country;
            },
          ),
          const RadioAttributionSliver(),
          const SliverSafeArea(sliver: SliverGap(24)),
        ],
      ),
    );
  }
}
