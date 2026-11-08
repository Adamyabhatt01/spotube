import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginAlbumReleasesNotifier
    extends AutoDisposePaginatedAsyncNotifier<SpotubeSimpleAlbumObject>
    with SavedListCacheMixin<SpotubeSimpleAlbumObject> {
  @override
  String? get snapshotKey => librarySnapshotKeyNewReleases;

  @override
  SpotubeSimpleAlbumObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeSimpleAlbumObject.fromJson;

  // A snapshot is already on screen; a 429 should stop at the session gate
  // instead of spending its cooldown on retries.
  @override
  bool get retryRateLimits => false;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin)
        .album
        .releases(limit: limit, offset: offset);
  }

  @override
  build() async {
    ref.cacheFor();

    // The snapshot paints immediately; the network revalidation behind it is
    // the same fetch the old build blocked on. No auth watch: this shelf is
    // market catalog data, and waiting for the auth future's 3 s credential
    // ceiling was exactly the empty-home delay. A rebuild on every auth flap
    // would also spend an extra request per settle.
    return await buildSavedList();
  }
}

final metadataPluginAlbumReleasesProvider = AutoDisposeAsyncNotifierProvider<
    MetadataPluginAlbumReleasesNotifier,
    SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>(
  () => MetadataPluginAlbumReleasesNotifier(),
);
