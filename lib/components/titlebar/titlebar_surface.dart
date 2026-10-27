import 'dart:ui';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The title bar's surface: shadcn's [AppBar] layout, minus its unconditional
/// [BackdropFilter].
///
/// shadcn's `AppBar` always builds `ClipRect` + `BackdropFilter`, even when the
/// resolved sigma is 0, so a transparent window chrome (or any theme whose
/// `surfaces.blur` is 0) paid a backdrop pass on every frame for a filter that
/// blurs nothing. This widget mirrors that layout and only creates the filter
/// layer when there is a real blur to apply.
class TitleBarSurface extends StatelessWidget {
  final List<Widget> trailing;
  final List<Widget> leading;
  final Widget? child;
  final Widget? title;
  final Widget? header;
  final Widget? subtitle;
  final bool trailingExpanded;
  final AlignmentGeometry alignment;
  final Color? backgroundColor;
  final double? leadingGap;
  final double? trailingGap;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final bool useSafeArea;
  final double? surfaceBlur;
  final double? surfaceOpacity;

  const TitleBarSurface({
    super.key,
    this.trailing = const [],
    this.leading = const [],
    this.title,
    this.header,
    this.subtitle,
    this.child,
    this.trailingExpanded = false,
    this.alignment = Alignment.center,
    this.padding,
    this.backgroundColor,
    this.leadingGap,
    this.trailingGap,
    this.height,
    this.surfaceBlur,
    this.surfaceOpacity,
    this.useSafeArea = true,
  }) : assert(
          child == null || title == null,
          'Cannot provide both child and title',
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaling = theme.scaling;
    final barData = Data.maybeOf<ScaffoldBarData>(context);

    final bar = Container(
      color: backgroundColor ??
          theme.colorScheme.card.scaleAlpha(surfaceOpacity ?? 1),
      alignment: alignment,
      padding: padding ??
          (const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ) *
              scaling),
      child: SafeArea(
        top: useSafeArea && barData?.isHeader == true && barData?.childIndex == 0,
        right: useSafeArea,
        left: useSafeArea,
        bottom: useSafeArea &&
            barData?.isHeader == false &&
            barData?.childIndex == (barData?.childrenCount ?? 0) - 1,
        child: SizedBox(
          height: height,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leading.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: leading,
                  ).gap(leadingGap ?? (4 * scaling)),
                Flexible(
                  fit: trailingExpanded ? FlexFit.loose : FlexFit.tight,
                  child: child ??
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (header != null)
                            KeyedSubtree(
                              key: const ValueKey('header'),
                              child: header!.muted().small(),
                            ),
                          if (title != null)
                            KeyedSubtree(
                              key: const ValueKey('title'),
                              child: title!.large().medium(),
                            ),
                          if (subtitle != null)
                            KeyedSubtree(
                              key: const ValueKey('subtitle'),
                              child: subtitle!.muted().small(),
                            ),
                        ],
                      ),
                ),
                if (trailing.isNotEmpty)
                  if (!trailingExpanded)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: trailing,
                    ).gap(trailingGap ?? (4 * scaling))
                  else
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: trailing,
                      ).gap(trailingGap ?? (4 * scaling)),
                    ),
              ],
            ).gap(18 * scaling),
          ),
        ),
      ),
    );

    final sigma = surfaceBlur ?? theme.surfaceBlur;
    if (sigma == null || sigma <= 0) return bar;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: bar,
      ),
    );
  }
}
