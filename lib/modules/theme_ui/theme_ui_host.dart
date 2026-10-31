import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_debug_overlay.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';
import 'package:spotube/modules/root/region_scope.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/theme_ui/artwork_palette_provider.dart';

/// The live tree and the contract document, assembled once per build.
typedef _LiveUi = ({ThemeUiRuntime runtime, ThemeUiDocument ui});

_LiveUi? _liveUi(
  BuildContext context,
  WidgetRef ref, {
  ThemeUiBindings? bindings,
}) {
  final definition = ref.watch(themeDefinitionProvider).asData?.value;
  final ui = ref.watch(themeUiProvider).asData?.value;
  if (definition == null || ui == null) return null;

  // Starts the font load and rebuilds the subtree once the faces are ready;
  // text is still rendered on the host fallback while that is in flight.
  ref.watch(themeUiFontsProvider);

  final assets =
      ref.watch(themeUiAssetsProvider).asData?.value ?? const ThemeUiAssets();
  // One scan per document, shared by every slot. Builds the provider set the
  // document actually references; an unused scope costs no subscription.
  final demand = ref.watch(themeUiBindingDemandProvider);
  final base = bindings ??
      buildThemeUiBindings(
        ref,
        brightness: Theme.of(context).brightness,
        themeMode: ref.watch(userPreferencesProvider).themeMode.name,
        demand: demand,
        layout: context.layout,
      );
  final page = ThemeUiPageBindings.of(context);
  final region = RegionScope.maybeOf(context);
  final regionValues = region?.state.bindings ?? const <String, Object?>{};
  var resolvedBindings = ThemeUiBindings({
    ...base.values,
    ...regionValues,
    if (page != null) ...page,
  });

  final wantsPalette = demand.wantsNamespace('palette');
  final paletteCache =
      wantsPalette ? ref.watch(themeUiPaletteCacheProvider) : null;
  if (paletteCache != null) {
    resolvedBindings = withArtworkPalette(
      resolvedBindings,
      paletteFor: (url) => paletteCache[url],
      request: (url) => unawaited(paletteCache.load(url)),
    );
  }

  return (
    runtime: ThemeUiRuntime(
      theme: definition,
      bindings: resolvedBindings,
      assets: assets,
      templates: ui.templates,
      renderPoints: ui.renderPoints,
      specVersion: ui.specVersion,
      paletteFor: paletteCache == null ? null : (url) => paletteCache[url],
      requestPalette: paletteCache == null
          ? null
          : (url) => unawaited(paletteCache.load(url)),
      onAction: (action) {
        unawaited(dispatchThemeUiAction(context, ref, action));
      },
    ),
    ui: ui,
  );
}

/// Installs a runtime for host widgets that are not mounted inside a slot.
///
/// Slots and screens build their own runtime because they also carry page
/// bindings. Host-owned surfaces such as the search bar have no slot to hang
/// from, so the app root publishes this lighter runtime once; render-point
/// templates then receive their surface context (`search.*`, `item.*`) from
/// the widget that owns the point.
///
/// The runtime deliberately does not carry player position or duration: a
/// host surface that needs those supplies them as render-point bindings, and
/// the search bar must not rebuild once a second just because a song plays.
class ThemeUiRuntimeScopeHost extends ConsumerWidget {
  final Widget child;

  const ThemeUiRuntimeScopeHost({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debug = ref.watch(themeUiDebugOverlayProvider);
    final definition = ref.watch(themeDefinitionProvider).asData?.value;
    final ui = ref.watch(themeUiProvider).asData?.value;
    if (definition == null || ui == null) {
      return debug ? _withDebugOverlay(child) : child;
    }

    final assets =
        ref.watch(themeUiAssetsProvider).asData?.value ?? const ThemeUiAssets();
    final themeMode = ref.watch(userPreferencesProvider).themeMode.name;
    final runtime = ThemeUiRuntime(
      theme: definition,
      bindings: buildThemeUiBindings(
        ref,
        brightness: Theme.of(context).brightness,
        themeMode: themeMode,
        // A host surface that is not inside a slot has no page bindings;
        // only the cheap app facts are published here.
        demand: ThemeUiBindingDemand(
          const ['app.version', 'app.brightness', 'app.themeMode'],
        ),
        layout: context.layout,
      ),
      assets: assets,
      templates: ui.templates,
      renderPoints: ui.renderPoints,
      specVersion: ui.specVersion,
      onAction: (action) {
        unawaited(dispatchThemeUiAction(context, ref, action));
      },
    );

    final scoped = ThemeUiRuntimeScope(runtime: runtime, child: child);
    return debug ? _withDebugOverlay(scoped) : scoped;
  }

  Widget _withDebugOverlay(Widget child) {
    return Stack(
      children: [
        child,
        const Positioned(
          right: 12,
          bottom: 12,
          child: ThemeUiBindingDebugOverlay(),
        ),
      ],
    );
  }
}

/// True when the active theme filled [name].
///
/// Callers use this to decide whether a slot replaces host chrome or should
/// fall back to the widget the app shipped with, without building a widget
/// just to find out it is empty.
bool themeUiSlotExists(WidgetRef ref, String name) {
  final ui = ref.watch(themeUiProvider).asData?.value;
  return ui?.slots[name]?.children.isNotEmpty ?? false;
}

/// Renders one named slot from the active theme, or [fallback] when the
/// theme did not fill it.
///
/// Slots are content, not layout: the host still owns the surface, padding
/// and scroll position around them. That keeps a theme from moving a button
/// outside the sidebar it was given, while leaving the content inside the
/// slot entirely up to the theme.
class ThemeSlot extends ConsumerWidget {
  final String name;
  final Widget? fallback;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;

  /// A binding snapshot to use instead of the live providers.
  ///
  /// Production callers leave this null. Tests and previews use it to render
  /// a slot without standing up the audio player, database and plugin stack.
  final ThemeUiBindings? bindings;

  const ThemeSlot(
    this.name, {
    this.fallback,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.bindings,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = _liveUi(context, ref, bindings: bindings);
    final slot = live?.ui.slots[name];
    if (live == null || slot == null || slot.children.isEmpty) {
      return fallback ?? const SizedBox.shrink();
    }

    return ThemeUiNodes(
      nodes: slot.children,
      runtime: live.runtime,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: mainAxisAlignment,
    );
  }
}

/// Renders an arbitrary node list with the active theme's runtime.
///
/// Used by slots, theme screens and the stage. Keeping this separate from
/// [ThemeUiSlot] means a screen does not have to pretend to be a slot key.
class ThemeUiNodes extends StatelessWidget {
  final List<Map<String, dynamic>> nodes;
  final ThemeUiRuntime runtime;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final double gap;

  const ThemeUiNodes({
    required this.nodes,
    required this.runtime,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.gap = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0 && gap > 0) children.add(SizedBox(height: gap));
      children.add(ThemeUiNodeView(node: nodes[i], runtime: runtime));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }
}

/// Replaces a page body with [slot] when the active theme filled it.
///
/// A content slot is the "edit everything" lever: when a theme supplies one
/// for a page, it owns the page's scroll, spacing and composition instead of
/// adding to the host's. The page still publishes its data through
/// [ThemeUiPageBindings] (title, artwork, tracks, and so on), and the host
/// still owns the titlebar, back gesture and any chrome outside the body.
class ThemePageContent extends ConsumerWidget {
  final String slot;
  final Map<String, Object?> bindings;
  final Widget fallback;
  final bool scroll;
  final EdgeInsetsGeometry padding;

  /// A binding snapshot to use instead of the live providers.
  ///
  /// Production callers leave this null; the page's own [bindings] still
  /// override whatever the snapshot carries.
  final ThemeUiBindings? liveBindings;

  const ThemePageContent({
    required this.slot,
    required this.bindings,
    required this.fallback,
    this.scroll = true,
    this.padding = EdgeInsets.zero,
    this.liveBindings,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!themeUiSlotExists(ref, slot)) {
      return ThemeUiPageBindings(values: bindings, child: fallback);
    }

    Widget content = Padding(
      padding: padding,
      child: ThemeSlot(slot, bindings: liveBindings),
    );
    if (scroll) content = SingleChildScrollView(child: content);
    return ThemeUiPageBindings(values: bindings, child: content);
  }
}

/// The full-window overlay a `screen:<id>` action opens.
///
/// It is mounted above the shell so a theme screen can cover the sidebar and
/// player without becoming a route the user can get lost in. The back
/// control is host chrome on purpose: a theme screen can always dismiss
/// itself through `navigate`, but the host guarantees an exit even when it
/// cannot.
class ThemeUiScreenHost extends ConsumerWidget {
  final Widget child;

  /// Binding snapshot override for tests and previews; see [ThemeSlot].
  final ThemeUiBindings? bindings;

  const ThemeUiScreenHost({required this.child, this.bindings, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(themeUiScreenStackProvider);
    if (stack.isEmpty) return child;

    final live = _liveUi(context, ref, bindings: bindings);
    final screen = live?.ui.screens[stack.last];
    if (live == null || screen == null) return child;

    final scheme = Theme.of(context).colorScheme;
    final theme = live.runtime.theme;
    final title = screen.title ?? stack.last;
    final family = _family(theme.typography['brandFamily']) ??
        _family(theme.typography['family']);

    return Stack(
      children: [
        IgnorePointer(child: child),
        Positioned.fill(
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) popThemeUiScreen(ref);
            },
            child: ColoredBox(
              color: scheme.background,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 16, 8),
                      child: Row(
                        children: [
                          IconButton.ghost(
                            icon: const Icon(SpotubeIcons.angleLeft),
                            onPressed: () => popThemeUiScreen(ref),
                          ),
                          const Gap(6),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.foreground,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFamily: family,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                        child: ThemeUiNodes(
                          nodes: screen.children,
                          runtime: live.runtime,
                          crossAxisAlignment: CrossAxisAlignment.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _family(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty || value.length > 64) return null;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$').hasMatch(value)) return null;
    return value;
  }
}

/// The stage a `dock: "stage"` theme places on the home page.
class ThemeUiStage extends ConsumerWidget {
  /// Binding snapshot override for tests and previews; see [ThemeSlot].
  final ThemeUiBindings? bindings;

  const ThemeUiStage({this.bindings, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = _liveUi(context, ref, bindings: bindings);
    if (live == null) return const SizedBox.shrink();
    final center = live.ui.slots['stage.center'];
    final below = live.ui.slots['stage.below'];
    if ((center?.children.isEmpty ?? true) &&
        (below?.children.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        children: [
          if (center != null && center.children.isNotEmpty)
            ThemeUiNodes(
              nodes: center.children,
              runtime: live.runtime,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
          if (below != null && below.children.isNotEmpty) ...[
            const SizedBox(height: 20),
            ThemeUiNodes(
              nodes: below.children,
              runtime: live.runtime,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
          ],
        ],
      ),
    );
  }
}
