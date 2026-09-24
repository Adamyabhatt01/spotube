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
