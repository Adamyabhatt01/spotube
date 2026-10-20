import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/utils/platform.dart';

/// Real window transparency: the compositor shows through wherever the app
/// paints nothing, instead of the app painting its own wallpaper to fake it.
///
/// Plugin-driven: the active theme requests it with
/// `background.transparent == true`, and the user can only veto via the
/// `transparentWindow` allow-setting (an opt-out, default on for fresh
/// installs). Anything else is opaque — an explicit `false` (veto), an
/// absent flag (old themes: no opinion means no transparency), and no theme
/// plugin at all (real transparency is a theme feature; stock stays opaque).
///
/// Linux-only: only the Linux window offers an alpha channel (see
/// `linux/my_application.cc`).
///
/// While the theme is still loading with no cached theme the predicate is
/// false (opaque until resolved): a transparent flash that a veto later
/// retracts would be worse than a late transparency. With a cached theme,
/// its flag holds across the reload instead of blipping opaque.
final realTransparencyActiveProvider = Provider<bool>((ref) {
  if (!kIsLinux) return false;
  final allowed = ref.watch(
    userPreferencesProvider.select((s) => s.transparentWindow),
  );
  if (!allowed) return false;
  final live = ref.watch(themeDefinitionProvider);
  final transparent = live.asData?.value?.background.transparent ??
      ref.watch(
        cachedThemeDefinitionProvider.select(
          (s) => s.asData?.value?.background.transparent,
        ),
      );
  return transparent == true;
});
