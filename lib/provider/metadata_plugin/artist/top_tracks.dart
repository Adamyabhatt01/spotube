import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';

class MetadataPluginArtistTopTracksNotifier
    extends AutoDisposeFamilyPaginatedAsyncNotifier<SpotubeFullTrackObject,
        String> {
  MetadataPluginArtistTopTracksNotifier() : super();

  @override
  fetch(offset, limit) async {
    final tracks = await (await metadataPlugin).artist.topTracks(
          arg,
          offset: offset,
          limit: limit,
        );

    return tracks;
  }

  @override
  build(arg) async {
    ref.cacheFor();

    // The future, not the AsyncValue: watching the value rebuilds (and
    // refetches page 1) once for the loading emission and again for data.
    // A recreated plugin VM still yields a new future, so invalidation on
    // plugin switch is preserved.
    await ref.watch(metadataPluginProvider.future);
    return await fetchGated(() => fetch(0, 20));
  }
}

final metadataPluginArtistTopTracksProvider =
    AutoDisposeAsyncNotifierProviderFamily<
        MetadataPluginArtistTopTracksNotifier,
        SpotubePaginationResponseObject<SpotubeFullTrackObject>,
        String>(
  () => MetadataPluginArtistTopTracksNotifier(),
);
