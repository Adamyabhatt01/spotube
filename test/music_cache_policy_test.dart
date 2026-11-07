import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/music_cache_policy.dart';

/// The music cache had no ceiling at all: 360 MB of streamed tracks in 34
/// files, growing until the disk complained. These pin the eviction policy that
/// replaces that, including the two things it must never do — evict a track the
/// player is about to need, or disturb a mirror mid-write.
void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('spotube_music_cache');
    MusicCacheUsage.resetForTest();
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  Future<File> seed(String name, int bytes, {DateTime? modified}) async {
    final file = File('${cache.path}/$name');
    await file.writeAsBytes(List<int>.filled(bytes, 0x61));
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  final old = DateTime(2026, 1, 1);
  final older = DateTime(2025, 1, 1);

  test('a zero limit leaves the cache alone', () async {
    await seed('a.mp3', 1000, modified: older);

    final report = await enforceCacheQuota(dir: cache, limitBytes: 0);

    expect(report.didWork, isFalse);
    expect(await File('${cache.path}/a.mp3').exists(), isTrue);
  });

  test('under the cap, nothing is removed', () async {
    await seed('a.mp3', 1000, modified: older);
    await seed('b.mp3', 1000, modified: old);

    final report = await enforceCacheQuota(dir: cache, limitBytes: 4000);

    expect(report.didWork, isFalse);
    expect(await cache.list().length, 2);
  });

  test('evicts by age until under the cap, and reports the bytes', () async {
    await seed('oldest.mp3', 900, modified: older);
    await seed('older.mp3', 900, modified: old);
    await seed('newest.mp3', 900);

    final report = await enforceCacheQuota(dir: cache, limitBytes: 1500);

    expect(report.removedFiles, 2);
    expect(report.freedBytes, 1800);
    expect(await File('${cache.path}/newest.mp3').exists(), isTrue);
    expect(await File('${cache.path}/older.mp3').exists(), isFalse);
    expect(await File('${cache.path}/oldest.mp3').exists(), isFalse);
    // Stops as soon as the cap holds rather than emptying the directory.
    expect(await cache.list().length, 1);
  });

  test('a pinned path survives even when it is the oldest', () async {
    await seed('pinned.mp3', 900, modified: older);
    await seed('victim.mp3', 900, modified: old);

    final report = await enforceCacheQuota(
      dir: cache,
      limitBytes: 500,
      pinnedPaths: {'${cache.path}/pinned.mp3'},
    );

    expect(report.removedFiles, 1);
    expect(await File('${cache.path}/pinned.mp3').exists(), isTrue);
    expect(await File('${cache.path}/victim.mp3').exists(), isFalse);
    // Pinned work still counts toward the cap; the pass just cannot reach it.
    expect(await cache.list().length, 1);
  });

  test('a track served this session outranks its own mtime', () async {
    // Written long ago but played a moment ago (the current or next track),
    // versus a file written later that nobody has served.
    await seed('playing.mp3', 900, modified: older);
    await seed('stale.mp3', 900, modified: old);
    MusicCacheUsage.markServed('${cache.path}/playing.mp3');

    final report = await enforceCacheQuota(dir: cache, limitBytes: 900);

    expect(report.removedFiles, 1);
    expect(await File('${cache.path}/playing.mp3').exists(), isTrue);
    expect(await File('${cache.path}/stale.mp3').exists(), isFalse);
  });

  test('eviction never touches a .part, however old', () async {
    await seed('ancient.mp3', 900, modified: older);
    await seed('mid-write.mp3.part', 900, modified: older);

    final report = await enforceCacheQuota(dir: cache, limitBytes: 100);

    expect(report.removedFiles, 1);
    expect(await File('${cache.path}/mid-write.mp3.part').exists(), isTrue);
  });

  test('the .part sweep removes only abandoned mirrors', () async {
    final stale = await seed('abandoned.mp3.part', 5000, modified: older);
    await seed('fresh.mp3.part', 5000, modified: DateTime.now());
    await seed('cached.mp3', 5000);

    final report = await sweepIncompleteMirrors(
      dir: cache,
      olderThan: const Duration(minutes: 10),
    );

    expect(report.removedFiles, 1);
    expect(report.freedBytes, 5000);
    expect(await stale.exists(), isFalse);
    expect(await File('${cache.path}/cached.mp3').exists(), isTrue);
    expect(await File('${cache.path}/fresh.mp3.part').exists(), isTrue);
  });

  test('the .part sweep keeps a part written just inside the window', () async {
    await seed('recent.mp3.part', 5000, modified: DateTime.now());

    final report = await sweepIncompleteMirrors(
      dir: cache,
      olderThan: const Duration(hours: 1),
      now: DateTime.now().add(const Duration(minutes: 30)),
    );

    expect(report.didWork, isFalse);
    expect(await File('${cache.path}/recent.mp3.part').exists(), isTrue);
  });
}
