import 'package:flutter/widgets.dart';

/// Anchor registry for the `anchor` node prop and the `scrollTo` action.
///
/// A node may declare `anchor: '<name>'`; the renderer wraps it in a keyed
/// subtree whose [GlobalKey] lands here. A `scrollTo` action naming the same
/// `target` then calls `Scrollable.ensureVisible` on whatever scrollable
/// ancestor holds the anchor — no scroll-controller plumbing crosses the
/// theme boundary.
///
/// The registry is scoped to one mounted document (see
/// [ThemeUiAnchorRegistryScope]), so names only have to be unique inside a
/// single theme document. Anchor names must be unique: two live nodes
/// claiming one name would share a [GlobalKey], which Flutter rejects.
class ThemeUiAnchorRegistry {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// The key for [name], created on first use and stable afterwards.
  GlobalKey keyFor(String name) => _keys.putIfAbsent(name, GlobalKey.new);

  /// The key currently registered for [name], or null when nothing anchored.
  GlobalKey? operator [](String name) => _keys[name];
}

/// Makes the document's [ThemeUiAnchorRegistry] reachable from node builds
/// and overlay builders. Installed once by the host next to
/// `ThemeUiRuntimeScope`; overlays re-provide the same instance so an anchor
/// inside a dialog or menu still resolves.
class ThemeUiAnchorRegistryScope extends InheritedWidget {
  final ThemeUiAnchorRegistry registry;

  const ThemeUiAnchorRegistryScope({
    required this.registry,
    required super.child,
    super.key,
  });

  static ThemeUiAnchorRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeUiAnchorRegistryScope>()
        ?.registry;
  }

  /// Non-dependent read for dispatch paths that must not subscribe.
  static ThemeUiAnchorRegistry? read(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ThemeUiAnchorRegistryScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(ThemeUiAnchorRegistryScope oldWidget) {
    return registry != oldWidget.registry;
  }
}
