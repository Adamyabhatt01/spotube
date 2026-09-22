import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/hooks/configurators/use_check_yt_dlp_installed.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/root/sidebar/sidebar.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/hooks/configurators/use_endless_playback.dart';
import 'package:spotube/modules/root/use_global_subscriptions.dart';
import 'package:spotube/provider/glance/glance.dart';

/// The shell around the router can legitimately gain or lose layers — a
/// background image, a surface tint, a collapsing sidebar, an inset-chrome
/// panel — and each of those changes the depth at which `AutoRouter` mounts.
/// Without a key that is a teardown, not a move, and `AutoRouter` re-pushes
/// the level's `initial: true` route: an open page jumps to Home.
final appRouterSlotKey = GlobalKey(debugLabel: 'app-router-slot');

@RoutePage()
class RootAppPage extends HookConsumerWidget {
  const RootAppPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final backgroundColor = Theme.of(context).colorScheme.background;
    final brightness = Theme.of(context).brightness;

    ref.listen(glanceProvider, (_, __) {});

    useGlobalSubscriptions(ref);
    useEndlessPlayback(ref);
    useCheckYtDlpInstalled(ref);

    useEffect(() {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: backgroundColor, // status bar color
          statusBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
      );
      return null;
    }, [backgroundColor, brightness]);

    final content = Sidebar(
      child: MediaQuery(
        key: appRouterSlotKey,
        data: MediaQuery.of(context).copyWith(
          padding: MediaQuery.paddingOf(context)
              .copyWith(bottom: 100 * context.theme.scaling),
        ),
        child: const AutoRouter(),
      ),
    );

    // `chrome: inset` floats the shell in a rounded panel over a darkened
    // shade of the theme's own background. The player is a scaffold footer, so
    // it stays full width on that shade — the one move that makes an otherwise
    // unchanged UI read as a different application.
    final insetChrome = context.insetChrome;
    final scaffold = MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: SafeArea(
        top: false,
        child: Scaffold(
          footers: const [
            BottomPlayer(),
            SpotubeNavigationBar(),
          ],
          floatingFooter: true,
          backgroundColor: insetChrome ? context.chromeInkColor : null,
          child: !insetChrome
              ? content
              : Padding(
                  padding: EdgeInsets.all(context.chromeInsetGap),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      context.surfaceCornerRadius,
                    ),
                    child: ColoredBox(
                      color: context.theme.colorScheme.background,
                      child: content,
                    ),
                  ),
                ),
        ),
      ),
    );

    return scaffold;
  }
}
