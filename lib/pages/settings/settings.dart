import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/pages/settings/sections/about.dart';
import 'package:spotube/pages/settings/sections/accounts.dart';
import 'package:spotube/pages/settings/sections/appearance.dart';
import 'package:spotube/pages/settings/sections/desktop.dart';
import 'package:spotube/pages/settings/sections/developers.dart';
import 'package:spotube/pages/settings/sections/downloads.dart';
import 'package:spotube/pages/settings/sections/language_region.dart';
import 'package:spotube/pages/settings/sections/playback.dart';
import 'package:spotube/pages/settings/sections/sidebar.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class SettingsPage extends HookConsumerWidget {
  static const name = "settings";

  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controller = useScrollController();
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final layout = context.layout;
    final hasBefore = themeUiSlotExists(ref, 'settings.before');
    final hasAfter = themeUiSlotExists(ref, 'settings.after');

    // A non-empty section list is the theme's surface; otherwise the host
    // order is kept whole. Platform-only groups are not offered on the
    // platforms they do not exist on.
    final sections = useMemoized(
      () => resolveThemeSections(
        defaults: [
          'accounts',
          'language_region',
          'appearance',
          'sidebar',
          'playback',
          'downloads',
          if (kIsDesktop) 'desktop',
          if (!kIsWeb) 'developers',
          'about',
        ],
        block: layout.settings,
      ),
      [layout],
    );

    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: [
          TitleBar(
            title: Text(context.l10n.settings),
          )
        ],
        child: Scrollbar(
          controller: controller,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1366),
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(scrollbars: false),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListView(
                    controller: controller,
                    children: [
                      if (hasBefore)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: ThemeSlot(
                            'settings.before',
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                          ),
                        ),
                      for (final section in sections)
                        switch (section) {
                          'accounts' => const SettingsAccountSection(),
                          'language_region' =>
                            const SettingsLanguageRegionSection(),
                          'appearance' => const SettingsAppearanceSection(),
                          'sidebar' => const SettingsSidebarSection(),
                          'playback' => const SettingsPlaybackSection(),
                          'downloads' => const SettingsDownloadsSection(),
                          'desktop' when kIsDesktop =>
                            const SettingsDesktopSection(),
                          'developers' when !kIsWeb =>
                            const SettingsDevelopersSection(),
                          'about' => const SettingsAboutSection(),
                          _ => const SizedBox.shrink(),
                        },
                      Center(
                        child: Button.destructive(
                          onPressed: preferencesNotifier.reset,
                          child: Text(context.l10n.restore_defaults),
                        ),
                      ),
                      if (hasAfter)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: ThemeSlot(
                            'settings.after',
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                          ),
                        ),
                      const SizedBox(height: 200),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
