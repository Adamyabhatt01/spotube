import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/dio/dio.dart';
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

class MetadataPluginRepositoriesNotifier
    extends PaginatedAsyncNotifier<MetadataPluginRepository> {
  MetadataPluginRepositoriesNotifier() : super();

  final Map<String, bool> _hasMore = {};

  Future<_IndexSource> _query(
    String host,
    String url,
    Map<String, dynamic> queryParameters,
  ) async {
    try {
      return _IndexSource(
        host: host,
        response: await globalDio.get(
          url,
          queryParameters: queryParameters,
        ),
      );
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
