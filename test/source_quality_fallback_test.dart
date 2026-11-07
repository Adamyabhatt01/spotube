// Tests for graceful quality/container fallback in SourcedTrack
// (remediation fix 5). The selected container can disappear AFTER
// validation (re-fetched manifest, different engine result set); stream
// selection must degrade to a valid available stream instead of throwing
// StateError from reduce() on an empty iterable or RangeError from an
// out-of-range quality/preset index.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

import 'support/common_fakes.dart';

final _refProbeProvider = Provider<Ref>((ref) => ref);

SpotubeAudioSourceStreamObject _stream(
  String url,
  String container,
  double bitrate,
) {
  return SpotubeAudioSourceStreamObject(
    url: url,
    container: container,
    type: SpotubeMediaCompressionType.lossy,
    bitrate: bitrate,
  );
}

SpotubeAudioSourceContainerPreset _preset(
  String name,
  List<int> bitrates,
) {
  return SpotubeAudioSourceContainerPreset.lossy(
    type: SpotubeMediaCompressionType.lossy,
    name: name,
    qualities: [
      for (final b in bitrates) SpotubeAudioLossyContainerQuality(bitrate: b),
    ],
  );
}

SourcedTrack _track(List<SpotubeAudioSourceStreamObject> sources, Ref ref) {
  return SourcedTrack(
    deps: ref.sourceDeps,
    info: SpotubeAudioSourceMatchObject(
      id: 'match-1',
      title: 'Fallback Test',
      artists: const ['Test Artist'],
      duration: const Duration(minutes: 3),
      externalUri: 'https://example.test/watch/1',
    ),
    query: SpotubeFullTrackObject(
      id: 'fallback-test-track',
      name: 'Fallback Test',
      externalUri: 'https://example.test/track/1',
      artists: [
        SpotubeSimpleArtistObject(
          id: 'a1',
          name: 'Test Artist',
          externalUri: 'https://example.test/artist/1',
        ),
      ],
      album: SpotubeSimpleAlbumObject(
        id: 'alb1',
        name: 'Test Album',
        externalUri: 'https://example.test/album/1',
        artists: const [],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: 180000,
      isrc: 'TEST00000003',
      explicit: false,
    ),
    source: 'youtube',
    siblings: const [],
    sources: sources,
  );
}

void main() {
  late ProviderContainer container;

  ProviderContainer buildContainer(AudioSourcePresetsState presets) {
    return ProviderContainer(
      overrides: [
        audioSourcePresetsProvider.overrideWith(
          () => FixedPresetsNotifier(presets),
        ),
      ],
    );
  }

  tearDown(() => container.dispose());

  group('getStreamOfQuality', () {
    test('selected container gone after validation → best other stream', () {
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [
          _stream('low.webm', 'webm', 96000),
          _stream('high.m4a', 'm4a', 256000)
        ],
        container.read(_refProbeProvider),
      );

      final picked = track.getStreamOfQuality(_preset('opus', [128000]), 0);

      expect(picked?.url, 'high.m4a');
    });

    test('quality index past the end → best stream of the container', () {
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [_stream('a', 'webm', 96000), _stream('b', 'webm', 128000)],
        container.read(_refProbeProvider),
      );

      final picked = track.getStreamOfQuality(
        _preset('webm', [96000, 128000, 320000]),
        2, // no 320k stream exists
      );

      expect(picked?.url, 'b');
    });

    test('exact bitrate match is still preferred', () {
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [_stream('a', 'webm', 96000), _stream('b', 'webm', 128000)],
        container.read(_refProbeProvider),
      );

      final picked = track.getStreamOfQuality(_preset('webm', [96000]), 0);

      expect(picked?.url, 'a');
    });

    test('no sources at all → null, no throw', () {
      container = buildContainer(AudioSourcePresetsState());
      final track = _track([], container.read(_refProbeProvider));

      expect(track.getStreamOfQuality(_preset('webm', [96000]), 0), isNull);
    });
  });

  group('url getter', () {
    test('empty preset list → first validated stream', () {
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [_stream('first', 'webm', 96000), _stream('second', 'm4a', 128000)],
        container.read(_refProbeProvider),
      );

      expect(track.url, 'first');
    });

    test('stale container index → falls back to first preset', () {
      container = buildContainer(
        AudioSourcePresetsState(
          presets: [
            _preset('webm', [96000])
          ],
          selectedStreamingContainerIndex: 7,
        ),
      );
      final track = _track(
        [_stream('only', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.url, 'only');
    });

    test('disappeared container → serves best available stream', () {
      container = buildContainer(
        AudioSourcePresetsState(
          presets: [
            _preset('opus', [128000])
          ],
        ),
      );
      final track = _track(
        [_stream('only.webm', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.url, 'only.webm');
    });
  });

  // Regression for the release-build playback crash:
  //
  //   Null check operator used on a null value
  //   #0  ServerPlaybackRoutes._getTrackCacheFilePath (playback.dart:413)
  //   #1  ServerPlaybackRoutes.streamTrack (playback.dart:596)
  //
  // `qualityPreset` is nullable by design — the audio-source plugin
  // publishes its presets asynchronously, and a persisted index can point
  // past the end of a shrunken list. The playback routes force-unwrapped
  // it, so any of those states crashed the stream request and the player
  // reported "Failed to open http://127.0.0.1:<port>/stream/<id>".
  group('container resolution', () {
    test('names the selected preset and its file extension', () {
      container = buildContainer(
        AudioSourcePresetsState(
          presets: [
            _preset('webm', [96000]),
            _preset('mp4', [128000])
          ],
          selectedStreamingContainerIndex: 1,
        ),
      );
      final track = _track(
        [_stream('a.webm', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.container?.name, 'mp4');
      expect(track.container?.extension, 'm4a');
    });

    test('maps webm to the weba extension', () {
      container = buildContainer(
        AudioSourcePresetsState(presets: [
          _preset('webm', [96000])
        ]),
      );
      final track = _track(
        [_stream('a.webm', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.container?.name, 'webm');
      expect(track.container?.extension, 'weba');
    });

    test('stale container index → falls back to the first preset', () {
      container = buildContainer(
        AudioSourcePresetsState(
          presets: [
            _preset('webm', [96000])
          ],
          selectedStreamingContainerIndex: 7,
        ),
      );
      final track = _track(
        [_stream('only.webm', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.container?.name, 'webm');
      expect(track.container?.extension, 'weba');
    });

    test('no published preset → names the resolved stream container', () {
      // The plugin has not finished loading: the preset list is empty but
      // the manifest already resolved, so the bytes have a container.
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [_stream('a.webm', 'webm', 96000)],
        container.read(_refProbeProvider),
      );

      expect(track.container?.name, 'webm');
      expect(track.container?.extension, 'weba');
    });

    test('no preset and no stream → null, no throw', () {
      // Nothing to serve either, so there is no container to name. This
      // must be null rather than a throw — the old code force-unwrapped it.
      container = buildContainer(AudioSourcePresetsState());
      final track = _track(
        [],
        container.read(_refProbeProvider),
      );

      expect(track.container, isNull);
      expect(track.qualityPreset, isNull);
    });
  });

  group('container file extension mapping', () {
    test('is shared between the preset and the bare container name', () {
      expect(
        SpotubeAudioSourceContainerPreset.fileExtensionForContainer('mp4'),
        'm4a',
      );
      expect(
        SpotubeAudioSourceContainerPreset.fileExtensionForContainer('webm'),
        'weba',
      );
      expect(
        SpotubeAudioSourceContainerPreset.fileExtensionForContainer('opus'),
        'opus',
      );
    });

    test('matches the preset getter for the same name', () {
      final preset = _preset('webm', [96000]);
      expect(
        preset.getFileExtension(),
        SpotubeAudioSourceContainerPreset.fileExtensionForContainer(
            preset.name),
      );
    });
  });

  group('clampPresetIndex', () {
    // A persisted index is chosen against the plugin's list at write time.
    // A later plugin update can present a shorter list, and the index then
    // points past the end — direct indexing throws a RangeError in the
    // playback, download and settings paths.
    test('keeps an index that is in range', () {
      expect(clampPresetIndex(0, 3), 0);
      expect(clampPresetIndex(2, 3), 2);
    });

    test('clamps an index past the end to the last entry', () {
      expect(clampPresetIndex(7, 1), 0);
      expect(clampPresetIndex(5, 3), 2);
    });

    test('clamps a negative index to the first entry', () {
      expect(clampPresetIndex(-1, 3), 0);
      expect(clampPresetIndex(-5, 1), 0);
    });

    test('an empty list clamps to zero', () {
      expect(clampPresetIndex(0, 0), 0);
      expect(clampPresetIndex(7, 0), 0);
      expect(clampPresetIndex(-2, 0), 0);
    });
  });
}
