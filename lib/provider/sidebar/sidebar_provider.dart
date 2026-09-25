import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/playlist_download_provider.dart';

/// Default order of the sidebar Library group. Stable ids matching
/// [SideBarTiles.id] in `lib/collections/side_bar_tiles.dart`.
const defaultSidebarLibraryOrder = [
  'playlists',
  'artists',
  'albums',
  'local_library',
];

/// Pure order resolution for the sidebar Library group.
///
/// Stored ids come first with unknown ids dropped (a removed tile must not
/// strand the list); any missing defaults are appended so a newly added
/// tile appears at the end until the user reorders it.
List<String> resolveSidebarLibraryOrder(List<String> stored) {
  final ordered = [
    for (final id in stored)
      if (defaultSidebarLibraryOrder.contains(id)) id,
  ];
  for (final id in defaultSidebarLibraryOrder) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  return ordered;
}

/// Moves the entry at [from] to [to] within [order]; both index the same
/// visible list. Returns a new list, never mutating the input. Out-of-range
/// indexes yield a copy unchanged, so a stray drop event cannot corrupt the
/// persisted order. Shared by the Settings order dialog and the in-sidebar
/// drag handles so both persist through the same math.
List<String> moveSidebarEntry(List<String> order, int from, int to) {
  if (from < 0 || from >= order.length || to < 0 || to >= order.length) {
    return List.of(order);
  }
  if (from == to) return List.of(order);
  final reordered = List<String>.of(order);
  final moved = reordered.removeAt(from);
  reordered.insert(to, moved);
  return reordered;
}

/// Moves the pin at [from] to [to]; both index into [visible], the ids the
/// UI actually shows. Pinned ids with no playlist behind them (deleted,
/// offline, still loading — or below the rail cap) are hidden, so indexing
/// [pins] directly would move the wrong entry. Hidden ids keep their relative
/// order and sink below the visible ones.
List<String> moveSidebarPin(
  List<String> pins,
  List<String> visible,
  int from,
  int to,
) {
  if (from < 0 || from >= visible.length || to < 0 || to >= visible.length) {
    return List.of(pins);
  }
  final reordered = moveSidebarEntry(visible, from, to);
  return [
    ...reordered,
    for (final id in pins)
      if (!visible.contains(id)) id,
  ];
}

/// Maps a directional drop onto visible indexes: dropping on the top half of
/// a row inserts before it, on the bottom half after it — so the bottom half
/// of the last row is how an item reaches the very end. Returns null when the
/// drop changes nothing (unknown ids, self-drop, or an adjacent drop that
/// would reproduce the current order).
({int from, int to})? resolveSidebarDrop(
  List<String> visible,
  String draggedId,
  String targetId, {
  required bool after,
}) {
  final from = visible.indexOf(draggedId);
  final target = visible.indexOf(targetId);
  if (from == -1 || target == -1 || from == target) return null;
  final int to;
  if (after) {
    to = from < target ? target : target + 1;
  } else {
    to = from < target ? target - 1 : target;
  }
  if (to < 0 || to >= visible.length || to == from) return null;
  return (from: from, to: to);
}

/// Stable partition of the Playlists page list: pinned playlists first in pin
/// order, everything else keeping its existing (Spotify) order.
///
/// [pinnedIds] holds raw playlist ids, including the `"user-liked-tracks"`
/// synthetic. A pinned id with no object in [playlists] (deleted, offline,
/// not yet loaded) is skipped, never a placeholder — the same rule the
/// sidebar pinned block uses. Empty [pinnedIds] returns an equal copy, so
/// non-pinners see zero reorder churn. Never mutates the input. Only applied
/// when the page filter is empty; search ranking bypasses it.
List<SpotubeSimplePlaylistObject> pinnedFirstPlaylists(
  List<SpotubeSimplePlaylistObject> playlists,
  List<String> pinnedIds,
) {
  if (pinnedIds.isEmpty) return List.of(playlists);
  final byId = {for (final playlist in playlists) playlist.id: playlist};
  final pinnedSet = pinnedIds.toSet();
  return [
    for (final id in pinnedIds)
      if (byId[id] != null) byId[id]!,
    for (final playlist in playlists)
      if (!pinnedSet.contains(playlist.id)) playlist,
  ];
}

/// Saved + mirrored playlists keyed by id, for sidebar pins.
///
/// Same merge as `UserPlaylistsPage` (saved first, mirrored supplying what
/// the network did not, deduped by id) minus the liked-tracks synthetic and
/// the search filter: the sidebar builds that entry itself because its name
/// needs `l10n`, which providers cannot reach. A pinned id absent from this
/// map (deleted, offline, logged out) renders skipped, never a crash.
final sidebarPlaylistIndexProvider =
    Provider<Map<String, SpotubeSimplePlaylistObject>>((ref) {
  final saved =
      ref.watch(metadataPluginSavedPlaylistsProvider).asData?.value.items ??
          const <SpotubeSimplePlaylistObject>[];
  final mirrored =
      ref.watch(mirroredPlaylistsProvider).asData?.value ?? const [];

  final seen = <String>{};
  final index = <String, SpotubeSimplePlaylistObject>{};
  for (final playlist in [...saved, ...mirrored]) {
    if (seen.add(playlist.id)) {
      index[playlist.id] = playlist;
    }
  }
  return index;
});
