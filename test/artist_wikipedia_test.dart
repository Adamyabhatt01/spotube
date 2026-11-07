// The artist bio is fetched at most twice per name (exact title, then the
// "(singer)" fallback) and the provider entry is keyed by artist id, so
// revisits and re-fetched artist objects cost zero HTTP.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/metadata_plugin/artist/wikipedia.dart';
import 'package:wikipedia_api/wikipedia_api.dart';

Summary _summary(String? type) => Summary(
      type: type,
      titles: TitlesSet(canonical: 'X', normalized: 'X', display: 'X'),
      extract: '',
      lang: 'en',
      dir: 'ltr',
    );

void main() {
  test('a standard page answers in one request', () async {
    final queries = <String>[];
    final res = await fetchArtistWikipediaSummary(
      'Arijit Singh',
      pageSummary: (query) async {
        queries.add(query);
        return _summary('standard');
      },
    );

    expect(res?.type, 'standard');
    expect(queries, ['Arijit_Singh']);
  });

  test('a non-standard page falls back to the singer title', () async {
    final queries = <String>[];
    final res = await fetchArtistWikipediaSummary(
      'Sim',
      pageSummary: (query) async {
        queries.add(query);
        return _summary(query.endsWith('_(singer)') ? 'standard' : 'disambiguation');
      },
    );

    expect(res?.type, 'standard');
    expect(queries, ['Sim', 'Sim_(singer)']);
  });

  test('a missing page still tries the singer title once', () async {
    final queries = <String>[];
    final res = await fetchArtistWikipediaSummary(
      'Nobody Here',
      pageSummary: (query) async {
        queries.add(query);
        return null;
      },
    );

    expect(res, isNull);
    expect(queries, ['Nobody_Here', 'Nobody_Here_(singer)']);
  });
}
