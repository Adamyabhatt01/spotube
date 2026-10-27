import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/components/button/back_button.dart';
import 'package:spotube/components/titlebar/titlebar_buttons.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

final kTitlebarVisible = kIsWindows || kIsLinux;

class TitleBar extends HookConsumerWidget implements PreferredSizeWidget {
  final bool automaticallyImplyLeading;
  final List<Widget> trailing;
  final List<Widget> leading;
  final Widget? child;
  final Widget? title;
  final Widget? header; // small widget placed on top of title
  final Widget? subtitle; // small widget placed below title
  final bool
      trailingExpanded; // expand the trailing instead of the main content
  final AlignmentGeometry alignment;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? leadingGap;
  final double? trailingGap;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final bool useSafeArea;
  final double? surfaceBlur;
  final double? surfaceOpacity;

  const TitleBar({
    super.key,
    this.automaticallyImplyLeading = true,
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
    this.foregroundColor,
    this.leadingGap,
    this.trailingGap,
    this.height,
    this.surfaceBlur,
    this.surfaceOpacity,
    this.useSafeArea = false,
  });

  void onDrag(WidgetRef ref) {
    final systemTitleBar =
        ref.read(userPreferencesProvider.select((s) => s.systemTitleBar));
    if (kIsDesktop && !systemTitleBar) {
      windowManager.startDragging();
    }
  }

  @override
  Widget build(BuildContext context, ref) {
    final hasLeadingOrCanPop = leading.isNotEmpty || Navigator.canPop(context);
    final lastClicked = useRef<int>(DateTime.now().millisecondsSinceEpoch);

    // shadcn's AppBar fills itself with `card` at the surface opacity, a
    // neutral near-black, which reads as a solid band across the top of every
    // page that has a title bar. It cannot just wear the backdrop's veil
    // instead: the ground behind it is already veiled, so a second veil at the
    // same alpha composites to ~95% surface and the band is solid again. With
    // no fill at all the strip is the ground - and the frost stays, which is
    // what the four `floatingHeader: true` pages need to keep scrolled content
    // legible under the title. Real transparency joins the same rule: with
    // the desktop behind the strip, any fill is the window.
    final bareChrome = ref.watch(themeBackdropActiveProvider) ||
        ref.watch(realTransparencyActiveProvider);
    // In-app blur over a transparent region blurs nothing (the compositor
    // owns blur here) while still costing a filter per frame — off with it.
    // Hoisted: `ref.watch` inside the `LayoutBuilder` below would subscribe
    // outside this widget's build.
    final noAppBlur = ref.watch(realTransparencyActiveProvider);

    // A theme may resize the strip and decide whether the back control exists.
    // The height is theme-logical pixels, so it follows the same scaling as
    // every other chrome dimension the host owns.
    final layout = context.layout;
    final themeHeight = themeTitlebarHeight(layout);
    final themePadding = themeTitlebarPadding(layout);
    final themeShowBack = themeTitlebarShowBack(layout);
    final resolvedHeight = themeHeight == null
        ? height ?? 48 * context.theme.scaling
        : themeHeight * context.theme.scaling;
    final resolvedPadding = padding ??
        (themePadding == null
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: themePadding * context.theme.scaling,
              ));

    return SizedBox(
      height: resolvedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasFullscreen =
              MediaQuery.sizeOf(context).width == constraints.maxWidth;

          final canPop = leading.isEmpty &&
              (themeShowBack ??
                  (automaticallyImplyLeading &&
                      (Navigator.canPop(context) ||
                          context.watchRouter.canPop())));

          return GestureDetector(
            onHorizontalDragStart: (_) => onDrag(ref),
            onVerticalDragStart: (_) => onDrag(ref),
            onTapDown: (details) async {
              final systemTitlebar = ref.read(
                  userPreferencesProvider.select((s) => s.systemTitleBar));
              if (!kIsDesktop || systemTitlebar) return;

              int currMills = DateTime.now().millisecondsSinceEpoch;

              if ((currMills - lastClicked.value) < 500) {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              } else {
                lastClicked.value = currMills;
              }
            },
            child: AppBar(
              leading: canPop ? [const BackButton()] : leading,
              trailing: [
                ...trailing,
                Align(
                  alignment: Alignment.topRight,
                  child:
                      WindowTitleBarButtons(foregroundColor: foregroundColor),
                ),
              ],
              title: title,
              header: header,
              subtitle: subtitle,
              trailingExpanded: trailingExpanded,
              alignment: alignment,
              padding: resolvedPadding,
              backgroundColor: backgroundColor ??
                  (bareChrome ? Colors.transparent : null),
              leadingGap: leadingGap,
              trailingGap: trailingGap,
              height: resolvedHeight,
              surfaceBlur: noAppBlur ? 0 : surfaceBlur,
              surfaceOpacity: surfaceOpacity,
              useSafeArea: useSafeArea,
              child: child,
            ).withPadding(
                left: kIsMacOS && hasFullscreen && hasLeadingOrCanPop ? 65 : 0),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height ?? 48);
}
