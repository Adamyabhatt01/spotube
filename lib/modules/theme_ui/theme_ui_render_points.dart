import 'package:flutter/foundation.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';

/// The render points the v4.0 host publishes.
///
/// This list is closed on purpose: a host surface may only expose one of these
/// names, and a theme that maps anything else is ignored at runtime. Adding a
/// point is a contract change, not a theme decision.
///
/// The catalogue is mirrored in `themes/lib/v4_validator.dart` so the SDK can
/// report unknown ids without importing app code. Keep the two lists in step.
const themeUiRenderPoints = <String>{
  'search.field',
  'search.suggestions',
  'search.suggestion.item',
  'search.suggestion.group',
  'search.empty',
  'search.loading',
  'search.recent',
  'contextMenu.container',
  'contextMenu.item',
  'contextMenu.separator',
  'contextMenu.submenu',
  'library.playlist.item',
  'library.playlist.group',
  'library.playlist.empty',
  'queue.item',
  'table.header',
  'table.row',
  'player.trackDetails',
  'toast.item',
};

/// Templates may expand other templates, but not without a floor.
///
/// The limit is about render-point templates, not ordinary node nesting: a
/// template that refers to itself (directly or through a chain) would build a
/// new subtree on every frame, so the host stops at eight expansions.
const themeUiMaxTemplateDepth = 8;

/// The result of mapping one render point to a template.
///
/// [problem] is null when the theme declared no template for the point (the
/// host default is used without complaint) or when the template is usable.
/// A non-null problem means the theme *asked* for a template the host cannot
/// render and the host falls back.
@immutable
class ThemeUiRenderPointResolution {
  final String renderPoint;
  final String? templateName;
  final ThemeUiTemplate? template;
  final String? problem;

  const ThemeUiRenderPointResolution({
    required this.renderPoint,
    this.templateName,
    this.template,
    this.problem,
  });

  bool get hasTemplate => template != null;
}

/// Resolves [renderPoint] against a theme document.
///
/// Host surfaces call this once per build to decide whether their default
/// chrome is replaced and, when it is, to hand the resolution to
/// `ThemeUiTemplateHost` (so the template graph is not walked twice).
ThemeUiRenderPointResolution resolveThemeUiRenderPoint({
  required Map<String, String> renderPoints,
  required Map<String, ThemeUiTemplate> templates,
  required String renderPoint,
}) {
  if (!themeUiRenderPoints.contains(renderPoint)) {
    return ThemeUiRenderPointResolution(renderPoint: renderPoint);
  }

  final name = renderPoints[renderPoint];
  if (name == null || name.trim().isEmpty) {
    return ThemeUiRenderPointResolution(renderPoint: renderPoint);
  }

  final template = templates[name];
  if (template == null) {
    return ThemeUiRenderPointResolution(
      renderPoint: renderPoint,
      templateName: name,
      problem: 'template "$name" is missing',
    );
  }

  final problem = templateReferenceProblem(templates, name);
  if (problem != null) {
    return ThemeUiRenderPointResolution(
      renderPoint: renderPoint,
      templateName: name,
      problem: problem,
    );
  }

  return ThemeUiRenderPointResolution(
    renderPoint: renderPoint,
    templateName: name,
    template: template,
  );
}

/// Reports a resolution the host could not honour.
///
/// Surfaces that keep their shipped widget when [ThemeUiRenderPointResolution.hasTemplate]
/// is false still need the diagnostic, otherwise a missing template would
/// silently change nothing. The report is deduped by point/template/reason.
void reportThemeUiRenderPointFallback(
  ThemeUiRenderPointResolution resolution,
) {
  final problem = resolution.problem;
  if (problem == null) return;
  ThemeUiDiagnostics.renderPointFallback(
    renderPoint: resolution.renderPoint,
    template: resolution.templateName,
    reason: problem,
  );
}

/// Walks a template and everything it expands, returning the first reason the
/// host could not render it.
///
/// Shared by the runtime and by the theme SDK's validator indirectly (the SDK
/// keeps its own copy because it cannot import host code).
String? templateReferenceProblem(
  Map<String, ThemeUiTemplate> templates,
  String name,
) {
  String? walk(
    String current,
    List<String> path,
    int depth,
  ) {
    if (depth > themeUiMaxTemplateDepth) {
      return 'template nesting is deeper than $themeUiMaxTemplateDepth';
    }
    if (path.contains(current)) {
      return 'template "$current" refers to itself';
    }
    final template = templates[current];
    if (template == null) return 'template "$current" is missing';

    final nextPath = [...path, current];
    for (final node in template.children) {
      final problem = _nodeProblem(templates, node, nextPath, depth);
      if (problem != null) return problem;
    }
    return null;
  }

  return walk(name, const [], 1);
}

String? _nodeProblem(
  Map<String, ThemeUiTemplate> templates,
  Map<String, dynamic> node,
  List<String> path,
  int depth,
) {
  final type = node['type'];
  if (type == 'hostWidget') {
    return 'hostWidget is not allowed in a render-point template';
  }
  if (type == 'template') {
    final reference = _prop(node, 'name');
    if (reference is String && reference.trim().isNotEmpty) {
      final problem = _referenceProblem(
        templates,
        reference,
        path,
        depth + 1,
      );
      if (problem != null) return problem;
    }
  }

  final children = node['children'];
  if (children is List) {
    for (final child in children) {
      if (child is! Map) continue;
      final problem = _nodeProblem(
        templates,
        child.cast<String, dynamic>(),
        path,
        depth,
      );
      if (problem != null) return problem;
    }
  }
  return null;
}

String? _referenceProblem(
  Map<String, ThemeUiTemplate> templates,
  String name,
  List<String> path,
  int depth,
) {
  if (depth > themeUiMaxTemplateDepth) {
    return 'template nesting is deeper than $themeUiMaxTemplateDepth';
  }
  if (path.contains(name)) return 'template "$name" refers to itself';
  final template = templates[name];
  if (template == null) return 'template "$name" is missing';

  final nextPath = [...path, name];
  for (final node in template.children) {
    final problem = _nodeProblem(templates, node, nextPath, depth);
    if (problem != null) return problem;
  }
  return null;
}

/// Reads a prop from either the flat v4 shape or the original `props` object.
Object? _prop(Map<String, dynamic> node, String name) {
  final props = node['props'];
  if (props is Map && props[name] != null) return props[name];
  return node[name];
}
