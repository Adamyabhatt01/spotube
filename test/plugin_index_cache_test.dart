// PR 8 (N-03): index answers inside the 60 s TTL are served from the static
// cache with no network call at all, and each page is its own cache entry.
// The revalidation branch (ETag -> 304) is deliberately not exercised: faking
// TTL expiry would need a clock seam the notifier does not expose.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/repositories.dart';

class _FakeIndex implements HttpClientAdapter {
  _FakeIndex(this.marker);

  /// The repo name this fake answers with — lets the test tell a cached
  /// answer from a fresh one.
  final String marker;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode({
        'total_count': 1,
        'items': [
          {
            'name': marker,
            'owner': {'login': 'someone'},
            'description': '$marker description',
            'html_url': 'https://example.com/$marker',
            'topics': ['spotube-plugin'],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(MetadataPluginRepositoriesNotifier.debugClearIndexCache);

  Future<SpotubePaginationResponseObject<MetadataPluginRepository>> loadPage(
    MetadataPluginRepositoriesNotifier notifier,
    int offset,
  ) =>
      notifier.fetch(offset, 1);

  test('a repeat of the same page within the TTL costs no network', () async {
    final first = _FakeIndex('fresh');
    final dio = Dio()..httpClientAdapter = first;
    final notifier = MetadataPluginRepositoriesNotifier(dio: dio);
    // One item against a limit of one keeps per-source `_hasMore` true, so
    // the second call really attempts the network again.
    final initial = await loadPage(notifier, 0);
    // The same fixture body answers for both hosts, so a full page is the
    // repo twice.
    expect(initial.items.map((r) => r.name), ['fresh', 'fresh']);
    expect(first.requests.length, 2, reason: 'github + codeberg');

    final second = _FakeIndex('would-be-fresh');
    dio.httpClientAdapter = second;
    final cached = await loadPage(notifier, 0);

    expect(second.requests, isEmpty, reason: 'cache served the whole page');
    expect(cached.items.map((r) => r.name), ['fresh', 'fresh']);
  });

  test('pages are cached separately, not one entry per host', () async {
    final fake = _FakeIndex('p0');
    final dio = Dio()..httpClientAdapter = fake;
    final notifier = MetadataPluginRepositoriesNotifier(dio: dio);

    await loadPage(notifier, 0);
    final pageTwo = await notifier.fetch(1, 1);

    expect(fake.requests.length, 4, reason: 'offset 1 is a different key');
    expect(pageTwo.items, isNotEmpty);
  });
}
