// Regression test for local artwork degradation and cover collisions.
//
// The art path used to be `basename + imgMimeToExt[mime]!`:
//  - an embedded picture in an unlisted MIME type threw on the null-assert,
//    and the track disappeared from the library entirely;
//  - two files sharing a basename in different folders mapped to the SAME
//    art file, and the exists-check kept the first cover written.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';

void main() {
  const tempDir = '/tmp/spotube-test-temp';

  group('localArtFilePath', () {
    test('unknown picture mime degrades to an extension instead of throwing',
        () {
      final path =
          localArtFilePath(tempDir, '/music/artist/song.flac', 'image/bmp');

      expect(path, endsWith('.jpg'));
      expect(path, startsWith('$tempDir/spotube/'));
    });

    test('null picture mime also degrades instead of throwing', () {
      expect(
        localArtFilePath(tempDir, '/music/artist/song.mp3', null),
        endsWith('.jpg'),
      );
    });

    test('known picture mimes keep their own extension', () {
      for (final entry in imgMimeToExt.entries) {
        final path = localArtFilePath(tempDir, '/music/a/song.m4a', entry.key);
        expect(path, endsWith(entry.value));
      }
    });

    test('same basename in different folders gets different art files', () {
      final a =
          localArtFilePath(tempDir, '/music/album-one/track.mp3', 'image/jpeg');
      final b =
          localArtFilePath(tempDir, '/music/album-two/track.mp3', 'image/jpeg');

      expect(a, isNot(equals(b)));
    });

    test('the same file always maps to the same art path', () {
      final first =
          localArtFilePath(tempDir, '/music/album/track.mp3', 'image/png');
      final second =
          localArtFilePath(tempDir, '/music/album/track.mp3', 'image/png');

      expect(first, equals(second));
    });
  });

  group('pruneOrphanedArt', () {
    late String tempRoot;
    late String artDir;

    String art(String name) => join(tempRoot, 'spotube', name);

    File write(String path, [String content = 'x']) {
      final file = File(path);
      file.createSync(recursive: true);
      file.writeAsStringSync(content);
      return file;
    }

    setUp(() async {
      tempRoot =
          (await Directory.systemTemp.createTemp('spotube-art-prune')).path;
      artDir = join(tempRoot, 'spotube');
      addTearDown(() {
        if (Directory(tempRoot).existsSync()) {
          Directory(tempRoot).deleteSync(recursive: true);
        }
      });
    });

    test('keeps referenced covers and deletes the rest', () async {
      final kept = write(art('stay-1.jpg'));
      final orphan = write(art('gone-2.jpg'));
      final renamed = write(art('oldname-3.png'));

      await pruneOrphanedArt(tempRoot, {kept.path});

      expect(kept.existsSync(), isTrue);
      expect(kept.readAsStringSync(), 'x');
      expect(orphan.existsSync(), isFalse);
      expect(renamed.existsSync(), isFalse);
    });

    test('nothing is removed when the whole library is still referenced',
        () async {
      final files = [
        for (final name in ['a-1.jpg', 'b-2.jpg', 'c-3.png']) write(art(name)),
      ];

      await pruneOrphanedArt(tempRoot, files.map((f) => f.path).toSet());

      expect(files.where((f) => f.existsSync()).length, 3);
    });

    test('an empty keep-set only clears the covers, not the library', () async {
      // The case behind the whole feature: every source file was deleted, so
      // the next completed scan references no art at all.
      final libraryFile = File(join(tempRoot, 'music', 'song.mp3'))
        ..createSync(recursive: true);
      final cover = write(art('song-1.jpg'));

      await pruneOrphanedArt(tempRoot, {});

      expect(cover.existsSync(), isFalse);
      expect(libraryFile.existsSync(), isTrue);
    });

    test('a missing art directory is a no-op', () async {
      expect(Directory(artDir).existsSync(), isFalse);

      await pruneOrphanedArt(tempRoot, {});

      expect(Directory(artDir).existsSync(), isFalse);
    });

    test('only the spotube subdirectory of the temp dir is swept', () async {
      // The temp dir is shared: unrelated files in it must survive a sweep,
      // including a directory that merely looks like our naming scheme.
      final outside = write(join(tempRoot, 'other', 'song-1.jpg'));
      final inRoot = write(join(tempRoot, 'song-1.jpg'));
      final nested = write(join(artDir, 'deep', 'song-1.jpg'));
      final cover = write(art('song-2.jpg'));

      await pruneOrphanedArt(tempRoot, {});

      expect(outside.existsSync(), isTrue);
      expect(inRoot.existsSync(), isTrue);
      expect(nested.existsSync(), isTrue);
      expect(cover.existsSync(), isFalse);
    });

    test('the path the scan actually stores is the path that survives',
        () async {
      // Guards the join() the two share: localArtFilePath builds
      // <temp>/spotube/<name>, the sweep lists that directory and compares
      // full paths. A mismatch would delete every cover on every scan.
      final path = localArtFilePath(
        tempRoot,
        '/music/album/track.m4a',
        'image/jpeg',
      );
      final cover = write(path, 'cover-bytes');

      await pruneOrphanedArt(tempRoot, {path});

      expect(cover.existsSync(), isTrue);
      expect(cover.readAsStringSync(), 'cover-bytes');
    });
  });
}
