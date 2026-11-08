part of 'metadata.dart';

@Freezed(genericArgumentFactories: true)
class SpotubeBrowseSectionObject<T> with _$SpotubeBrowseSectionObject<T> {
  factory SpotubeBrowseSectionObject({
    required String id,
    required String title,
    required String externalUri,
    required bool browseMore,
    required List<T> items,
  }) = _SpotubeBrowseSectionObject<T>;

  factory SpotubeBrowseSectionObject.fromJson(
    Map<String, Object?> json,
    T Function(Map<String, dynamic> json) fromJsonT,
  ) =>
      _$SpotubeBrowseSectionObjectFromJson<T>(
        json,
        (json) => fromJsonT(json as Map<String, dynamic>),
      );
}

/// Decodes the polymorphic entries a browse section can hold.
///
/// The plugin payload identifies the kind by shape: a playlist has an
/// `owner`, an album has `artists`, and everything else is an artist. The
/// live endpoint and the snapshot reader share this so a cached section
/// decodes to the same types the network produced.
Object spotubeBrowseItemFromJson(Map<String, dynamic> json) {
  if (json['owner'] != null) {
    return SpotubeSimplePlaylistObject.fromJson(json);
  }
  if (json['artists'] != null) {
    return SpotubeSimpleAlbumObject.fromJson(json);
  }
  return SpotubeFullArtistObject.fromJson(json);
}

/// Encodes a browse section and its polymorphic items for a snapshot.
///
/// `SpotubeBrowseSectionObject.toJson` takes the item serializer as an
/// argument (freezed generic argument factories), so it cannot be
/// dynamic-dispatched like the other snapshot items.
Map<String, dynamic> spotubeBrowseSectionToJson(
  SpotubeBrowseSectionObject<Object> section,
) =>
    section.toJson((item) => (item as dynamic).toJson());
