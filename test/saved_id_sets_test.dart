import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/services/logger/logger.dart';

SpotubePaginationResponseObject<T> _page<T>(
  List<T> items, {
  required bool hasMore,
  int? nextOffset,
  int limit = 50,
}) {
  return SpotubePaginationResponseObject<T>(
    limit: limit,
    nextOffset: nextOffset,
    total: items.length,
    hasMore: hasMore,
    items: items,
  );
}

SpotubeFullArtistObject _artist(String id) => SpotubeFullArtistObject(
      id: id,
      name: 'Artist $id',
      externalUri: 'https://example.test/artist/$id',
    );

SpotubeSimpleAlbumObject _album(String id) => SpotubeSimpleAlbumObject(
      id: id,
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    );

class _FakeSavedArtists extends MetadataPluginSavedArtistNotifier {
  _FakeSavedArtists(this.pages);
  final List<SpotubePaginationResponseObject<SpotubeFullArtistObject>> pages;
  final seenOffsetsLimits = <List<int>>[];
  int _next = 1;

  @override
  String? get snapshotKey => null; // keep the fake off the database

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> build() =>
      Future.value(pages.first);

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    seenOffsetsLimits.add([offset, limit]);
    return pages[_next++ % pages.length];
  }
}

class _FakeSavedAlbums extends MetadataPluginSavedAlbumNotifier {
  _FakeSavedAlbums(this.pages);
  final List<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> pages;
  final seenOffsetsLimits = <List<int>>[];
  int _next = 1;

  @override
  String? get snapshotKey => null; // keep the fake off the database

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> build() =>
      Future.value(pages.first);

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
    int offset,
    int limit,
  ) async {
    seenOffsetsLimits.add([offset, limit]);
    return pages[_next++ % pages.length];
  }
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  test('saved-artist lookups share ONE pagination pass', () async {
    final fake = _FakeSavedArtists([
      _page(
        [_artist('a0'), _artist('a1')],
        hasMore: true,
        nextOffset: 50,
      ),
      _page([_artist('a2'), _artist('a9')], hasMore: false),
    ]);
    final container = ProviderContainer(
      overrides: [metadataPluginSavedArtistsProvider.overrideWith(() => fake)],
    );
    addTearDown(container.dispose);

    final results = await Future.wait([
      for (final id in ['a0', 'a2', 'a9', 'nope', 'a0'])
        container.read(metadataPluginIsSavedArtistProvider(id).future),
    ]);

    expect(results, [true, true, true, false, true]);
    // Exactly one extra page fetched — the fan-out used to run one full
    // fetchAll() per family instance.
    expect(fake.seenOffsetsLimits, hasLength(1));
    expect(fake.seenOffsetsLimits.first.first, 50);
  });

  test('single-page saved list needs no fetchAll at all', () async {
    final fake = _FakeSavedArtists([
      _page([_artist('a0')], hasMore: false),
    ]);
    final container = ProviderContainer(
      overrides: [metadataPluginSavedArtistsProvider.overrideWith(() => fake)],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(metadataPluginIsSavedArtistProvider('a0').future),
      isTrue,
    );
    expect(fake.seenOffsetsLimits, isEmpty);
  });

  test('saved-album lookups share ONE pagination pass', () async {
    final fake = _FakeSavedAlbums([
      _page(
        [_album('b0'), _album('b1')],
        hasMore: true,
        nextOffset: 50,
      ),
      _page([_album('b7')], hasMore: false),
    ]);
    final container = ProviderContainer(
      overrides: [metadataPluginSavedAlbumsProvider.overrideWith(() => fake)],
    );
    addTearDown(container.dispose);

    final results = await Future.wait([
      for (final id in ['b0', 'b7', 'nope'])
        container.read(metadataPluginIsSavedAlbumProvider(id).future),
    ]);

    expect(results, [true, true, false]);
    expect(fake.seenOffsetsLimits, hasLength(1));
  });
}
