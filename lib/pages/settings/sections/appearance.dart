import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show ListTile;
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
import 'package:spotube/modules/settings/section_card_with_heading.dart';
import 'package:spotube/modules/splash/splash_prefs.dart';
import 'package:spotube/modules/splash/splash_screen.dart';
import 'package:spotube/components/adaptive/adaptive_select_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

class SettingsAppearanceSection extends HookConsumerWidget {
  final bool isGettingStarted;
  const SettingsAppearanceSection({
    super.key,
    this.isGettingStarted = false,
  });

  @override
  Widget build(BuildContext context, ref) {
    // Narrow slice: a write to any other preference must not rebuild
    // this whole section (the row notifier emits on every write).
    final preferences = ref.watch(userPreferencesProvider.select(
      (p) => (
        layoutMode: p.layoutMode,
        themeMode: p.themeMode,
        accentColorScheme: p.accentColorScheme,
        themeTransition: p.themeTransition,
        themeTransitionMs: p.themeTransitionMs,
      ),
    ));
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final splashPrefs =
        ref.watch(splashPrefsProvider).asData?.value ?? const SplashPrefs();
    final splashNotifier = ref.watch(splashPrefsProvider.notifier);
    final pickColorScheme = useCallback(() {
      return () => showDialog(
          context: context,
          builder: (context) {
            return const ColorSchemePickerDialog();
          });
    }, []);

    Future<void> pickSplashFile(String kind) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await splashNotifier.setFile(kind, File(path));
    }

    String fileLabel(String? path, String fallback) {
      if (path == null) return fallback;
      return p.basename(path);
    }

    String animationLabel(SplashAnimation animation) {
      return switch (animation) {
        SplashAnimation.none => context.l10n.splash_animation_none,
        SplashAnimation.fade => context.l10n.splash_animation_fade,
        SplashAnimation.scale => context.l10n.splash_animation_scale,
        SplashAnimation.slide => context.l10n.splash_animation_slide,
      };
    }

    final children = [
      AdaptiveSelectTile<LayoutMode>(
        secondary: const Icon(SpotubeIcons.dashboard),
        title: Text(context.l10n.layout_mode),
        subtitle: Text(context.l10n.override_layout_settings),
        value: preferences.layoutMode,
        onChanged: (value) {
          if (value != null) {
            preferencesNotifier.setLayoutMode(value);
          }
        },
        options: [
          SelectItemButton(
            value: LayoutMode.adaptive,
            child: Text(context.l10n.adaptive),
          ),
          SelectItemButton(
            value: LayoutMode.compact,
            child: Text(context.l10n.compact),
          ),
          SelectItemButton(
            value: LayoutMode.extended,
            child: Text(context.l10n.extended),
          ),
        ],
      ),
      AdaptiveSelectTile<ThemeMode>(
        secondary: const Icon(SpotubeIcons.darkMode),
        title: Text(context.l10n.theme),
        value: preferences.themeMode,
        options: [
          SelectItemButton(
            value: ThemeMode.dark,
            child: Text(context.l10n.dark),
          ),
          SelectItemButton(
            value: ThemeMode.light,
            child: Text(context.l10n.light),
          ),
          SelectItemButton(
            value: ThemeMode.system,
            child: Text(context.l10n.system),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            preferencesNotifier.setThemeMode(value);
          }
        },
      ),
      ListTile(
        leading: const Icon(SpotubeIcons.palette),
        title: Text(context.l10n.accent_color),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 5,
        ),
        trailing: ColorChip(
          color: preferences.accentColorScheme,
          name: preferences.accentColorScheme.name,
          onPressed: pickColorScheme(),
          isActive: false,
        ),
        onTap: pickColorScheme(),
      ),
      ListTile(
        leading: const Icon(SpotubeIcons.magic),
        title: Text(context.l10n.theme_transition),
        subtitle: Text(context.l10n.theme_transition_description),
        trailing: Switch(
          value: preferences.themeTransition,
          onChanged: preferencesNotifier.setThemeTransition,
        ),
      ),
      if (preferences.themeTransition)
        AdaptiveSelectTile<int>(
          secondary: const Icon(SpotubeIcons.timer),
          title: Text(context.l10n.theme_transition_duration),
          value: preferences.themeTransitionMs,
          onChanged: (value) {
            if (value != null) {
              preferencesNotifier.setThemeTransitionMs(value);
            }
          },
          options: [
            for (final ms in [100, 150, 250, 400, 600, 1000])
              SelectItemButton(
                value: ms,
                child: Text("${ms / 1000}s"),
              ),
          ],
        ),
      AdaptiveSelectTile<SplashAnimation>(
        secondary: const Icon(SpotubeIcons.lightningOutlined),
        title: Text(context.l10n.splash_animation),
        value: splashPrefs.animation,
        onChanged: (value) {
          if (value != null) {
            splashNotifier.setAnimation(value);
          }
        },
        options: [
          for (final animation in SplashAnimation.values)
            SelectItemButton(
              value: animation,
              child: Text(animationLabel(animation)),
            ),
        ],
      ),
      AdaptiveSelectTile<int>(
        secondary: const Icon(SpotubeIcons.timer),
        title: Text(context.l10n.splash_duration),
        value: splashPrefs.duration.inMilliseconds,
        onChanged: (value) {
          if (value != null) {
            splashNotifier.setDuration(Duration(milliseconds: value));
          }
        },
        options: [
          for (final ms in [500, 900, 1500, 2500])
            SelectItemButton(
              value: ms,
              child: Text("${ms / 1000}s"),
            ),
        ],
      ),
      ListTile(
        leading: const Icon(SpotubeIcons.album),
        title: Text(context.l10n.splash_themed_background),
        subtitle: Text(context.l10n.splash_themed_background_description),
        trailing: Switch(
          value: splashPrefs.useThemedBackground,
          onChanged: splashNotifier.setThemedBackground,
        ),
      ),
      ListTile(
        leading: const Icon(SpotubeIcons.album),
        title: Text(context.l10n.splash_custom_logo),
        subtitle: Text(fileLabel(
            splashPrefs.logoPath, context.l10n.splash_no_custom_file)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (splashPrefs.logoPath != null)
              IconButton.ghost(
                icon: const Icon(SpotubeIcons.close),
                onPressed: () => splashNotifier.setFile('logo', null),
              ),
            Button.secondary(
              onPressed: () => pickSplashFile('logo'),
              child: Text(context.l10n.splash_pick_image),
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(SpotubeIcons.album),
        title: Text(context.l10n.splash_custom_background),
        subtitle: Text(fileLabel(
            splashPrefs.backgroundPath, context.l10n.splash_no_custom_file)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (splashPrefs.backgroundPath != null)
              IconButton.ghost(
                icon: const Icon(SpotubeIcons.close),
                onPressed: () => splashNotifier.setFile('background', null),
              ),
            Button.secondary(
              onPressed: () => pickSplashFile('background'),
              child: Text(context.l10n.splash_pick_image),
            ),
          ],
        ),
      ),
    ];

    if (isGettingStarted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in children) ...[
            child,
            const Gap(16),
          ],
        ],
      );
    }

    return SectionCardWithHeading(
      heading: context.l10n.appearance,
      children: children,
    );
  }
}
