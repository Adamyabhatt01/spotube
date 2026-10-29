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
    'playItem',
    'openItem',
    'likeItem',
    'downloadItem',
    'dismiss',
    'setQuery',
    'clearQuery',
    'setSetting',
    'toggleSetting',
    'copy',
    'refresh',
    'toggleSidebar',
    'toggleAside',
    'toggleRegion',
  };

  final String type;
  final Map<String, dynamic> args;

  const ThemeUiAction(this.type, [this.args = const {}]);

  /// A copy whose arguments have `$value` replaced by [value].
  ///
  /// An argument that is exactly `$value` keeps the value's type (a slider
  /// hands `setBass` a number, not the string "3"); a `$value` inside a longer
  /// string is interpolated. Lists and maps are walked so a future action with
  /// a nested arg bag works without another helper.
  ThemeUiAction withValue(Object? value) {
    Object? replace(Object? raw) {
      if (raw == r'$value') return value;
      if (raw is String) return raw.replaceAll(r'$value', '$value');
      if (raw is Map) {
        return {
          for (final entry in raw.entries) entry.key: replace(entry.value),
        };
      }
      if (raw is List) return raw.map(replace).toList();
      return raw;
    }

    return ThemeUiAction(type, {
      for (final entry in args.entries) entry.key: replace(entry.value),
    });
  }

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
