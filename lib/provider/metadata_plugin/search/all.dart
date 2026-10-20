import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

final metadataPluginSearchAllProvider =
    FutureProvider.autoDispose.family<SpotubeSearchResponseObject, String>(
  (ref, query) async {
    final metadataPlugin = await ref.watch(metadataPluginProvider.future);

    if (metadataPlugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    return runGated(
      ref.read(rateLimitGateProvider.notifier),
      () => metadataPlugin.search.all(query),
    );
  },
);

final metadataPluginSearchChipsProvider = FutureProvider((ref) async {
  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }
  // Same 15 s ceiling as every other interactive read: a stalled plugin must
  // fail the chips row, not the whole search shell. (`chips` is a sync
  // getter, so it is lifted into a future for the gated runner.)
  return runGated(
    ref.read(rateLimitGateProvider.notifier),
    () async => metadataPlugin.search.chips,
  );
});
