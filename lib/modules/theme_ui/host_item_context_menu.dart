import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/dialogs/confirm_download_dialog.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/components/track_presentation/presentation_actions.dart';
import 'package:spotube/components/track_tile/track_context_menu.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_region.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/playlist/playlist_create_dialog.dart';
import 'package:spotube/modules/playlist/playlist_delete.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/artist/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/tracks/album.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';

/// Right-click / long-press menu for a host-owned non-track item (album,
/// playlist or artist) opened through a `contextMenu` node with `hostItem:
/// true`.
///
/// Track items keep the host's existing [TrackContextMenu] exactly as today;
/// this widget only handles album/playlist/artist. The rows are built from the
/// shared `contextMenuDefaults` table for the item's target, and host verbs
/// are dispatched through [dispatchThemeUiAction] or routed directly, mirroring
/// [TrackContextMenu._onSelected] and [PlaylistContextMenu].
///
/// Collection verbs (`play`, `addToQueue`, `download`) resolve the item's
/// tracks through the same providers the cards and pages use — page 1 plus
/// `appendCollectionTail` for playback, a full walk for queue/download — so a
/// menu tap behaves exactly like the matching card button.
class HostItemContextMenu extends StatelessWidget {
  const HostItemContextMenu({
    super.key,
    required this.item,
    required this.child,
  });

  final Object? item;
  final Widget child;

  static ContextMenuTarget? _targetFor(Object? item) {
    if (item is SpotubeTrackObject) return ContextMenuTarget.track;
    if (item is SpotubeSimpleAlbumObject || item is SpotubeFullAlbumObject) {
      return ContextMenuTarget.album;
    }
    if (item is SpotubeSimplePlaylistObject ||
        item is SpotubeFullPlaylistObject) {
      return ContextMenuTarget.playlist;
    }
    if (item is SpotubeSimpleArtistObject || item is SpotubeFullArtistObject) {
      return ContextMenuTarget.artist;
    }
    return null;
  }

  static String? _playlistId(Object? item) {
    if (item is SpotubeSimplePlaylistObject) return item.id;
    if (item is SpotubeFullPlaylistObject) return item.id;
    return null;
  }

  static String? _albumId(Object? item) {
    if (item is SpotubeSimpleAlbumObject) return item.id;
    if (item is SpotubeFullAlbumObject) return item.id;
    return null;
  }

  static String? _artistId(Object? item) {
    if (item is SpotubeSimpleArtistObject) return item.id;
    if (item is SpotubeFullArtistObject) return item.id;
    return null;
  }

  static String? _playlistOwnerId(Object? item) {
    if (item is SpotubeSimplePlaylistObject) return item.owner.id;
    if (item is SpotubeFullPlaylistObject) return item.owner.id;
    return null;
  }

  static SpotubeSimpleAlbumObject? _asSimpleAlbum(Object? item) {
    if (item is SpotubeSimpleAlbumObject) return item;
    if (item is SpotubeFullAlbumObject) {
      return SpotubeSimpleAlbumObject(
        id: item.id,
        name: item.name,
        externalUri: item.externalUri,
        artists: item.artists,
        images: item.images,
        albumType: item.albumType,
        releaseDate: item.releaseDate,
      );
    }
    return null;
  }

  static SpotubeSimplePlaylistObject? _asSimplePlaylist(Object? item) {
    if (item is SpotubeSimplePlaylistObject) return item;
    if (item is SpotubeFullPlaylistObject) {
      return SpotubeSimplePlaylistObject(
        id: item.id,
        name: item.name,
        description: item.description,
        externalUri: item.externalUri,
        owner: item.owner,
        images: item.images,
      );
    }
    return null;
  }

  static String? _externalUri(Object? item) {
    if (item is SpotubeSimpleAlbumObject) return item.externalUri;
    if (item is SpotubeFullAlbumObject) return item.externalUri;
    if (item is SpotubeSimpleArtistObject) return item.externalUri;
    if (item is SpotubeFullArtistObject) return item.externalUri;
    if (item is SpotubeSimplePlaylistObject) return item.externalUri;
    if (item is SpotubeFullPlaylistObject) return item.externalUri;
    return null;
  }

  /// The host action ids this surface can actually run, matching the defaults
  /// table for each target. Anything outside the set never renders, which is
  /// why the Settings → Context Menu configuration appeared broken: the
  /// whitelist, not the config, was hiding the rows.
  static Set<String> _supportedIds(ContextMenuTarget target) {
    switch (target) {
      case ContextMenuTarget.album:
        return const {
          'play',
          'addToQueue',
          'download',
          'goToArtist',
          'copyLink',
        };
      case ContextMenuTarget.artist:
        return const {'play', 'addToQueue', 'download', 'copyLink'};
      case ContextMenuTarget.playlist:
        return const {
          'play',
          'open',
          'pin',
          'unpin',
          'addToQueue',
          'download',
          'rename',
          'delete',
          'copyLink',
        };
      default:
        return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetFor(item);
    if (target == null) return child;

    // Track rows keep the host's existing track menu exactly as today.
    // (`item` is a field, so copy to a local for type promotion.)
    final track = item;
    if (track is SpotubeTrackObject) {
      return TrackContextMenu(track: track, child: child);
    }

    return ContextMenuRegion(
      item: ContextMenuItemContext(target: target, item: item),
      builderFor: (context) => _builderFor(context, target),
      onSelected: (context, container, action) =>
          _onSelected(context, container, action),
      child: child,
    );
  }

  ContextMenuBuilder _builderFor(BuildContext context, ContextMenuTarget target) {
    final container = ProviderScope.containerOf(context, listen: false);
    final ui = container.read(themeUiProvider).asData?.value;

    // Which declared pin targets actually hold this playlist: the sidebar
    // keeps its preference column, every other target lives in themePins.
    Set<String> pinnedTargetsFor() {
      final id = _playlistId(item);
      if (id == null) return const {};
      final prefs = container.read(userPreferencesProvider);
      final pins = container.read(themePinsProvider.notifier);
      return {
        for (final target in context.layout.pinTargets)
          if (target.id == 'sidebar'
              ? prefs.pinnedPlaylistIds.contains(id)
              : pins.isPinned(target.id, id))
            target.id,
      };
    }

    final playlistId =
        target == ContextMenuTarget.playlist ? _playlistId(item) : null;
    final pinnedTargets =
        target == ContextMenuTarget.playlist ? pinnedTargetsFor() : const <String>{};

    // Owner-gated rows (`rename`, `delete`) and the play/pause label swap
    // read these flags; they are resolved once when the menu opens, never
    // watched, so a grid of cards holds no subscriptions for them.
    var owner = false;
    var playing = false;
    if (playlistId != null) {
      final ownerId = _playlistOwnerId(item);
      final meId =
          container.read(metadataPluginUserProvider).asData?.value?.id;
      owner = playlistId != likedTracksPlaylistId &&
          ownerId != null &&
          meId != null &&
          ownerId == meId;
      final playerState = container.read(audioPlayerProvider);
      playing = playerState.collections.contains(playlistId) &&
          playerState.playing;
    }

    return ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: container.read(contextMenuConfigProvider),
      pinTargets: context.layout.pinTargets,
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
      availableActions: _supportedIds(target),
      itemFlags: {
        if (playlistId != null) ...{
          'pinned': pinnedTargets.isNotEmpty,
          'pinnedTargets': pinnedTargets,
          'owner': owner,
          'playing': playing,
        },
      },
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    ProviderContainer container,
    ContextMenuAction action,
  ) async {
    final themeAction = action.themeAction;
    if (themeAction != null) {
      await dispatchThemeUiAction(context, container, themeAction);
      return;
    }

    // The pin submenu resolves to `pin:<target>` for both directions; the
    // target's current state decides which way the toggle goes.
    if (action.id.startsWith('pin:')) {
      await _togglePinTo(
        container,
        action.id.substring('pin:'.length),
      );
      return;
    }

    switch (action.id) {
      case 'open':
        await dispatchThemeUiAction(
          context,
          container,
          ThemeUiAction('openItem', <String, dynamic>{'item': item}),
        );
      case 'copyLink':
        _copyLink(context);
      case 'goToArtist':
        _goToArtist(context);
      case 'pin':
      case 'unpin':
        _togglePin(container);
      case 'play':
        await _play(context, container);
      case 'addToQueue':
        await _addToQueue(context, container);
      case 'download':
        await _download(context, container);
      case 'rename':
        await _renamePlaylist(context, container);
      case 'delete':
        // Let the dropdown/drawer finish dismissing before the dialog
        // opens, so the two overlays cannot fight over the barrier.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) unawaited(_deletePlaylist(context, container));
        });
    }
  }

  // --- Collection verbs -------------------------------------------------

  /// Plays the item the way its card's play button does: pause/resume while
  /// the collection is already queued, otherwise load page 1 and stream the
  /// tail in behind it (albums and playlists), or the artist's top tracks.
  Future<void> _play(BuildContext context, ProviderContainer container) async {
    final album = _asSimpleAlbum(item);
    if (album != null) return _playAlbum(context, container, album);

    final artistId = _artistId(item);
    if (artistId != null) return _playArtist(context, container, artistId);

    final playlist = _asSimplePlaylist(item);
    if (playlist != null) return _playPlaylist(context, container, playlist);
  }

  Future<void> _playAlbum(
    BuildContext context,
    ProviderContainer container,
    SpotubeSimpleAlbumObject album,
  ) async {
    final playerState = container.read(audioPlayerProvider);
    if (playerState.collections.contains(album.id)) {
      final port = container.read(audioPlayerPortProvider);
      return playerState.playing ? port.pause() : port.resume();
    }

    final initial = await _fetchOrToast(
      context,
      container,
      () async => (await container.read(
        metadataPluginAlbumTracksProvider(album.id).future,
      ))
          .items,
    );
    if (initial == null || initial.isEmpty || !context.mounted) return;

    final isRemote = await showSelectDeviceDialog(context, container.read);
    if (isRemote == null || !context.mounted) return;

    Future<List<SpotubeFullTrackObject>> fetchAll() async {
      await container.read(metadataPluginAlbumTracksProvider(album.id).future);
      return container.read(
        metadataPluginAlbumTracksProvider(album.id).notifier,
      ).fetchAll();
    }

    if (isRemote) {
      final all = await fetchAll();
      if (all.isEmpty) return;
      await container.read(connectProvider.notifier).load(
            WebSocketLoadEventData.album(
              tracks: all,
              collection: album,
            ),
          );
      return;
    }

    final notifier = container.read(audioPlayerProvider.notifier);
    await notifier.load(initial, autoPlay: true);
    await notifier.addCollection(album.id);
    unawaited(
      container.read(playbackHistoryActionsProvider).addAlbums([album]),
    );
    unawaited(
      appendCollectionTail(
        appendTail: (tail) => notifier.addTracks(tail),
        readCollections: () => container.read(audioPlayerProvider).collections,
        collectionId: album.id,
        alreadyLoaded: initial,
        fetchAll: fetchAll,
      ),
    );
  }

  /// An artist has no queue collection of its own; "play" means its top
  /// tracks, matching the artist page's play button (including the
  /// pause/resume toggle while those tracks are already queued).
  Future<void> _playArtist(
    BuildContext context,
    ProviderContainer container,
    String artistId,
  ) async {
    final tracks = await _fetchOrToast(
      context,
      container,
      () async => (await container.read(
        metadataPluginArtistTopTracksProvider(artistId).future,
      ))
          .items,
    );
    if (tracks == null || tracks.isEmpty || !context.mounted) return;

    final playerState = container.read(audioPlayerProvider);
    if (AudioPlayerState.listContainsTracks(playerState.tracks, tracks)) {
      final port = container.read(audioPlayerPortProvider);
      return playerState.playing ? port.pause() : port.resume();
    }

    final isRemote = await showSelectDeviceDialog(context, container.read);
    if (isRemote == null || !context.mounted) return;

    if (isRemote) {
      await container.read(metadataPluginArtistTopTracksProvider(artistId)
          .future);
      final all = await container.read(
        metadataPluginArtistTopTracksProvider(artistId).notifier,
      ).fetchAll();
      if (all.isEmpty) return;
      await container.read(connectProvider.notifier).load(
            WebSocketLoadEventData.playlist(
              tracks: all,
              collection: null,
            ),
          );
      return;
    }

    await container.read(audioPlayerProvider.notifier).load(
          tracks,
          autoPlay: true,
        );
  }

  /// Mirrors `usePlaylistPlay`: the fetch helpers already own the Liked
  /// Tracks synthetic playlist and the offline mirror fallback.
  Future<void> _playPlaylist(
    BuildContext context,
    ProviderContainer container,
    SpotubeSimplePlaylistObject playlist,
  ) async {
    final playerState = container.read(audioPlayerProvider);
    if (playerState.collections.contains(playlist.id)) {
      final port = container.read(audioPlayerPortProvider);
      return playerState.playing ? port.pause() : port.resume();
    }

    final initial = await _fetchOrToast(
      context,
      container,
      () => fetchPlaylistInitialTracks(container.read, playlist),
    );
    if (initial == null || initial.isEmpty || !context.mounted) return;

    final isRemote = await showSelectDeviceDialog(context, container.read);
    if (isRemote == null || !context.mounted) return;

    if (isRemote) {
      final all = await _fetchOrToast(
        context,
        container,
        () => fetchPlaylistAllTracks(container.read, playlist),
      );
      if (all == null || all.isEmpty) return;
      await container.read(connectProvider.notifier).load(
            WebSocketLoadEventData.playlist(
              tracks: all,
              collection: playlist,
            ),
          );
      return;
    }

    final notifier = container.read(audioPlayerProvider.notifier);
    await notifier.load(initial, autoPlay: true);
    await notifier.addCollection(playlist.id);
    unawaited(
      container.read(playbackHistoryActionsProvider).addPlaylists([playlist]),
    );
    unawaited(
      appendCollectionTail(
        appendTail: (tail) => notifier.addTracks(tail),
        readCollections: () => container.read(audioPlayerProvider).collections,
        collectionId: playlist.id,
        alreadyLoaded: initial,
        fetchAll: () => fetchPlaylistAllTracks(container.read, playlist),
      ),
    );
  }

  Future<void> _addToQueue(
    BuildContext context,
    ProviderContainer container,
  ) async {
    final album = _asSimpleAlbum(item);
    if (album != null) return _addAlbumToQueue(context, container, album);

    final artistId = _artistId(item);
    if (artistId != null) return _addArtistToQueue(context, container, artistId);

    final playlist = _asSimplePlaylist(item);
    if (playlist != null) {
      return _addPlaylistToQueue(context, container, playlist);
    }
  }

  Future<void> _addAlbumToQueue(
    BuildContext context,
    ProviderContainer container,
    SpotubeSimpleAlbumObject album,
  ) async {
    if (container.read(audioPlayerProvider).collections.contains(album.id)) {
      return;
    }
    final tracks = await _fetchOrToast(
      context,
      container,
      () => _albumAllTracks(container, album.id),
    );
    if (tracks == null || tracks.isEmpty || !context.mounted) return;

    final notifier = container.read(audioPlayerProvider.notifier);
    await notifier.addTracks(tracks);
    await notifier.addCollection(album.id);
    unawaited(
      container.read(playbackHistoryActionsProvider).addAlbums([album]),
    );
    if (!context.mounted) return;
    showToastForAction(context, 'add-to-queue', tracks.length);
  }

  Future<void> _addArtistToQueue(
    BuildContext context,
    ProviderContainer container,
    String artistId,
  ) async {
    final tracks = await _fetchOrToast(
      context,
      container,
      () async => (await container.read(
        metadataPluginArtistTopTracksProvider(artistId).future,
      ))
          .items,
    );
    if (tracks == null || tracks.isEmpty || !context.mounted) return;

    await container.read(audioPlayerProvider.notifier).addTracks(tracks);
    if (!context.mounted) return;
    showToastForAction(context, 'add-to-queue', tracks.length);
  }

  Future<void> _addPlaylistToQueue(
    BuildContext context,
    ProviderContainer container,
    SpotubeSimplePlaylistObject playlist,
  ) async {
    if (container.read(audioPlayerProvider).collections.contains(playlist.id)) {
      return;
    }
    final tracks = await _fetchOrToast(
      context,
      container,
      () => fetchPlaylistAllTracks(container.read, playlist),
    );
    if (tracks == null || tracks.isEmpty || !context.mounted) return;

    final notifier = container.read(audioPlayerProvider.notifier);
    await notifier.addTracks(tracks);
    await notifier.addCollection(playlist.id);
    unawaited(
      container.read(playbackHistoryActionsProvider).addPlaylists([playlist]),
    );
    if (!context.mounted) return;
    showToastForAction(context, 'add-to-queue', tracks.length);
  }

  /// Whole-collection download: confirm dialog, then the download manager —
  /// the same path `TrackPresentationActionsSection` takes for "download
  /// all". A playlist also mirrors so the page keeps membership and order.
  Future<void> _download(
    BuildContext context,
    ProviderContainer container,
  ) async {
    String? collectionId;
    SpotubeSimplePlaylistObject? mirror;
    Future<List<SpotubeFullTrackObject>> Function() fetch;

    final albumId = _albumId(item);
    if (albumId != null) {
      fetch = () => _albumAllTracks(container, albumId);
    } else {
      final artistId = _artistId(item);
      if (artistId != null) {
        fetch = () => _artistAllTracks(container, artistId);
      } else {
        final playlist = _asSimplePlaylist(item);
        if (playlist == null) return;
        collectionId = playlist.id;
        mirror = playlist;
        fetch = () => fetchPlaylistAllTracks(container.read, playlist);
      }
    }

    final tracks = await _fetchOrToast(context, container, fetch);
    if (tracks == null || tracks.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => const ConfirmDownloadDialog(),
        ) ??
        false;
    if (confirmed != true || !context.mounted) return;

    container.read(downloadManagerProvider.notifier).addAllToQueue(
          tracks,
          collectionId: collectionId,
        );
    if (mirror != null) {
      unawaited(
        container.read(playlistMirrorServiceProvider).mirror(mirror, tracks),
      );
    }
    if (!context.mounted) return;
    showToastForAction(context, 'download', tracks.length);
  }

  // --- Playlist management ----------------------------------------------

  /// Whether the signed-in account owns this playlist. The `when` flag on
  /// the rename/delete rows already hides them for other people's playlists;
  /// this re-checks at tap time because the menu can outlive a login change.
  Future<bool> _isOwner(ProviderContainer container) async {
    final id = _playlistId(item);
    final ownerId = _playlistOwnerId(item);
    if (id == null ||
        id == likedTracksPlaylistId ||
        ownerId == null ||
        ownerId.isEmpty) {
      return false;
    }
    try {
      final me = await container.read(metadataPluginUserProvider.future);
      return me != null && me.id == ownerId;
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return false;
    }
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    ProviderContainer container,
  ) async {
    final id = _playlistId(item);
    if (id == null || !await _isOwner(container) || !context.mounted) return;
    // Same dialog the playlist header's edit button opens; deferred a frame
    // so the menu finishes dismissing first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => PlaylistCreateDialog(playlistId: id),
        ),
      );
    });
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    ProviderContainer container,
  ) async {
    final id = _playlistId(item);
    if (id == null || !await _isOwner(container) || !context.mounted) return;
    await deletePlaylistWithConfirmation(context, container.read, id);
  }

  // --- Shared helpers ----------------------------------------------------

  Future<List<SpotubeFullTrackObject>> _albumAllTracks(
    ProviderContainer container,
    String albumId,
  ) async {
    await container.read(metadataPluginAlbumTracksProvider(albumId).future);
    return container.read(
      metadataPluginAlbumTracksProvider(albumId).notifier,
    ).fetchAll();
  }

  Future<List<SpotubeFullTrackObject>> _artistAllTracks(
    ProviderContainer container,
    String artistId,
  ) async {
    await container.read(metadataPluginArtistTopTracksProvider(artistId).future);
    return container.read(
      metadataPluginArtistTopTracksProvider(artistId).notifier,
    ).fetchAll();
  }

  /// Runs [fetch], reporting failures the way `usePlaylistPlay` does: an
  /// offline miss gets the offline toast, anything else the generic one.
  Future<List<SpotubeFullTrackObject>?> _fetchOrToast(
    BuildContext context,
    ProviderContainer container,
    Future<List<SpotubeFullTrackObject>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      if (context.mounted) _errorToast(context, container);
      return null;
    }
  }

  void _errorToast(BuildContext context, ProviderContainer container) {
    final isOnline = container.read(isOnlineProvider).asData?.value ?? true;
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(
        child: Text(
          isOnline
              ? context.l10n.something_went_wrong
              : context.l10n.you_are_offline,
        ),
      ),
    );
  }

  void _copyLink(BuildContext context) {
    final uri = _externalUri(item);
    if (uri == null || uri.isEmpty) return;
    Clipboard.setData(ClipboardData(text: uri));
    if (!context.mounted) return;
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(
        child: Text(context.l10n.copied_shareurl_to_clipboard(uri)),
      ),
    );
  }

  void _goToArtist(BuildContext context) {
    final it = item;
    String? artistId;
    if (it is SpotubeSimpleAlbumObject) {
      artistId = it.artists.isNotEmpty ? it.artists.first.id : null;
    } else if (it is SpotubeFullAlbumObject) {
      artistId = it.artists.isNotEmpty ? it.artists.first.id : null;
    } else if (it is SpotubeSimpleArtistObject) {
      artistId = it.id;
    } else if (it is SpotubeFullArtistObject) {
      artistId = it.id;
    }
    if (artistId == null || artistId.isEmpty) return;
    if (!context.mounted) return;
    context.navigateTo(ArtistRoute(artistId: artistId));
  }

  Future<void> _togglePinTo(
    ProviderContainer container,
    String target,
  ) async {
    final id = _playlistId(item);
    if (id == null) return;
    if (target == 'sidebar') {
      container
          .read(userPreferencesProvider.notifier)
          .togglePinnedPlaylist(id);
      return;
    }
    final pins = container.read(themePinsProvider);
    final pinned = (pins[target] ?? const <String>[]).contains(id);
    container
        .read(themePinsProvider.notifier)
        .setPinned(target, id, pinned: !pinned);
  }

  void _togglePin(ProviderContainer container) {
    final id = _playlistId(item);
    if (id == null) return;
    container.read(userPreferencesProvider.notifier).togglePinnedPlaylist(id);
  }
}
