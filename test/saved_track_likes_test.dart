import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/library/saved_track_likes.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';

void main() {
  group('optimistic liked state', () {
    late int queries;
    late ProviderContainer container;

    setUp(() {
      queries = 0;
      container = ProviderContainer(
        overrides: [
          // Spotify's library query still says "not saved": exactly the lag
          // that made the first tap look like a no-op.
          savedTrackBatcherProvider.overrideWithValue(
            IsSavedBatcher((ids) async {
              queries++;
              return [for (final _ in ids) false];
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test('a local like outranks the query and skips the network', () async {
      final provider = metadataPluginIsSavedTrackProvider('t1');

      expect(await container.read(provider.future), isFalse);
      expect(queries, 1);

      container.read(savedTrackLikesProvider.notifier).set('t1', true);

      expect(
        await container.read(provider.future),
        isTrue,
        reason: 'the tap is the freshest fact we have',
      );
      expect(
        queries,
        1,
        reason: 'an overridden track must not query the lagging endpoint',
      );
    });

    test('a local unlike outranks a saved answer too', () async {
      container.read(savedTrackLikesProvider.notifier).set('t1', false);

      expect(
        await container.read(metadataPluginIsSavedTrackProvider('t1').future),
        isFalse,
      );
      expect(queries, 0);
    });

    test('reading an untouched track still asks the batcher', () async {
      expect(
        await container
            .read(metadataPluginIsSavedTrackProvider('other').future),
        isFalse,
      );
      expect(queries, 1);
    });
  });
}
