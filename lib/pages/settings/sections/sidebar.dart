import 'package:flutter/material.dart' show ListTile;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/root/sidebar/sidebar_order_dialog.dart';
import 'package:spotube/modules/settings/section_card_with_heading.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

class SettingsSidebarSection extends HookConsumerWidget {
  const SettingsSidebarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);

    void openOrderDialog() {
      showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (context) => const SidebarOrderDialog(),
      );
    }

    return SectionCardWithHeading(
      heading: context.l10n.sidebar,
      children: [
        ListTile(
          leading: const Icon(SpotubeIcons.dashboard),
          title: Text(context.l10n.sidebar_order),
          subtitle: Text(context.l10n.sidebar_order_description),
          onTap: openOrderDialog,
          trailing: const Icon(SpotubeIcons.angleRight),
        ),
        ListTile(
          leading: const Icon(SpotubeIcons.pinOn),
          title: Text(context.l10n.pinned_playlists),
          subtitle: Text(context.l10n.pinned_playlists_description),
          onTap: openOrderDialog,
          trailing: const Icon(SpotubeIcons.angleRight),
        ),
        ListTile(
          leading: const Icon(SpotubeIcons.close),
          title: Text(context.l10n.reset_sidebar),
          onTap: () {
            preferencesNotifier.setSidebarLibraryOrder([]);
            preferencesNotifier.setPinnedPlaylistIds([]);
          },
          trailing: const Icon(SpotubeIcons.angleRight),
        ),
      ],
    );
  }
}
