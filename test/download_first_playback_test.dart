// Focused tests for download-first playback: when a Spotify (non-downloaded
// playlist) track is requested, the server should serve the user's local
// downloaded copy (matched by sanitized base name) before resolving an online
// YouTube source. These tests exercise the pure matching helper and the file
// response builders directly — no Riverpod / DB / network stack required.
//
// Covered:
//  - a matching downloaded file is found regardless of codec/extension.
//  - an absent download falls back to null (the caller then goes online).
//  - empty / nonexistent download locations return null.
//  - multi-artist and sanitization-parity filenames still match.
//  - nested files (subfolders) are not matched (downloads are flat).
//  - GET and HEAD response builders describe the local file correctly.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/server/routes/playback.dart';
import 'package:spotube/utils/service_utils.dart';

SpotubeFullTrackObject _testTrack({
  String name = 'Test Track',
  List<String> artists = const ['Test Artist'],
}) {
  return SpotubeFullTrackObject(
    id: 'test-track-1',
    name: name,
    externalUri: 'https://example.test/track/1',
    artists: [
      for (final artist in artists)
        SpotubeSimpleArtistObject(
          id: artist,
          name: artist,
          externalUri: 'https://example.test/artist/1',
        ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

String _sanitizedBase(SpotubeFullTrackObject track) =>
    ServiceUtils.sanitizeFilename(
      '${track.name} - ${track.artists.map((e) => e.name).join(', ')}',
    );

Future<Directory> _withDownloadLocation(
  Directory root,
  List<String> fileNames,
) async {
  for (final name in fileNames) {
    final f = File('${root.path}${Platform.pathSeparator}$name');
    await f.create(recursive: true);
    await f.writeAsString('audio-bytes');
  }
  return root;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('download_first_playback_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  group('findDownloadedFile', () {
    test('returns the matching file regardless of extension', () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.mp3']);
      final found = await findDownloadedFile(temp.path, track);
      expect(found, isNotNull);
      expect(found!.path, '${temp.path}${Platform.pathSeparator}$base.mp3');
    });

    test('matches any downloaded codec', () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      for (final ext in ['m4a', 'weba', 'opus', 'ogg', 'flac']) {
        final dir = await Directory.systemTemp.createTemp('ext_$ext');
        try {
          await _withDownloadLocation(dir, ['$base.$ext']);
          final found = await findDownloadedFile(dir.path, track);
          expect(found, isNotNull,
              reason: 'should match extension $ext');
        } finally {
          await dir.delete(recursive: true);
        }
      }
    });

    test('returns null when no download exists', () async {
      await _withDownloadLocation(temp, ['Some Other Song - Someone.mp3']);
      final found = await findDownloadedFile(temp.path, _testTrack());
      expect(found, isNull);
    });

    test('returns null for empty download location', () async {
      final found = await findDownloadedFile('', _testTrack());
      expect(found, isNull);
    });

    test('returns null for nonexistent directory', () async {
      final missing = '${temp.path}${Platform.pathSeparator}nope';
      final found = await findDownloadedFile(missing, _testTrack());
      expect(found, isNull);
    });

    test('matches multi-artist filenames', () async {
      final track = _testTrack(artists: ['Artist A', 'Artist B']);
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.mp3']);
      final found = await findDownloadedFile(temp.path, track);
      expect(found, isNotNull);
      expect(found!.path, '${temp.path}${Platform.pathSeparator}$base.mp3');
    });

    test('matches filenames needing sanitization', () async {
      // Characters sanitizeFilename strips: / ? < > \ : * | "
      final track = _testTrack(name: 'Song: The ? Sequel*');
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.m4a']);
      final found = await findDownloadedFile(temp.path, track);
      expect(found, isNotNull);
      expect(found!.path, '${temp.path}${Platform.pathSeparator}$base.m4a');
    });

    test('does not match files in subdirectories (downloads are flat)',
        () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      final nested =
          Directory('${temp.path}${Platform.pathSeparator}Artist');
      await _withDownloadLocation(nested, ['$base.mp3']);
      final found = await findDownloadedFile(temp.path, track);
      expect(found, isNull);
    });
  });

  group('DownloadedFileIndex', () {
    test('repeated hits are served from the index, not by re-listing',
        () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.mp3']);

      final index = DownloadedFileIndex();
      expect(await index.find(temp.path, track), isNotNull);
      final listingsAfterFirst = index.listingCount;
      for (var i = 0; i < 10; i++) {
        expect(await index.find(temp.path, track), isNotNull);
      }

      expect(index.listingCount, equals(listingsAfterFirst),
          reason: 'a cached hit must not walk the download directory');
    });

    test('a download that appears later is found', () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      final other = _testTrack(name: 'Warm Up');

      final index = DownloadedFileIndex();
      await _withDownloadLocation(
        temp,
        ['${_sanitizedBase(other)}.mp3'],
      );
      expect(await index.find(temp.path, track), isNull);

      await _withDownloadLocation(temp, ['$base.flac']);
      expect(await index.find(temp.path, track), isNotNull,
          reason: 'finishing a download must not need an app restart');
    });

    test('a deleted download stops being served', () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.mp3']);

      final index = DownloadedFileIndex();
      expect(await index.find(temp.path, track), isNotNull);

      await File('${temp.path}${Platform.pathSeparator}$base.mp3')
          .delete();
      expect(await index.find(temp.path, track), isNull);
    });

    test('repeated hits do not re-list, even as unrelated files appear',
        () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      await _withDownloadLocation(temp, ['$base.mp3']);
      final index = DownloadedFileIndex();
      expect(await index.find(temp.path, track), isNotNull);
      final listingsAfterHit = index.listingCount;

      for (var i = 0; i < 50; i++) {
        await File('${temp.path}${Platform.pathSeparator}extra-$i.mp3')
            .create();
      }
      // The directory moved under us, so one rebuild is expected; the point
      // is that it stays bounded instead of one walk per request.
      expect(await index.find(temp.path, track), isNotNull);
      expect(
        index.listingCount - listingsAfterHit,
        lessThanOrEqualTo(2),
        reason: 'a hit must not scale with the number of requests',
      );
    });

    test('switching the download location rebuilds the index', () async {
      final track = _testTrack();
      final base = _sanitizedBase(track);
      final elsewhere =
          await Directory.systemTemp.createTemp('download_first_elsewhere_');
      try {
        await _withDownloadLocation(temp, ['$base.mp3']);
        final index = DownloadedFileIndex();
        expect(await index.find(temp.path, track), isNotNull);

        expect(await index.find(elsewhere.path, track), isNull,
            reason: 'the previous location must not leak into the new one');
      } finally {
        await elsewhere.delete(recursive: true);
      }
    });
  });

  group('response builders', () {
    test('cachedFileHeadResponse describes the local file', () {
      final res = cachedFileHeadResponse(
        fileLength: 100,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
      );
      expect(res.statusCode, 200);
      expect(res.headers.value('content-length'), '100');
      expect(res.headers.value('accept-ranges'), 'bytes');
      expect(res.headers.value('content-range'), 'bytes 0-99/100');
    });

    test('cachedFileStreamResponse serves a byte stream with range headers',
        () async {
      final f = File('${temp.path}${Platform.pathSeparator}x.mp3');
      await f.writeAsString('audio-bytes');
      final length = await f.length();
      final res = cachedFileStreamResponse(
        file: f,
        fileLength: length,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
      );
      expect(res.statusCode, 200);
      expect(res.data, isA<Stream<List<int>>>());
      // content-length must be the full byte count: the body streams every
      // byte of the file. Declaring length - 1 makes strict HTTP clients
      // abort with "content size exceeds contentLength".
      expect(res.headers.value('content-length'), '$length');
      expect(res.headers.value('content-range'),
          'bytes 0-${length - 1}/$length');
    });

    test('cachedFileStreamResponse HEAD and GET content-length agree',
        () async {
      final f = File('${temp.path}${Platform.pathSeparator}y.mp3');
      await f.writeAsString('0123456789');
      final length = await f.length();
      final head = cachedFileHeadResponse(
        fileLength: length,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
      );
      final get = cachedFileStreamResponse(
        file: f,
        fileLength: length,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
      );
      expect(get.headers.value('content-length'),
          head.headers.value('content-length'));
    });

    test('cachedFileStreamResponse honors a Range request with a 206 body',
        () async {
      final f = File('${temp.path}${Platform.pathSeparator}z.mp3');
      await f.writeAsString('0123456789');
      final res = cachedFileStreamResponse(
        file: f,
        fileLength: 10,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
        rangeHeader: 'bytes=2-5',
      );
      expect(res.statusCode, 206);
      expect(res.headers.value('content-length'), '4');
      expect(res.headers.value('content-range'), 'bytes 2-5/10');
      final bytes = await (res.data as Stream<List<int>>)
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      expect(String.fromCharCodes(bytes), '2345');
    });

    test(
        'cachedFileStreamResponse clamps an overlong end and '
        'accepts open-ended ranges', () async {
      final f = File('${temp.path}${Platform.pathSeparator}w.mp3');
      await f.writeAsString('0123456789');
      final res = cachedFileStreamResponse(
        file: f,
        fileLength: 10,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
        rangeHeader: 'bytes=7-9999',
      );
      expect(res.statusCode, 206);
      expect(res.headers.value('content-length'), '3');
      expect(res.headers.value('content-range'), 'bytes 7-9/10');
      final bytes = await (res.data as Stream<List<int>>)
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      expect(String.fromCharCodes(bytes), '789');

      final openEnded = cachedFileStreamResponse(
        file: f,
        fileLength: 10,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
        rangeHeader: 'bytes=8-',
      );
      expect(openEnded.statusCode, 206);
      expect(openEnded.headers.value('content-length'), '2');
      expect(openEnded.headers.value('content-range'), 'bytes 8-9/10');
    });

    test('cachedFileStreamResponse falls back to full body on a bad range',
        () async {
      final f = File('${temp.path}${Platform.pathSeparator}v.mp3');
      await f.writeAsString('0123456789');

      final pastEnd = cachedFileStreamResponse(
        file: f,
        fileLength: 10,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
        rangeHeader: 'bytes=42-99',
      );
      expect(pastEnd.statusCode, 200);
      expect(pastEnd.headers.value('content-length'), '10');

      final malformed = cachedFileStreamResponse(
        file: f,
        fileLength: 10,
        contentType: 'audio/mpeg',
        requestPath: 'http://localhost/stream/track',
        rangeHeader: 'not-a-range',
      );
      expect(malformed.statusCode, 200);
      expect(malformed.headers.value('content-length'), '10');
    });
  });
}