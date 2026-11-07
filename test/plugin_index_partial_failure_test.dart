import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/repositories.dart';
import 'package:spotube/services/logger/logger.dart';

/// A registry answer for one host: either a body or an outage.
class _Source {
  final Object? failure;
  final Map<String, dynamic>? body;

  _Source.answer(this.body) : failure = null;
  _Source.down(Object this.failure) : body = null;
}

class _FakeIndex implements HttpClientAdapter {
  _FakeIndex(this.sources);

  final Map<String, _Source> sources;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    requests.add(options.uri);
    final source = sources[host];
    if (source == null) {
      throw Exception('the index queried an unexpected host: $host');
    }
    if (source.failure != null) {
      throw source.failure!;
    }
    return ResponseBody.fromString(
      jsonEncode(source.body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// GitHub's search shape: `items`, an `owner` object and `topics`.
Map<String, dynamic> _github(List<Map<String, dynamic>> repos) => {
      "total_count": repos.length,
      "items": repos,
    };

/// Codeberg (Gitea) answers with `data` and no `total_count`.
Map<String, dynamic> _codeberg(List<Map<String, dynamic>> repos) => {
      "ok": true,
      "data": repos,
    };

Map<String, dynamic> _repo(String name,
        {List<String>? topics, bool url = true}) =>
    {
      "name": name,
      "owner": {"login": "someone"},
      "description": "$name description",
      if (url) "html_url": "https://example.com/$name",
      if (topics != null) "topics": topics,
    };

void main() {
  setUpAll(() => AppLogger.initialize(false));

  late _FakeIndex fake;

  /// Runs one page of the index against [sources], restoring the real adapter
  /// either way.
  Future<SpotubePaginationResponseObject<MetadataPluginRepository>> load(
    Map<String, _Source> sources, {
    int offset = 0,
    int limit = 10,
  }) async {
    fake = _FakeIndex(sources);
    final dio = Dio()..httpClientAdapter = fake;
    return await MetadataPluginRepositoriesNotifier(dio: dio)
        .fetch(offset, limit);
  }

  setUp(() {
    // The N-03 index cache is static (it survives provider invalidation);
    // without this, a test's answer would be served to the next one.
    MetadataPluginRepositoriesNotifier.debugClearIndexCache();
  });

  final bothHosts = <String, _Source>{
    "api.github.com": _Source.answer(
      _github([
        _repo(
          "spotube-plugin-spotify",
          topics: ["spotube-plugin", "spotube-metadata-plugin"],
        ),
      ]),
    ),
    "codeberg.org": _Source.answer(
      _codeberg([
        _repo(
          "spotube-plugin-jiosaavn",
          topics: ["spotube-plugin", "spotube-audio-source-plugin"],
        ),
      ]),
    ),
  };

  test('both registries answer, both lists arrive', () async {
    final page = await load(bothHosts);

    expect(
      page.items.map((r) => r.name),
      containsAll(["spotube-plugin-spotify", "spotube-plugin-jiosaavn"]),
    );
    final spotify =
        page.items.firstWhere((r) => r.name == "spotube-plugin-spotify");
    expect(spotify.owner, "someone");
    expect(spotify.repoUrl, "https://example.com/spotube-plugin-spotify");
    expect(spotify.topics, contains("spotube-metadata-plugin"));
    expect(page.hasMore, isFalse, reason: 'one item against a page of 10');
    expect(fake.requests.map((u) => u.host),
        containsAll(["api.github.com", "codeberg.org"]));
  });

  test('one registry down still yields the other one\'s plugins', () async {
    // The bug this guards: both hosts were awaited as one Future.wait, so an
    // unreachable codeberg.org (ordinary on mobile data) rejected the request
    // and the plugins screen showed an empty list with no error in it.
    final page = await load({
      "api.github.com": _Source.answer(
        _github([
          _repo("spotube-plugin-spotify", topics: ["spotube-metadata-plugin"]),
          _repo("spotube-plugin-youtube-audio",
              topics: ["spotube-audio-source-plugin"]),
        ]),
      ),
      "codeberg.org": _Source.down(DioException(
        requestOptions: RequestOptions(path: "https://codeberg.org"),
        type: DioExceptionType.connectionTimeout,
      )),
    });

    expect(page.items.map((r) => r.name), [
      "spotube-plugin-spotify",
      "spotube-plugin-youtube-audio",
    ]);
    expect(page.total, 2);
  });

  test('a payload that never decodes into repos is not an error', () async {
    // Codeberg answers `{"ok":true,"data":[]}` for a search with no hits; a
    // malformed body must leave GitHub's results standing, not throw.
    final page = await load({
      "api.github.com": _Source.answer(
        _github([_repo("spotube-plugin-spotify")]),
      ),
      "codeberg.org": _Source.answer({"ok": true, "data": []}),
    });

    expect(page.items.length, 1);
    expect(page.hasMore, isFalse);
  });

  test('every field a registry may omit is tolerated', () async {
    final page = await load({
      "api.github.com": _Source.answer(
        _github([
          {"name": "no-topics-no-owner"}, // no owner, no topics, no html_url
          _repo("no-url", topics: ["spotube-plugin"], url: false),
          _repo("installable", topics: ["spotube-plugin"]),
        ]),
      ),
      "codeberg.org": _Source.answer(_codeberg([])),
    });

    // The entries with nothing to install from are dropped instead of listed
    // with an Install button that can only fail.
    expect(page.items.map((r) => r.name), ["installable"]);
    expect(page.items.single.topics, ["spotube-plugin"]);
  });

  test('pagination continues per source, not for the pair', () async {
    final full = List.generate(10, (i) => _repo("gh$i", topics: const []));
    final page = await load({
      "api.github.com": _Source.answer(_github(full)),
      "codeberg.org": _Source.down(Exception("refused")),
    }, limit: 10);

    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 1);
  });

  test('all registries down is a failed load, not an empty catalog', () async {
    // The screen renders this as an error with a retry instead of a blank
    // section that reads like "no plugins exist".
    await expectLater(
      load({
        "api.github.com": _Source.down(Exception("github unreachable")),
        "codeberg.org": _Source.down(Exception("codeberg unreachable")),
      }),
      throwsA(isA<Exception>()),
    );
  });
}
