import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';

class MetadataPluginArtistAlbumNotifier extends AutoDisposeFamilyPaginatedAsyncNotifier<
    SpotubeSimpleAlbumObject, String> {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).artist.albums(
          arg,
          limit: limit,
          offset: offset,
        );
  }

  @override
  build(arg) async {
    // Matches the top-tracks sibling: kept briefly, not forever.
    ref.cacheFor();

    // The future, not the AsyncValue: watching the value rebuilds (and
    // refetches page 1) once for the loading emission and again for data.
    // A recreated plugin VM still yields a new future, so invalidation on
    // plugin switch is preserved.
    await ref.watch(metadataPluginProvider.future);
    return await fetchGated(() => fetch(0, 20));
  }
}

final metadataPluginArtistAlbumsProvider =
    AutoDisposeAsyncNotifierProviderFamily<
    MetadataPluginArtistAlbumNotifier,
    SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>,
    String>(
  () => MetadataPluginArtistAlbumNotifier(),
);
