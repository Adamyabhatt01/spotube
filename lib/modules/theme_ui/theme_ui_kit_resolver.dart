import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit.dart';

/// The node components each kit can render natively.
///
/// Shadcn is the app's own kit and implements the whole vocabulary. Material
/// and Cupertino start with the controls that make the kit switch visible
/// (buttons and sliders); a semantic node outside this set keeps the default
/// kit's rendering instead of disappearing.
const kitComponents = <ThemeUiKit, Set<String>>{
  ThemeUiKit.shadcn: {
    'button',
    'progress',
    'card',
    'text',
    'icon',
    'image',
    'row',
    'column',
    'stack',
    'wrap',
    'padding',
    'align',
    'expanded',
    'scroll',
    'list',
    'template',
    'conditional',
    'animate',
    'box',
    'grid',
    'safeArea',
    'aspectRatio',
    'slider',
    'switch',
    'checkbox',
    'radioGroup',
    'textField',
    'textArea',
    'select',
    'segmented',
    'tabs',
    'menu',
    'contextMenu',
    'popover',
    'tooltip',
    'dialog',
    'sheet',
  },
  ThemeUiKit.material: {'button', 'progress', 'slider'},
  ThemeUiKit.cupertino: {'button', 'progress', 'slider'},
};

/// Puts a kit in scope for a subtree.
///
/// This is the runtime half of the `kitScope` node: the nearest ancestor wins
/// over the theme's `uiKit`, and a node's own `kit` still wins over both.
class ThemeUiKitScope extends InheritedWidget {
  final ThemeUiKit kit;

  const ThemeUiKitScope({
    required this.kit,
    required super.child,
    super.key,
  });

  static ThemeUiKit? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeUiKitScope>()?.kit;
  }

  @override
  bool updateShouldNotify(ThemeUiKitScope oldWidget) => kit != oldWidget.kit;
}

/// Resolves the kit a node renders through.
///
/// Resolution order, highest first:
/// 1. the node's `kit` prop;
/// 2. the nearest [ThemeUiKitScope] ancestor (`kitScope` node);
/// 3. the theme's `uiKit`;
/// 4. [ThemeUiKit.fallback].
class ThemeUiKitResolver {
  const ThemeUiKitResolver({required this.themeKit});

  final ThemeUiKit themeKit;

  ThemeUiKit resolve(BuildContext context, {Object? nodeKit}) {
    return ThemeUiKit.tryParse(nodeKit) ??
        ThemeUiKitScope.maybeOf(context) ??
        themeKit;
  }

  /// The kit to use for [component], applying the fallback rule.
  ///
  /// When the requested kit does not implement the component, the theme's own
  /// kit is tried next and then the default kit. The fallback is recorded so
  /// the debug diagnostics can report it per node.
  ThemeUiKit resolveForComponent(
    BuildContext context, {
    required String component,
    required String nodeType,
    Object? nodeKit,
    String? variant,
  }) {
    final requested = resolve(context, nodeKit: nodeKit);
    if (kitComponents[requested]?.contains(component) ?? false) {
      return requested;
    }

    final themeSupports = kitComponents[themeKit]?.contains(component) ?? false;
    final target = themeSupports ? themeKit : ThemeUiKit.fallback;
    if (kitComponents[target]?.contains(component) ?? false) {
      ThemeUiDiagnostics.kitFallback(
        nodeType: nodeType,
        variant: variant,
        requested: requested,
        used: target,
      );
      return target;
    }

    ThemeUiDiagnostics.missingComponent(
      nodeType: nodeType,
      variant: variant,
      requested: requested,
    );
    return ThemeUiKit.fallback;
  }
}

/// One kit/variant/fallback observation.
@immutable
class ThemeUiDiagnostic {
  final String nodeType;
  final String? variant;
  final ThemeUiKit requested;
  final ThemeUiKit used;

  /// True when no kit implements the component at all, as opposed to a
  /// fallback to another kit that does.
  final bool missing;

  const ThemeUiDiagnostic({
    required this.nodeType,
    required this.requested,
    required this.used,
    this.missing = false,
    this.variant,
  });

  @override
  String toString() {
    final style = variant == null ? '' : ' variant "$variant"';
    return 'ThemeUi: $nodeType$style requested ${requested.id}, '
        'used ${used.id}';
  }
}

/// Debug-only record of kit and variant fallbacks.
///
/// Themes declare a kit per node and a variant per component; when the host
/// cannot honour one it silently chooses another. These entries make that
/// choice visible while authoring without paying for logging in release.
class ThemeUiDiagnostics {
  ThemeUiDiagnostics._();

  /// Off in release builds by default; tests can set it explicitly.
  static bool enabled = kDebugMode;

  static const maxEntries = 100;

  static final List<ThemeUiDiagnostic> entries = [];

  /// One report per node type/variant/kit combination, so a list with 200
  /// rows does not produce 200 identical lines.
  static final Set<String> _reported = {};

  static void kitFallback({
    required String nodeType,
    required ThemeUiKit requested,
    required ThemeUiKit used,
    String? variant,
  }) {
    _record(
      ThemeUiDiagnostic(
        nodeType: nodeType,
        variant: variant,
        requested: requested,
        used: used,
      ),
    );
  }

  static void missingComponent({
    required String nodeType,
    required ThemeUiKit requested,
    String? variant,
  }) {
    _record(
      ThemeUiDiagnostic(
        nodeType: nodeType,
        variant: variant,
        requested: requested,
        used: ThemeUiKit.fallback,
        missing: true,
      ),
    );
  }

  static void _record(ThemeUiDiagnostic entry, {bool missing = false}) {
    if (!enabled) return;
    final key = '${entry.nodeType}/${entry.requested.id}/${entry.used.id}/'
        '${entry.variant ?? ''}/$missing';
    if (!_reported.add(key)) return;

    if (entries.length >= maxEntries) entries.removeAt(0);
    entries.add(entry);
    debugPrint(
        entry.missing ? '${entry.toString()} (no implementation)' : '$entry');
  }

  /// One render-point fallback observation.
  static final List<ThemeUiRenderPointDiagnostic> renderPointEntries = [];
  static final Set<String> _renderPointReported = {};

  /// Reports that a theme mapped a render point to a template the host could
  /// not use, so the host default is showing instead.
  static void renderPointFallback({
    required String renderPoint,
    String? template,
    required String reason,
  }) {
    if (!enabled) return;
    final key = '$renderPoint/${template ?? ''}/$reason';
    if (!_renderPointReported.add(key)) return;

    final entry = ThemeUiRenderPointDiagnostic(
      renderPoint: renderPoint,
      template: template,
      reason: reason,
    );
    if (renderPointEntries.length >= maxEntries) {
      renderPointEntries.removeAt(0);
    }
    renderPointEntries.add(entry);
    debugPrint('$entry');
  }

  /// Clears the recorded entries. Tests call this between cases.
  static void reset() {
    entries.clear();
    _reported.clear();
    renderPointEntries.clear();
    _renderPointReported.clear();
  }
}

/// One render-point fallback: which point, which template, and why the host
/// could not honour it.
@immutable
class ThemeUiRenderPointDiagnostic {
  final String renderPoint;
  final String? template;
  final String reason;

  const ThemeUiRenderPointDiagnostic({
    required this.renderPoint,
    required this.reason,
    this.template,
  });

  @override
  String toString() {
    final name = template == null ? '' : ' (template "$template")';
    return 'ThemeUi: render point $renderPoint$name fell back to the host '
        'default: $reason';
  }
}

/// A theme's component style for [group], with the active kit's override on
/// top.
///
/// `components.<group>` is the v3 baseline; `components.<kit>.<group>` is the
/// v4 per-kit override. Both may carry a variant entry
/// (`buttons.primary`, ...), which is merged last.
Map<String, dynamic> themeUiComponentStyle(
  ThemeDefinition theme,
  ThemeUiKit kit,
  String group, {
  String? variant,
}) {
  Map<String, dynamic> asMap(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : const {};

  final kitBlock = asMap(theme.components[kit.id]);
  final baseGroup = asMap(theme.components[group]);
  final kitGroup = asMap(kitBlock[group]);

  final style = <String, dynamic>{...baseGroup, ...kitGroup};
  if (variant != null) {
    style.addAll({
      ...asMap(baseGroup[variant]),
      ...asMap(kitGroup[variant]),
    });
  }
  return style;
}
