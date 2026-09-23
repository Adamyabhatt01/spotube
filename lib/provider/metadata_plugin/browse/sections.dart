import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';

class MetadataPluginBrowseSectionsNotifier
    extends AutoDisposePaginatedAsyncNotifier<
        SpotubeBrowseSectionObject<Object>> {
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
    // Retained briefly after last use (not forever): home remounts and
    // auth flaps used to be free only because this never disposed.
    ref.cacheFor();

    // The future, not the AsyncValue: same loading-echo rule as the plugin
    // providers above. Auth flaps still rebuild (new future per emission).
    await ref.watch(metadataPluginAuthenticatedProvider.future);
    return await fetchGated(() => fetch(0, 20));
  }
}

final metadataPluginBrowseSectionsProvider =
    AutoDisposeAsyncNotifierProvider<
    MetadataPluginBrowseSectionsNotifier,
    SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>(
  () => MetadataPluginBrowseSectionsNotifier(),
);
