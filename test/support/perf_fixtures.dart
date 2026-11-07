import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;

import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Deterministic fixtures for the performance measurements in
/// `test/perf_baseline_test.dart` and the scaling guards added by the
/// optimization PRs.
///
/// Everything here is synthetic and seeded: two runs of the same call produce
/// byte-identical payloads, so before/after numbers are comparable.
class PerfFixtures {
  PerfFixtures._();

  /// A track JSON payload shaped like a real Spotify track (~500 bytes):
  /// one artist with artwork, one album with three renditions.
  static SpotubeFullTrackObject track(String id) {
    return SpotubeFullTrackObject(
      id: id,
      name: 'Fixture track $id',
      externalUri: 'https://open.spotify.com/track/$id',
      artists: [
        SpotubeSimpleArtistObject(
          id: 'artist-${id.hashCode.abs() % 997}',
          name: 'Fixture Artist',
          externalUri: 'https://open.spotify.com/artist/a',
          images: [
            SpotubeImageObject(url: 'https://example.test/a300.jpg', height: 300, width: 300),
          ],
        ),
      ],
      album: SpotubeSimpleAlbumObject(
        id: 'album-${id.hashCode.abs() % 991}',
        name: 'Fixture Album',
        externalUri: 'https://open.spotify.com/album/b',
        artists: const [],
        albumType: SpotubeAlbumType.album,
        images: [
          SpotubeImageObject(url: 'https://example.test/64.jpg', height: 64, width: 64),
          SpotubeImageObject(url: 'https://example.test/300.jpg', height: 300, width: 300),
          SpotubeImageObject(url: 'https://example.test/640.jpg', height: 640, width: 640),
        ],
      ),
      durationMs: 180000 + (id.hashCode.abs() % 60000).abs(),
      isrc: 'US${Random(id.hashCode.abs()).nextInt(999999)}000001',
      explicit: false,
    );
  }

  static List<SpotubeFullTrackObject> tracks(int count) =>
      List.generate(count, (i) => track('t${i.toString().padLeft(5, '0')}'));

  /// `count` playback-history rows, one per synthetic listen, alternating
  /// track/album entries the way the real writer does.
  static List<HistoryTableCompanion> history(int count, {DateTime? newest}) {
    final base = newest ?? DateTime.utc(2026, 1, 1);
    return List.generate(count, (i) {
      final isTrack = i % 5 != 0;
      final subject = track('h${(i % max(1, count ~/ 3)).toString().padLeft(6, '0')}');
      return HistoryTableCompanion.insert(
        createdAt: Value(base.subtract(Duration(minutes: i * 3))),
        type: isTrack ? HistoryEntryType.track : HistoryEntryType.album,
        itemId: isTrack ? subject.id : subject.album.id,
        data: isTrack ? subject.toJson() : subject.album.toJson(),
      );
    });
  }

  static Future<void> insertHistory(AppDatabase db, int count) async {
    await db.batch((batch) => batch.insertAll(db.historyTable, history(count)));
  }

  /// A playlist JSON payload shaped like a real Spotify playlist summary.
  static SpotubeSimplePlaylistObject playlist(String id) {
    return SpotubeSimplePlaylistObject(
      id: id,
      name: 'Fixture playlist $id',
      description: 'Synthetic playlist for performance probes',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: SpotubeUserObject(
        id: 'user-${id.hashCode.abs() % 97}',
        name: 'Fixture User',
        externalUri: 'https://open.spotify.com/user/f',
      ),
      images: [
        SpotubeImageObject(url: 'https://example.test/p300.jpg', height: 300, width: 300),
      ],
    );
  }

  /// Like [history] but a sixth of the rows are playlist entries, so the
  /// album/playlist/top-track probes all scan a window proportional to
  /// `count`. Kept separate from [history] so the PR 1 baseline stays
  /// reproducible byte-for-byte.
  static List<HistoryTableCompanion> historyAllKinds(int count, {DateTime? newest}) {
    final base = newest ?? DateTime.utc(2026, 1, 1);
    return List.generate(count, (i) {
      final subject = track('h${(i % max(1, count ~/ 3)).toString().padLeft(6, '0')}');
      final HistoryEntryType type;
      final Map<String, dynamic> data;
      final String itemId;
      if (i % 6 == 0) {
        type = HistoryEntryType.playlist;
        final pl = playlist('p${(i % max(1, count ~/ 6)).toString().padLeft(6, '0')}');
        data = pl.toJson();
        itemId = pl.id;
      } else if (i % 5 == 0) {
        type = HistoryEntryType.album;
        data = subject.album.toJson();
        itemId = subject.album.id;
      } else {
        type = HistoryEntryType.track;
        data = subject.toJson();
        itemId = subject.id;
      }
      return HistoryTableCompanion.insert(
        createdAt: Value(base.subtract(Duration(minutes: i * 3))),
        type: type,
        itemId: itemId,
        data: data,
      );
    });
  }

  static Future<void> insertMixedHistory(AppDatabase db, int count) async {
    await db
        .batch((batch) => batch.insertAll(db.historyTable, historyAllKinds(count)));
  }

  /// A directory tree of `dirCount * perDir` placeholder audio files. Content is
  /// irrelevant (metadata reads are not performed against these); the walk and
  /// stat costs are what they measure.
  static Future<List<String>> fileTree(
    String root, {
    required int dirCount,
    required int perDir,
  }) async {
    final paths = <String>[];
    for (var d = 0; d < dirCount; d++) {
      final dir = await Directory("$root/artist-$d").create(recursive: true);
      for (var f = 0; f < perDir; f++) {
        final file = File('${dir.path}/track-$f.flac');
        await file.writeAsBytes(List.filled(64, 0));
        paths.add(file.path);
      }
    }
    return paths;
  }
}
