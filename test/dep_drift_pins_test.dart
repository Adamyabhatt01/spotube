// scripts/dep_drift.dart scans pubspec.yaml by indentation because making
// `yaml` a direct dependency just to read one file is a worse trade. This is
// the part of it that can be checked without spending GitHub API calls.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../scripts/dep_drift.dart';

void main() {
  final pins = readPins(File('pubspec.yaml').readAsStringSync());

  test('finds every git pin in both dependency sections', () {
    expect(pins, isNotEmpty);

    final byPackage = {for (final pin in pins) pin.package: pin};
    // Pinned in `dependencies:`...
    expect(byPackage['media_kit']?.isSha, isTrue);
    expect(byPackage['disable_battery_optimization']?.isSha, isTrue);
    // ...and in `dependency_overrides:`.
    expect(byPackage['bonsoir_android']?.ref, 'bonsoir-v6.1.0');
    expect(byPackage['hetu_std']?.isSha, isTrue);
    // Vendored on 2026-11-04 because the upstream embedder destroyed the login
    // view: `desktop_webview_window` is a path dependency now, so its absence
    // from the pin list is the decision, not drift.
    expect(byPackage['desktop_webview_window'], isNull);

    for (final pin in pins) {
      expect(pin.slug, isNotEmpty, reason: '${pin.package} url is not GitHub');
      expect(pin.shortRef, isNotEmpty);
    }
  });

  test('groups the packages that share one pin instead of listing them twice',
      () {
    final mediaKit =
        pins.where((pin) => pin.slug.endsWith('media-kit/media-kit'));
    final distinctRefs = mediaKit.map((pin) => pin.ref).toSet();

    expect(distinctRefs, hasLength(1));
    expect(
      mediaKit.expand((pin) => pin.packages).toSet(),
      containsAll(
          ['media_kit', 'media_kit_libs_audio', 'media_kit_libs_linux']),
    );
    expect(
      pins.where((pin) => pin.packages.contains('media_kit')).length,
      1,
      reason: 'one report row per pin, not per package',
    );
  });

  test('ignores hosted dependencies', () {
    expect(pins.map((pin) => pin.package), isNot(contains('dio')));
    expect(pins.map((pin) => pin.package), isNot(contains('bonsoir')));
  });
}
