/// One action carried by a theme UI node, already reduced to the host-known
/// vocabulary.
///
/// Parsing is deliberately narrow: an installed plugin need not have been
/// built by this checkout's validator, so an unknown verb never reaches the
/// dispatcher and an over-long list is truncated rather than fanned out.
class ThemeUiAction {
  static const maxPerNode = 4;

  static const knownTypes = <String>{
    'navigate',
    'playPause',
    'next',
    'previous',
    'seek',
    'setVolume',
    'setShuffle',
    'setLoopMode',
    'like',
    'download',
    'openSettings',
    'openLyrics',
    'openQueue',
    'openDownloads',
    'toast',
    'plugin',
  };

  final String type;
  final Map<String, dynamic> args;

  const ThemeUiAction(this.type, [this.args = const {}]);

  static ThemeUiAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String || !knownTypes.contains(type)) return null;
    final rawArgs = raw['args'];
    final args = rawArgs is Map
        ? rawArgs.cast<String, dynamic>()
        : const <String, dynamic>{};
    return ThemeUiAction(type, args);
  }

  /// `actions` wins over `action`, matching the build validator: a node that
  /// carries both is read as the list and the extra verb is ignored.
  static List<ThemeUiAction> fromNode(Map<String, dynamic> node) {
    final rawList = node['actions'];
    final source = rawList is List ? rawList : <Object?>[node['action']];
    final actions = <ThemeUiAction>[];
    for (final raw in source.take(maxPerNode)) {
      final action = tryParse(raw);
      if (action != null) actions.add(action);
    }
    return actions;
  }
}
