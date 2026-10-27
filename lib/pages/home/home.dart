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
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/modules/theme_shell/theme_branding.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/history/recent.dart';
import 'package:spotube/provider/metadata_plugin/album/releases.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
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
    final isStage = context.layout.player.dock == ThemePlayerDock.stage;
    final hasHomeBefore = themeUiSlotExists(ref, 'home.before_sections');
    final hasHomeAfter = themeUiSlotExists(ref, 'home.after_sections');
    final branding = useMemoized(
      () => ThemeBranding.from(themeDefinition),
      [themeDefinition],
    );

    // A non-empty section list is the theme's surface; otherwise the host
    // order is kept whole.
    final layout = context.layout;
    final homeSections = useMemoized(
      () => resolveThemeSections(
        defaults: const ['recent', 'featured', 'new_releases', 'browse'],
        block: layout.home,
      ),
      [layout],
    );

    // The whole body can belong to the theme. The host still supplies the
    // feed it would have drawn: recent items, new releases and browse
    // sections, each as typed objects the theme's lists can iterate.
    final hasHomeContent = themeUiSlotExists(ref, 'home.content');
    // The fallback list must be typed: `const []` widens the loop variable to
    // `dynamic`, and an extension getter (`entry.playlist`) is not visible
    // through dynamic dispatch. That turned every non-empty history into a
    // NoSuchMethodError at build time.
    final recentHistory =
        ref.watch(recentlyPlayedItems).asData?.value ??
            const <HistoryTableData>[];
    final recentItems = hasHomeContent
        ? [
            for (final entry in recentHistory)
              if (entry.playlist != null)
                entry.playlist!
              else if (entry.album != null)
                entry.album!,
          ]
        : const <Object>[];
    final newReleases = hasHomeContent
        ? (ref.watch(metadataPluginAlbumReleasesProvider).asData?.value.items ??
            const <SpotubeSimpleAlbumObject>[])
        : const <SpotubeSimpleAlbumObject>[];
    final browseSections = hasHomeContent
        ? (ref
                .watch(metadataPluginBrowseSectionsProvider)
                .asData
                ?.value
                .items ??
            const <SpotubeBrowseSectionObject<Object>>[])
        : const <SpotubeBrowseSectionObject<Object>>[];
    final homeBindings = <String, Object?>{
      'home.greeting': greetingFor(DateTime.now()),
      'home.recent': recentItems,
      'home.newReleases': newReleases,
      'home.browse': [
        for (final section in browseSections)
          {
            'id': section.id,
            'title': section.title,
            'browseMore': section.browseMore,
            'items': section.items,
          },
      ],
      'home.hasRecent': recentItems.isNotEmpty,
      'home.hasNewReleases': newReleases.isNotEmpty,
      'home.hasBrowse': browseSections.isNotEmpty,
    };

    return SafeArea(
        bottom: false,
        child: Scaffold(
          child: ThemePageContent(
            slot: 'home.content',
            bindings: homeBindings,
            fallback: CustomScrollView(
              controller: controller,
              slivers: [
                if (mediaQuery.smAndDown || layoutMode == LayoutMode.compact)
                  SliverAppBar(
                    floating: true,
                    title: ThemeBrandMark(
                      branding: branding,
                      fontSize: 30,
                      color: theme.colorScheme.foreground,
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
                  for (final section in homeSections)
                    switch (section) {
                      'recent' => const SliverToBoxAdapter(
                          child: HomeRecentlyPlayedSection(),
                        ),
                      'featured' => const SliverToBoxAdapter(
                          child: HomeFeaturedSection(),
                        ),
                      'new_releases' => const SliverToBoxAdapter(
                          child: HomeNewReleasesSection(),
                        ),
                      'browse' => const SliverSafeArea(
                          sliver: HomePageBrowseSection(),
                        ),
                      _ => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    },
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
          ),
        ));
  }
}
