/// One reference-counted hold on the shared VPN connection.
///
/// Obtained from `VpnManager.acquire()` and released exactly once via
/// [release]. Release is idempotent: calling it twice (e.g. a `finally`
/// racing provider disposal) is a safe no-op, and it never throws, so it is
/// safe inside `finally` blocks.
class VpnLease {
  final String id;

  Future<void> Function(String id)? _release;

  VpnLease(this.id, Future<void> Function(String id) release)
      : _release = release;

  bool get isReleased => _release == null;

  Future<void> release() async {
    final release = _release;
    if (release == null) return;
    _release = null;
    await release(id);
  }
}
