import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';
import 'package:spotube/provider/radio/stations.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

/// Bounded memo of pins the owning directory resolved over the network.
///
/// [radioHistoryProvider] declares `readsFrom: {historyTable}`, so it re-emits
/// on *any* history insert — including the track scrobbles of an ordinary music
/// session. A pin that is in neither offline snapshot (pinning does not
/// favorite, so anything never played qualifies) therefore re-asks the directory
/// on every one of those emissions: one round-trip per pin per track played.
///
/// Only successes are stored — a miss is exactly the answer that may change
/// once the directory loads or the station appears — and the whole memo is
/// dropped when the installed directory set changes, because a plugin update
/// rotates stream URLs. Capped so a long session cannot grow it without bound;
/// the same trade the playback fallback memo makes (`fallbackUrlsFor`).
///
/// Container-scoped rather than a top-level variable: the memo's lifetime should
/// be the app's (and a test's) container, not the isolate's, or one test's
/// resolution would satisfy the next one's directory.
class _NetworkResolvedPins {
  static const limit = 32;

  final Map<String, RadioStation> _stations = {};
  List<RadioDirectoryProvider>? _registry;

  /// Drop everything when the registry this memo was filled from is no longer
  /// the one being offered. Compared by identity, not by directory id: a plugin
  /// *update* keeps its display name (which is the id) and rotates its stream
  /// URLs, so an id-based signature would happily serve a stale stream URL for
  /// the rest of the session.
  void resetIfRegistryChanged(List<RadioDirectoryProvider> directories) {
    if (identical(_registry, directories)) return;
    _registry = directories;
    _stations.clear();
  }

  RadioStation? operator [](String favoriteKey) => _stations[favoriteKey];

  void operator []=(String favoriteKey, RadioStation station) {
    if (_stations.length >= limit && !_stations.containsKey(favoriteKey)) {
      _stations.remove(_stations.keys.first);
    }
    _stations[favoriteKey] = station;
  }
}

final _networkResolvedPinsProvider =
    Provider<_NetworkResolvedPins>((ref) => _NetworkResolvedPins());

/// Resolves one sidebar-pinned station from its persisted `favoriteKey`
/// (`"$provider:$id"`), or null when it cannot be found.
///
/// Order is deliberate: the favorites snapshot carries the full station
/// object and reads offline; the listen-history snapshot is the second
/// offline source; only then does the owning directory get asked over the
/// network. A miss resolves to null (never a throw) so the sidebar skips
/// the pin exactly like it skips a deleted playlist pin — the same
/// skip-never-crash rule, minus the playlist index.
///
/// Reads are synchronous snapshots rather than awaited futures on purpose:
/// awaiting inside the build lets a snapshot emission rebuild the provider
/// mid-flight and discard the in-flight directory call, so one pin costs a
/// directory call per emission instead of one. While the snapshots are still
/// loading the directory is authoritative anyway, and the provider rebuilds
/// (re-resolving from the snapshots) the moment either snapshot lands.
final pinnedStationProvider =
    FutureProvider.autoDispose.family<RadioStation?, String>(
  (ref, favoriteKey) async {
    final sep = favoriteKey.indexOf(':');
    if (sep < 0) return null;
    final providerId = favoriteKey.substring(0, sep);
    final stationId = favoriteKey.substring(sep + 1);
    if (providerId.isEmpty || stationId.isEmpty) return null;

    final favorites = ref.watch(radioFavoritesProvider).asData?.value ??
        const <RadioStation>[];
    for (final station in favorites) {
      if (station.favoriteKey == favoriteKey) return station;
    }

    final history =
        ref.watch(radioHistoryProvider).asData?.value ?? const <RadioStation>[];
    for (final station in history) {
      if (station.favoriteKey == favoriteKey) return station;
    }

    // Watched, not read: the registry is a mutable global, so this is the only
    // thing that makes a pin re-resolve when the plugin sync finally populates
    // it. Reading it would freeze the empty registry this provider first saw.
    final directories = ref.watch(radioDirectoryRegistryProvider);

    final memo = ref.read(_networkResolvedPinsProvider);
    memo.resetIfRegistryChanged(directories);
    final memoized = memo[favoriteKey];
    if (memoized != null) return memoized;

    for (final directory in directories) {
      if (directory.id != providerId) continue;
      try {
        final station = await directory.byId(stationId);
        if (station != null) memo[favoriteKey] = station;
        return station;
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'pinned station $favoriteKey');
        return null;
      }
    }
    return null;
  },
);
