extension UniqueItemExtension<T> on List<T> {
  List<T> unique(bool Function(T a, T b) equals) {
    final copy = <T>[];

    for (final item in this) {
      if (copy.any((element) => equals(element, item))) continue;
      copy.add(item);
    }

    return copy;
  }

  /// First-occurrence dedupe like [unique], but O(n): one [keyOf] call per
  /// item and one hash lookup instead of a nested scan (~n²/2 comparisons).
  /// Keeps the first item of each key, drops later ones — same result as
  /// `unique((a, b) => keyOf(a) == keyOf(b))` whenever key equality agrees
  /// with `==` (true for the String/Uri keys this is used with).
  List<T> uniqueByKey<K>(K Function(T item) keyOf) {
    final seen = <K>{};
    final copy = <T>[];
    for (final item in this) {
      if (seen.add(keyOf(item))) copy.add(item);
    }
    return copy;
  }

  bool containsBy(T item, dynamic Function(T a) fn) {
    for (final el in this) {
      if (fn(el) == fn(item)) return true;
    }
    return false;
  }
}
