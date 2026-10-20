import 'package:flutter/material.dart'
    hide AlertDialog, IconButton, Tooltip, showDialog;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/playlist_order.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Reorders the main Playlists section only.
///
/// Sidebar pins are a separate list with a separate dialog; the two never
/// write each other's persisted order.
class PlaylistOrderDialog extends ConsumerStatefulWidget {
  final List<SpotubeSimplePlaylistObject> playlists;

  const PlaylistOrderDialog({required this.playlists, super.key});

  @override
  ConsumerState<PlaylistOrderDialog> createState() =>
      _PlaylistOrderDialogState();
}

class _PlaylistOrderDialogState extends ConsumerState<PlaylistOrderDialog> {
  late List<SpotubeSimplePlaylistObject> _playlists;

  @override
  void initState() {
    super.initState();
    _playlists = List.of(widget.playlists);
  }

  void _move(int from, int to) {
    if (from < 0 ||
        from >= _playlists.length ||
        to < 0 ||
        to >= _playlists.length ||
        from == to) {
      return;
    }

    final visible = [for (final playlist in _playlists) playlist.id];
    final stored = ref.read(userPreferencesProvider).mainPlaylistOrder;
    final nextOrder = moveMainPlaylistEntry(stored, visible, from, to);

    setState(() {
      final moved = _playlists.removeAt(from);
      _playlists.insert(to, moved);
    });
    ref.read(userPreferencesProvider.notifier).setMainPlaylistOrder(nextOrder);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: AlertDialog(
        title: Text(context.l10n.playlist_order).h4(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.playlist_order_description),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  _move(oldIndex, newIndex);
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  return ListTile(
                    key: ValueKey('main-order:${playlist.id}'),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(SpotubeIcons.dragHandle),
                    ),
                    title: Row(
                      spacing: 8,
                      children: [
                        const Icon(SpotubeIcons.playlist),
                        Expanded(
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed:
                              index == 0 ? null : () => _move(index, index - 1),
                        ),
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: index == _playlists.length - 1
                              ? null
                              : () => _move(index, index + 1),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          Button.outline(
            child: Text(context.l10n.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class PlaylistOrderDialogButton extends ConsumerWidget {
  final List<SpotubeSimplePlaylistObject> playlists;

  const PlaylistOrderDialogButton({required this.playlists, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      tooltip: TooltipContainer(child: Text(context.l10n.playlist_order)).call,
      child: IconButton.outline(
        icon: const Icon(SpotubeIcons.sort),
        enabled: playlists.isNotEmpty,
        onPressed: () {
          showDialog(
            context: context,
            alignment: Alignment.center,
            builder: (context) => ToastLayer(
              child: PlaylistOrderDialog(playlists: playlists),
            ),
          );
        },
      ),
    );
  }
}
