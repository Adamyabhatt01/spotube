import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/string.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/utils/platform.dart';

/// Fades an overlay in when the pointer hovers its card.
///
/// Touch input never reports a hovered state, so on mobile the animated target
/// is a constant and both implicit animations - two controllers and two
/// tickers per card - exist only to be mounted and disposed as the grid
/// recycles cards while scrolling. [animated] is a parameter rather than a read
/// of [kIsMobile] because the platform flags come from the host process, so a
/// test could otherwise only ever exercise one of the two shapes.
@visibleForTesting
Widget hoverReveal({
  required bool shown,
  required Duration duration,
  required bool animated,
  required Widget child,
}) {
  if (!animated) {
    // Held at zero rather than dropped: the slot keeps the play button where it
    // is while the card loads, exactly as the faded animation did.
    return shown ? child : Opacity(opacity: 0, child: child);
  }
  return AnimatedScale(
    curve: Curves.easeOutBack,
    duration: duration,
    scale: shown ? 1 : 0.7,
    child: AnimatedOpacity(
      duration: duration,
      opacity: shown ? 1 : 0,
      child: child,
    ),
  );
}

class PlaybuttonCard extends StatelessWidget {
  final void Function()? onTap;
  final void Function()? onPlaybuttonPressed;
  final void Function()? onAddToQueuePressed;
  final void Function()? onPinPressed;
  final String? description;

  final String? imageUrl;
  final Widget? image;
  final bool isPlaying;
  final bool isLoading;
  final bool isPinned;
  final String title;
  final bool isOwner;

  const PlaybuttonCard({
    required this.isPlaying,
    required this.isLoading,
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
    final unescapeHtml = description.strippedHtml();
    // 4/3 is the decode oversample the fixed 150px card used with a 200px
    // image; the cover is square, so one value serves both edges.
    final coverSize = context.gridCardWidth;
    final coverRadius = BorderRadius.circular(context.cardCornerRadius);

    return SizedBox(
      width: coverSize,
      child: CardImage(
        image: Stack(
          children: [
            if (imageUrl != null)
              Container(
                width: coverSize,
                height: coverSize,
                decoration: BoxDecoration(
                  borderRadius: coverRadius,
                  image: DecorationImage(
                    image: UniversalImage.imageProvider(
                      imageUrl!,
                      height: coverSize * 4 / 3,
                      width: coverSize * 4 / 3,
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              SizedBox(
                width: coverSize,
                height: coverSize,
                child: ClipRRect(
                  borderRadius: coverRadius,
                  child: image!,
                ),
              ),
            StatedWidget.builder(
              builder: (context, states) {
                final hovered = states.contains(WidgetState.hovered) ||
                    kIsMobile;
                return Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    children: [
                      hoverReveal(
                        shown: hovered && !isLoading,
                        duration: const Duration(milliseconds: 300),
                        animated: !kIsMobile,
                        child: IconButton.secondary(
                          icon: const Icon(SpotubeIcons.queueAdd),
                          onPressed: onAddToQueuePressed,
                          size: ButtonSize.small,
                        ),
                      ),
                      const Gap(5),
                      hoverReveal(
                        shown: hovered || isPlaying || isLoading,
                        duration: const Duration(milliseconds: 150),
                        animated: !kIsMobile,
                        child: IconButton.secondary(
                          icon: switch ((isLoading, isPlaying)) {
                            (true, _) => const CircularProgressIndicator(
                                size: 15,
                              ),
                            (false, false) => const Icon(SpotubeIcons.play),
                            (false, true) => const Icon(SpotubeIcons.pause)
                          },
                          enabled: !isLoading,
                          onPressed: onPlaybuttonPressed,
                          size: ButtonSize.small,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (isOwner)
              const Positioned(
                right: 5,
                top: 5,
                child: SecondaryBadge(
                  style: ButtonStyle.secondaryIcon(
                    shape: ButtonShape.circle,
                    size: ButtonSize.small,
                  ),
                  child: Icon(SpotubeIcons.user),
                ),
              ),
            // Pin affordance, mirroring the play button's hover reveal.
            // Top-left: top-right carries the owner badge. On touch there is
            // no hover, so the button only exists when pinned — an invisible
            // Opacity-zero button would still swallow taps on the cover.
            if (onPinPressed != null && (isPinned || !kIsMobile))
              StatedWidget.builder(
                builder: (context, states) {
                  final hovered = states.contains(WidgetState.hovered);
                  return Positioned(
                    left: 8,
                    top: 8,
                    child: hoverReveal(
                      shown: isPinned || hovered,
                      duration: const Duration(milliseconds: 150),
                      animated: !kIsMobile,
                      child: Tooltip(
                        tooltip: TooltipContainer(
                          child: Text(isPinned
                              ? context.l10n.unpin_from_sidebar
                              : context.l10n.pin_to_sidebar),
                        ).call,
                        child: IconButton.secondary(
                          icon: Icon(
                            isPinned ? SpotubeIcons.pinOn : SpotubeIcons.pinOff,
                          ),
                          onPressed: onPinPressed,
                          size: ButtonSize.small,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        title: Tooltip(
          tooltip: TooltipContainer(child: Text(title)).call,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Text(
          unescapeHtml.isEmpty ? "\n" : unescapeHtml,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: onTap,
      ),
    );
  }
}
