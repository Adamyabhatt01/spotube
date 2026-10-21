import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/play_pause_icon.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/string.dart';

class PlaybuttonTile extends HookWidget {
  final void Function()? onTap;
  final void Function()? onPlaybuttonPressed;
  final void Function()? onAddToQueuePressed;
  final void Function()? onPinPressed;
  final String? description;

  final String? imageUrl;
  final Widget? image;

  /// Whether this row's collection is in the player's queue.
  ///
  /// Drives the "is it queued" state, NOT the play/pause icon.
  final bool isPlaying;

  /// Whether the audio is currently sounding from this collection.
  ///
  /// This is what the play/pause icon shows. It differs from [isPlaying]
  /// the moment playback is paused.
  final bool isActuallyPlaying;

  final bool isLoading;

  /// Add-to-queue work only. Kept separate from [isLoading] so filling the
  /// queue never turns the play/pause control into a spinner.
  final bool isQueueLoading;
  final bool isPinned;
  final String title;
  final bool isOwner;

  const PlaybuttonTile({
    required this.isPlaying,
    this.isActuallyPlaying = false,
    required this.isLoading,
    this.isQueueLoading = false,
    required this.title,
    this.description,
    this.onPlaybuttonPressed,
    this.onAddToQueuePressed,
    this.onPinPressed,
    this.onTap,
    this.isOwner = false,
    this.isPinned = false,
    this.imageUrl,
    this.image,
    super.key,
  }) : assert(
          imageUrl != null || image != null,
          "imageUrl and image can't be null at the same time",
        );

  @override
  Widget build(BuildContext context) {
    final cleanDescription = description.strippedHtml();
    final scale = context.theme.scaling;
    // A play spinner is only honest while nothing is sounding. This guards
    // against a caller whose loading flag outlives audible playback (for
    // example, a slow manifest after a downloaded copy has already started).
    final showPlaySpinner = isLoading && !isActuallyPlaying;
    // A preparation flag can outlive audio startup. Once the collection is
    // audible, the control has to become an enabled pause button even if the
    // source manifest (or a tail fetch) is still settling.
    final canPressPlay = !isLoading || isActuallyPlaying;

    // Memoized like the card/tile siblings: building a fresh provider per
    // build re-resolves the image cache on every row rebuild while
    // scrolling. Rounded to whole px so float noise can't fragment keys.
    final decodeSide = (100 * scale).roundToDouble();
    final tileArt = useMemoized(
      () => imageUrl == null
          ? null
          : UniversalImage.imageProvider(
              imageUrl!,
              height: decodeSide,
              width: decodeSide,
            ),
      [imageUrl, decodeSide],
    );

    // The trailing buttons are in a separate row slot and keep winning their
    // own regions; the cover stays part of the row's navigation tap.
    final tileCover = imageUrl != null
        ? Container(
            width: 50 * scale,
            height: 50 * scale,
            decoration: BoxDecoration(
              borderRadius: context.theme.borderRadiusMd,
              image: DecorationImage(
                // Phase 2 perf (IMG.2): decode at 2x the 50x50 display
                // size instead of full resolution.
                image: tileArt!,
                fit: BoxFit.cover,
              ),
            ),
          )
        : SizedBox(
            width: 50 * scale,
            height: 50 * scale,
            child: ClipRRect(
              borderRadius: context.theme.borderRadiusMd,
              child: image,
            ),
          );

    return Button(
      leading: tileCover,
      style: ButtonVariance.ghost.copyWith(
        padding: (context, states, value) {
          return (ButtonVariance.ghost.padding(context, states) as EdgeInsets)
              .copyWith(right: 0, left: 0);
        },
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPinPressed != null) ...[
            Tooltip(
              tooltip: TooltipContainer(
                child: Text(isPinned
                    ? context.l10n.unpin_from_sidebar
                    : context.l10n.pin_to_sidebar),
              ).call,
              child: IconButton.outline(
                icon: Icon(
                  isPinned ? SpotubeIcons.pinOn : SpotubeIcons.pinOff,
                ),
                onPressed: onPinPressed,
                enabled: !isLoading,
              ),
            ),
            const Gap(8),
          ],
          Tooltip(
            tooltip: TooltipContainer(child: Text(context.l10n.add_to_queue)).call,
            child: IconButton.outline(
              icon: const Icon(SpotubeIcons.queueAdd),
              onPressed: onAddToQueuePressed,
              enabled: !isLoading && !isQueueLoading,
            ),
          ),
          const Gap(8),
          Tooltip(
            tooltip: TooltipContainer(child: Text(context.l10n.play)).call,
            child: IconButton.secondary(
              icon: switch ((showPlaySpinner, isActuallyPlaying)) {
                (true, _) => const CircularProgressIndicator(
                    size: 22,
                  ),
                (false, _) => AnimatedPlayPauseIcon(
                    isPlaying: isActuallyPlaying,
                  ),
              },
              onPressed: onPlaybuttonPressed,
              enabled: canPressPlay,
            ),
          ),
        ],
      ),
      // Navigation is independent of playback readiness: gating it on
      // canPressPlay made the whole row a dead tap while tracks resolved.
      enabled: onTap != null,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (cleanDescription.isNotEmpty)
            Text(
              description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ).xSmall().muted(),
        ],
      ),
    );
  }
}
