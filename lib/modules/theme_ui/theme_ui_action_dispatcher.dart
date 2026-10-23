import 'package:auto_route/auto_route.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
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
    switch (action.type) {
      case 'playPause':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        if (audioPlayer.isPlaying) {
          await audioPlayer.pause();
        } else {
          await audioPlayer.resume();
        }
      case 'next':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        await audioPlayer.skipToNext();
      case 'previous':
        if (ref.read(audioPlayerProvider).activeTrack == null) return;
        await audioPlayer.skipToPrevious();
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
    }
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'themeUiAction:${action.type}');
  }
}

Future<void> _seek(WidgetRef ref, Map<String, dynamic> args) async {
  final duration = audioPlayer.duration;
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
  await audioPlayer.seek(
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
  await audioPlayer.setShuffle(target);
}

Future<void> _setLoopMode(WidgetRef ref, Map<String, dynamic> args) async {
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
  await audioPlayer.setLoopMode(mode);
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
