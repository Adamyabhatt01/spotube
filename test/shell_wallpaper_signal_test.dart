// Why the wallpaper watch is not debounced like the theme watch.
//
// `caelestia wallpaper -f` (the only writer of the state dir) goes
// path.txt -> unlink current -> symlink current -> unlink/create thumbnail, all
// inside ~1ms, and then leaves the directory alone. A trailing debounce turns
// that into "the backdrop lands 300ms after the desktop did", on every change,
// forever. Resolving the link per raw event and dropping repeats gets the same
// single emission without the window.
//
// These pin the emission count and the latency against a real temp directory
// and a real inotify watch, because both halves are the point: one event for a
// burst, and that event early.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/modules/theme_background/caelestia_shell_source.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';

/// Mirrors the order `caelestia.utils.wallpaper.set_wallpaper` writes in.
Future<void> _applyCaelestiaBurst(Directory state, String to) async {
  final wallpaper = Directory('${state.path}/wallpaper')..createSync();
  File('${wallpaper.path}/path.txt').writeAsStringSync(to);
  final current = Link('${wallpaper.path}/current');
  if (current.existsSync()) current.deleteSync();
  current.createSync(to);
  final thumb = Link('${wallpaper.path}/thumbnail.jpg');
  if (thumb.existsSync()) thumb.deleteSync();
  thumb.createSync('$to.thumb');
}

/// Lets the watcher finish attaching to a directory that already exists, so the
/// first measured event is a change rather than the setup.
Future<void> settle() => Future<void>.delayed(
      const Duration(milliseconds: 100),
    );

void main() {
  late Directory state;
  late List<String> wallpapers;
  late ThemeShellSource source;

  setUp(() {
    state = Directory.systemTemp.createTempSync('wallpaper-signal');
    Directory('${state.path}/wallpaper').createSync();
    wallpapers = [
      'alpha.jpg',
      'beta.jpg',
      'gamma.jpg',
    ].map((name) {
      final file = File('${state.path}/$name')..writeAsStringSync(name);
      return file.path;
    }).toList();
    Link('${state.path}/wallpaper/current').createSync(wallpapers.first);
    source = CaelestiaShellSource(stateDir: state.path);
  });

  tearDown(() => state.deleteSync(recursive: true));

  test('a full apply burst emits once', () async {
    var emissions = 0;
    final subscription = source.watchBackground().listen((_) => emissions++);
    addTearDown(subscription.cancel);
    await settle();

    await _applyCaelestiaBurst(state, wallpapers[1]);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(emissions, 1, reason: 'four raw events, one real change');
    expect(source.getBackgroundPath(), wallpapers[1]);
  });

  test('it emits inside the old debounce window, not after it', () async {
    final arrived = Completer<Duration>();
    final elapsed = Stopwatch();
    final subscription = source.watchBackground().listen((_) {
      if (!arrived.isCompleted) arrived.complete(elapsed.elapsed);
    });
    addTearDown(subscription.cancel);
    await settle();

    // From the first write of the burst, which is deliberately earlier than the
    // link swap the signal is about, so this only overstates the latency.
    elapsed.start();
    await _applyCaelestiaBurst(state, wallpapers[2]);

    final latency = await arrived.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('the signal never fired'),
    );
    expect(
      latency,
      lessThan(const Duration(milliseconds: 300)),
      reason: 'the backdrop must not trail the desktop by the debounce',
    );
  });

  test('events that leave the link alone are silent', () async {
    var emissions = 0;
    final subscription = source.watchBackground().listen((_) => emissions++);
    addTearDown(subscription.cancel);
    await settle();

    // The thumbnail half of the burst, and a rewrite of the same path.
    final wallpaper = Directory('${state.path}/wallpaper');
    File('${wallpaper.path}/path.txt').writeAsStringSync(wallpapers.first);
    Link('${wallpaper.path}/thumbnail.jpg')
        .createSync('${wallpapers.first}.thumb');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(emissions, 0,
        reason: 'equality, not timing, is what collapses them');
  });

  test('the unlink gap does not blank the backdrop, a real removal does',
      () async {
    final emissions = <void>[];
    final subscription = source.watchBackground().listen(
          (_) => emissions.add(null),
        );
    addTearDown(subscription.cancel);
    await settle();

    // Caelestia unlinks `current` before recreating it: a hole, not a removal.
    final current = Link('${state.path}/wallpaper/current');
    current.deleteSync();
    current.createSync(wallpapers[1]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(emissions.length, 1, reason: 'the swap, and nothing for the gap');

    // Same link gone for good.
    current.deleteSync();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      emissions.length,
      2,
      reason: 'a null that outlives the grace is reported',
    );
  });
}
