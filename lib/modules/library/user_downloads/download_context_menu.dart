import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/components/dialogs/prompt_dialog.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/sourced_track/local_library_lookup.dart';

/// Right-click (desktop) / long-press (touch) menu for a download row.
///
/// State is resolved when the menu opens, like the other host menus. The
/// file-backed rows (`openFolder`, `removeDownload`) need a match in the
/// scanned local library, so they appear only once the scan has produced one
/// for this track.
class DownloadContextMenu extends StatelessWidget {
  const DownloadContextMenu({
    super.key,
    required this.task,
    required this.child,
  });

  final DownloadTask task;
  final Widget child;

  SpotubeLocalTrackObject? _matchedLocalFile(ProviderContainer container) {
    if (task.status != DownloadStatus.completed) return null;
    final library = container.read(localTracksProvider).asData?.value;
    if (library == null) return null;
    final match = LocalLibraryLookup.find(
      task.track,
      library.values.expand((tracks) => tracks),
    );
    return match?.track;
  }

  ContextMenuBuilder _builderFor(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final ui = container.read(themeUiProvider).asData?.value;
    final hasLocalFile = _matchedLocalFile(container) != null;

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: {
        'play',
        'copyLink',
        if (hasLocalFile) ...['openFolder', 'removeDownload'],
      },
      itemFlags: {
        'completed': task.status == DownloadStatus.completed,
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
      case 'play':
        await container
            .read(audioPlayerProvider.notifier)
            .load([task.track], autoPlay: true);
      case 'openFolder':
        final local = _matchedLocalFile(container);
        if (local != null) {
          await OpenFile.open(File(local.path).parent.path);
        }
      case 'removeDownload':
        final local = _matchedLocalFile(container);
        if (local == null) return;
        final file = File(local.path);
        if (await file.exists()) {
          await file.delete();
        }
        container.invalidate(localTracksProvider);
      case 'copyLink':
        if (task.track.externalUri.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: task.track.externalUri));
        if (!context.mounted) return;
        showToast(
          context: context,
          builder: (context, overlay) => SurfaceCard(
            child: Text(
              context.l10n.copied_shareurl_to_clipboard(
                task.track.externalUri,
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      item: ContextMenuItemContext(
        target: ContextMenuTarget.download,
        item: task.track,
      ),
      builderFor: _builderFor,
      onSelected: _onSelected,
      // Deleting the file is irreversible, so the user's confirm-destructive
      // knob gates it, resolved when the row is picked.
      confirmDestructive: (action) async {
        final container = ProviderScope.containerOf(context, listen: false);
        final config = container
            .read(contextMenuConfigProvider)
            .forTarget(ContextMenuTarget.download);
        if (!config.confirmDestructive) return true;
        if (!context.mounted) return false;
        return showPromptDialog(
          context: context,
          title: action.label,
          message: task.track.name,
          okText: context.l10n.delete,
          destructive: true,
        );
      },
      child: child,
    );
  }
}
