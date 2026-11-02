import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// The active theme's own settings, as a plain widget.
///
/// A theme opts in by answering `showSettings()` with a UI document; the host
/// renders that document's `settings.content` slot. Two surfaces use this: the
/// Settings dialog (see `lib/pages/settings/theme_settings.dart`) and the
/// `theme.settings` host widget, so a theme can either be configured from the
/// host's screens or place its controls inline in its own layout.
///
/// Both read the same per-theme namespace, which is what makes a toggle survive
/// the rebuild its own `setSetting` action causes.
class ThemeSettingsBody extends ConsumerWidget {
  final ThemeUiDocument ui;

  /// Whether to wrap the nodes in their own scroller. The dialog does; an
  /// inline host widget sits inside the page that is already scrolling.
  final bool scroll;

  const ThemeSettingsBody({
    required this.ui,
    this.scroll = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definition = ref.watch(themeDefinitionProvider).asData?.value;
    if (definition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final assets =
        ref.watch(themeUiAssetsProvider).asData?.value ?? const ThemeUiAssets();
    final demand = ThemeUiBindingDemand.scan(ui);
    final runtime = ThemeUiRuntime(
      theme: definition,
      bindings: buildThemeUiBindings(
        ref,
        brightness: Theme.of(context).brightness,
        themeMode: ref.watch(
          userPreferencesProvider.select((prefs) => prefs.themeMode.name),
        ),
        demand: demand,
        layout: context.layout,
      ),
      assets: assets,
      templates: ui.templates,
      renderPoints: ui.renderPoints,
      specVersion: ui.specVersion,
      capabilities: ui.capabilities.toSet(),
      onAction: (action) {
        unawaited(
          dispatchThemeUiAction(
            context,
            ProviderScope.containerOf(context, listen: false),
            action,
          ),
        );
      },
    );

    final children = ui.slots['settings.content']?.children ?? const [];
    final nodes = ThemeUiSettingsScope(
      child: ThemeUiRuntimeScope(
        runtime: runtime,
        child: ThemeUiNodes(
          nodes: children,
          runtime: runtime,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
      ),
    );
    if (!scroll) return nodes;
    return SingleChildScrollView(child: nodes);
  }
}

/// Marks the subtree that is already rendering a settings document.
///
/// `theme.settings` mounted from inside the settings document would otherwise
/// re-render itself, because the document it opens is the one it lives in. The
/// registry checks this and renders nothing instead of recursing.
class ThemeUiSettingsScope extends StatefulWidget {
  final Widget child;

  const ThemeUiSettingsScope({required this.child, super.key});

  static bool isInside(BuildContext context) =>
      context.findAncestorWidgetOfExactType<ThemeUiSettingsScope>() != null;

  @override
  State<ThemeUiSettingsScope> createState() => _ThemeUiSettingsScopeState();
}

class _ThemeUiSettingsScopeState extends State<ThemeUiSettingsScope> {
  @override
  Widget build(BuildContext context) => widget.child;
}
