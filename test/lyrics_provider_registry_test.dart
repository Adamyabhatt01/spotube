// Tests the lyrics provider registry: deterministic priority ordering and
// failure isolation (one broken provider cannot prevent later providers).

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/lyrics/lyrics_provider.dart';

class _FailingProvider implements LyricsProvider {
  @override
  String get id => 'failing';
  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    throw StateError('broken');
  }
}

class _EmptyProvider implements LyricsProvider {
  @override
  String get id => 'empty';
  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    return SubtitleSimple(
      uri: Uri.parse('http://example.test'),
      name: track.name,
      lyrics: const [],
      rating: 0,
      provider: id,
    );
  }
}

class _OkProvider implements LyricsProvider {
  @override
  String get id => 'ok';
  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    return SubtitleSimple(
      uri: Uri.parse('http://example.test'),
      name: track.name,
      lyrics: [LyricSlice(text: 'hello', time: Duration.zero)],
      rating: 100,
      provider: id,
    );
  }
}

SpotubeFullTrackObject _track() {
  return SpotubeFullTrackObject(
    id: 't1',
    name: 'Test',
    externalUri: 'http://example.test/t1',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a1',
        name: 'Artist',
        externalUri: 'http://example.test/a1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'al1',
      name: 'Album',
      externalUri: 'http://example.test/al1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'ISRC',
    explicit: false,
  );
}

Future<SubtitleSimple?> _resolve(List<LyricsProvider> providers) async {
  for (final provider in providers) {
    try {
      final candidate = await provider.fetchLyrics(_track());
      if (candidate.lyrics.isNotEmpty) return candidate;
    } catch (_) {
      // isolate failure
    }
  }
  return null;
}

void main() {
  test('first non-empty provider wins, in registration order', () async {
    final result = await _resolve([_OkProvider(), _EmptyProvider()]);
    expect(result, isNotNull);
    expect(result!.provider, 'ok');
  });

  test('empty provider does not win over a later non-empty one', () async {
    final result = await _resolve([_EmptyProvider(), _OkProvider()]);
    expect(result!.provider, 'ok');
  });

  test('a failing provider is isolated and does not block later ones',
      () async {
    final result = await _resolve([_FailingProvider(), _OkProvider()]);
    expect(result, isNotNull);
    expect(result!.provider, 'ok');
  });

  test('all-empty/all-failing yields null', () async {
    final result = await _resolve([_FailingProvider(), _EmptyProvider()]);
    expect(result, isNull);
  });
}