import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';

class MetadataPluginBrowseSectionItemsNotifier
    extends AutoDisposeFamilyPaginatedAsyncNotifier<Object, String> {
  @override
  Future<SpotubePaginationResponseObject<Object>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).browse.sectionItems(
          arg,
          limit: limit,
          offset: offset,
        );
  }

  @override
  build(arg) async {
    // One retained page per drilled-down section used to live forever; a
    // short keep-alive covers back-navigation without the unbounded growth.
    ref.cacheFor();

    // The future, not the AsyncValue: same loading-echo rule as the plugin
    // providers above. Auth flaps still rebuild (new future per emission).
    await ref.watch(metadataPluginAuthenticatedProvider.future);
    return await fetchGated(() => fetch(0, 20));
  }
}

final metadataPluginBrowseSectionItemsProvider =
    AutoDisposeAsyncNotifierProviderFamily<
    MetadataPluginBrowseSectionItemsNotifier,
    SpotubePaginationResponseObject<Object>,
    String>(
  () => MetadataPluginBrowseSectionItemsNotifier(),
);
