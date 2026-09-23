import 'package:flutter/material.dart' show ListTile;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/settings/section_card_with_heading.dart';
import 'package:spotube/components/adaptive/adaptive_select_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

class SettingsDesktopSection extends HookConsumerWidget {
  const SettingsDesktopSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    // Narrow slice: a write to any other preference must not rebuild
    // this whole section (the row notifier emits on every write).
    final preferences = ref.watch(userPreferencesProvider.select(
      (p) => (
        closeBehavior: p.closeBehavior,
        discordPresence: p.discordPresence,
        showSystemTrayIcon: p.showSystemTrayIcon,
        systemTitleBar: p.systemTitleBar,
        volumeControlMode: p.volumeControlMode,
      ),
    ));
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);

    return SectionCardWithHeading(
      heading: context.l10n.desktop,
      children: [
        const Gap(10),
        AdaptiveSelectTile<CloseBehavior>(
          secondary: const Icon(SpotubeIcons.close),
          title: Text(context.l10n.close_behavior),
          value: preferences.closeBehavior,
          options: [
            SelectItemButton(
              value: CloseBehavior.close,
              child: Text(context.l10n.close),
            ),
            SelectItemButton(
              value: CloseBehavior.minimizeToTray,
              child: Text(context.l10n.minimize_to_tray),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              preferencesNotifier.setCloseBehavior(value);
            }
          },
        ),
        AdaptiveSelectTile<VolumeControlMode>(
          secondary: const Icon(SpotubeIcons.volumeHigh),
          title: Text(context.l10n.volume_control),
          value: preferences.volumeControlMode,
          options: [
            SelectItemButton(
              value: VolumeControlMode.always,
              child: Text(context.l10n.volume_control_always),
            ),
            SelectItemButton(
              value: VolumeControlMode.hover,
              child: Text(context.l10n.volume_control_hover),
            ),
            SelectItemButton(
              value: VolumeControlMode.hidden,
              child: Text(context.l10n.volume_control_hidden),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              preferencesNotifier.setVolumeControlMode(value);
            }
          },
        ),
        ListTile(
          leading: const Icon(SpotubeIcons.tray),
          title: Text(context.l10n.show_tray_icon),
          trailing: Switch(
            value: preferences.showSystemTrayIcon,
            onChanged: preferencesNotifier.setShowSystemTrayIcon,
          ),
        ),
        ListTile(
          leading: const Icon(SpotubeIcons.window),
          title: Text(context.l10n.use_system_title_bar),
          trailing: Switch(
            value: preferences.systemTitleBar,
            onChanged: preferencesNotifier.setSystemTitleBar,
          ),
        ),
        ListTile(
          leading: const Icon(SpotubeIcons.discord),
          title: Text(context.l10n.discord_rich_presence),
          trailing: Switch(
            value: preferences.discordPresence,
            onChanged: preferencesNotifier.setDiscordPresence,
          ),
        ),
      ],
    );
  }
}
