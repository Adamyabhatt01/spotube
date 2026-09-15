import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/utils/theme_converter.dart';

/// Applies the plugin surface tint centrally via [CardTheme].
///
/// Inactive (no tint, or malformed tint) returns [child] unchanged,
/// preserving existing appearance exactly. When active, overrides only
/// the fill behavior (`filled: true`, `fillColor: tint`); surface
/// opacity/blur are deliberately left null so they keep resolving
/// through [ThemeData] (wired from `ThemeDefinition.surfaces` in main).
/// Cards with explicit `fillColor` keep their intentional appearance
/// since widget values beat component-theme values.
class ThemeSurfacesScope extends ConsumerWidget {
  final Widget child;
  const ThemeSurfacesScope({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tintHex = ref.watch(
      themeDefinitionProvider.select((s) => s.asData?.value?.surfaces.tint),
    );
    if (tintHex == null) return child;

    late final Color tint;
    try {
      tint = ThemeConverter.parseColor(tintHex);
    } catch (_) {
      return child;
    }

    return ComponentTheme(
      data: CardTheme(filled: true, fillColor: tint),
      child: child,
    );
  }
}
