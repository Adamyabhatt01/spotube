// Focused tests for the download/playback source fallback helpers that are
// pure and do not require the Hetu VM, Drift DB, or a live network.
//
// Covered:
//  - getStreamOfAnyContainer picks the best stream when the preferred
//    container is absent (the "never require quality" download behavior).
//  - getStreamOfAnyContainer prefers the exact container when present.
//  - empty sources yield null.
//  - quality-preference selection still honors the selected quality when a
//    container exists (getUrlOfQuality).

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

SpotubeAudioSourceStreamObject _stream({
  required String container,
  required double bitrate,
  double? sampleRate,
  int? bitDepth,
}) {
  return SpotubeAudioSourceStreamObject(
    url: 'http://example.test/$container/$bitrate',
    container: container,
    type: SpotubeMediaCompressionType.lossy,
    bitrate: bitrate,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
  );
}

SpotubeAudioSourceContainerPreset _lossyPreset(String name, int bitrate) {
  return SpotubeAudioSourceContainerPreset.lossy(
    type: SpotubeMediaCompressionType.lossy,
    name: name,
    qualities: [SpotubeAudioLossyContainerQuality(bitrate: bitrate)],
  );
}

SpotubeFullTrackObject _query() {
  return SpotubeFullTrackObject(
    id: 't1',
    name: 'Test',
    externalUri: 'http://example.test/t1',
    artists: const [],
    album: SpotubeSimpleAlbumObject(
      id: 'a1',
      name: 'Album',
      externalUri: 'http://example.test/a1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'ISRC',
    explicit: false,
  );
}

final _refProbeProvider = Provider<Ref>((ref) => ref);

Ref _testRef() {
  return ProviderContainer().read(_refProbeProvider);
}

void main() {
  group('getStreamOfAnyContainer', () {
    test('returns the highest-bitrate stream across all containers', () {
      final track = SourcedTrack(
        ref: _testRef(),
        info: SpotubeAudioSourceMatchObject(
          id: 'v1',
          title: 'Test',
          artists: const ['Artist'],
          duration: const Duration(seconds: 180),
          externalUri: 'http://example.test/v1',
        ),
        source: 'youtube-audio',
        siblings: const [],
        sources: [
          _stream(container: 'mp4', bitrate: 128),
          _stream(container: 'webm', bitrate: 320),
          _stream(container: 'mp4', bitrate: 256),
        ],
        query: _query(),
      );

      // Preferred container "mp3" does not exist -> best across all = webm/320.
      final preset = _lossyPreset('mp3', 128);
      final best = track.getStreamOfAnyContainer(preset);
      expect(best, isNotNull);
      expect(best!.container, 'webm');
      expect(best.bitrate, 320);
    });

    test('prefers the exact container when present', () {
      final track = SourcedTrack(
        ref: _testRef(),
        info: SpotubeAudioSourceMatchObject(
          id: 'v1',
          title: 'Test',
          artists: const ['Artist'],
          duration: const Duration(seconds: 180),
          externalUri: 'http://example.test/v1',
        ),
        source: 'youtube-audio',
        siblings: const [],
        sources: [
          _stream(container: 'webm', bitrate: 320),
          _stream(container: 'mp3', bitrate: 256),
        ],
        query: _query(),
      );

      final best = track.getStreamOfAnyContainer(_lossyPreset('mp3', 128));
      expect(best, isNotNull);
      expect(best!.container, 'mp3');
    });

    test('returns null for empty sources', () {
      final track = SourcedTrack(
        ref: _testRef(),
        info: SpotubeAudioSourceMatchObject(
          id: 'v1',
          title: 'Test',
          artists: const ['Artist'],
          duration: const Duration(seconds: 180),
          externalUri: 'http://example.test/v1',
        ),
        source: 'youtube-audio',
        siblings: const [],
        sources: const [],
        query: _query(),
      );

      expect(track.getStreamOfAnyContainer(_lossyPreset('mp3', 128)), isNull);
    });
  });

  group('getUrlOfQuality (quality-preference preserved when container exists)',
      () {
    test('returns nearest matching URL within the preferred container', () {
      final track = SourcedTrack(
        ref: _testRef(),
        info: SpotubeAudioSourceMatchObject(
          id: 'v1',
          title: 'Test',
          artists: const ['Artist'],
          duration: const Duration(seconds: 180),
          externalUri: 'http://example.test/v1',
        ),
        source: 'youtube-audio',
        siblings: const [],
        sources: [
          _stream(container: 'mp3', bitrate: 128),
          _stream(container: 'mp3', bitrate: 256),
        ],
        query: _query(),
      );

      final preset = _lossyPreset('mp3', 256);
      final url = track.getUrlOfQuality(preset, 0);
      expect(url, 'http://example.test/mp3/256.0');
    });
  });
}