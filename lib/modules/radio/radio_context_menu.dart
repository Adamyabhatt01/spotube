import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/radio/radio_station_commands.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Right-click (desktop) / long-press (touch) actions for a station.
///
/// Rows come from the shared `radio` defaults table; station state is read
/// from the container when the menu opens, like the other host menus.
class RadioStationContextMenu extends StatelessWidget {
  const RadioStationContextMenu({
    super.key,
    required this.station,
    required this.child,
  });

  final RadioStation station;
  final Widget child;

  ContextMenuBuilder _builderFor(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final status =
        container.read(radioStationStatusProvider(station.favoriteKey));
    final favorited =
        container.read(radioFavoriteKeysProvider).contains(station.favoriteKey);
    final isPinned = container
        .read(userPreferencesProvider)
        .pinnedStationIds
        .contains(station.favoriteKey);
    final homepageUrl = station.homepageUrl;
    final hasHomepage = homepageUrl != null && homepageUrl.isNotEmpty;
    final ui = container.read(themeUiProvider).asData?.value;

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: {
        if (!status.isLoading) 'playPause',
        'favorite',
        'pinStation',
        'copyStreamUrl',
        'openHomepage',
      },
      itemFlags: {
        'playing': status.isPlaying,
        'favorited': favorited,
        'pinned': isPinned,
        'hasHomepage': hasHomepage,
      },
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    ProviderContainer container,
    ContextMenuAction action,
  ) async {
    final themeAction = action.themeAction;
    if (themeAction != null) {
      await dispatchThemeUiAction(context, container, themeAction);
      return;
    }

    switch (action.id) {
      case 'playPause':
        toggleRadioStationPlaybackContainer(
          container,
          station,
          container.read(radioStationStatusProvider(station.favoriteKey)),
        );
      case 'favorite':
        await container.read(radioFavoritesProvider.notifier).toggle(station);
      case 'pinStation':
        toggleRadioStationPinContainer(context, container, station);
      case 'copyStreamUrl':
        await Clipboard.setData(ClipboardData(text: station.streamUrl));
        if (!context.mounted) return;
        showToast(
          context: context,
          builder: (context, overlay) => SurfaceCard(
            child: Text(
              context.l10n.copied_to_clipboard(station.streamUrl),
            ),
          ),
        );
      case 'openHomepage':
        final homepageUrl = station.homepageUrl;
        if (homepageUrl != null && homepageUrl.isNotEmpty) {
          await launchUrlString(
            homepageUrl,
            mode: LaunchMode.externalApplication,
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      item: ContextMenuItemContext(
        target: ContextMenuTarget.radio,
        item: station,
      ),
      builderFor: _builderFor,
      onSelected: _onSelected,
      child: child,
    );
  }
}
