part of 'theme_ui_node.dart';

/// Makes a theme runtime available to host widgets that live outside a slot.
///
/// Search is mounted directly by the page, not inside a theme slot, so it
/// cannot receive a runtime through constructor arguments from the theme
/// host. The app root installs one scope and host surfaces read it; a test or
/// preview that pumps a host widget on its own simply gets no scope and keeps
/// the shipped default.
class ThemeUiRuntimeScope extends InheritedWidget {
  final ThemeUiRuntime runtime;

  const ThemeUiRuntimeScope({
    required this.runtime,
    required super.child,
    super.key,
  });

  static ThemeUiRuntime? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeUiRuntimeScope>()
        ?.runtime;
  }

  static ThemeUiRuntime? read(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ThemeUiRuntimeScope>()
        ?.runtime;
  }

  @override
  bool updateShouldNotify(ThemeUiRuntimeScope oldWidget) {
    final before = oldWidget.runtime;
    final after = runtime;
    return before.theme != after.theme ||
        before.templates != after.templates ||
        before.renderPoints != after.renderPoints ||
        before.assets != after.assets ||
        !mapEquals(before.bindings.values, after.bindings.values);
  }
}

/// Renders a render-point template over a scoped binding map.
///
/// The host surface keeps every behaviour around this widget: positioning,
/// focus, keyboard, gesture handling and dispatch. The template is visual
/// only, which is why it receives a fresh runtime with the context merged
/// over the app bindings instead of a writable state handle.
///
/// A missing or malformed template returns [fallback] and reports once through
/// [ThemeUiDiagnostics]. A template that resolves to zero children is treated
/// as an intentional "draw nothing", not as a failure.
class ThemeUiTemplateHost extends StatelessWidget {
  final ThemeUiRuntime runtime;
  final String renderPoint;
  final Map<String, Object?> bindings;
  final Widget fallback;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;

  /// A resolution the caller already computed, so a host surface can decide
  /// whether to keep its own chrome without walking the template graph twice.
  final ThemeUiRenderPointResolution? resolution;

  const ThemeUiTemplateHost({
    required this.runtime,
    required this.renderPoint,
    required this.fallback,
    this.bindings = const {},
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.resolution,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolution ??
        resolveThemeUiRenderPoint(
          renderPoints: runtime.renderPoints,
          templates: runtime.templates,
          renderPoint: renderPoint,
        );

    if (resolved.problem != null) {
      reportThemeUiRenderPointFallback(resolved);
      return fallback;
    }

    final template = resolved.template;
    final templateName = resolved.templateName;
    if (template == null || templateName == null) return fallback;

    if (!runtime.canExpandTemplate(templateName)) {
      ThemeUiDiagnostics.renderPointFallback(
        renderPoint: renderPoint,
        template: templateName,
        reason: 'template is already expanding or past the nesting limit',
      );
      return fallback;
    }

    if (template.children.isEmpty) return const SizedBox.shrink();

    final scoped = runtime
        .withBindings(ThemeUiBindings({
          ...runtime.bindings.values,
          ...bindings,
        }))
        .descendTemplate(templateName);

    if (template.children.length == 1) {
      return ThemeUiNodeView(
        node: template.children.first,
        runtime: scoped,
        depth: 0,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        for (final child in template.children)
          ThemeUiNodeView(node: child, runtime: scoped, depth: 0),
      ],
    );
  }
}
