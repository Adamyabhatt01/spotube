import 'package:spotube/collections/assets.gen.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Stable id of the synthetic "Liked Tracks" playlist entry.
///
/// Built in UI (not in a provider) because its display name needs `l10n`,
/// which providers cannot reach. Shared by the sidebar, the sidebar order
/// dialog and the Playlists page so all three agree on its identity.
const likedTracksPlaylistId = "user-liked-tracks";

/// Owner placeholder for the synthetic entry when the account is signed in
/// but the live profile fetch is unavailable (offline: `user.me()` has no
/// snapshot fallback). Only `name` ever renders (Liked page header), so an
/// empty owner is preferable to dropping the whole entry. Never used when
/// logged out — [resolveLikedTracksPlaylist] returns null there instead.
SpotubeUserObject fallbackLikedTracksOwner() =>
    SpotubeUserObject(id: '', name: '', externalUri: '');

/// Builds the synthetic Liked Tracks entry. [owner] is the live profile when
/// reachable, otherwise [fallbackLikedTracksOwner].
SpotubeSimplePlaylistObject buildLikedTracksPlaylist({
  required String name,
  required String description,
  required SpotubeUserObject owner,
}) {
  return SpotubeSimplePlaylistObject(
    id: likedTracksPlaylistId,
    name: name,
    description: description,
    externalUri: "",
    owner: owner,
    images: [
      SpotubeImageObject(
        url: Assets.images.likedTracks.path,
        width: 300,
        height: 300,
      ),
    ],
  );
}

/// Resolves which Liked entry the UI may show: the live profile's, an
/// offline-capable fallback while signed in, or null when logged out.
///
/// - [me] is `metadataPluginUserProvider` data (null offline — the profile
///   fetch has no snapshot fallback).
/// - [authenticated] is `metadataPluginAuthenticatedProvider` data, which is
///   local plugin state and stays true offline, so a pinned Liked entry
///   survives losing the network. The tracks themselves come from the
///   `savedTracks` snapshot, which serves stale-while-revalidate.
SpotubeSimplePlaylistObject? resolveLikedTracksPlaylist({
  required String name,
  required String description,
  required SpotubeUserObject? me,
  required bool? authenticated,
}) {
  final owner =
      me ?? (authenticated == true ? fallbackLikedTracksOwner() : null);
  if (owner == null) return null;
  return buildLikedTracksPlaylist(
    name: name,
    description: description,
    owner: owner,
  );
}
