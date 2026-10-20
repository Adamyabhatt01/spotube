import 'package:flutter/material.dart' as material;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The length [PaletteTransitionScope] should fade over, from the two stored
/// preferences.
///
/// [Duration.zero] is the only "off" signal — the scope collapses that case to
/// a plain [Theme], so a disabled transition costs nothing at runtime. The
/// clamp exists because the column is user-editable data like every other
/// preference: `0ms` would collide with "off" and a huge value would leave the
/// app permanently crossfading.
Duration resolveThemeTransition(bool enabled, int milliseconds) {
  if (!enabled) return Duration.zero;
  return Duration(milliseconds: milliseconds.clamp(50, 2000));
}

/// Crossfades the colour palette when the theme changes, on this app's clock.
///
/// `ShadcnApp` already animates its theme, but hardcodes `kDefaultDuration`
/// (150ms, linear) at `shadcn_app.dart:660` of shadcn_flutter 0.0.47 and its
/// `enableThemeAnimation` flag is accepted without ever being read — so the only
/// hook left is a nested [Theme] below its own, which wins for everything under
/// `ShadcnApp.builder`.
///
/// The [DefaultTextStyle]/[IconTheme] merges repeat what `ShadcnLayer` does above
/// this point (`shadcn_app.dart:668-675`) using the *animated* value. Without them
/// the package's 150ms clock keeps crossfading inherited text and icon colors even
/// when [duration] is [Duration.zero], which would make "off" only half work.
class PaletteTransitionScope extends HookWidget {
  final ThemeData theme;
  final ThemeData darkTheme;
  final AdaptiveScaling scaling;

  /// The app's resolved brightness, not the stored [ThemeMode] — the same value
  /// `ThemeMode` already produced for the Material theme.
  final Brightness brightness;
  final Duration duration;
  final Widget child;

  /// Real window transparency. A plain constructor parameter — not a provider
  /// watch — on purpose: this scope sits on the frame-exact theme-transition
  /// clock, and subscribing it to the async theme chain shifts rebuild timing
  /// (proven by `theme_transition_test.dart` going red on a `Consumer` form).
  /// The single watch lives in `Spotube.build`, which already watches prefs.
  final bool realTransparent;

  const PaletteTransitionScope({
    super.key,
    required this.theme,
    required this.darkTheme,
    required this.scaling,
    required this.brightness,
    required this.duration,
    required this.child,
    this.realTransparent = false,
  });

  @override
  Widget build(BuildContext context) {
    // Built the way `ShadcnLayer` builds the theme it animates
    // (`shadcn_app.dart:641-645`): the resolved brightness picks the side and
    // the app's scaling goes on top, because `ThemeData.scaling` is a real field
    // components size against. Memoized because that layer's own tween rebuilds
    // this widget for its first 150ms, and a fresh-but-equal [ThemeData] each
    // time would re-run `Typography.scale` for nothing.
    final resolved = useMemoized(
      () => scaling.scale(brightness == Brightness.dark ? darkTheme : theme),
      [scaling, theme, darkTheme, brightness],
    );

    return ShadcnAnimatedTheme(
      data: resolved,
      duration: duration,
      curve: Curves.easeOutCubic,
      // A plain Builder, not a Consumer: this scope sits on the frame-exact
      // theme-transition clock, and a provider subscription inside it
      // rebuilds the subtree on the provider's schedule instead of the
      // animation's — which shifts the crossfade off the stored length
      // (proven by `theme_transition_test.dart` going red on a `Consumer`
      // form). `realTransparent` is passed in as a plain parameter for
      // exactly this reason; the single watch lives in `Spotube.build`,
      // which already watches the other preferences.
      child: Builder(
        builder: (context) {
          final animated = Theme.of(context);
          final foreground = animated.colorScheme.foreground;
          final background = animated.colorScheme.background;
          // `ShadcnApp` provides the Material theme above this point
          // (`shadcn_app.dart:527`), and the app builds it from a resolved
          // `Brightness`, not the animated palette. Every route paints its
          // opaque `Material` background from that stepped theme, so without a
          // re-provision here the surfaces jump to the new palette in one frame
          // while the inherited text below crossfades — the "plain black/white"
          // gap. Re-issuing the Material surfaces from the *animated* background
          // puts them on this scope's clock, so ground and text move together.
          return material.Theme(
            data: material.Theme.of(context).copyWith(
              // Real transparency: Material grounds go clear with the
              // rest, instead of covering the compositor.
              scaffoldBackgroundColor: realTransparent
                  ? material.Colors.transparent
                  : background,
              canvasColor:
                  realTransparent ? material.Colors.transparent : background,
            ),
            child: DefaultTextStyle.merge(
              style: animated.typography.base.copyWith(color: foreground),
              child: IconTheme.merge(
                data: animated.iconTheme.medium.copyWith(color: foreground),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
