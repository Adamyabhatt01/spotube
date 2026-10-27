import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';

/// Actions whose argument is the item a `list` node is currently drawing.
///
/// The renderer injects the typed object into the action's args, so the
/// dispatcher never has to re-resolve an id against a provider that may have
/// moved on since the row was built.
const itemActionTypes = <String>{
  'playItem',
  'openItem',
  'likeItem',
  'downloadItem',
};

/// Flattens one collection entry into the `item.*` binding namespace.
///
/// Collections are handed to slots as their typed objects, not as display
/// strings: a text node formats the value, an image node resolves its URL,
/// and an item action receives the object itself. Every type the host can
/// list has an entry here so a theme never has to know which page it is on.
Map<String, Object?> themeItemBindings(
  Object? item, {
  int index = 0,
  String? activeTrackId,
}) {
  final values = <String, Object?>{
    'item.index': index,
    'item.number': index + 1,
    'item.playing': false,
  };

  switch (item) {
    case SpotubeTrackObject track:
      _track(values, track);
      values['item.playing'] = track.id == activeTrackId;
      values['item.kind'] = 'track';
    case SpotubeFullAlbumObject album:
      _album(
        values,
        SpotubeSimpleAlbumObject(
          id: album.id,
          name: album.name,
          externalUri: album.externalUri,
          artists: album.artists,
          images: album.images,
          albumType: album.albumType,
          releaseDate: album.releaseDate,
        ),
      );
      values['item.kind'] = 'album';
      values['item.trackCount'] = album.totalTracks;
      values['item.label'] = album.recordLabel ?? '';
      values['item.genres'] = (album.genres ?? const []).join(', ');
    case SpotubeSimpleAlbumObject album:
      _album(values, album);
      values['item.kind'] = 'album';
      values['item.trackCount'] = 0;
    case SpotubeFullArtistObject artist:
      values['item.id'] = artist.id;
      values['item.title'] = artist.name;
      values['item.name'] = artist.name;
      values['item.artwork'] = artist.images.asUrlString(
        placeholder: ImagePlaceholder.artist,
      );
      values['item.uri'] = artist.externalUri;
      values['item.kind'] = 'artist';
      values['item.followers'] = artist.followers ?? 0;
      values['item.genres'] = (artist.genres ?? const []).join(', ');
    case SpotubeSimpleArtistObject artist:
      values['item.id'] = artist.id;
      values['item.title'] = artist.name;
      values['item.name'] = artist.name;
      values['item.artwork'] =
          artist.images?.asUrlString(placeholder: ImagePlaceholder.artist) ??
              '';
      values['item.uri'] = artist.externalUri;
      values['item.kind'] = 'artist';
      values['item.followers'] = 0;
    case SpotubeFullPlaylistObject playlist:
      _playlist(
        values,
        SpotubeSimplePlaylistObject(
          id: playlist.id,
          name: playlist.name,
          description: playlist.description,
          externalUri: playlist.externalUri,
          owner: playlist.owner,
          images: playlist.images,
        ),
      );
      values['item.kind'] = 'playlist';
      values['item.collaborative'] = playlist.collaborative;
      values['item.public'] = playlist.public;
    case SpotubeSimplePlaylistObject playlist:
      _playlist(values, playlist);
      values['item.kind'] = 'playlist';
    case DownloadTask task:
      _track(values, task.track);
      values['item.kind'] = 'download';
      values['item.status'] = task.status.name;
      values['item.size'] = task.totalSizeBytes ?? 0;
    case final Map map:
      for (final entry in map.entries) {
        values['item.${entry.key}'] = entry.value;
      }
  }

  return values;
}

void _track(Map<String, Object?> values, SpotubeTrackObject track) {
  final artists = track.artists.map((artist) => artist.name).join(', ');
  values['item.id'] = track.id;
  values['item.title'] = track.name;
  values['item.name'] = track.name;
  values['item.artist'] = artists;
  values['item.artistId'] = track.artists.isEmpty ? '' : track.artists.first.id;
  values['item.album'] = track.album.name;
  values['item.albumId'] = track.album.id;
  values['item.artwork'] = track.album.images.asUrlString(
    placeholder: ImagePlaceholder.albumArt,
  );
  values['item.duration'] = Duration(milliseconds: track.durationMs);
  values['item.uri'] = track.externalUri;
  values['item.explicit'] =
      track is SpotubeFullTrackObject ? track.explicit : false;
}

void _album(Map<String, Object?> values, SpotubeSimpleAlbumObject album) {
  final artistNames = album.artists.map((artist) => artist.name).join(', ');
  final releaseDate = album.releaseDate;
  values['item.id'] = album.id;
  values['item.title'] = album.name;
  values['item.name'] = album.name;
  values['item.artist'] = artistNames;
  values['item.artistId'] = album.artists.isEmpty ? '' : album.artists.first.id;
  values['item.artwork'] = album.images.asUrlString(
    placeholder: ImagePlaceholder.albumArt,
  );
  values['item.uri'] = album.externalUri;
  values['item.releaseDate'] = releaseDate ?? '';
  values['item.year'] =
      releaseDate == null ? '' : (DateTime.tryParse(releaseDate)?.year ?? '');
}

void _playlist(
  Map<String, Object?> values,
  SpotubeSimplePlaylistObject playlist,
) {
  values['item.id'] = playlist.id;
  values['item.title'] = playlist.name;
  values['item.name'] = playlist.name;
  values['item.description'] = playlist.description;
  values['item.owner'] = playlist.owner.name;
  values['item.ownerId'] = playlist.owner.id;
  values['item.artwork'] = playlist.images.asUrlString(
    placeholder: ImagePlaceholder.collection,
  );
  values['item.uri'] = playlist.externalUri;
}
