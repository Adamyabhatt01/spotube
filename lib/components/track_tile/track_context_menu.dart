import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/track_options/track_options_provider.dart';

/// Right-click (desktop) / long-press (touch) menu for a track row.
///
/// Mirrors [PlaylistContextMenu]: rows come from the shared defaults table for
/// `track`, the callback seam maps ids onto the existing
/// [TrackOptionsActions] verbs, and the ⋯ trigger menu stays untouched. All
/// per-track state is read from the container when the menu opens — a
/// scrolling list carries no subscription per row for a menu it never showed.
class TrackContextMenu extends StatelessWidget {
  const TrackContextMenu({
    super.key,
    required this.track,
    required this.child,
    this.userPlaylist = false,
    this.playlistId,
    this.onSelect,
  });

  final SpotubeTrackObject track;
  final Widget child;
  final bool userPlaylist;
  final String? playlistId;

  /// Enters the surrounding list's multi-select mode; null hides the row
  /// (the trigger menu treats it the same way).
  final VoidCallback? onSelect;

  ContextMenuBuilder _builderFor(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final flags = container.read(trackOptionsStateProvider(track));
    final ui = container.read(themeUiProvider).asData?.value;
    final isLocalTrack = track is SpotubeLocalTrackObject;

    final available = <String>{
      'playNext',
      'addToQueue',
      'removeFromQueue',
      'goToAlbum',
      'goToArtist',
      'copyLink',
      if (onSelect != null) 'select',
      if (!isLocalTrack) ...[
        'download',
        'share',
        'details',
        'blacklist',
        if (flags.isAuthenticated) ...[
          'like',
          'startRadio',
          'addToPlaylist',
          if (userPlaylist) 'removeFromPlaylist',
        ],
      ] else
        'delete',
    };

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: available,
      itemFlags: {
        'local': isLocalTrack,
        'inQueue': flags.isInQueue,
        'activeTrack': flags.isActiveTrack,
        'authenticated': flags.isAuthenticated,
        'liked': flags.isLiked,
        'blacklisted': flags.isBlacklisted,
        'userPlaylist': userPlaylist,
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

    if (action.id == 'select') {
      onSelect?.call();
      return;
    }
    if (action.id == 'goToArtist') {
      final artist = track.artists.isEmpty ? null : track.artists.first;
      if (artist != null) {
        await context.navigateTo(ArtistRoute(artistId: artist.id));
      }
      return;
    }
    if (action.id == 'copyLink') {
      if (track.externalUri.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: track.externalUri));
      if (!context.mounted) return;
      showToast(
        context: context,
        builder: (context, overlay) => SurfaceCard(
          child: Text(
            context.l10n.copied_shareurl_to_clipboard(track.externalUri),
          ),
        ),
      );
      return;
    }

    final verb = switch (action.id) {
      'playNext' => TrackOptionValue.playNext,
      'addToQueue' => TrackOptionValue.addToQueue,
      'removeFromQueue' => TrackOptionValue.removeFromQueue,
      'like' => TrackOptionValue.favorite,
      'download' => TrackOptionValue.download,
      'addToPlaylist' => TrackOptionValue.addToPlaylist,
      'goToAlbum' => TrackOptionValue.album,
      'startRadio' => TrackOptionValue.startRadio,
      'removeFromPlaylist' => TrackOptionValue.removeFromPlaylist,
      'blacklist' => TrackOptionValue.blacklist,
      'delete' => TrackOptionValue.delete,
      'share' => TrackOptionValue.share,
      'details' => TrackOptionValue.details,
      _ => null,
    };
    if (verb == null) return;

    final flags = container.read(trackOptionsStateProvider(track));
    if (verb == TrackOptionValue.removeFromQueue && flags.isActiveTrack) {
      return;
    }
    if (verb == TrackOptionValue.download &&
        (flags.isInDownloadQueue || flags.isDownloaded)) {
      return;
    }

    await container.read(trackOptionActionsProvider(track)).action(
          rootNavigatorKey.currentContext!,
          verb,
          playlistId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      item: ContextMenuItemContext(
        target: ContextMenuTarget.track,
        item: track,
      ),
      builderFor: _builderFor,
      onSelected: _onSelected,
      child: child,
    );
  }
}
