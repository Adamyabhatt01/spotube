import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/services/logger/logger.dart';

/// Simulates what Spotify's `/me/{tracks,albums,artists}/contains` answers:
/// "for these ids, is each one in the saved set?" Records every chunk that
/// was fetched, so tests can count calls and inspect their size.
class _RecordingContains {
  _RecordingContains(this.saved);
  final Set<String> saved;
  final calls = <List<String>>[];

  Future<List<bool>> call(List<String> ids) async {
    calls.add(List.of(ids));
    return ids.map(saved.contains).toList();
  }
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('is-saved family providers route through contains, not fetchAll', () {
    test('saved-artist lookups coalesce into one chunked plugin call',
        () async {
      final recorder = _RecordingContains({'a0', 'a2', 'a9'});
      final container = ProviderContainer(
        overrides: [
          savedArtistBatcherProvider
              .overrideWithValue(IsSavedBatcher(recorder.call)),
        ],
      );
      addTearDown(container.dispose);

      final results = await Future.wait([
        for (final id in ['a0', 'a2', 'a9', 'nope', 'a0'])
          container.read(metadataPluginIsSavedArtistProvider(id).future),
      ]);

      expect(results, [true, true, true, false, true]);
      // One plugin call for the whole batch — previously this pattern walked
      // the saved-artists list once per family instance.
      expect(recorder.calls, hasLength(1));
      // Dedup: the two `a0` requests collapsed into a single id in the chunk.
      expect(recorder.calls.single.toSet(), {'a0', 'a2', 'a9', 'nope'});
    });

    test('saved-album lookups coalesce into one chunked plugin call', () async {
      final recorder = _RecordingContains({'b0', 'b7'});
      final container = ProviderContainer(
        overrides: [
          savedAlbumBatcherProvider
              .overrideWithValue(IsSavedBatcher(recorder.call)),
        ],
      );
      addTearDown(container.dispose);

      final results = await Future.wait([
        for (final id in ['b0', 'b7', 'nope'])
          container.read(metadataPluginIsSavedAlbumProvider(id).future),
      ]);

      expect(results, [true, true, false]);
      expect(recorder.calls, hasLength(1));
    });

    test('saved-track lookups coalesce into one chunked plugin call', () async {
      final recorder = _RecordingContains({'t1', 't2'});
      final container = ProviderContainer(
        overrides: [
          savedTrackBatcherProvider
              .overrideWithValue(IsSavedBatcher(recorder.call)),
        ],
      );
      addTearDown(container.dispose);

      final results = await Future.wait([
        for (final id in ['t1', 't2', 'nope'])
          container.read(metadataPluginIsSavedTrackProvider(id).future),
      ]);

      expect(results, [true, true, false]);
      expect(recorder.calls, hasLength(1));
    });

    test('a 51-id burst fans out into exactly 50 + 1 plugin calls', () async {
      final saved = {'x0', 'x50'};
      final recorder = _RecordingContains(saved);
      final container = ProviderContainer(
        overrides: [
          savedTrackBatcherProvider
              .overrideWithValue(IsSavedBatcher(recorder.call)),
        ],
      );
      addTearDown(container.dispose);

      final ids = List.generate(51, (i) => 'x$i');
      final results = await Future.wait(
        ids.map((id) => container.read(
              metadataPluginIsSavedTrackProvider(id).future,
            )),
      );

      expect(recorder.calls.map((c) => c.length).toList(), [50, 1]);
      // Batch-equivalence: what contains answered == what the walk would say.
      for (var i = 0; i < ids.length; i++) {
        expect(results[i], saved.contains(ids[i]), reason: 'id ${ids[i]}');
      }
    });
  });

  group('isSavedPlaylist', () {
    test('resolves per id, no false-negative after a positive answer',
        () async {
      final saved = {'pl-a', 'pl-c'};
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          savedPlaylistLookupProvider.overrideWithValue((id) async {
            calls.add(id);
            return saved.contains(id);
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(metadataPluginIsSavedPlaylistProvider('pl-a').future),
        isTrue,
      );
      expect(
        await container.read(metadataPluginIsSavedPlaylistProvider('pl-b').future),
        isFalse,
      );
      expect(
        await container.read(metadataPluginIsSavedPlaylistProvider('pl-c').future),
        isTrue,
      );

      expect(calls, ['pl-a', 'pl-b', 'pl-c']);
    });
  });
}
