import 'package:auto_route/annotations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/player/player_queue.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';

@RoutePage()
class PlayerQueuePage extends HookConsumerWidget {
  const PlayerQueuePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(
      audioPlayerProvider,
    );
    final playlistNotifier = ref.read(audioPlayerProvider.notifier);
    final nextTracks = playlist.currentIndex >= 0
        ? playlist.tracks.skip(playlist.currentIndex + 1).toList()
        : playlist.tracks;
    return ThemePageContent(
      slot: 'queue.content',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      bindings: {
        'queue.tracks': playlist.tracks,
        'queue.next': nextTracks,
        'queue.currentIndex': playlist.currentIndex,
        'queue.count': playlist.tracks.length,
      },
      fallback: Scaffold(
        child: SafeArea(
          bottom: false,
          child: PlayerQueue.fromAudioPlayerNotifier(
            floating: false,
            playlist: playlist,
            notifier: playlistNotifier,
          ),
        ),
      ),
    );
  }
}
