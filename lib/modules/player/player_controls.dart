import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/collections/intents.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/utils/platform.dart';

class PlayerControls extends HookConsumerWidget {
  final PaletteGenerator? palette;
  final bool compact;

  /// False when the theme moved the seek bar out to the player's own row
  /// (`progress: "below"`), so the transport column stops reserving it.
  /// Only the desktop bar opts out; the full-screen and mini players always
  /// draw their own.
  final bool progressInline;

  const PlayerControls({
    this.palette,
    this.compact = false,
    this.progressInline = true,
    super.key,
  });

  static FocusNode focusNode = FocusNode();

  @override
  Widget build(BuildContext context, ref) {
    final shortcuts = useMemoized(
        () => {
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  SeekIntent(ref, true),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  SeekIntent(ref, false),
            },
        [ref]);
    final actions = useMemoized(
        () => {
              SeekIntent: SeekAction(),
            },
        []);
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;
    final theme = Theme.of(context);

    final buttonSize =
        kIsMobile ? const ButtonSize(1.5) : const ButtonSize(1.2);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (focusNode.canRequestFocus) {
          focusNode.requestFocus();
        }
      },
      child: FocusableActionDetector(
        focusNode: focusNode,
        shortcuts: shortcuts,
        actions: actions,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              if (!compact && progressInline)
                const PlayerProgress(inline: true),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Consumer(builder: (context, ref, _) {
                    final shuffled = ref
                        .watch(audioPlayerProvider.select((s) => s.shuffled));
                    return Tooltip(
                      tooltip: TooltipContainer(
                        child: Text(
                          shuffled
                              ? context.l10n.unshuffle_playlist
                              : context.l10n.shuffle_playlist,
                        ),
                      ).call,
                      child: IconButton(
                        size: buttonSize,
                        icon: Icon(
                          SpotubeIcons.shuffle,
                          color: shuffled ? theme.colorScheme.primary : null,
                          size: 22,
                        ),
                        variance: shuffled
                            ? ButtonVariance.secondary
                            : ButtonVariance.ghost,
                        onPressed: isFetchingActiveTrack
                            ? null
                            : () {
                                if (shuffled) {
                                  audioPlayer.setShuffle(false);
                                } else {
                                  audioPlayer.setShuffle(true);
                                }
                              },
                      ),
                    );
                  }),
                  Tooltip(
                    tooltip: TooltipContainer(
                      child: Text(context.l10n.previous_track),
                    ).call,
                    child: IconButton.ghost(
                      size: buttonSize,
                      enabled: !isFetchingActiveTrack,
                      icon: const Icon(SpotubeIcons.skipBack),
                      onPressed: audioPlayer.skipToPrevious,
                    ),
                  ),
                  Tooltip(
                    tooltip: TooltipContainer(
                      child: Text(
                        playing
                            ? context.l10n.pause_playback
                            : context.l10n.resume_playback,
                      ),
                    ).call,
                    child: IconButton.primary(
                      size: buttonSize,
                      shape: ButtonShape.circle,
                      icon: isFetchingActiveTrack
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(),
                            )
                          : Icon(
                              playing ? SpotubeIcons.pause : SpotubeIcons.play,
                            ),
                      onPressed: isFetchingActiveTrack
                          ? null
                          : Actions.handler<PlayPauseIntent>(
                              context,
                              PlayPauseIntent(ref),
                            ),
                    ),
                  ),
                  Tooltip(
                    tooltip:
                        TooltipContainer(child: Text(context.l10n.next_track))
                            .call,
                    child: IconButton.ghost(
                      size: buttonSize,
                      icon: const Icon(SpotubeIcons.skipForward),
                      onPressed:
                          isFetchingActiveTrack ? null : audioPlayer.skipToNext,
                    ),
                  ),
                  Consumer(builder: (context, ref, _) {
                    final loopMode = ref
                        .watch(audioPlayerProvider.select((s) => s.loopMode));

                    return Tooltip(
                      tooltip: TooltipContainer(
                        child: Text(
                          loopMode == PlaylistMode.single
                              ? context.l10n.loop_track
                              : loopMode == PlaylistMode.loop
                                  ? context.l10n.repeat_playlist
                                  : "",
                        ),
                      ).call,
                      child: IconButton(
                        size: buttonSize,
                        icon: Icon(
                          loopMode == PlaylistMode.single
                              ? SpotubeIcons.repeatOne
                              : SpotubeIcons.repeat,
                          color: loopMode != PlaylistMode.none
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        variance: loopMode == PlaylistMode.single ||
                                loopMode == PlaylistMode.loop
                            ? ButtonVariance.secondary
                            : ButtonVariance.ghost,
                        onPressed: isFetchingActiveTrack
                            ? null
                            : () async {
                                await audioPlayer.setLoopMode(
                                  switch (loopMode) {
                                    PlaylistMode.loop => PlaylistMode.single,
                                    PlaylistMode.single => PlaylistMode.none,
                                    PlaylistMode.none => PlaylistMode.loop,
                                  },
                                );
                              },
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 5)
            ],
          ),
        ),
      ),
    );
  }
}
