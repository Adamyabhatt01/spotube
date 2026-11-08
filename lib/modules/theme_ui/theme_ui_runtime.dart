import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit.dart';
import 'package:spotube/modules/theme_ui/theme_ui_render_points.dart';
import 'package:spotube/services/theme_ui/artwork_palette.dart';

typedef ThemeUiActionCallback = void Function(ThemeUiAction action);

/// Everything a node needs to render, independent of Riverpod and routing.
///
/// Keeping the runtime explicit is what makes the node vocabulary testable:
/// a widget test supplies a few bindings and a recording callback and checks
/// the tree, without a provider container, database or audio backend.
class ThemeUiRuntime {
  final ThemeDefinition theme;
  final ThemeUiBindings bindings;
  final ThemeUiAssets assets;
  final Map<String, ThemeUiTemplate> templates;

  /// Render point id → template name. Empty when the theme did not replace
  /// any host surface.
  final Map<String, String> renderPoints;
  final int specVersion;
  final ThemeUiActionCallback onAction;

  /// The host callback underneath any list-row argument injection.
  ///
  /// A `list` nested inside another `list` scopes each row to the nearest
  /// entry. Its wrapper must call this callback rather than [onAction]:
  /// calling [onAction] would reach the outer row's wrapper, which injects
  /// the outer entry over the inner one and makes the inner row act on the
  /// section instead of the album/playlist/artist it draws.
  final ThemeUiActionCallback baseOnAction;

  /// The typed collection entry a list row is drawing, if any.
  ///
  /// The host keeps the object so a row can offer the same verbs the host's
  /// own rows do (a track's right-click menu, for example) without the theme
  /// having to rebuild them from `item.*` strings.
  final Object? item;

  /// Capability names the active document grants (`library.write`,
  /// `ui.hostWidgets`, ...). The authoring validator enforces the full table;
  /// the host repeats the checks that would otherwise let an installed plugin
  /// reach host-only surfaces or mutate the user's account.
  final Set<String> capabilities;

  /// The cached palette for an artwork URL, or null when the document never
  /// binds `palette.*` (then the renderer is not handed a lookup at all).
  final ArtworkPalette? Function(String url)? paletteFor;

  /// Asks the host to extract a palette the cache did not have yet.
  final void Function(String url)? requestPalette;

  /// How many render-point/template expansions enclose this runtime.
  ///
  /// Ordinary nodes have their own depth guard; this counter only exists for
  /// templates, which are the one part of the tree that can expand itself.
  final int templateDepth;
  final Set<String> templateStack;
  static const maxTemplateDepth = themeUiMaxTemplateDepth;

  const ThemeUiRuntime({
    required this.theme,
    required this.bindings,
    required this.assets,
    required this.templates,
    this.renderPoints = const {},
    required this.specVersion,
    required this.onAction,
    ThemeUiActionCallback? baseOnAction,
    this.item,
    this.capabilities = const {},
    this.paletteFor,
    this.requestPalette,
    this.templateDepth = 0,
    this.templateStack = const {},
  }) : baseOnAction = baseOnAction ?? onAction;

  /// The kit semantic nodes use when neither the node nor a `kitScope`
  /// ancestor chooses one.
  ThemeUiKit get defaultKit => ThemeUiKit.fromId(theme.uiKit);

  /// Whether the document may mount a host widget.
  bool get canUseHostWidgets => capabilities.contains('ui.hostWidgets');

  /// Whether [name] may be expanded here.
  ///
  /// A template the theme document does not carry, a chain that already
  /// contains the name, and a chain longer than the contract's limit all
  /// resolve to "no".
  bool canExpandTemplate(String name) {
    return templates.containsKey(name) &&
        templateDepth < maxTemplateDepth &&
        !templateStack.contains(name);
  }

  /// The runtime a template's children render with.
  ThemeUiRuntime descendTemplate(String name) {
    return ThemeUiRuntime(
      theme: theme,
      bindings: bindings,
      assets: assets,
      templates: templates,
      renderPoints: renderPoints,
      specVersion: specVersion,
      onAction: onAction,
      baseOnAction: baseOnAction,
      item: item,
      capabilities: capabilities,
      paletteFor: paletteFor,
      requestPalette: requestPalette,
      templateDepth: templateDepth + 1,
      templateStack: {...templateStack, name},
    );
  }

  /// The same runtime with a scoped binding map.
  ///
  /// Render points merge their context over the app bindings; the result is
  /// read-only by construction ([ThemeUiBindings] has no writer).
  ThemeUiRuntime withBindings(ThemeUiBindings next) {
    return ThemeUiRuntime(
      theme: theme,
      bindings: next,
      assets: assets,
      templates: templates,
      renderPoints: renderPoints,
      specVersion: specVersion,
      onAction: onAction,
      baseOnAction: baseOnAction,
      item: item,
      capabilities: capabilities,
      paletteFor: paletteFor,
      requestPalette: requestPalette,
      templateDepth: templateDepth,
      templateStack: templateStack,
    );
  }
}
