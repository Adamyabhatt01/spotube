import 'package:spotube/models/metadata/metadata.dart';

/// Applies the persisted main-section playlist order to [playlists].
///
/// Known stored ids come first in stored order; ids with no playlist behind
/// them (deleted, offline, not yet loaded) are skipped. Everything missing from
/// the stored list is appended in the source order, so adding a playlist never
/// resets the custom order. A null order means "never initialized" and behaves
/// exactly like an empty one.
///
/// This is intentionally independent of sidebar pins: the sidebar owns
/// `pinnedPlaylistIds`, the Playlists page owns `mainPlaylistOrder`.
List<SpotubeSimplePlaylistObject> applyMainPlaylistOrder(
  List<SpotubeSimplePlaylistObject> playlists,
  List<String>? storedOrder,
) {
  if (storedOrder == null || storedOrder.isEmpty) return List.of(playlists);

  final byId = {for (final playlist in playlists) playlist.id: playlist};
  final seen = <String>{};
  final ordered = <SpotubeSimplePlaylistObject>[];

  for (final id in storedOrder) {
    final playlist = byId[id];
    if (playlist != null && seen.add(id)) ordered.add(playlist);
  }
  for (final playlist in playlists) {
    if (seen.add(playlist.id)) ordered.add(playlist);
  }
  return ordered;
}

/// Ranks pinned playlists first, in pin order, then everything else in the
/// order it arrived in.
///
/// The sidebar renders pins in `pinnedPlaylistIds` order. A phone has no
/// sidebar, so pinning there used to change nothing the user could see; this
/// applies the same list to the Playlists page in that layout. Pinned ids with
/// no playlist behind them are skipped, and unpinned playlists keep their
/// [playlists] order.
List<SpotubeSimplePlaylistObject> applyPinnedFirst(
  List<SpotubeSimplePlaylistObject> playlists,
  List<String> pinnedIds,
) {
  if (pinnedIds.isEmpty) return List.of(playlists);

  final byId = {for (final playlist in playlists) playlist.id: playlist};
  final seen = <String>{};
  final ordered = <SpotubeSimplePlaylistObject>[];

  for (final id in pinnedIds) {
    final playlist = byId[id];
    if (playlist != null && seen.add(id)) ordered.add(playlist);
  }
  if (ordered.isEmpty) return List.of(playlists);

  for (final playlist in playlists) {
    if (seen.add(playlist.id)) ordered.add(playlist);
  }
  return ordered;
}

/// Moves the visible main-section entry at [from] to [to].
///
/// [visible] is what the dialog actually shows; [storedOrder] may also hold ids
/// that are currently hidden (offline/deleted). Hidden ids keep their relative
/// order and sink below the visible ones, so reordering never discards them.
List<String> moveMainPlaylistEntry(
  List<String>? storedOrder,
  List<String> visible,
  int from,
  int to,
) {
  final stored = storedOrder ?? const <String>[];
  if (from < 0 || from >= visible.length || to < 0 || to >= visible.length) {
    return List.of(stored);
  }

  final reordered = List<String>.of(visible);
  if (from != to) {
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
  }
  final visibleSet = visible.toSet();

  return [
    ...reordered,
    for (final id in stored)
      if (!visibleSet.contains(id)) id,
  ];
}
