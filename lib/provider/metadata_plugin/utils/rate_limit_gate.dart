import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';

/// Session-wide gate that stops metadata requests from re-probing Spotify's
/// rate limiter after a 429. Each strike closes the gate for an escalating
/// [rateLimitBackoff] window; a successful request clears it.
///
/// Intentionally not persisted: a fresh app launch should probe once (then
/// fall back to cached data quickly), rather than stay blocked across runs.
class RateLimitGate extends Notifier<DateTime?> {
  int _strikes = 0;

  @override
  DateTime? build() => null;

  bool get isBlocked {
    final blockedUntil = state;
    return blockedUntil != null && DateTime.now().isBefore(blockedUntil);
  }

  void recordRateLimit() {
    ++_strikes;
    state = DateTime.now().add(rateLimitBackoff(_strikes));
  }

  void recordSuccess() {
    _strikes = 0;
    state = null;
  }

  /// Throws [RateLimitedUntilException] without making a request while the
  /// gate is closed. Checked on entry to a request sequence; the bounded
  /// in-request cooldown retries continue even while closed by design.
  void ensureOpen() {
    if (isBlocked) throw RateLimitedUntilException(state!);
  }
}

final rateLimitGateProvider =
    NotifierProvider<RateLimitGate, DateTime?>(() => RateLimitGate());
