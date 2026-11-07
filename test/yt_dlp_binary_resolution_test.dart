// yt-dlp discovery.
//
// A desktop session gives GUI apps a PATH built for packaged programs, so the
// usual Linux install of yt-dlp (pip --user, uv tool, pipx → ~/.local/bin)
// used to read as "not installed": the nag dialog *and* a null binary
// location, which fails every resolution through the engine. The resolver
// therefore falls back to the well-known install directories.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';

/// A throwaway filesystem holding `yt-dlp` in each of [withBinaryIn] and
/// nothing in the rest. Returns the root and a name → absolute path map.
Future<(String, Map<String, String>)> _tree(
  List<String> all,
  List<String> withBinaryIn,
) async {
  final root = await Directory.systemTemp.createTemp('ytdlp-where');
  final dirs = <String, String>{};
  for (final name in all) {
    final path = '${root.path}/$name';
    await Directory(path).create(recursive: true);
    dirs[name] = path;
  }
  for (final name in withBinaryIn) {
    await File('${dirs[name]}/yt-dlp').writeAsString('#!/bin/sh\n');
  }
  return (root.path, dirs);
}

void main() {
  test('finds yt-dlp in a fallback dir that PATH never mentions', () async {
    final (root, dirs) = await _tree(['on-path', 'local-bin'], ['local-bin']);
    addTearDown(() => Directory(root).delete(recursive: true));

    final found = await YtDlpEngine.resolveBinaryPath(
      environment: {'PATH': dirs['on-path']!},
      fallbackDirs: [dirs['local-bin']!],
    );

    expect(found, '${dirs['local-bin']}/yt-dlp');
  });

  test('PATH wins over the fallbacks', () async {
    final (root, dirs) = await _tree(
      ['on-path', 'local-bin'],
      ['on-path', 'local-bin'],
    );
    addTearDown(() => Directory(root).delete(recursive: true));

    final found = await YtDlpEngine.resolveBinaryPath(
      environment: {'PATH': dirs['on-path']!},
      fallbackDirs: [dirs['local-bin']!],
    );

    expect(found, '${dirs['on-path']}/yt-dlp');
  });

  test('reports nothing when no candidate exists', () async {
    final (root, dirs) = await _tree(['on-path', 'local-bin'], []);
    addTearDown(() => Directory(root).delete(recursive: true));

    final found = await YtDlpEngine.resolveBinaryPath(
      // The trailing ':' is an empty entry; it must not become the CWD.
      environment: {'PATH': '${dirs['on-path']!}:'},
      fallbackDirs: [dirs['local-bin']!],
    );

    expect(found, isNull);
  });

  test('HOME drives the fallback list, including ~/.local/bin', () {
    final dirs = YtDlpEngine.commonInstallDirs({'HOME': '/home/tester'});

    expect(dirs, contains('/home/tester/.local/bin'));
    expect(dirs.every((dir) => dir.startsWith('/')), isTrue);
  });

  test('an unset HOME drops the home-relative candidates', () {
    final dirs = YtDlpEngine.commonInstallDirs({});

    expect(dirs, isNot(contains('/.local/bin')));
  });

  group('isBinaryReady', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await KVStoreService.initialize();
    });

    test('a stored custom path that exists wins over an empty env',
        () async {
      final dir = await Directory.systemTemp.createTemp('ytdlp-custom');
      addTearDown(() => dir.delete(recursive: true));
      final binary = File('${dir.path}/yt-dlp');
      await binary.writeAsString('#!/bin/sh\n');
      await KVStoreService.setYoutubeEnginePath(
        YoutubeClientEngine.ytDlp,
        binary.path,
      );

      expect(
        // Empty PATH + no fallbacks: only the stored path can answer.
        await YtDlpEngine.isBinaryReady(
          environment: {'PATH': ''},
          fallbackDirs: const [],
        ),
        isTrue,
      );
    });

    test('a stale stored path does not read as ready', () async {
      await KVStoreService.setYoutubeEnginePath(
        YoutubeClientEngine.ytDlp,
        '/nonexistent/yt-dlp',
      );

      // Empty PATH + no fallbacks: nothing real to find, and the stale
      // stored entry must not count.
      expect(
        await YtDlpEngine.isBinaryReady(
          environment: {'PATH': ''},
          fallbackDirs: const [],
        ),
        isFalse,
      );
    });
  });
}
