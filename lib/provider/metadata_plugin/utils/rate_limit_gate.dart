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

/// Runs [request] behind the session [RateLimitGate], recording the outcome on
/// [gate].
///
/// [maxRetries] is the in-request cooldown budget. It defaults to 0 because
/// most metadata reads back UI that is rebuilt by navigation: waiting 30s
/// inside a build is worse than showing the rate-limit error, and the strike
/// makes the next read fail fast without re-probing Spotify. Callers that
/// would rather wait than fail (saved-list builds) pass
/// [maxRateLimitAutoRetries].
Future<T> runGated<T>(
  RateLimitGate gate,
  Future<T> Function() request, {
  int maxRetries = 0,
  Duration cooldown = rateLimitRetryCooldown,
}) async {
  gate.ensureOpen();

  var attempt = 0;
  while (true) {
    try {
      final result = await request();
      gate.recordSuccess();
      return result;
    } catch (e) {
      if (!isRateLimitedError(e)) rethrow;
      if (e is! RateLimitedUntilException) gate.recordRateLimit();
      if (!shouldRetryAfterRateLimit(e, attempt, maxRetries: maxRetries)) {
        rethrow;
      }
      ++attempt;
      await Future.delayed(cooldown);
    }
  }
}
