import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/theme_background_layer.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// Wraps the app content with the plugin background when one is active.
///
/// Inactive (no plugin, source none, or no image data) returns [child]
/// unchanged, preserving existing appearance exactly. When active,
/// descendant scaffolds paint the semantic background role so
/// Caelestia's background palette does its job; cards keep their own
/// `card` role with glass settings. The shell/album-art layer stays
/// behind for transparent screens (player, lyrics). Covers navigation
/// and dialogs since it wraps the router outlet.
class ThemeBackgroundScope extends ConsumerWidget {
  final Widget child;
  const ThemeBackgroundScope({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      themeDefinitionProvider.select(
        (s) => s.asData?.value?.background.source,
      ),
    );
    final image = ref.watch(themeBackgroundImageProvider);

    final active =
        source != null && source != ThemeBackgroundSource.none && image != null;
    if (!active) return child;

    return ComponentTheme(
      data: ScaffoldTheme(
        backgroundColor: Theme.of(context).colorScheme.background,
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: ThemeBackgroundLayer()),
          child,
        ],
      ),
    );
  }
}
