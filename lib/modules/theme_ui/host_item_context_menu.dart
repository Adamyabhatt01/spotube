import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/track_tile/track_context_menu.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';

/// Right-click / long-press menu for a host-owned non-track item (album,
/// playlist or artist) opened through a `contextMenu` node with `hostItem:
/// true`.
///
/// Track items keep the host's existing [TrackContextMenu] exactly as today;
/// this widget only handles album/playlist/artist. The rows are built from the
/// shared `contextMenuDefaults` table for the item's target, and host verbs
/// are dispatched through [dispatchThemeUiAction] or routed directly, mirroring
/// [TrackContextMenu._onSelected] and [PlaylistContextMenu].
class HostItemContextMenu extends StatelessWidget {
  const HostItemContextMenu({
    super.key,
    required this.item,
    required this.child,
  });

  final Object? item;
  final Widget child;

  static ContextMenuTarget? _targetFor(Object? item) {
    if (item is SpotubeTrackObject) return ContextMenuTarget.track;
    if (item is SpotubeSimpleAlbumObject || item is SpotubeFullAlbumObject) {
      return ContextMenuTarget.album;
    }
    if (item is SpotubeSimplePlaylistObject ||
        item is SpotubeFullPlaylistObject) {
      return ContextMenuTarget.playlist;
    }
    if (item is SpotubeSimpleArtistObject || item is SpotubeFullArtistObject) {
      return ContextMenuTarget.artist;
    }
    return null;
  }

  static String? _playlistId(Object? item) {
    if (item is SpotubeSimplePlaylistObject) return item.id;
    if (item is SpotubeFullPlaylistObject) return item.id;
    return null;
  }

  static String? _externalUri(Object? item) {
    if (item is SpotubeSimpleAlbumObject) return item.externalUri;
    if (item is SpotubeFullAlbumObject) return item.externalUri;
    if (item is SpotubeSimpleArtistObject) return item.externalUri;
    if (item is SpotubeFullArtistObject) return item.externalUri;
    if (item is SpotubeSimplePlaylistObject) return item.externalUri;
    if (item is SpotubeFullPlaylistObject) return item.externalUri;
    return null;
  }

  static Set<String> _supportedIds(ContextMenuTarget target) {
    switch (target) {
      case ContextMenuTarget.album:
        return const {'open', 'copyLink', 'goToArtist'};
      case ContextMenuTarget.artist:
        return const {'open', 'copyLink'};
      case ContextMenuTarget.playlist:
        return const {'open', 'copyLink', 'pin', 'unpin'};
      default:
        return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetFor(item);
    if (target == null) return child;

    // Track rows keep the host's existing track menu exactly as today.
    // (`item` is a field, so copy to a local for type promotion.)
    final track = item;
    if (track is SpotubeTrackObject) {
      return TrackContextMenu(track: track, child: child);
    }

    return ContextMenuRegion(
      item: ContextMenuItemContext(target: target, item: item),
      builderFor: (context) => _builderFor(context, target),
      onSelected: (context, container, action) =>
          _onSelected(context, container, action),
      child: child,
    );
  }

  ContextMenuBuilder _builderFor(BuildContext context, ContextMenuTarget target) {
    final container = ProviderScope.containerOf(context, listen: false);
    final ui = container.read(themeUiProvider).asData?.value;

    // Which declared pin targets actually hold this playlist: the sidebar
    // keeps its preference column, every other target lives in themePins.
    Set<String> pinnedTargetsFor() {
      final id = _playlistId(item);
      if (id == null) return const {};
      final prefs = container.read(userPreferencesProvider);
      final pins = container.read(themePinsProvider.notifier);
      return {
        for (final target in context.layout.pinTargets)
          if (target.id == 'sidebar'
              ? prefs.pinnedPlaylistIds.contains(id)
              : pins.isPinned(target.id, id))
            target.id,
      };
    }

    final pinnedTargets =
        target == ContextMenuTarget.playlist ? pinnedTargetsFor() : const <String>{};

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      pinTargets: context.layout.pinTargets,
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: _supportedIds(target),
      itemFlags: {
        if (target == ContextMenuTarget.playlist) ...{
          'pinned': pinnedTargets.isNotEmpty,
          'pinnedTargets': pinnedTargets,
        },
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
      case 'open':
        await dispatchThemeUiAction(
          context,
          container,
          ThemeUiAction('openItem', <String, dynamic>{'item': item}),
        );
      case 'copyLink':
        _copyLink(context);
      case 'goToArtist':
        _goToArtist(context);
      case 'pin':
      case 'unpin':
        _togglePin(container);
    }
  }

  void _copyLink(BuildContext context) {
    final uri = _externalUri(item);
    if (uri == null || uri.isEmpty) return;
    Clipboard.setData(ClipboardData(text: uri));
    if (!context.mounted) return;
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(
        child: Text(context.l10n.copied_shareurl_to_clipboard(uri)),
      ),
    );
  }

  void _goToArtist(BuildContext context) {
    final it = item;
    String? artistId;
    if (it is SpotubeSimpleAlbumObject) {
      artistId = it.artists.isNotEmpty ? it.artists.first.id : null;
    } else if (it is SpotubeFullAlbumObject) {
      artistId = it.artists.isNotEmpty ? it.artists.first.id : null;
    } else if (it is SpotubeSimpleArtistObject) {
      artistId = it.id;
    } else if (it is SpotubeFullArtistObject) {
      artistId = it.id;
    }
    if (artistId == null || artistId.isEmpty) return;
    if (!context.mounted) return;
    context.navigateTo(ArtistRoute(artistId: artistId));
  }

  void _togglePin(ProviderContainer container) {
    final id = _playlistId(item);
    if (id == null) return;
    container.read(userPreferencesProvider.notifier).togglePinnedPlaylist(id);
  }
}
