import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final audioPlayerLoopMode = StreamProvider<PlaylistMode>((ref) {
  return ref.read(audioPlayerPortProvider).loopModeStream;
});

final audioPlayerShuffleMode = StreamProvider<bool>((ref) {
  return ref.read(audioPlayerPortProvider).shuffledStream;
});
final audioPlayerPlaying = StreamProvider<bool>((ref) {
  return ref.read(audioPlayerPortProvider).playingStream;
});

final trayMenuProvider = Provider((ref) {
  final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
  final player = ref.read(audioPlayerPortProvider);
  final isPlaybackPlaying =
      ref.watch(audioPlayerProvider.select((s) => s.activeTrack != null));
  final isLoopOne =
      ref.watch(audioPlayerLoopMode).asData?.value == PlaylistMode.single;
  final isShuffled = ref.watch(audioPlayerShuffleMode).asData?.value ?? false;
  final isPlaying = ref.watch(audioPlayerPlaying).asData?.value ?? false;

  return Menu(
    items: [
      MenuItem(
        label: "Show/Hide Window",
        onClick: (menuItem) async {
          if (await windowManager.isVisible()) {
            await windowManager.hide();
          } else {
            await windowManager.focus();
            await windowManager.show();
          }
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: isPlaying ? "Pause" : "Play",
        disabled: !isPlaybackPlaying,
        onClick: (menuItem) async {
          if (player.isPlaying) {
            await player.pause();
          } else {
            await player.resume();
          }
        },
      ),
      MenuItem(
        label: "Next",
        disabled: !isPlaybackPlaying,
        onClick: (menuItem) {
          player.skipToNext();
        },
      ),
      MenuItem(
        label: "Previous",
        disabled: !isPlaybackPlaying,
        onClick: (menuItem) {
          player.skipToPrevious();
        },
      ),
      MenuItem.submenu(
        label: "Playback",
        submenu: Menu(
          items: [
            MenuItem(
              label: "Repeat",
              checked: isLoopOne,
              onClick: (menuItem) {
                player.setLoopMode(
                  isLoopOne ? PlaylistMode.none : PlaylistMode.single,
                );
              },
            ),
            MenuItem(
              label: "Shuffle",
              checked: isShuffled,
              onClick: (menuItem) {
                player.setShuffle(!isShuffled);
              },
            ),
            MenuItem.separator(),
            MenuItem(
              label: "Stop",
              onClick: (menuItem) {
                playlistNotifier.stop();
              },
            ),
          ],
        ),
      ),
      MenuItem.separator(),
      MenuItem(
        label: "Quit",
        onClick: (menuItem) {
          exit(0);
        },
      ),
    ],
  );
});
