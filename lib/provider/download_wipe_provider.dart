import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/downloads/download_wipe.dart';

/// Plans and executes the user's explicit "delete all downloads" action.
///
/// Kept in the provider layer because the wipe is only sound when the download
/// records are cleared first (via [PlaylistMirrorService.forgetEverything]),
/// which is provider-owned state.
class DownloadWiper {
  final Ref _ref;
  const DownloadWiper(this._ref);

  Future<DownloadWipePlan> plan() async {
    final preferences = _ref.read(userPreferencesProvider);
    final cacheRoot = await UserPreferencesNotifier.getMusicCacheDir();
    return planDownloadWipe(
      database: _ref.read(databaseProvider),
      downloadRoot: preferences.downloadLocation,
      cacheRoot: cacheRoot,
      libraryLocations: preferences.localLibraryLocation,
    );
  }

  /// Clears every record and every file the app owns. User library folders are
  /// untouched. Returns the number of files that could not be deleted.
  Future<int> wipe(DownloadWipePlan plan) async {
    try {
      // Records first: this also cancels in-flight transfers and invalidates
      // any background playlist sync, so nothing re-creates a row or writes a
      // file behind the wipe.
      await _ref.read(playlistMirrorServiceProvider).forgetEverything();
      return await executeDownloadWipe(plan);
    } finally {
      _ref.invalidate(localTracksProvider);
    }
  }
}

final downloadWiperProvider = Provider<DownloadWiper>(
  (ref) => DownloadWiper(ref),
);

/// Number of download records on this device. Drives the enable state of the
/// "delete all downloads" action.
final downloadRecordCountProvider = StreamProvider<int>(
  (ref) => watchDownloadRecordCount(ref.watch(databaseProvider)),
);
