import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginBrowseSectionsNotifier
    extends AutoDisposePaginatedAsyncNotifier<
        SpotubeBrowseSectionObject<Object>>
    with SavedListCacheMixin<SpotubeBrowseSectionObject<Object>> {
  @override
  String? get snapshotKey => librarySnapshotKeyBrowseSections;

  /// Each section holds playlists, albums and artists by shape, not by a
  /// single type; the shared helper decodes the same way the live endpoint
  /// does.
  @override
  SpotubeBrowseSectionObject<Object> Function(Map<String, dynamic>)?
      get snapshotDecoder =>
          (json) => SpotubeBrowseSectionObject<Object>.fromJson(
                json,
                spotubeBrowseItemFromJson,
              );

  @override
  Object? Function(SpotubeBrowseSectionObject<Object>)? get snapshotEncoder =>
      spotubeBrowseSectionToJson;

  // A snapshot is already on screen; a 429 should stop at the session gate
  // instead of spending its cooldown on retries.
  @override
  bool get retryRateLimits => false;

  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).browse.sections(
          limit: limit,
          offset: offset,
        );
  }

  @override
  build() async {
    // Retained briefly after last use (not forever): home remounts used to
    // be free only because this never disposed.
    ref.cacheFor();

    // The snapshot paints the shelves immediately. No auth watch: waiting
    // for the auth future's 3 s credential ceiling was the empty-home delay,
    // and an auth flap would spend an extra request per settle.
    return await buildSavedList();
  }
}

final metadataPluginBrowseSectionsProvider = AutoDisposeAsyncNotifierProvider<
    MetadataPluginBrowseSectionsNotifier,
    SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>(
  () => MetadataPluginBrowseSectionsNotifier(),
);
