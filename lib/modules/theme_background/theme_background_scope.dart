import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/theme_background_layer.dart';

/// Wraps the app content with the plugin background when one is active.
///
/// Inactive (no plugin, a theme that is not shell-sourced, or no wallpaper to
/// show) returns [child] unchanged, preserving existing appearance exactly.
/// When active, descendant
/// scaffolds turn their own background off: the [ThemeBackgroundLayer] below
/// them is what paints the app's ground, exactly as the desktop paints foot's.
/// An opaque `background` role here would cover that layer and the theme's
/// glass would be computed and never seen.
class ThemeBackgroundScope extends ConsumerWidget {
  final Widget child;
  const ThemeBackgroundScope({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real transparency turns scaffolds off the same way: with no painted
    // layer behind them, an opaque `background` role would be the window.
    if (!ref.watch(themeBackdropActiveProvider) &&
        !ref.watch(realTransparencyActiveProvider)) {
      return child;
    }

    return ComponentTheme(
      data: const ScaffoldTheme(backgroundColor: Colors.transparent),
      child: Stack(
        children: [
          const Positioned.fill(child: ThemeBackgroundLayer()),
          child,
        ],
      ),
    );
  }
}
