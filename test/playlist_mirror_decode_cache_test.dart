// Proves the P1.7 decode cache on mirroredPlaylistTracksProvider: a mirrored
// playlist re-emits its whole row set whenever any of its tracks changes, and
// every unchanged row's SpotubeFullTrackObject must come back as the exact
// same instance rather than a freshly decoded one.
//
// Instance identity is the assertion because it is the whole point: without
// the cache every emission decodes every row, so a 500-track playlist
// completing downloads one at a time pays 250,000 decodes. With the cache it
// pays 500.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST000000$id',
    explicit: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late AppDatabase db;
  late ProviderContainer container;
  late ProviderSubscription<AsyncValue<List<SpotubeFullTrackObject>>> sub;
  late List<List<SpotubeFullTrackObject>> emissions;

  Future<void> seedPlaylist({
    required String playlistId,
    required List<String> trackIds,
  }) async {
    for (final id in trackIds) {
      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: id,
          filePath: '/nowhere/$id.weba',
          baseName: id,
          status: DownloadPersistedStatus.completed,
          trackData: jsonEncode(_track(id).toJson()),
        ),
      );
    }
    await writePlaylistMembership(
      db,
      playlistId: playlistId,
      trackIds: trackIds,
    );
  }

  Future<void> waitForLength(int length) async {
    for (var i = 0;
        i < 500 && (emissions.isEmpty || emissions.last.length != length);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (emissions.isEmpty || emissions.last.length != length) {
      fail(
          'expected an emission with $length tracks; got ${emissions.map((e) => e.length).toList()}');
    }
  }

  /// Return once one more AsyncData has arrived than [previousCount].
  ///
  /// Some of these writes produce two emissions (drift may notify once per
  /// statement) so callers use `>=`, not `==`.
  Future<void> waitForMoreEmissionsThan(int previousCount) async {
    for (var i = 0; i < 500 && emissions.length <= previousCount; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (emissions.length <= previousCount) {
      fail(
          'no new emission arrived (had $previousCount, now ${emissions.length})');
    }
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
      ],
    );
    emissions = [];
    sub = container.listen(
      mirroredPlaylistTracksProvider('pl'),
      (previous, next) {
        if (next case AsyncData(:final value)) emissions.add(value);
      },
    );
  });

  tearDown(() async {
    sub.close();
    container.dispose();
    await db.close();
  });

  test('an unchanged row keeps its decoded object across re-emissions',
      () async {
    await seedPlaylist(playlistId: 'pl', trackIds: ['a', 'b', 'c']);
    await waitForLength(3);

    final byIdFirst = {for (final t in emissions.last) t.id: t};
    final emissionsBefore = emissions.length;

    // Completing 'b' touches only b's row; a and c must ride the cache.
    await writeDownloadStatus(
      db,
      DownloadRecord(
        trackId: 'b',
        filePath: '/nowhere/b.weba',
        baseName: 'b',
        status: DownloadPersistedStatus.completed,
        sizeBytes: 4321,
        trackData: jsonEncode(_track('b').toJson()),
      ),
    );
    await waitForMoreEmissionsThan(emissionsBefore);
    expect(emissions.last.length, 3,
        reason: 'the update must not have dropped a or c from the list');

    final byIdSecond = {for (final t in emissions.last) t.id: t};
    expect(identical(byIdSecond['a'], byIdFirst['a']), isTrue,
        reason: 'a is unchanged, so re-decoding it is exactly what the cache '
            'exists to avoid');
    expect(identical(byIdSecond['c'], byIdFirst['c']), isTrue);
    expect(identical(byIdSecond['b'], byIdFirst['b']), isFalse,
        reason: 'b updated updatedAtMs, so its cached decode is stale and '
            'the fresh one must replace it');
  });

  test('a mirror row rewrite (no download change) does not re-decode',
      () async {
    await seedPlaylist(playlistId: 'pl', trackIds: ['a', 'b']);
    await waitForLength(2);
    final byId = {for (final t in emissions.last) t.id: t};
    final emissionsBefore = emissions.length;

    // Reorder membership; nothing on the download side changes.
    await writePlaylistMembership(
      db,
      playlistId: 'pl',
      trackIds: const ['b', 'a'],
    );
    await waitForMoreEmissionsThan(emissionsBefore);

    final afterReorder = emissions.last;
    final afterById = {for (final t in afterReorder) t.id: t};
    expect(identical(afterById['a'], byId['a']), isTrue);
    expect(identical(afterById['b'], byId['b']), isTrue);
    expect(afterReorder.map((t) => t.id).toList(), ['b', 'a'],
        reason: 'the list follows the new membership order, cache or not');
  });
}
