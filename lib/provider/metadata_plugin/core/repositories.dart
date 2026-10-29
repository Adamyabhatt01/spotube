import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/logger/logger.dart';

/// One plugin registry and whatever it answered.
///
/// Exactly one of [response] / [failure] is set. Kept as data instead of a
/// thrown error so a source that is down cannot take the other one's results
/// with it.
class _IndexSource {
  final String host;
  final Response? response;
  final Object? failure;

  const _IndexSource({
    required this.host,
    this.response,
    this.failure,
  });
}

/// One cached index page: the response verbatim plus whatever validators the
/// server offered for revalidation.
class _CachedIndex {
  final Response response;
  final DateTime fetchedAt;
  final String? etag;
  final String? lastModified;

  const _CachedIndex({
    required this.response,
    required this.fetchedAt,
    this.etag,
    this.lastModified,
  });
}

/// Answers inside this window are served from memory without touching the
/// network; GitHub's search API is rate-limited to 10 req/min unauthenticated,
/// and the page was being refetched on every refresh tap and remount.
const _indexTtl = Duration(seconds: 60);

class MetadataPluginRepositoriesNotifier
    extends PaginatedAsyncNotifier<MetadataPluginRepository> {
  /// [dio] is the test seam: a directly constructed notifier has no container
  /// to read from, so tests pass their stubbed client explicitly.
  MetadataPluginRepositoriesNotifier({Dio? dio})
      : _dio = dio,
        super();

  final Dio? _dio;

  Dio get _client => _dio ?? ref.read(appDioProvider);

  final Map<String, bool> _hasMore = {};

  /// Keyed by full request URL including query parameters — every page is
  /// its own entry. Static so provider invalidation cannot throw the cache
  /// away; the TTL bounds staleness instead. Capped at 32 pages (evict
  /// oldest): the index holds full Dio responses and pagination is bounded
  /// in practice to a handful of pages per host.
  static final Map<String, _CachedIndex> _cache = {};

  @visibleForTesting
  static int get debugIndexCacheLength => _cache.length;

  static void _storeIndexPage(String key, _CachedIndex entry) {
    while (_cache.length >= 32) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = entry;
  }

  @visibleForTesting
  static void debugClearIndexCache() => _cache.clear();

  Future<_IndexSource> _query(
    String host,
    String url,
    Map<String, dynamic> queryParameters,
  ) async {
    final key = '$url?$queryParameters';
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.fetchedAt) < _indexTtl) {
      return _IndexSource(host: host, response: cached.response);
    }

    try {
      final response = await _client.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          // Dio's default stops at <300, which would surface the revalidation
          // hit as an error.
          validateStatus: (status) => status == null || status < 400,
          headers: {
            if (cached?.etag case final etag?) 'if-none-match': etag,
            if (cached?.lastModified case final modified?)
              'if-modified-since': modified,
          },
        ),
      );

      // A validated 304 carries no body: the previous answer stands, and its
      // clock is reset so the revalidation is amortized over the TTL again.
      if (response.statusCode == 304) {
        if (cached == null) {
          // A validator we never sent: nothing to stand in for a body.
          return _IndexSource(
            host: host,
            failure: StateError('304 for $key without a cached response'),
          );
        }
        _storeIndexPage(
          key,
          _CachedIndex(
            response: cached.response,
            fetchedAt: now,
            etag: cached.etag,
            lastModified: cached.lastModified,
          ),
        );
        return _IndexSource(host: host, response: cached.response);
      }

      _storeIndexPage(
        key,
        _CachedIndex(
          response: response,
          fetchedAt: now,
          etag: response.headers["etag"]?[0],
          lastModified: response.headers["last-modified"]?[0],
        ),
      );
      return _IndexSource(host: host, response: response);
    } catch (e) {
      return _IndexSource(host: host, failure: e);
    }
  }

  /// GitHub answers in `items`, Codeberg (Gitea) in `data`.
  List<dynamic> _itemsOf(Response response) {
    final data = response.data;
    final items =
        data is Map ? data["data"] ?? data["items"] ?? const [] : const [];
    return items is List ? items : const [];
  }

  int _totalCountOf(Response response) {
    final data = response.data;
    if (data is Map && data["total_count"] is int) {
      return data["total_count"] as int;
    }
    return int.tryParse(response.headers["x-total-count"]?[0] ?? "") ?? 0;
  }

  @override
  fetch(int offset, int limit) async {
    final sources = await Future.wait([
      if (_hasMore["github.com"] ?? true)
        _query(
          "github.com",
          "https://api.github.com/search/repositories",
          {
            "q": "topic:spotube-plugin",
            "sort": "stars",
            "order": "desc",
            "page": offset,
            "per_page": limit,
          },
        ),
      if (_hasMore["codeberg.org"] ?? true)
        _query(
          "codeberg.org",
          "https://codeberg.org/api/v1/repos/search",
          {
            "q": "spotube-plugin",
            "topic": "true",
            "sort": "stars",
            "order": "desc",
            "page": offset,
            "limit": limit,
          },
        ),
    ]);

    final answered = sources.where((source) => source.response != null);
    final failures = sources.where((source) => source.failure != null);

    for (final failure in failures) {
      AppLogger.reportError(
        failure.failure!,
        StackTrace.empty,
        'plugin index: ${failure.host} unavailable',
      );
    }

    // Nothing answered: a failed load, not an empty catalog. The screen has to
    // be able to tell the two apart, so this stays an error instead of a page
    // with nothing on it.
    if (answered.isEmpty) {
      throw sources.first.failure!;
    }

    // A repo with no URL has nothing to install from, so it is dropped rather
    // than listed with an Install button that can only fail.
    final repos = [
      for (final source in answered)
        for (final repo in _itemsOf(source.response!))
          if (repo is Map)
            MetadataPluginRepository(
              name: repo["name"] as String? ?? "",
              owner: (repo["owner"] as Map?)?["login"] as String? ?? "",
              description: repo["description"] as String? ?? "",
              repoUrl: repo["html_url"] as String? ?? "",
              topics: (repo["topics"] as List?)?.whereType<String>().toList() ??
                  const [],
            ),
    ].where((repo) => repo.repoUrl.isNotEmpty).toList();

    var hasMore = false;
    for (final source in answered) {
      final items = _itemsOf(source.response!);
      final sourceHasMore = items.length >= limit && items.isNotEmpty;
      _hasMore[source.host] = sourceHasMore;
      hasMore = hasMore || sourceHasMore;
    }

    return SpotubePaginationResponseObject(
      items: repos,
      total: answered.fold<int>(
        0,
        (previousValue, source) =>
            previousValue + _totalCountOf(source.response!),
      ),
      hasMore: hasMore,
      nextOffset: hasMore ? offset + 1 : null,
      limit: limit,
    );
  }

  @override
  build() async {
    return await fetch(0, 10);
  }
}

final metadataPluginRepositoriesProvider = AsyncNotifierProvider<
    MetadataPluginRepositoriesNotifier,
    SpotubePaginationResponseObject<MetadataPluginRepository>>(
  () => MetadataPluginRepositoriesNotifier(),
);
