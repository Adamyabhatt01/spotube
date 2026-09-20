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

/// Spotify's read quotas reset on minute-scale windows; two waits of 30s add
/// at most a minute of latency before surfacing a terminal error.
const rateLimitRetryCooldown = Duration(seconds: 30);
const maxRateLimitAutoRetries = 2;
const maxRateLimitBackoff = Duration(minutes: 10);

/// Pure decision fn (repo idiom: state stays in the caller).
bool shouldRetryAfterRateLimit(Object error, int attempt) {
  return attempt < maxRateLimitAutoRetries && isRateLimitedError(error);
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
