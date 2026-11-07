import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/components/dialogs/confirm_download_dialog.dart';
import 'package:spotube/components/track_presentation/presentation_actions.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/playlist/playlist_create_dialog.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';

/// Right-click (desktop) / long-press (touch) actions for a playlist card.
///
/// The rows come from the shared context-menu builder; this widget only
/// supplies the callbacks it can actually run and the playlist-specific state
/// (`owner`, playing, pinned targets). Every host surface uses the same table
/// and the same user configuration. Nothing is watched: the menu is resolved
/// from the container when it opens, so a grid of cards holds no subscriptions
/// for menus that were never shown.
class PlaylistContextMenu extends StatelessWidget {
  const PlaylistContextMenu({
    super.key,
    required this.playlist,
    required this.child,
    required this.isOwner,
    required this.isPinned,
    required this.isPlaying,
    required this.isLoading,
    required this.isQueueLoading,
    required this.onOpen,
    required this.onPlayPause,
    required this.onAddToQueue,
    required this.onTogglePin,
    required this.onDelete,
  });

  final SpotubeSimplePlaylistObject playlist;
  final Widget child;
  final bool isOwner;
  final bool isPinned;

  /// Whether the audio is actually sounding, which is what the label follows.
  final bool isPlaying;
  final bool isLoading;
  final bool isQueueLoading;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback onAddToQueue;
  final VoidCallback onTogglePin;
  final Future<void> Function() onDelete;

  static const _supported = <String>{
    'play',
    'open',
    'pin',
    'unpin',
    'addToQueue',
    'download',
    'rename',
    'delete',
    'copyLink',
  };

  ContextMenuBuilder _builderFor(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final ui = container.read(themeUiProvider).asData?.value;
    final themePins = container.read(themePinsProvider);
    final pinnedTargets = <String>{
      if (isPinned) 'sidebar',
      for (final entry in themePins.entries)
        if (entry.value.contains(playlist.id)) entry.key,
    };

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      pinTargets: context.layout.pinTargets,
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: _supported,
      itemFlags: {
        'owner': isOwner,
        'playing': isPlaying,
        'pinned': pinnedTargets.isNotEmpty,
        'pinnedTargets': pinnedTargets,
      },
    );
  }

  Future<void> _togglePinTo(
    ProviderContainer container,
    BuildContext context,
    String target,
  ) async {
    if (target == 'sidebar') {
      onTogglePin();
      return;
    }
    final pins = container.read(themePinsProvider);
    final pinned = (pins[target] ?? const <String>[]).contains(playlist.id);
    container
        .read(themePinsProvider.notifier)
        .setPinned(target, playlist.id, pinned: !pinned);
  }

  /// Whole-playlist download: confirm, then the same download-manager and
  /// mirror path the playlist header uses.
  Future<void> _download(
    BuildContext context,
    ProviderContainer container,
  ) async {
    final List<SpotubeFullTrackObject> tracks;
    try {
      tracks = await fetchPlaylistAllTracks(container.read, playlist);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      if (context.mounted) _errorToast(context, container);
      return;
    }
    if (tracks.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => const ConfirmDownloadDialog(),
        ) ??
        false;
    if (confirmed != true || !context.mounted) return;

    container.read(downloadManagerProvider.notifier).addAllToQueue(
          tracks,
          collectionId: playlist.id,
        );
    unawaited(
      container.read(playlistMirrorServiceProvider).mirror(playlist, tracks),
    );
    if (!context.mounted) return;
    showToastForAction(context, 'download', tracks.length);
  }

  Future<void> _rename(
    BuildContext context,
    ProviderContainer container,
  ) async {
    if (!await _isOwnerNow(container) || !context.mounted) return;
    // Let the dropdown/drawer finish dismissing before the dialog opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => PlaylistCreateDialog(playlistId: playlist.id),
        ),
      );
    });
  }

  /// The `when` flag on the rename row already hides it for other people's
  /// playlists; this re-checks at tap time because the menu can outlive a
  /// login change.
  Future<bool> _isOwnerNow(ProviderContainer container) async {
    if (playlist.id == likedTracksPlaylistId) return false;
    final ownerId = playlist.owner.id;
    if (ownerId.isEmpty) return false;
    try {
      final me = await container.read(metadataPluginUserProvider.future);
      return me != null && me.id == ownerId;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return false;
    }
  }

  void _errorToast(BuildContext context, ProviderContainer container) {
    final isOnline = container.read(isOnlineProvider).asData?.value ?? true;
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(
        child: Text(
          isOnline
              ? context.l10n.something_went_wrong
              : context.l10n.you_are_offline,
        ),
      ),
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

    if (action.id.startsWith('pin:')) {
      await _togglePinTo(container, context, action.id.substring('pin:'.length));
      return;
    }

    switch (action.id) {
      case 'play':
        if (!isLoading) onPlayPause();
      case 'open':
        onOpen();
      case 'addToQueue':
        if (!isLoading && !isQueueLoading) onAddToQueue();
      case 'download':
        await _download(context, container);
      case 'rename':
        await _rename(context, container);
      case 'delete':
        // Let the dropdown/drawer finish dismissing before the dialog
        // opens, so the two overlays cannot fight over the barrier.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) unawaited(onDelete());
        });
      case 'copyLink':
        final externalUri = playlist.externalUri;
        if (externalUri.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: externalUri));
        if (!context.mounted) return;
        showToast(
          context: context,
          builder: (context, overlay) => SurfaceCard(
            child: Text(
              context.l10n.copied_shareurl_to_clipboard(externalUri),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      item: ContextMenuItemContext(
        target: ContextMenuTarget.playlist,
        item: playlist,
      ),
      builderFor: _builderFor,
      onSelected: _onSelected,
      child: child,
    );
  }
}
