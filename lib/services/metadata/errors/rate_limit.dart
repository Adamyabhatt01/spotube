import 'dart:math';

import 'package:dio/dio.dart';

/// Spotify throttles metadata requests with HTTP 429 per token/client.
/// Metadata calls run inside the Hetu plugin VM, where the typed
/// [DioException] usually crosses the boundary as its stringified form,
/// so detection accepts both shapes.
bool isRateLimitedError(Object error) {
  if (error is RateLimitedUntilException) return true;
  if (error is DioException && error.response?.statusCode == 429) return true;
  return error.toString().contains('status code of 429');
}

/// A rejected credential: 401/403, arriving either as a typed [DioException] or
/// as its stringified form from across the plugin VM boundary.
///
/// Kept apart from [isRateLimitedError] on purpose, and never folded into the
/// rate-limit gate: a quota backoff cannot fix an expired token, and closing
/// the gate would suppress unrelated reads behind an error that only
/// re-authentication clears.
bool isCredentialError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) return true;
  }
  final text = error.toString();
  return text.contains('status code of 401') ||
      text.contains('status code of 403');
}

/// Spotify's read quotas reset on minute-scale windows; two waits of 30s add
/// at most a minute of latency before surfacing a terminal error.
const rateLimitRetryCooldown = Duration(seconds: 30);
const maxRateLimitAutoRetries = 2;
const maxRateLimitBackoff = Duration(minutes: 10);

/// Wall-clock ceiling for a single plugin request.
///
/// The Spotify plugin builds its HTTP client with no options
/// (`HttpClient()` in `hetu_std`), so `hetu_std` hands Dio a null
/// `BaseOptions` and connect/receive/send timeouts are all infinite. Nothing
/// else bounds those requests either: metadata never touches `globalDio`,
/// whose 15s/30s/15s applies only to the app's own client. A stalled-but-open
/// connection to Spotify therefore left the screen spinning forever, visually
/// identical to a hang.
///
/// This abandons the await, it does not cancel the request: Hetu interprets
/// in-process, so the plugin's own Dio call keeps running and its eventual
/// result is discarded. That is why a timeout is deliberately *not* a
/// rate-limit strike — it is a distinct failure, and the gate must not
/// suppress unrelated reads because of it.
const metadataRequestBudget = Duration(seconds: 15);

/// Pure decision fn (repo idiom: state stays in the caller). [maxRetries] is
/// the caller's in-request budget: interactive screens pass 0 so a 429
/// surfaces at once instead of waiting out cooldowns mid-build.
bool shouldRetryAfterRateLimit(
  Object error,
  int attempt, {
  int maxRetries = maxRateLimitAutoRetries,
}) {
  return attempt < maxRetries && isRateLimitedError(error);
}

/// Escalating session-wide cooldown after repeated 429s: 30s, 1min, 2min,
/// capped at [maxRateLimitBackoff]. Sustained windows can outlast any
/// in-request retry, so probing the wall faster never helps.
Duration rateLimitBackoff(int strikes) {
  var seconds = rateLimitRetryCooldown.inSeconds;
  for (var i = 1; i < strikes && seconds < maxRateLimitBackoff.inSeconds; i++) {
    seconds *= 2;
  }
  return Duration(seconds: min(seconds, maxRateLimitBackoff.inSeconds));
}

/// Thrown (without any network call) while the session rate-limit gate is
/// closed. [retryAt] is when the next probe is allowed.
class RateLimitedUntilException implements Exception {
  final DateTime retryAt;

  const RateLimitedUntilException(this.retryAt);

  @override
  String toString() => 'RateLimitedUntilException: retry after $retryAt';
}
