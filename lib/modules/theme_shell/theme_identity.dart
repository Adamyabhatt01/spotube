/// A memoization key that compares by object identity only.
///
/// Theme payloads are large freezed trees; their value equality walks
/// nested maps and lists, and `flutter_hooks` compares memo keys on every
/// rebuild. Providers replace these payloads by identity when the selected
/// theme changes, so identity is the correct (and cheap) change signal.
class IdentityKey<T> {
  const IdentityKey(this.value);

  final T? value;

  @override
  bool operator ==(Object other) =>
      other is IdentityKey<T> && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}
