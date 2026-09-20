import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
// ignore: implementation_imports
import 'package:riverpod/src/async_notifier.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';

const _vmCrossed429 =
    'DioException [bad response]: This exception was thrown because the '
    'response has a status code of 429 and RequestOptions.validateStatus was '
    'configured to throw for this status code.';

DioException _dio(int status) {
  return DioException(
    requestOptions: RequestOptions(path: 'https://example.test/x'),
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: RequestOptions(path: 'https://example.test/x'),
      statusCode: status,
    ),
  );
}

class _RetryHost extends AsyncNotifier<SpotubePaginationResponseObject<String>>
    with MetadataPluginMixin<String> {
  @override
  Future<SpotubePaginationResponseObject<String>> build() async =>
      throw UnimplementedError();
}

void main() {
  group('isRateLimitedError', () {
    test('matches typed DioException 429', () {
      expect(isRateLimitedError(_dio(429)), isTrue);
    });

    test('matches the stringified form crossing the Hetu VM', () {
      expect(isRateLimitedError(StateError(_vmCrossed429)), isTrue);
      expect(isRateLimitedError(_vmCrossed429), isTrue);
    });

    test('rejects other statuses and errors', () {
      expect(isRateLimitedError(_dio(500)), isFalse);
      expect(isRateLimitedError(_dio(403)), isFalse);
      expect(isRateLimitedError(Exception('boom')), isFalse);
    });
  });

  group('shouldRetryAfterRateLimit', () {
    test('allows retries only within the attempt budget', () {
      expect(shouldRetryAfterRateLimit(_dio(429), 0), isTrue);
      expect(shouldRetryAfterRateLimit(_dio(429), maxRateLimitAutoRetries - 1),
          isTrue);
      expect(shouldRetryAfterRateLimit(_dio(429), maxRateLimitAutoRetries),
          isFalse);
    });

    test('never retries non-rate-limit errors', () {
      expect(shouldRetryAfterRateLimit(_dio(500), 0), isFalse);
    });
  });

  group('fetchWithRateLimitRetry', () {
    final host = _RetryHost();
    const noWait = Duration.zero;

    test('succeeds after transient 429s', () async {
      var calls = 0;
      final result = await host.fetchWithRateLimitRetry(() async {
        calls++;
        if (calls <= 2) throw _vmCrossed429;
        return calls;
      }, cooldown: noWait);

      expect(result, 3);
      expect(calls, 3);
    });

    test('gives up after the attempt budget and rethrows', () async {
      var calls = 0;
      await expectLater(
        host.fetchWithRateLimitRetry<int>(() async {
          calls++;
          throw _dio(429);
        }, cooldown: noWait),
        throwsA(isA<DioException>()),
      );
      // Initial attempt + maxRateLimitAutoRetries retries.
      expect(calls, maxRateLimitAutoRetries + 1);
    });

    test('rethrows non-rate-limit errors immediately', () async {
      var calls = 0;
      await expectLater(
        host.fetchWithRateLimitRetry<int>(() async {
          calls++;
          throw StateError('other');
        }, cooldown: noWait),
        throwsStateError,
      );
      expect(calls, 1);
    });
  });
}
