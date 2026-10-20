import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';

class MetadataPluginPlaylistNotifier
    extends AutoDisposeFamilyAsyncNotifier<SpotubeFullPlaylistObject, String> {
  bool _disposed = false;

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
  }) async {
    final userId = await ref
        .read(metadataPluginUserProvider.selectAsync((data) => data?.id));
    if (userId == null) {
      throw Exception('User ID is not available. Please log in first.');
    }

    state = const AsyncValue.loading();
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

      return playlist;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      onError?.call(e);
      rethrow;
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
