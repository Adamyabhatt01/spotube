/// The UI kits a v4 theme's semantic nodes can render through.
///
/// `shadcn` is the app's own kit and the fallback; `material` and `cupertino`
/// are Flutter's built-in widget sets, bridged from the same semantic palette
/// by `ShadcnApp`.
enum ThemeUiKit {
  shadcn('shadcn'),
  material('material'),
  cupertino('cupertino');

  const ThemeUiKit(this.id);

  /// The spelling used in theme JSON.
  final String id;

  /// The kit used when a node, scope and theme all leave the choice open.
  static const fallback = ThemeUiKit.shadcn;

  /// Parses a kit name, or returns null when it is not a kit this host knows.
  ///
  /// An unknown kit is not an error at runtime: the theme validator rejects
  /// it, but a payload from a newer plugin must still paint with the default
  /// kit rather than losing its palette.
  static ThemeUiKit? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final kit in values) {
      if (kit.id == raw) return kit;
    }
    return null;
  }

  /// Parses a kit name, falling back to [fallback].
  static ThemeUiKit fromId(Object? raw) => tryParse(raw) ?? fallback;
}
