import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/intents.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';

/// The transport play/pause control used by the docked and floating players.
///
/// The widget owns the playback watch on purpose. Reading the playing flag in
/// the caller's `build` rebuilt the whole blurred player card on every toggle,
/// which repaints the card's `BackdropFilter`. On Android that repaint can
/// ghost the backdrop while Impeller reuses the previous inline blur pass —
/// the multi-`BackdropFilter` flicker of flutter/flutter#173622 (fixed in the
/// engine only from Flutter 3.38 / commit 84f5d26). Keeping the watch here,
/// plus the [RepaintBoundary] around the button, confines a toggle to this
/// widget: the card and the controls row around it neither rebuild nor
/// repaint.
class PlayerPlayPauseButton extends ConsumerWidget {
  /// Button size, matching the caller's transport row. Defaults to shadcn's
  /// normal icon size.
  final ButtonSize? size;

  /// Button shape. The docked/full-player control is circular; the compact
  /// mini player keeps the default rectangle.
  final ButtonShape? shape;

  /// Whether the control is the filled primary action (docked/full player)
  /// rather than a ghost button (mini player).
  final bool primary;

  /// Whether to wrap the button in the localized play/pause tooltip. The
  /// compact mini player has no tooltip today; the docked bar does.
  final bool showTooltip;

  const PlayerPlayPauseButton({
    super.key,
    this.size,
    this.shape,
    this.primary = false,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(audioPlayerProvider.select((s) => s.playing));
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final button = IconButton(
      size: size ?? ButtonSize.normal,
      shape: shape ?? ButtonShape.rectangle,
      variance: primary ? ButtonVariance.primary : ButtonVariance.ghost,
      icon: isFetchingActiveTrack
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(),
            )
          : Icon(playing ? SpotubeIcons.pause : SpotubeIcons.play),
      onPressed: isFetchingActiveTrack
          ? null
          : Actions.handler<PlayPauseIntent>(context, PlayPauseIntent(ref)),
    );

    // The icon swap (and the spinner's per-frame animation while a track is
    // being resolved) must not dirty the player card's backdrop filter.
    final isolated = RepaintBoundary(child: button);

    if (!showTooltip) return isolated;

    return Tooltip(
      tooltip: TooltipContainer(
        child: Text(
          playing ? context.l10n.pause_playback : context.l10n.resume_playback,
        ),
      ).call,
      child: isolated,
    );
  }
}
