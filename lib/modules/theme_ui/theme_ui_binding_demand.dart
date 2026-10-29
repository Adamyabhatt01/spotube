import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_registry.dart';

/// The set of bindings a document actually references.
///
/// Computed once per document (theme switch or UI override) and handed to
/// the binding builder, which subscribes only to the sources in this set.
/// Without it every slot would watch the player, the saved library and the
/// queue even when the theme draws a static label.
class ThemeUiBindingDemand {
  final Set<String> names;
  final bool everything;

  late final Set<String> namespaces = {
    for (final name in names) _namespace(name),
  };

  ThemeUiBindingDemand(Iterable<String> names, {this.everything = false})
      : names = Set.unmodifiable(names.toSet());

  static final all = ThemeUiBindingDemand(
    ThemeUiBindingRegistry.globalNames,
    everything: true,
  );

  static final none = ThemeUiBindingDemand(const []);

  bool wants(String name) => everything || names.contains(name);

  bool wantsNamespace(String namespace) =>
      everything || namespaces.contains(namespace);

  bool wantsAny(Iterable<String> candidates) =>
      everything || candidates.any(names.contains);

  Set<String> get sources => everything
      ? {
          for (final definition in ThemeUiBindingRegistry.definitions)
            definition.source,
        }
      : ThemeUiBindingRegistry.sourcesFor(names);

  static const _bindingPattern = r'^[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_-]+)+$';
  static final _binding = RegExp(_bindingPattern);
  static final _paletteToken = RegExp(r'@(palette\.[A-Za-z]+)');

  /// Walks slots, screens, templates and every nested node value.
  ///
  /// Scanning values rather than a fixed key list keeps the detector honest
  /// when the vocabulary grows (a table's `columns[].bind`, a filter's
  /// `bind`, a new input prop) and picks up `@palette.*` colour tokens.
  /// False positives only cost a subscription the theme did not need; a
  /// missed binding would render an empty node.
  static ThemeUiBindingDemand scan(ThemeUiDocument? ui) {
    if (ui == null) return none;
    final names = <String>{};

    void walk(Object? value) {
      if (value is String) {
        if (_binding.hasMatch(value)) names.add(value);
        for (final match in _paletteToken.allMatches(value)) {
          final token = match.group(1);
          if (token != null) names.add(token);
        }
        return;
      }
      if (value is Map) {
        for (final entry in value.values) {
          walk(entry);
        }
        return;
      }
      if (value is Iterable) {
        for (final entry in value) {
          walk(entry);
        }
      }
    }

    for (final slot in ui.slots.values) {
      walk(slot.children);
    }
    for (final screen in ui.screens.values) {
      walk(screen.children);
    }
    for (final template in ui.templates.values) {
      walk(template.children);
    }

    // Row bindings such as `item.playing` are derived from the player even
    // when the theme never mentions `player.*`; without this the row would
    // compare every entry against a missing id.
    if (names.any((name) => name.startsWith('item.'))) {
      names.add('player.trackId');
    }

    return ThemeUiBindingDemand(names);
  }
}

String _namespace(String name) {
  final separator = name.indexOf('.');
  return separator < 0 ? name : name.substring(0, separator);
}
