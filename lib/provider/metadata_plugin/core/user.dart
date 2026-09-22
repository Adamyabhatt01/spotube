import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

final metadataPluginUserProvider = FutureProvider<SpotubeUserObject?>(
  (ref) async {
    final metadataPlugin = await ref.watch(metadataPluginProvider.future);
    final authenticated =
        await ref.watch(metadataPluginAuthenticatedProvider.future);

    if (!authenticated || metadataPlugin == null) {
      return null;
    }
    // Deliberately not gated: this builds once per session and the sidebar
    // reads it to decide whether the account looks signed in, so a 429 from
    // some other screen must not be able to make the profile look logged out.
    return metadataPlugin.user.me();
  },
);
