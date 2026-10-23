import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/connect/connect_device.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/home/home_search_results.dart';
import 'package:spotube/modules/home/sections/featured.dart';
import 'package:spotube/modules/home/sections/sections.dart';
import 'package:spotube/modules/home/sections/new_releases.dart';
import 'package:spotube/modules/home/sections/recent.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

@RoutePage()
class HomePage extends HookConsumerWidget {
  static const name = "home";
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final controller = useScrollController();
    final mediaQuery = MediaQuery.of(context);
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    // Non-blank term replaces the Browse sections inline with search
    // results; clearing it restores Browse. No navigation involved.
    // On mobile the Search tab owns search: the inline row (and its inline
    // results) hides wherever the bottom bar is visible, so Browse stays
    // pure browse and the term can only be edited on the Search page.
    final searching =
        ref.watch(searchTermStateProvider.select((s) => s.trim().isNotEmpty));
    final showInlineSearch = !isBottomNavVisible(mediaQuery.size, layoutMode);
    final themeDefinition = ref.watch(themeDefinitionProvider).asData?.value;
    final isStage =
        themeDefinition?.layout.player.dock == ThemePlayerDock.stage;
    final hasHomeBefore = themeUiSlotExists(ref, 'home.before_sections');
    final hasHomeAfter = themeUiSlotExists(ref, 'home.after_sections');

    return SafeArea(
        bottom: false,
        child: Scaffold(
          child: CustomScrollView(
            controller: controller,
            slivers: [
              if (mediaQuery.smAndDown || layoutMode == LayoutMode.compact)
                SliverAppBar(
                  floating: true,
                  title: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: "Cookie",
                      fontSize: 30,
                      letterSpacing: 1.8,
                      color: theme.colorScheme.foreground,
                    ),
                    child: const Text("Spotube"),
                  ),
                  backgroundColor: theme.colorScheme.background,
                  foregroundColor: theme.colorScheme.foreground,
                  actions: [
                    const ConnectDeviceButton(),
                    const Gap(10),
                    IconButton.ghost(
                      icon: const Icon(SpotubeIcons.settings, size: 20),
                      onPressed: () {
                        context.navigateTo(const SettingsRoute());
                      },
                    ),
                    const Gap(10),
                  ],
                ),
              if (showInlineSearch)
                const SliverToBoxAdapter(child: HomeSearchBar()),
              if (searching && showInlineSearch)
                const SliverFillRemaining(
                  hasScrollBody: true,
                  child: HomeSearchResults(),
                )
              else ...[
                if (hasHomeBefore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: ThemeSlot(
                        'home.before_sections',
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                      ),
                    ),
                  ),
                if (isStage) const SliverToBoxAdapter(child: ThemeUiStage()),
                SliverList.builder(
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return switch (index) {
                      // 0 => const HomeGenresSection(),
                      0 => const HomeRecentlyPlayedSection(),
                      1 => const HomeFeaturedSection(),
                      // 3 => const HomePageFriendsSection(),
                      _ => const HomeNewReleasesSection()
                    };
                  },
                ),
                const SliverSafeArea(sliver: HomePageBrowseSection()),
                if (hasHomeAfter)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
                      child: ThemeSlot(
                        'home.after_sections',
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ));
  }
}
