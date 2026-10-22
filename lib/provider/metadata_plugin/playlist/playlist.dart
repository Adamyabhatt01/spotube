import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/metadata.dart';

class MetadataPluginPlaylistNotifier
    extends AutoDisposeFamilyAsyncNotifier<SpotubeFullPlaylistObject, String> {
  bool _disposed = false;

  /// The library-membership check that ran after the last create.
  ///
  /// Exposed only so a test can wait for it instead of guessing at it with
  /// event-loop rounds: the check runs in the background, after the dialog is
  /// already closed.
  @visibleForTesting
  Future<void>? get libraryCheck => _libraryCheck;

  Future<void>? _libraryCheck;

  Future<MetadataPlugin> get metadataPlugin async {
    final metadataPlugin = await ref.read(metadataPluginProvider.future);

    if (metadataPlugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    return metadataPlugin;
  }

  @override
  build(playlistId) async {
    ref.cacheFor();
    ref.onDispose(() => _disposed = true);

    final plugin = await metadataPlugin;
    return runGated(
      ref.read(rateLimitGateProvider.notifier),
      () => plugin.playlist.getPlaylist(playlistId),
    );
  }

  Future<SpotubeFullPlaylistObject?> create({
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
    List<String> trackIds = const [],
    void Function(dynamic error)? onError,
    void Function(String message)? onWarning,
  }) async {
    final userId = await ref
        .read(metadataPluginUserProvider.selectAsync((data) => data?.id));
    if (userId == null) {
      throw Exception('User ID is not available. Please log in first.');
    }

    state = const AsyncValue.loading();

    // The ids the library holds *before* the create. A playlist that shows
    // up afterwards is the one this call made.
    final beforeIds = ref
            .read(metadataPluginSavedPlaylistsProvider)
            .value
            ?.items
            .map((e) => e.id)
            .toSet() ??
        const <String>{};

    try {
      final plugin = await metadataPlugin;
      final playlist = await plugin.playlist.create(
        userId,
        name: name,
        description: description,
        public: public,
        collaborative: collaborative,
      );
      if (playlist == null) {
        throw Exception('The metadata provider did not return the playlist.');
      }

      AppLogger.logEvent(
        '[library] create "${playlist.name}" -> ${playlist.id}',
      );

      // The remote create already inserted the playlist into the new
      // playlist's notifier. Put it into the saved list immediately instead
      // of invalidating and re-fetching the whole library.
      state = AsyncValue.data(playlist);
      ref.read(metadataPluginSavedPlaylistsProvider.notifier).insertPlaylist(
            SpotubeSimplePlaylistObject(
              id: playlist.id,
              name: playlist.name,
              description: playlist.description,
              externalUri: playlist.externalUri,
              owner: playlist.owner,
              images: playlist.images,
            ),
          );

      if (trackIds.isNotEmpty) {
        try {
          await ref
              .read(metadataPluginSavedPlaylistsProvider.notifier)
              .addTracks(playlist.id, trackIds);
        } catch (e) {
          // The playlist itself exists (and is already in the library).
          // Surface the track failure but keep the created playlist so a
          // retry cannot create a duplicate.
          onError?.call(e);
        }
      }

      // A brand-new playlist often has no cover yet: Spotify generates the
      // collage from its tracks asynchronously. Re-read this one playlist once
      // after the remote side has had a moment; no library-wide refresh, no
      // retry loop.
      if (playlist.images.isEmpty) {
        unawaited(_refreshCoverLater(plugin, playlist));
      }

      // The plugin's create follows the playlist into the account's library,
      // but that step is invisible from here — and it is the one step that
      // decides whether the playlist shows up on the *other* devices. If it
      // failed, the playlist exists on Spotify and in nobody's library:
      // invisible everywhere, including here after a restart.
      unawaited(
        _libraryCheck = _ensureInLibrary(plugin, playlist, onWarning),
      );

      return playlist;
    } catch (e, stackTrace) {
      // The create can fail *after* the playlist already exists. The
      // provider's create is several steps — create it, add it to the
      // account's library, set its visibility, read it back — and only the
      // later ones can fail (a throttled read is routine). Reporting that as
      // "the playlist was not created" is worse than wrong: the playlist sits
      // in the account, and the user would create a second one.
      //
      // So before believing the failure, look for the playlist.
      final adopted = await _adoptCreatedPlaylist(name, beforeIds);
      if (adopted != null) {
        AppLogger.logEvent(
          '[library] create reported a failure but the playlist is there: '
          '"${adopted.name}" -> ${adopted.id}',
        );
        state = AsyncValue.data(adopted);
        ref.read(metadataPluginSavedPlaylistsProvider.notifier).insertPlaylist(
              SpotubeSimplePlaylistObject(
                id: adopted.id,
                name: adopted.name,
                description: adopted.description,
                externalUri: adopted.externalUri,
                owner: adopted.owner,
                images: adopted.images,
              ),
            );
        unawaited(
          _libraryCheck = _ensureInLibrary(
            await metadataPlugin,
            adopted,
            onWarning,
          ),
        );
        return adopted;
      }

      state = AsyncValue.error(e, stackTrace);
      // Reported, not only toasted: a create that fails leaves a playlist
      // on Spotify that no device can see, and the toast is the only thing
      // the user sees — which they may well have missed.
      AppLogger.reportError(e, stackTrace);
      AppLogger.logEvent('[library] create FAILED — $e');
      onError?.call(e);
      rethrow;
    }
  }

  /// Finds the playlist a failed create actually made.
  ///
  /// The library is read fresh and the playlists that were not in it before
  /// the call are candidates; the one carrying the requested name is the
  /// match. The library arrives newest-first, so the first match is the
  /// playlist just made.
  Future<SpotubeFullPlaylistObject?> _adoptCreatedPlaylist(
    String name,
    Set<String> beforeIds,
  ) async {
    try {
      final saved = ref.read(metadataPluginSavedPlaylistsProvider.notifier);

      // The whole list: a new playlist can be at the end of it.
      final items = await saved.refresh(forceFullWalk: true);
      if (items == null) return null;

      for (final item in items) {
        if (beforeIds.contains(item.id)) continue;
        if (item.name.trim() != name.trim()) continue;

        final plugin = await metadataPlugin;
        final full = await plugin.playlist.getPlaylist(item.id);
        return full;
      }
    } catch (_) {
      // The adoption is a best-effort rescue: if it cannot be done, the
      // original failure is the answer.
    }
    return null;
  }

  /// Confirms the freshly created playlist really is in the account's
  /// library, and puts it there if it is not.
  ///
  /// The plugin's create does the library write itself, but the host cannot
  /// see whether it worked — a failure there is silent, and the symptom is
  /// exactly the one this guards against: a playlist that exists on Spotify
  /// and in no device's library.
  ///
  /// Best-effort and off the critical path: the dialog is already closed by
  /// the time this runs, and a failure here never fails the creation.
  Future<void> _ensureInLibrary(
    MetadataPlugin plugin,
    SpotubeFullPlaylistObject playlist,
    void Function(String message)? onWarning,
  ) async {
    try {
      final saved = ref.read(metadataPluginSavedPlaylistsProvider.notifier);

      // The optimistic insert is this device's guess, not evidence. The
      // network is the evidence.
      final ids = await saved.refreshIds();
      final alreadyThere = ids?.contains(playlist.id) ?? false;
      AppLogger.logEvent(
        '[library] created "${playlist.name}" (${playlist.id}): '
        'in account library = ${ids == null ? "unknown" : alreadyThere}',
      );
      if (alreadyThere) return;

      // Not in the library — or the library could not be read, which is the
      // same thing to act on: the write is idempotent in effect, and a
      // playlist that is not in the library is in no device's library.
      //
      // It goes through the session rate-limit gate like every other
      // metadata write: this account is throttled by Spotify often enough
      // that an unretried 429 here loses the library write silently.
      try {
        await runGated(
          ref.read(rateLimitGateProvider.notifier),
          () => plugin.playlist.save(playlist.id),
          maxRetries: maxRateLimitAutoRetries,
        );
        AppLogger.logEvent(
          '[library] created "${playlist.name}" (${playlist.id}): '
          'library write done',
        );
      } catch (e, stack) {
        // "Already in the library" is the benign answer — the plugin's own
        // create usually did the write already — and it is reported as an
        // event rather than an error so a successful creation does not fill
        // the log with noise.
        AppLogger.logEvent(
          '[library] created "${playlist.name}" (${playlist.id}): '
          'library write failed — $e',
        );
        AppLogger.reportError(e, stack);
      }

      final after = await saved.refreshIds();
      if (after == null) return;

      if (!after.contains(playlist.id)) {
        AppLogger.logEvent(
          '[library] created "${playlist.name}" (${playlist.id}): repair did '
          'not put it in the library',
        );
        // Reported as an error, not only through the toast: the toast needs
        // a live context, and this runs long after the dialog that created
        // the playlist is gone. This line is what Settings → Logs shows.
        AppLogger.reportError(
          StateError(
            'Playlist "${playlist.name}" (${playlist.id}) was created but is '
            'not in the account library. It exists on Spotify and in no '
            "device's library, so it will not appear on other devices.",
          ),
          StackTrace.current,
        );
        onWarning?.call(playlist.name);
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Re-reads one just-created playlist after its cover has had time to be
  /// generated remotely. This is deliberately a single best-effort request:
  /// it never loops and never refreshes the rest of the library.
  Future<void> _refreshCoverLater(
    MetadataPlugin plugin,
    SpotubeFullPlaylistObject playlist,
  ) async {
    final delay = ref.read(playlistCoverRefreshDelayProvider);
    await Future<void>.delayed(delay);
    if (_disposed) return;

    try {
      final refreshed = await plugin.playlist.getPlaylist(playlist.id);
      if (_disposed || refreshed.images.isEmpty) return;

      if (state.value?.id == playlist.id) {
        state = AsyncValue.data(refreshed);
      }

      final simple = SpotubeSimplePlaylistObject(
        id: refreshed.id,
        name: refreshed.name,
        description: refreshed.description,
        externalUri: refreshed.externalUri,
        owner: refreshed.owner,
        images: refreshed.images,
      );
      ref
          .read(metadataPluginSavedPlaylistsProvider.notifier)
          .updatePlaylist(simple);
    } catch (_) {
      // Cover art is best-effort. A failed refresh must not fail creation or
      // trigger a retry storm.
    }
  }

  Future<void> modify({
    String? name,
    String? description,
    bool? public,
    bool? collaborative,
    void Function(dynamic error)? onError,
  }) async {
    try {
      if (name == null &&
          description == null &&
          public == null &&
          collaborative == null) {
        throw Exception('No modifications provided.');
      }
      await (await metadataPlugin).playlist.update(
            arg,
            name: name,
            description: description,
            public: public,
            collaborative: collaborative,
          );

      final current = state.value;
      if (current != null) {
        final updated = current.copyWith(
          name: name ?? current.name,
          description: description ?? current.description,
          public: public ?? current.public,
          collaborative: collaborative ?? current.collaborative,
        );
        final simple = SpotubeSimplePlaylistObject(
          id: updated.id,
          name: updated.name,
          description: updated.description,
          externalUri: updated.externalUri,
          owner: updated.owner,
          images: updated.images,
        );
        ref
            .read(metadataPluginSavedPlaylistsProvider.notifier)
            .updatePlaylist(simple);
        await ref.read(playlistMirrorServiceProvider).updateMetadata(simple);
      }

      ref.invalidateSelf();
    } on Exception catch (e) {
      onError?.call(e);
      rethrow;
    }
  }

  Future<void> addTracks(List<String> trackIds,
      [void Function(dynamic error)? onError]) async {
    if (state.value == null) return;

    try {
      await ref
          .read(metadataPluginSavedPlaylistsProvider.notifier)
          .addTracks(arg, trackIds);
    } catch (e) {
      onError?.call(e);
      rethrow;
    }
  }

  Future<void> removeTracks(List<String> trackIds,
      [void Function(dynamic error)? onError]) async {
    try {
      if (state.value == null) return;

      await ref
          .read(metadataPluginSavedPlaylistsProvider.notifier)
          .removeTracks(arg, trackIds);
    } catch (e) {
      onError?.call(e);
      rethrow;
    }
  }

  Future<void> delete() async {
    if (state.value == null) return;
    final userId = await ref
        .read(metadataPluginUserProvider.selectAsync((data) => data?.id));
    if (userId == null || userId != state.value!.owner.id) {
      throw Exception('You can only delete your own playlists.');
    }

    await ref.read(metadataPluginSavedPlaylistsProvider.notifier).delete(arg);
  }
}

final metadataPluginPlaylistProvider = AutoDisposeAsyncNotifierProviderFamily<
    MetadataPluginPlaylistNotifier, SpotubeFullPlaylistObject, String>(
  () => MetadataPluginPlaylistNotifier(),
);

/// Delay before the single best-effort cover re-read after a playlist is
/// created. Overridable in tests so they do not wait on a real timer.
final playlistCoverRefreshDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);
