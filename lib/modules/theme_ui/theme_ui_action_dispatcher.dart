import 'package:auto_route/auto_route.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/logger/logger.dart';

/// Executes a theme action against the host.
///
/// This is the only place a plugin's action vocabulary meets real services,
/// which is why every verb is explicit and every argument is clamped or
/// whitelisted here. A theme can ask for the app's features; it cannot pass a
/// route object, a file path or an arbitrary callback through.
Future<void> dispatchThemeUiAction(
  BuildContext context,
  WidgetRef ref,
  ThemeUiAction action,
) async {
  try {
    final player = ref.read(audioPlayerPortProvider);
    switch (action.type) {
      case 'playPause':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        if (player.isPlaying) {
          await player.pause();
        } else {
          await player.resume();
        }
      case 'next':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        await player.skipToNext();
      case 'previous':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        await player.skipToPrevious();
      case 'seek':
        await _seek(ref, action.args);
      case 'setVolume':
        await _setVolume(ref, action.args);
      case 'setShuffle':
        await _setShuffle(ref, action.args);
      case 'setLoopMode':
        await _setLoopMode(ref, action.args);
      case 'like':
        await _toggleLike(ref);
      case 'download':
        _download(ref);
      case 'openSettings':
        context.navigateTo(const SettingsRoute());
      case 'openLyrics':
        context.navigateTo(const LyricsRoute());
      case 'openQueue':
        context.pushRoute(const PlayerQueueRoute());
      case 'openDownloads':
        context.navigateTo(const UserDownloadsRoute());
      case 'navigate':
        await _navigate(context, ref, action.args);
      case 'toast':
        _toast(context, action.args);
      case 'plugin':
        await _askPlugin(ref, action.args);
      case 'playItem':
        await _playItem(ref, action.args);
      case 'playCollection':
        await _playCollection(context, ref, action.args);
      case 'openItem':
        _openItem(context, action.args);
      case 'likeItem':
        await _likeItem(ref, action.args);
      case 'downloadItem':
        _downloadItem(ref, action.args);
    }
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'themeUiAction:${action.type}');
  }
}

Future<void> _seek(WidgetRef ref, Map<String, dynamic> args) async {
  final player = ref.read(audioPlayerPortProvider);
  final duration = player.duration;
  final seconds = args['position'];
  final fraction = args['fraction'];
  final target = switch ((seconds, fraction)) {
    (final num value, _) => Duration(milliseconds: (value * 1000).round()),
    (_, final num value) => Duration(
        milliseconds: (duration.inMilliseconds * value.clamp(0, 1)).round(),
      ),
    _ => null,
  };
  if (target == null) return;
  final max = duration > Duration.zero ? duration : target;
  await player.seek(
    Duration(
      milliseconds: target.inMilliseconds.clamp(0, max.inMilliseconds).toInt(),
    ),
  );
}

Future<void> _setVolume(WidgetRef ref, Map<String, dynamic> args) async {
  final current = ref.read(volumeProvider);
  final raw = args['volume'] ?? args['value'];
  final target = switch (raw) {
    final num value => value.toDouble(),
    _ =>
      args['delta'] is num ? current + (args['delta'] as num).toDouble() : null,
  };
  if (target == null || !target.isFinite) return;
  await ref.read(volumeProvider.notifier).setVolume(target.clamp(0, 1));
}

Future<void> _setShuffle(WidgetRef ref, Map<String, dynamic> args) async {
  final current = ref.read(audioPlayerProvider).shuffled;
  final raw = args['value'] ?? args['shuffle'];
  final target = raw is bool ? raw : !current;
  await ref.read(audioPlayerPortProvider).setShuffle(target);
}

Future<void> _setLoopMode(WidgetRef ref, Map<String, dynamic> args) async {
  final player = ref.read(audioPlayerPortProvider);
  final raw = args['mode'] ?? args['value'];
  final mode = switch (raw) {
    'off' || 'none' => PlaylistMode.none,
    'all' || 'loop' => PlaylistMode.loop,
    'one' || 'single' || 'track' => PlaylistMode.single,
    _ => switch (ref.read(audioPlayerProvider).loopMode) {
        PlaylistMode.none => PlaylistMode.loop,
        PlaylistMode.loop => PlaylistMode.single,
        _ => PlaylistMode.none,
      },
  };
  await player.setLoopMode(mode);
}

Future<void> _toggleLike(WidgetRef ref) async {
  final track = ref.read(audioPlayerProvider).activeTrack;
  if (track == null) return;
  await ref
      .read(metadataPluginSavedTracksProvider.notifier)
      .toggleFavorite(track);
}

void _download(WidgetRef ref) {
  final track = ref.read(audioPlayerProvider).activeTrack;
  if (track is! SpotubeFullTrackObject) return;
  ref.read(downloadManagerProvider.notifier).addToQueue(track);
}

/// Plays a row from a theme's `list`.
///
/// The renderer injects the typed item and the collection it came from, so a
/// row click starts the surrounding list — not a one-track queue that ends
/// after the song the user picked.
Future<void> _playItem(WidgetRef ref, Map<String, dynamic> args) async {
  final raw = args['item'];
  if (raw is! SpotubeTrackObject) return;

  final notifier = ref.read(audioPlayerProvider.notifier);
  final queue = ref.read(audioPlayerProvider);
  if (queue.tracks.any((track) => track.id == raw.id)) {
    await notifier.jumpToTrack(raw);
    return;
  }

  final items = args['items'] is List
      ? (args['items'] as List).whereType<SpotubeTrackObject>().toList()
      : const <SpotubeTrackObject>[];
  if (items.length > 1) {
    final index = items.indexWhere((track) => track.id == raw.id);
    await notifier.load(
      items,
      initialIndex: index < 0 ? 0 : index,
      autoPlay: true,
    );
    return;
  }
  await notifier.load([raw], autoPlay: true);
}

/// Plays the collection a page owns.
///
/// A content slot replaces the host's play button, so the theme needs a verb
/// for "play the thing this page is about". The page bindings carry the typed
/// list (`collection.tracks` or `artist.topTracks`); reading them at tap time
/// keeps the action from carrying data through the node tree.
Future<void> _playCollection(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> args,
) async {
  final page = ThemeUiPageBindings.read(context);
  if (page == null) return;
  final raw = page['collection.tracks'] ?? page['artist.topTracks'];
  if (raw is! List) return;
  final tracks = raw.whereType<SpotubeTrackObject>().toList();
  if (tracks.isEmpty) return;

  // A collection header's shuffle button is "play this collection, shuffled",
  // not just "toggle shuffle". Setting the mode before the load keeps the
  // first track random instead of always starting at index 0.
  if (args['shuffle'] == true) {
    await ref.read(audioPlayerPortProvider).setShuffle(true);
  }

  await ref.read(audioPlayerProvider.notifier).load(
        tracks,
        initialIndex: 0,
        autoPlay: true,
      );
}

void _openItem(BuildContext context, Map<String, dynamic> args) {
  switch (args['item']) {
    case SpotubeTrackObject track:
      context.navigateTo(TrackRoute(trackId: track.id));
    case SpotubeFullAlbumObject album:
      context.navigateTo(
        AlbumRoute(id: album.id, album: _simpleAlbum(album)),
      );
    case SpotubeSimpleAlbumObject album:
      context.navigateTo(AlbumRoute(id: album.id, album: album));
    case SpotubeFullArtistObject artist:
      context.navigateTo(ArtistRoute(artistId: artist.id));
    case SpotubeSimpleArtistObject artist:
      context.navigateTo(ArtistRoute(artistId: artist.id));
    case SpotubeFullPlaylistObject playlist:
      context.navigateTo(
        PlaylistRoute(id: playlist.id, playlist: _simplePlaylist(playlist)),
      );
    case SpotubeSimplePlaylistObject playlist:
      context.navigateTo(
        PlaylistRoute(id: playlist.id, playlist: playlist),
      );
    case DownloadTask task:
      context.navigateTo(TrackRoute(trackId: task.track.id));
  }
}

Future<void> _likeItem(WidgetRef ref, Map<String, dynamic> args) async {
  final raw = args['item'];
  if (raw is! SpotubeTrackObject) return;
  await ref
      .read(metadataPluginSavedTracksProvider.notifier)
      .toggleFavorite(raw);
}

void _downloadItem(WidgetRef ref, Map<String, dynamic> args) {
  final raw = args['item'];
  final track = raw is DownloadTask ? raw.track : raw;
  if (track is! SpotubeFullTrackObject) return;
  ref.read(downloadManagerProvider.notifier).addToQueue(track);
}

SpotubeSimpleAlbumObject _simpleAlbum(SpotubeFullAlbumObject album) {
  return SpotubeSimpleAlbumObject(
    id: album.id,
    name: album.name,
    externalUri: album.externalUri,
    artists: album.artists,
    images: album.images,
    albumType: album.albumType,
    releaseDate: album.releaseDate,
  );
}

SpotubeSimplePlaylistObject _simplePlaylist(
    SpotubeFullPlaylistObject playlist) {
  return SpotubeSimplePlaylistObject(
    id: playlist.id,
    name: playlist.name,
    description: playlist.description,
    externalUri: playlist.externalUri,
    owner: playlist.owner,
    images: playlist.images,
  );
}

Future<void> _navigate(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> args,
) async {
  final target = args['target'];
  if (target is! String || target.isEmpty) return;

  if (target.startsWith('screen:')) {
    final id = target.substring('screen:'.length);
    if (id.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) return;
    pushThemeUiScreen(ref, id);
    return;
  }

  final route = switch (target) {
    'home' => const HomeRoute(),
    'search' => const SearchRoute(),
    'radio' => const RadioRoute(),
    'stats' => const StatsRoute(),
    'library' => const LibraryRoute(),
    'lyrics' => const LyricsRoute(),
    'queue' => const PlayerQueueRoute(),
    'downloads' => const UserDownloadsRoute(),
    'settings' => const SettingsRoute(),
    'profile' => const ProfileRoute(),
    _ => null,
  };
  if (route == null) return;
  context.navigateTo(route);
}

void _toast(BuildContext context, Map<String, dynamic> args) {
  final raw = args['message'];
  if (raw is! String) return;
  final message = raw.trim();
  if (message.isEmpty) return;
  showToast(
    context: context,
    builder: (context, overlay) {
      return SurfaceCard(
        child: Text(message.length > 300 ? message.substring(0, 300) : message),
      );
    },
  );
}

Future<void> _askPlugin(WidgetRef ref, Map<String, dynamic> args) async {
  final id = args['id'];
  if (id is! String || id.isEmpty || id.length > 64) return;
  final payload = args['payload'];
  final result = await ref
      .read(themePluginProvider.future)
      .then((plugin) => plugin?.theme.onUiAction(
            id,
            payload is Map ? payload.cast<String, dynamic>() : const {},
          ));
  if (result != null) {
    ref.read(themeUiOverrideProvider.notifier).state = result;
  }
}
