import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/play_pause_icon.dart';
import 'package:spotube/components/playbutton_view/collection_row_policy.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/string.dart';

class PlaybuttonTile extends HookWidget {
  final void Function()? onTap;
  final void Function()? onPlaybuttonPressed;
  final void Function()? onAddToQueuePressed;
  final void Function()? onPinPressed;

  /// Tapping the cover plays (or resumes) the collection. Null keeps the
  /// cover as part of the row's navigation tap.
  final void Function()? onCoverTap;

  /// The theme-managed row policy: which trailing actions render, whether the
  /// cover plays, whether the subtitle shows, and how dense the row is.
  ///
  /// Defaults preserve the historical presentation for every non-theme
  /// caller; a theme host widget overrides it through
  /// `collectionRowPolicyFromProps`.
  final CollectionRowPolicy rowPolicy;

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
    this.onCoverTap,
    this.rowPolicy = const CollectionRowPolicy(),
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
    final decodeSide =
        ((rowPolicy.coverSize ?? 50) * 2 * scale).roundToDouble();
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

    final coverEdge = (rowPolicy.coverSize ?? 50) * scale;
    final coverRadius = rowPolicy.coverRadius == null
        ? context.theme.borderRadiusMd
        : BorderRadius.circular(rowPolicy.coverRadius! * scale);

    final tileCover = imageUrl != null
        ? Container(
            width: coverEdge,
            height: coverEdge,
            decoration: BoxDecoration(
              borderRadius: coverRadius,
              image: DecorationImage(
                // Phase 2 perf (IMG.2): decode at 2x the display size
                // instead of full resolution.
                image: tileArt!,
                fit: BoxFit.cover,
              ),
            ),
          )
        : SizedBox(
            width: coverEdge,
            height: coverEdge,
            child: ClipRRect(
              borderRadius: coverRadius,
              child: image,
            ),
          );

    // A cover tap is its own hit region: Spotify plays the collection
    // instead of just navigating to it.
    final tappableCover = onCoverTap == null
        ? tileCover
        : Tooltip(
            tooltip: TooltipContainer(child: Text(context.l10n.play)).call,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCoverTap,
                child: Semantics(
                  label: context.l10n.play,
                  button: true,
                  child: tileCover,
                ),
              ),
            ),
          );

    // A cover-only row is the collapsed sidebar rail: the cover is the whole
    // row, so the title and the trailing actions have nowhere to go.
    if (!rowPolicy.showTitle) {
      // A playing cover must not sit inside a disabled Button: the disabled
      // state can swallow the cover's own tap, leaving the rail dead.
      if (rowPolicy.coverPlays && onCoverTap != null) {
        return tappableCover;
      }
      return Button(
        style: ButtonVariance.ghost.copyWith(
          padding: (context, states, value) {
            return (ButtonVariance.ghost.padding(context, states) as EdgeInsets)
                .copyWith(right: 0, left: 0);
          },
        ),
        // The cover owns the tap when it plays; otherwise the row navigates.
        enabled: rowPolicy.coverPlays ? false : onTap != null,
        onPressed: rowPolicy.coverPlays ? null : onTap,
        child: rowPolicy.coverPlays ? tappableCover : tileCover,
      );
    }

    return Button(
      leading: tappableCover,
      style: ButtonVariance.ghost.copyWith(
        padding: (context, states, value) {
          return (ButtonVariance.ghost.padding(context, states) as EdgeInsets)
              .copyWith(right: 0, left: 0);
        },
      ),
      trailing: rowPolicy.hasActions
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rowPolicy.showPin && onPinPressed != null) ...[
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
                if (rowPolicy.showQueue) ...[
                  Tooltip(
                    tooltip:
                        TooltipContainer(child: Text(context.l10n.add_to_queue))
                            .call,
                    child: IconButton.outline(
                      icon: const Icon(SpotubeIcons.queueAdd),
                      onPressed: onAddToQueuePressed,
                      enabled: !isLoading && !isQueueLoading,
                    ),
                  ),
                  const Gap(8),
                ],
                if (rowPolicy.showPlay)
                  Tooltip(
                    tooltip:
                        TooltipContainer(child: Text(context.l10n.play)).call,
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
            )
          : null,
      // Navigation is independent of playback readiness: gating it on
      // canPressPlay made the whole row a dead tap while tracks resolved.
      enabled: onTap != null,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (rowPolicy.showSubtitle && cleanDescription.isNotEmpty)
            Text(
              cleanDescription,
              maxLines: rowPolicy.compactDensity ? 1 : 2,
              overflow: TextOverflow.ellipsis,
            ).xSmall().muted(),
        ],
      ),
    );
  }
}
