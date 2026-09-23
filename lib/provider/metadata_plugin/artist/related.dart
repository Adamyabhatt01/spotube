import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';

class MetadataPluginArtistRelatedArtistsNotifier
    extends AutoDisposeFamilyPaginatedAsyncNotifier<
        SpotubeFullArtistObject, String> {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).artist.related(
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
    await ref.watch(metadataPluginProvider.future);
    return await fetchGated(() => fetch(0, 20));
  }
}

final metadataPluginArtistRelatedArtistsProvider =
    AutoDisposeAsyncNotifierProviderFamily<
    MetadataPluginArtistRelatedArtistsNotifier,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>,
    String>(
  () => MetadataPluginArtistRelatedArtistsNotifier(),
);
