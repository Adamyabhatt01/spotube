import 'package:dio/dio.dart';

/// Spotify throttles metadata requests with HTTP 429 per token/client.
/// Metadata calls run inside the Hetu plugin VM, where the typed
/// [DioException] usually crosses the boundary as its stringified form,
/// so detection accepts both shapes.
bool isRateLimitedError(Object error) {
  if (error is DioException && error.response?.statusCode == 429) return true;
  return error.toString().contains('status code of 429');
}

/// Spotify's read quotas reset on minute-scale windows; two waits of 30s add
/// at most a minute of latency before surfacing a terminal error.
const rateLimitRetryCooldown = Duration(seconds: 30);
const maxRateLimitAutoRetries = 2;

/// Pure decision fn (repo idiom: state stays in the caller).
bool shouldRetryAfterRateLimit(Object error, int attempt) {
  return attempt < maxRateLimitAutoRetries && isRateLimitedError(error);
}
