// PR6: download/media-path unit contracts.
//
// Covered (all hermetic, no network):
//  - retry classification: transient retried, permanent/cancel fail fast.
//  - progress throttle: coalesced intermediates, guaranteed terminal event.
//  - ENOSPC detection incl. Dio-wrapped filesystem errors.
//  - source-match TTL decision matrix (hit/refresh/negativeHit).
//  - fetchAll: single emission, offsets/limits sequence, dedupe, error
//    propagation with pre-call state preserved.
//  - cached-file response: stream body (never buffered), exact headers.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/provider/server/routes/playback.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

DioException _dioError(
  DioExceptionType type, {
  int? statusCode,
  Object? error,
}) {
  return DioException(
    requestOptions: RequestOptions(path: 'https://example.test/x'),
    type: type,
    response: statusCode == null
        ? null
        : Response(
            requestOptions: RequestOptions(path: 'https://example.test/x'),
            statusCode: statusCode,
          ),
    error: error,
  );
}

SpotubeAudioSourceMatchObject _match(String id) {
  return SpotubeAudioSourceMatchObject(
    id: id,
    title: 'Test Title $id',
    artists: const ['Test Artist'],
    duration: const Duration(minutes: 3),
    externalUri: 'https://example.test/watch/$id',
  );
}

class _ScriptedPages extends AsyncNotifier<SpotubePaginationResponseObject<String>>
    with PaginatedAsyncNotifierMixin<String> {
  final SpotubePaginationResponseObject<String> initial;
  final List<SpotubePaginationResponseObject<String>> pages;
  final List<List<int>> seenOffsetsLimits = [];
  final int failFirstNCalls;
  int _calls = 0;

  _ScriptedPages(this.initial, this.pages, {this.failFirstNCalls = 0});

  @override
  Future<SpotubePaginationResponseObject<String>> build() async => initial;

  @override
  Future<SpotubePaginationResponseObject<String>> fetch(
      int offset, int limit) async {
    seenOffsetsLimits.add([offset, limit]);
    final call = _calls++;
    if (call < failFirstNCalls) throw StateError('page fetch failed');
    return pages[call];
  }
}

SpotubePaginationResponseObject<String> _page(
  List<String> items, {
  required bool hasMore,
  int? nextOffset,
  int limit = 100,
}) {
  return SpotubePaginationResponseObject<String>(
    limit: limit,
    nextOffset: nextOffset,
    total: items.length,
    hasMore: hasMore,
    items: items,
  );
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('isRetryableDownloadError', () {
    test('transient network errors retry', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.unknown,
      ]) {
        expect(isRetryableDownloadError(_dioError(type)), isTrue,
            reason: '$type must retry');
      }
      expect(
        isRetryableDownloadError(_dioError(DioExceptionType.badResponse,
            statusCode: 500)),
        isTrue,
        reason: '5xx must retry',
      );
      expect(
        isRetryableDownloadError(
            _dioError(DioExceptionType.badResponse, statusCode: 503)),
        isTrue,
      );
    });

    test('permanent failures fail fast', () {
      expect(isRetryableDownloadError(_dioError(DioExceptionType.cancel)),
          isFalse);
      expect(
          isRetryableDownloadError(_dioError(DioExceptionType.badResponse,
              statusCode: 404)),
          isFalse);
      expect(
          isRetryableDownloadError(_dioError(DioExceptionType.badResponse,
              statusCode: 403)),
          isFalse);
      expect(
          isRetryableDownloadError(
              _dioError(DioExceptionType.badCertificate)),
          isFalse);
      // Missing-URL / config errors are plain Exceptions: never retried.
      expect(isRetryableDownloadError(Exception('No download URL')), isFalse);
      expect(isRetryableDownloadError(StateError('x')), isFalse);
    });

    test('retry schedule is bounded exponential', () {
      expect(downloadRetryDelays, hasLength(2));
      expect(downloadRetryDelays[0] < downloadRetryDelays[1], isTrue);
    });
  });

  group('shouldEmitDownloadProgress', () {
    final t0 = DateTime(2026, 1, 1);
    const interval = Duration(milliseconds: 250);

    test('coalesces within the interval', () {
      expect(
        shouldEmitDownloadProgress(
          count: 10,
          total: 100,
          now: t0.add(const Duration(milliseconds: 100)),
          lastEmit: t0,
          interval: interval,
        ),
        isFalse,
      );
      expect(
        shouldEmitDownloadProgress(
          count: 10,
          total: 100,
          now: t0.add(const Duration(milliseconds: 250)),
          lastEmit: t0,
          interval: interval,
        ),
        isTrue,
      );
    });

    test('terminal event always emits (guaranteed 100%)', () {
      expect(
        shouldEmitDownloadProgress(
          count: 100,
          total: 100,
          now: t0,
          lastEmit: t0,
          interval: interval,
        ),
        isTrue,
      );
      // Over-delivery (retries/concat races) also passes through.
      expect(
        shouldEmitDownloadProgress(
          count: 120,
          total: 100,
          now: t0,
          lastEmit: t0,
          interval: interval,
        ),
        isTrue,
      );
    });

    test('unknown totals only throttle (completion is status-driven)', () {
      expect(
        shouldEmitDownloadProgress(
          count: 50,
          total: -1,
          now: t0,
          lastEmit: t0,
          interval: interval,
        ),
        isFalse,
      );
    });
  });

  group('isNoSpaceError', () {
    test('errno ENOSPC and message match', () {
      expect(
        isNoSpaceError(const FileSystemException(
          'write failed',
          null,
          OSError('No space left on device', 28),
        )),
        isTrue,
      );
      expect(
        isNoSpaceError(
            const FileSystemException('No space left on device, write aborted')),
        isTrue,
      );
      expect(
        isNoSpaceError(const FileSystemException('connection reset by peer')),
        isFalse,
      );
    });

    test('Dio-wrapped filesystem errors unwrap', () {
      expect(
        isNoSpaceError(_dioError(
          DioExceptionType.unknown,
          error: const FileSystemException(
            'write failed',
            null,
            OSError('No space left on device', 28),
          ),
        )),
        isTrue,
      );
      expect(
        isNoSpaceError(_dioError(DioExceptionType.connectionTimeout)),
        isFalse,
      );
    });
  });

  group('classifyCachedSourceMatch', () {
    late String validInfo;
    setUp(() {
      validInfo = jsonEncode(_match('video-1').toJson());
    });

    test('fresh → hit, expired → refresh', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(
        classifyCachedSourceMatch(
          sourceInfo: validInfo,
          createdAt: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        SourceMatchCacheDecision.hit,
      );
      expect(
        classifyCachedSourceMatch(
          sourceInfo: validInfo,
          createdAt: now.subtract(const Duration(hours: 7)),
          now: now,
        ),
        SourceMatchCacheDecision.refresh,
      );
    });

    test('fresh tombstone/garbage → negativeHit (no re-search)', () {
      final now = DateTime(2026, 1, 1, 12);
      for (final info in ['{}', 'not json', '{"info": 42}']) {
        expect(
          classifyCachedSourceMatch(
            sourceInfo: info,
            createdAt: now.subtract(const Duration(minutes: 5)),
            now: now,
          ),
          SourceMatchCacheDecision.negativeHit,
          reason: '$info must negative-hit while fresh',
        );
      }
    });

    test('expired tombstone/garbage → refresh (re-search allowed)', () {
      final now = DateTime(2026, 1, 1, 12);
      for (final info in ['{}', 'not json']) {
        expect(
          classifyCachedSourceMatch(
            sourceInfo: info,
            createdAt: now.subtract(const Duration(hours: 7)),
            now: now,
          ),
          SourceMatchCacheDecision.refresh,
          reason: '$info must refresh once stale',
        );
      }
    });
  });

  group('fetchAll single emission', () {
    Future<(_ScriptedPages, ProviderContainer)> setupPages(
      SpotubePaginationResponseObject<String> initial,
      List<SpotubePaginationResponseObject<String>> pages, {
      int failFirstNCalls = 0,
    }) async {
      final notifier =
          _ScriptedPages(initial, pages, failFirstNCalls: failFirstNCalls);
      final container = ProviderContainer(
        overrides: [_scriptedProvider.overrideWith(() => notifier)],
      );
      // Settle the initial build before driving fetchAll.
      await container.read(_scriptedProvider.future);
      return (notifier, container);
    }

    test('three pages merge with one state set', () async {
      final (notifier, container) = await setupPages(
        _page(const [], hasMore: true, nextOffset: 0, limit: 20),
        [
          _page(const ['a', 'b'], hasMore: true, nextOffset: 2),
          _page(const ['b', 'c'], hasMore: true, nextOffset: 3),
          _page(const ['d'], hasMore: false),
        ],
      );
      addTearDown(container.dispose);

      var emissions = 0;
      container.listen(_scriptedProvider, (_, __) => emissions++);

      final items = await notifier.fetchAll();

      expect(items, ['a', 'b', 'c', 'd']);
      expect(emissions, 1);
      // First fetch uses max(limit, 100); offsets advance per page.
      expect(
        notifier.seenOffsetsLimits.map((e) => e.first),
        [0, 2, 3],
      );
      expect(notifier.seenOffsetsLimits.first[1], 100);
    });

    test('unrecoverable page error rethrows, state untouched', () async {
      final (notifier, container) = await setupPages(
        _page(const ['a'], hasMore: true, nextOffset: 1),
        [_page(const ['b'], hasMore: false)],
        failFirstNCalls: 10,
      );
      addTearDown(container.dispose);

      await expectLater(notifier.fetchAll(), throwsStateError);
      // All-or-nothing: no partial page landed in state.
      expect(
        container.read(_scriptedProvider).value?.items,
        ['a'],
      );
    });
  });

  group('cachedFileStreamResponse', () {
    test('streams identical bytes with identical headers', () async {
      final dir = await Directory.systemTemp.createTemp('spotube-cache');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/track.mp3');
      final bytes = List.generate(256 * 1024, (i) => i % 256);
      await file.writeAsBytes(bytes);

      final res = cachedFileStreamResponse(
        file: file,
        fileLength: bytes.length,
        contentType: 'audio/mp3',
        requestPath: '/stream/x',
      );

      expect(res.data, isA<Stream<List<int>>>());
      expect(res.data, isNot(isA<Uint8List>()));
      expect(res.headers.value('content-type'), 'audio/mp3');
      expect(res.headers.value('content-length'), '${bytes.length}');
      expect(res.headers.value('accept-ranges'), 'bytes');
      expect(
        res.headers.value('content-range'),
        'bytes 0-${bytes.length - 1}/${bytes.length}',
      );

      final collected = <int>[];
      await for (final chunk in res.data!) {
        collected.addAll(chunk);
      }
      expect(collected, bytes);
    });
  });
}

final _scriptedProvider =
    AsyncNotifierProvider<_ScriptedPages, SpotubePaginationResponseObject<String>>(
  () => throw UnimplementedError('override with a scripted instance'),
);
