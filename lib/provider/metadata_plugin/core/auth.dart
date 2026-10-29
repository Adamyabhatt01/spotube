import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';
import 'package:spotube/services/metadata/metadata.dart';

class MetadataPluginAuthenticatedNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() async {
    final defaultPluginConfig = ref.watch(metadataPluginsProvider);
    if (defaultPluginConfig.asData?.value.defaultMetadataPluginConfig?.abilities
            .contains(PluginAbilities.authentication) !=
        true) {
      return false;
    }

    final defaultPlugin = await ref.watch(metadataPluginProvider.future);
    if (defaultPlugin == null) {
      return false;
    }

    // The plugin reads its stored credentials asynchronously, and until it
    // has, `isAuthenticated()` answers false. Publishing that as the truth
    // and correcting it a moment later rebuilt every provider that watches
    // this one — the saved lists among them — which re-read the whole
    // library for nothing and threw away whatever the library sync was in
    // the middle of.
    //
    // So wait for the credentials to land before answering. The wait is
    // short (the plugin reads them from local storage) and bounded: a
    // plugin that never says is treated as "loaded", which is the older,
    // less careful behaviour.
    await _awaitCredentials(defaultPlugin);

    final sub = defaultPlugin.auth.authStateStream.listen((event) {
      // Account boundary: cached library snapshots belong to whoever was
      // signed in before, so drop them on explicit login/logout. "recovered"
      // and "refreshed" keep the same account and must not evict them.
      if (event is Map &&
          (event['type'] == 'login' || event['type'] == 'logout')) {
        unawaited(clearLibrarySnapshots(ref.read(databaseProvider)));
      }

      // Only a change of the *answer* is a change.
      //
      // A token refresh ("refreshed") and a recovered session ("recovered")
      // re-emit the same value, and writing it again rebuilds every provider
      // that watches this one — the saved lists among them. That re-reads
      // the whole library for nothing, and on a rejected token it loops:
      // read → 401 → refresh the token → rebuild → read → 401 → …
      // The library never settled, and never got the new rows.
      final authenticated = defaultPlugin.auth.isAuthenticated();
      if (state.value != authenticated) {
        state = AsyncData(authenticated);
      }
    });

    ref.onDispose(() {
      sub.cancel();
    });

    return defaultPlugin.auth.isAuthenticated();
  }

  /// Waits until the plugin has read its stored credentials.
  ///
  /// Bounded: a plugin that never answers is treated as loaded, which is the
  /// older and less careful behaviour — but a hang here would hold the whole
  /// library hostage.
  Future<void> _awaitCredentials(MetadataPlugin plugin) async {
    const step = Duration(milliseconds: 50);
    const ceiling = Duration(seconds: 3);

    var waited = Duration.zero;
    while (waited < ceiling) {
      if (plugin.auth.isCredentialsLoaded()) return;
      await Future<void>.delayed(step);
      waited += step;
    }
  }
}

final metadataPluginAuthenticatedProvider =
    AsyncNotifierProvider<MetadataPluginAuthenticatedNotifier, bool>(
  MetadataPluginAuthenticatedNotifier.new,
);

/// The account the app is signed in as — and nothing else.
///
/// The saved lists watch this rather than
/// [metadataPluginAuthenticatedProvider] itself. The auth provider's *state*
/// goes "unknown" for a moment every time the plugin is reloaded — which
/// happens at startup, when the bundled plugins are seeded and the default
/// handover runs — and every one of those flaps rebuilt the saved lists.
/// A rebuild re-read the whole library for nothing, and it threw away
/// whatever the library sync was in the middle of, so the sync never landed.
///
/// This provider answers with the last *settled* answer, so it changes only
/// when the account does.
class MetadataAccountNotifier extends Notifier<bool> {
  bool _last = false;

  @override
  bool build() {
    final auth = ref.watch(metadataPluginAuthenticatedProvider);

    // A state that is not a settled answer is not an answer: keep the last
    // one rather than flapping to "signed out" and back.
    final settled = auth.whenOrNull(data: (value) => value);
    if (settled != null) _last = settled;

    return _last;
  }
}

final metadataAccountProvider = NotifierProvider<MetadataAccountNotifier, bool>(
    MetadataAccountNotifier.new);

class AudioSourcePluginAuthenticatedNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() async {
    final defaultPluginConfig = ref.watch(metadataPluginsProvider);
    if (defaultPluginConfig
            .asData?.value.defaultAudioSourcePluginConfig?.abilities
            .contains(PluginAbilities.authentication) !=
        true) {
      return false;
    }

    final defaultPlugin = await ref.watch(audioSourcePluginProvider.future);
    if (defaultPlugin == null) {
      return false;
    }

    final sub = defaultPlugin.auth.authStateStream.listen((event) {
      state = AsyncData(defaultPlugin.auth.isAuthenticated());
    });

    ref.onDispose(() {
      sub.cancel();
    });

    return defaultPlugin.auth.isAuthenticated();
  }
}

final audioSourcePluginAuthenticatedProvider =
    AsyncNotifierProvider<AudioSourcePluginAuthenticatedNotifier, bool>(
  AudioSourcePluginAuthenticatedNotifier.new,
);
