import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
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
      _page(const ['ready']);
}

final _hostProvider =
    AsyncNotifierProvider<_RetryHost, SpotubePaginationResponseObject<String>>(
  () => _RetryHost(),
);

SpotubePaginationResponseObject<String> _page(List<String> items) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

_RetryHost _mountedHost(ProviderContainer container) {
  // Initialize the provider; the default _page value makes it AsyncData.
  container.listen(_hostProvider, (_, __) {});
  return container.read(_hostProvider.notifier);
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

    test('matches the gate exception', () {
      expect(
        isRateLimitedError(RateLimitedUntilException(DateTime.now())),
        isTrue,
      );
    });
  });

  group('rateLimitBackoff', () {
    test('doubles per strike and caps at maxRateLimitBackoff', () {
      expect(rateLimitBackoff(1), const Duration(seconds: 30));
      expect(rateLimitBackoff(2), const Duration(minutes: 1));
      expect(rateLimitBackoff(3), const Duration(minutes: 2));
      expect(rateLimitBackoff(10), maxRateLimitBackoff);
      expect(rateLimitBackoff(100), maxRateLimitBackoff);
    });
  });

  group('RateLimitGate', () {
    test('closed gate fails fast without touching the network', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);
      final host = _mountedHost(container);

      gate.recordRateLimit();
      var calls = 0;

      await expectLater(
        host.fetchWithRateLimitRetry<int>(() async {
          calls++;
          return 1;
        }),
        throwsA(isA<RateLimitedUntilException>()),
      );
      expect(calls, 0, reason: 'a blocked gate must not issue requests');
      expect(container.read(rateLimitGateProvider), isNotNull);
    });

    test('a success after transient 429s reopens the gate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final host = _mountedHost(container);

      var calls = 0;
      final result = await host.fetchWithRateLimitRetry(() async {
        calls++;
        if (calls <= 1) throw _vmCrossed429;
        return calls;
      }, cooldown: Duration.zero);

      expect(result, 2);
      expect(container.read(rateLimitGateProvider), isNull);
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
    const noWait = Duration.zero;

    test('succeeds after transient 429s', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final host = _mountedHost(container);

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
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final host = _mountedHost(container);

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
      // Persistent throttling leaves the gate closed for the next caller.
      expect(container.read(rateLimitGateProvider), isNotNull);
    });

    test('rethrows non-rate-limit errors immediately and keeps gate open',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final host = _mountedHost(container);

      var calls = 0;
      await expectLater(
        host.fetchWithRateLimitRetry<int>(() async {
          calls++;
          throw StateError('other');
        }, cooldown: noWait),
        throwsStateError,
      );
      expect(calls, 1);
      expect(container.read(rateLimitGateProvider), isNull);
    });
  });
}
