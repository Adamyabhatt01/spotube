/// The host item surfaces that carry a right-click / long-press menu.
///
/// The set is closed on purpose: a menu is built from one host defaults table
/// per target, and a theme may only append actions to these targets. A new
/// surface means a new enum value and a new table, not a stringly-typed key.
enum ContextMenuTarget {
  track('track'),
  playlist('playlist'),
  album('album'),
  artist('artist'),
  queueItem('queueItem'),
  download('download'),
  searchResult('searchResult'),
  radio('radio');

  const ContextMenuTarget(this.id);

  /// Stable contract id, used in theme `menus` and in the user's stored
  /// configuration. Never rename one without a migration.
  final String id;

  static ContextMenuTarget? fromId(Object? raw) {
    if (raw is! String) return null;
    for (final target in values) {
      if (target.id == raw) return target;
    }
    return null;
  }
}
