import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

/// Auto-disposed with a keep-alive window like every other single-item
/// provider: previously the one family that retained every visited track id
/// for the whole session.
final metadataPluginTrackProvider =
    FutureProvider.autoDispose.family<SpotubeFullTrackObject, String>(
        (ref, trackId) async {
  ref.cacheFor();

  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }

  return runGated(
    ref.read(rateLimitGateProvider.notifier),
    () => metadataPlugin.track.getTrack(trackId),
  );
});
