import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide AlertDialog, IconButton, Tooltip;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/radio/pinned_station.dart';
import 'package:spotube/provider/sidebar/sidebar_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Reorders the sidebar Library group, the pinned playlists and the pinned
/// radio stations.
///
/// Playlists are pinned from playlist pages and cards, stations from station
/// cards and rows; this dialog only reorders and unpins. Library tiles
/// (playlists, artists, albums, local library) reorder here too — the top
/// navigation stays fixed and never appears in this dialog. Stable ids are
/// persisted, so the order survives renames and plugin updates.
class SidebarOrderDialog extends ConsumerStatefulWidget {
  const SidebarOrderDialog({super.key});

  @override
  ConsumerState<SidebarOrderDialog> createState() => _SidebarOrderDialogState();
}

class _SidebarOrderDialogState extends ConsumerState<SidebarOrderDialog> {
  late List<String> _libraryOrder;
  late List<String> _pins;
  late List<String> _stationPins;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPreferencesProvider);
    _libraryOrder = resolveSidebarLibraryOrder(prefs.sidebarLibraryOrder);
    _pins = List.of(prefs.pinnedPlaylistIds);
    _stationPins = List.of(prefs.pinnedStationIds);
  }

  void _moveLibrary(int from, int to) {
    setState(() {
      _libraryOrder = moveSidebarEntry(_libraryOrder, from, to);
      ref
          .read(userPreferencesProvider.notifier)
          .setSidebarLibraryOrder(List.of(_libraryOrder));
    });
  }

  /// Moves the pin at [from] to [to]; both index into [visible], the ids the
  /// dialog actually shows. See [moveSidebarPin] for the hidden-id policy.
  void _movePin(int from, int to, List<String> visible) {
    setState(() {
      _pins = moveSidebarPin(_pins, visible, from, to);
      ref
          .read(userPreferencesProvider.notifier)
          .setPinnedPlaylistIds(List.of(_pins));
    });
  }

  void _unpin(String id) {
    setState(() {
      _pins.remove(id);
      ref
          .read(userPreferencesProvider.notifier)
          .setPinnedPlaylistIds(List.of(_pins));
    });
  }

  /// Moves the station pin at [from] to [to]; both index [_stationPins],
  /// which is also the visible list here (an unresolvable row renders empty
  /// but keeps its index, so the two never drift apart).
  void _moveStationPin(int from, int to) {
    setState(() {
      _stationPins =
          moveSidebarPin(_stationPins, List.of(_stationPins), from, to);
      ref
          .read(userPreferencesProvider.notifier)
          .setPinnedStationIds(List.of(_stationPins));
    });
  }

  void _unpinStation(String favoriteKey) {
    setState(() {
      _stationPins.remove(favoriteKey);
      ref
          .read(userPreferencesProvider.notifier)
          .setPinnedStationIds(List.of(_stationPins));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tilesById = {
      for (final tile in getSidebarLibraryTileList(context.l10n)) tile.id: tile,
    };
    final playlistIndex = ref.watch(sidebarPlaylistIndexProvider);
    final me = ref.watch(metadataPluginUserProvider).asData?.value;
    // Same offline fallback as the sidebar itself: local auth state stays
    // true without the network, so a pinned Liked entry stays reorderable
    // and unpinnable instead of vanishing from this dialog.
    final authenticated =
        ref.watch(metadataPluginAuthenticatedProvider).asData?.value;

    // Synthetic entry, mirroring UserPlaylistsPage: built in UI because its
    // name needs l10n, which providers cannot reach.
    final likedTracksPlaylist = resolveLikedTracksPlaylist(
      name: context.l10n.liked_tracks,
      description: context.l10n.liked_tracks_description,
      me: me,
      authenticated: authenticated,
    );

    final pinPlaylists = [
      for (final id in _pins)
        (
          id: id,
          playlist: id == likedTracksPlaylistId
              ? likedTracksPlaylist
              : playlistIndex[id],
        )
    ].where((e) => e.playlist != null).toList();
    final pinIds = [for (final entry in pinPlaylists) entry.id];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: AlertDialog(
        title: Text(context.l10n.sidebar).h4(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.sidebar_order_description),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _libraryOrder.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  _moveLibrary(oldIndex, newIndex);
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final id = _libraryOrder[index];
                  // [_libraryOrder] only holds known ids (see
                  // [resolveSidebarLibraryOrder]), so the tile exists.
                  final tile = tilesById[id]!;
                  return ListTile(
                    key: ValueKey(id),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(SpotubeIcons.dragHandle),
                    ),
                    title: Row(
                      spacing: 8,
                      children: [
                        Icon(tile.icon),
                        Expanded(child: Text(tile.title)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: index == 0
                              ? null
                              : () => _moveLibrary(index, index - 1),
                        ),
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: index == _libraryOrder.length - 1
                              ? null
                              : () => _moveLibrary(index, index + 1),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.pinned_playlists).bold(),
            Text(context.l10n.pinned_playlists_description),
            const SizedBox(height: 8),
            if (pinPlaylists.isEmpty)
              Text(context.l10n.pin_to_sidebar).muted().xSmall()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: pinPlaylists.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    _movePin(oldIndex, newIndex, pinIds);
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final entry = pinPlaylists[index];
                    final playlist = entry.playlist!;
                    return ListTile(
                      key: ValueKey('pin:${entry.id}'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(SpotubeIcons.dragHandle),
                      ),
                      title: Row(
                        spacing: 8,
                        children: [
                          SidebarPinCover(
                            imageUrl:
                                playlist.images.from200PxTo300PxOrSmallestImage(
                              ImagePlaceholder.collection,
                            ),
                            side: 32,
                          ),
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
                          Tooltip(
                            tooltip: TooltipContainer(
                              child: Text(context.l10n.unpin_from_sidebar),
                            ).call,
                            child: IconButton.outline(
                              icon: const Icon(SpotubeIcons.close),
                              onPressed: () => _unpin(entry.id),
                            ),
                          ),
                          IconButton.outline(
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: index == 0
                                ? null
                                : () => _movePin(index, index - 1, pinIds),
                          ),
                          IconButton.outline(
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: index == pinPlaylists.length - 1
                                ? null
                                : () => _movePin(index, index + 1, pinIds),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Button.outline(
              onPressed: () {
                Navigator.of(context).pop();
                context.navigateTo(const UserPlaylistsRoute());
              },
              child: Text(context.l10n.show_all_playlists),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.pinned_stations).bold(),
            Text(context.l10n.pinned_stations_description),
            const SizedBox(height: 8),
            if (_stationPins.isEmpty)
              Text(context.l10n.pin_to_sidebar).muted().xSmall()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: _stationPins.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    _moveStationPin(oldIndex, newIndex);
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final key = _stationPins[index];
                    return _StationPinRow(
                      key: ValueKey('station-pin:$key'),
                      favoriteKey: key,
                      index: index,
                      isFirst: index == 0,
                      isLast: index == _stationPins.length - 1,
                      onMoveUp: () => _moveStationPin(index, index - 1),
                      onMoveDown: () => _moveStationPin(index, index + 1),
                      onUnpin: () => _unpinStation(key),
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

/// One pinned-station row in the order dialog.
///
/// A per-row widget (rather than inline watches in the list builder) so row
/// count changes cannot reorder hook calls. Watches [pinnedStationProvider]
/// for its own key: loading shows a placeholder row, an unresolvable pin an
/// empty one that keeps its index — either way the row stays reorderable
/// and unpinnable instead of vanishing from this dialog.
class _StationPinRow extends ConsumerWidget {
  const _StationPinRow({
    super.key,
    required this.favoriteKey,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onUnpin,
  });

  final String favoriteKey;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(pinnedStationProvider(favoriteKey)).asData?.value;

    Widget title;
    Widget? leadingCover;
    if (station == null) {
      title = Text(
        favoriteKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ).muted();
    } else {
      leadingCover = SidebarPinCover(
        imageUrl: station.faviconUrl,
        side: 32,
        fallbackIcon: SpotubeIcons.radio,
      );
      title = Text(
        station.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(SpotubeIcons.dragHandle),
      ),
      title: Row(
        spacing: 8,
        children: [
          if (leadingCover != null) leadingCover,
          Expanded(child: title),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            tooltip: TooltipContainer(
              child: Text(context.l10n.unpin_from_sidebar),
            ).call,
            child: IconButton.outline(
              icon: const Icon(SpotubeIcons.close),
              onPressed: onUnpin,
            ),
          ),
          IconButton.outline(
            icon: const Icon(Icons.arrow_upward),
            onPressed: isFirst ? null : onMoveUp,
          ),
          IconButton.outline(
            icon: const Icon(Icons.arrow_downward),
            onPressed: isLast ? null : onMoveDown,
          ),
        ],
      ),
    );
  }
}
