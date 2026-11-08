import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/connect/connect_device.dart';
import 'package:spotube/modules/theme_shell/theme_branding.dart';
import 'package:spotube/modules/theme_shell/theme_identity.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/pages/radio/station_search.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

@RoutePage()
class RadioScreen extends HookConsumerWidget {
  static const name = "radio";
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = useScrollController();
    final mediaQuery = MediaQuery.of(context);
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
    final themeDefinition = ref.watch(effectiveThemeDefinitionProvider);
    final isStage = context.layout.player.dock == ThemePlayerDock.stage;
    final hasRadioBefore = themeUiSlotExists(ref, 'radio.before_sections');
    final hasRadioAfter = themeUiSlotExists(ref, 'radio.after_sections');
    final branding = useMemoized(
      () => ThemeBranding.from(themeDefinition),
      [IdentityKey(themeDefinition)],
    );

    final selectedTag = useState<String?>(null);
    final selectedCountry = useState<String?>(null);

    // The page is a single scroll: the shared station search (field, rails,
    // filter and grid) is the whole content above the attribution footer.
    return SafeArea(
      bottom: false,
      child: Scaffold(
        child: ThemePageContent(
          slot: 'radio.content',
          bindings: const {},
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
              if (hasRadioBefore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: ThemeSlot(
                      'radio.before_sections',
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    ),
                  ),
                ),
              if (isStage) const SliverToBoxAdapter(child: ThemeUiStage()),
              ...useStationSearchSlivers(
                context,
                ref,
                controller: controller,
                showSearchRow: showSearchRow,
                showHomeShortcut: true,
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
              if (hasRadioAfter)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
                    child: ThemeSlot(
                      'radio.after_sections',
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    ),
                  ),
                ),
              const RadioAttributionSliver(),
              const SliverSafeArea(sliver: SliverGap(24)),
            ],
          ),
        ),
      ),
    );
  }
}
