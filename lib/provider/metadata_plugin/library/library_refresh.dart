import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';

/// The shortest gap between two re-reads of the same list.
///
/// A trigger is not a licence to hammer the API: the window-focus event fires
/// every time the user alt-tabs back, and the Playlists page is opened and
/// closed repeatedly. Every trigger shares this one cooldown, so a burst of
/// triggers costs one re-read per list.
const savedLibraryRefreshCooldown = Duration(minutes: 1);

/// The names of the lists the app keeps in step with the account.
class SavedLibraryList {
  static const playlists = 'playlists';
  static const tracks = 'tracks';
  static const albums = 'albums';
  static const artists = 'artists';
}

/// Re-reads the saved library so two devices on the same account agree.
///
/// The saved lists are read once per app session: their build serves the
/// disk snapshot and revalidates behind it, and nothing else ever asks the
/// plugin again. A device that stays open therefore keeps showing whatever
/// the network said when it started — a playlist created on a phone never
/// reaches it, even though Spotify's own clients show it immediately.
///
/// This owns the *when*; the *what* is each notifier's own `refresh()`.
class SavedLibraryRefresher {
  SavedLibraryRefresher({
    required this.refreshers,
    required this.isReady,
    this.cooldown = savedLibraryRefreshCooldown,
  });

  /// The re-reads this refresher can run, by name.
  ///
  /// Each one is expected to do its own work; a failure in one must not stop
  /// the others, because a stale playlists list and a stale albums list are
  /// two different problems.
  final Map<String, Future<void> Function()> refreshers;

  /// Whether a re-read can run at all: signed in, and online.
  final Future<bool> Function() isReady;

  /// The shortest gap between two re-reads of the same list.
  final Duration cooldown;

  final Map<String, DateTime> _lastAttempts = {};

  /// Whether [name] may be re-read right now.
  bool isDue(String name) {
    final last = _lastAttempts[name];
    return last == null || DateTime.now().difference(last) >= cooldown;
  }

  /// Re-reads one list, unless the cooldown forbids it.
  ///
  /// Returns true when a re-read actually ran. A failed re-read still counts
  /// as an attempt: retrying it immediately would only spend more of the
  /// rate-limit budget on the same failure.
  Future<bool> maybeRefresh(String name) async {
    final refresh = refreshers[name];
    if (refresh == null) return false;
    if (!isDue(name)) return false;

    // The readiness check comes before the attempt is recorded: a list that
    // was skipped because the app was signed out or offline has to be
    // re-readable the moment that changes, not a minute later.
    if (!await isReady()) {
      AppLogger.logEvent(
        '[library] $name: sync skipped (signed out or offline)',
      );
      return false;
    }

    _lastAttempts[name] = DateTime.now();

    try {
      await refresh();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }

    return true;
  }

  /// Re-reads every list, one after the other.
  ///
  /// Sequential on purpose: a burst of parallel walks is what earns a rate
  /// limit, and the lists are independent — one failing must not stop the
  /// rest.
  Future<void> refreshAll() async {
    for (final name in refreshers.keys) {
      await maybeRefresh(name);
    }
  }
}

/// The app-wide saved-library refresher.
///
/// It owns the guards that make a re-read safe: the account has to be signed
/// in and the network has to be up. A re-read without either would spend
/// rate-limit budget on a request that cannot succeed.
final savedLibraryRefreshProvider = Provider<SavedLibraryRefresher>((ref) {
  return SavedLibraryRefresher(
    refreshers: {
      // The playlists list walks every page: Spotify appends a new playlist
      // to the *end* of the library, so a page-one probe cannot see it.
      SavedLibraryList.playlists: () => _syncList(
            ref,
            ensureBuilt: () =>
                ref.read(metadataPluginSavedPlaylistsProvider.future),
            refresh: () => ref
                .read(metadataPluginSavedPlaylistsProvider.notifier)
                .refresh(),
            wasDiscarded: () => ref
                .read(metadataPluginSavedPlaylistsProvider.notifier)
                .lastRefreshWasDiscarded,
          ),

      // The liked-tracks list is probed, never walked: it can hold
      // thousands of rows, and a newly liked track arrives at its head.
      SavedLibraryList.tracks: () => _syncList(
            ref,
            ensureBuilt: () =>
                ref.read(metadataPluginSavedTracksProvider.future),
            refresh: () =>
                ref.read(metadataPluginSavedTracksProvider.notifier).refresh(),
            wasDiscarded: () => ref
                .read(metadataPluginSavedTracksProvider.notifier)
                .lastRefreshWasDiscarded,
          ),

      SavedLibraryList.albums: () => _syncList(
            ref,
            ensureBuilt: () =>
                ref.read(metadataPluginSavedAlbumsProvider.future),
            refresh: () =>
                ref.read(metadataPluginSavedAlbumsProvider.notifier).refresh(),
            wasDiscarded: () => ref
                .read(metadataPluginSavedAlbumsProvider.notifier)
                .lastRefreshWasDiscarded,
          ),

      SavedLibraryList.artists: () => _syncList(
            ref,
            ensureBuilt: () =>
                ref.read(metadataPluginSavedArtistsProvider.future),
            refresh: () =>
                ref.read(metadataPluginSavedArtistsProvider.notifier).refresh(),
            wasDiscarded: () => ref
                .read(metadataPluginSavedArtistsProvider.notifier)
                .lastRefreshWasDiscarded,
          ),
    },
    isReady: () => _canReadLibrary(ref),
  );
});

/// Re-reads one list, making sure its own build has landed first.
///
/// A re-read that resolves before the build would simply be overwritten by
/// it, and the change it found would be lost — the exact failure this whole
/// path exists to prevent.
Future<void> _syncList(
  Ref ref, {
  required Future<Object?> Function() ensureBuilt,
  required Future<List<Object?>?> Function() refresh,
  required bool Function() wasDiscarded,
}) async {
  try {
    await ensureBuilt();
  } catch (_) {
    // The list's own build failed. The re-read below talks to the network
    // directly, so it is a second chance rather than a dead end.
  }

  // A rebuild of the list disposes the notifier the re-read was running on,
  // and the result goes with it. Rebuilds are not rare at startup: the
  // plugin manager settling changes the auth state, which rebuilds every
  // saved list. The rebuilt list is the current one, so the re-read is
  // simply done again on it.
  for (var attempt = 0; attempt < 3; attempt++) {
    final items = await refresh();
    if (items != null) return;
    if (!wasDiscarded()) return;
  }
}

/// Whether the account is signed in and the network is up.
Future<bool> _canReadLibrary(Ref ref) async {
  final authenticated = await _authState(ref);

  // "Not signed in" is a definite no. "Could not tell" is not: the plugin
  // may be recovering a session, and a wrongly-blocked sync is worse than a
  // failed one — a failed one keeps the last-known-good list and leaves a
  // trace in the log, while a blocked one leaves a stale list and no trace.
  if (authenticated == false) return false;

  return ref.read(networkAvailableProvider);
}

/// Whether the metadata plugin is signed in: true, false, or null when the
/// answer could not be established.
///
/// The provider is asked for its value first and awaited only when it has
/// none yet: at startup it is usually still loading, and a trigger that
/// arrives in that window should wait for the answer rather than skip the
/// re-read.
Future<bool?> _authState(Ref ref) async {
  final state = ref.read(metadataPluginAuthenticatedProvider);
  final value = state.value;
  if (value != null) return value;

  try {
    return await ref
        .read(metadataPluginAuthenticatedProvider.future)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // The answer could not be established. That is not the same as "signed
    // out", and it must not be treated as one.
    return null;
  }
}
