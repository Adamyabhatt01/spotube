// CloseGuard is the awaitable gate between the unawaited startup install of
// window_manager.setPreventClose and the close handler. These tests exercise
// the pure state machine with a fake installer; no platform channel is used.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/wm_tools/close_guard.dart';

void main() {
  test('install runs once for concurrent and later callers', () async {
    var calls = 0;
    final guard = CloseGuard(install: () async => calls++);

    await Future.wait([
      guard.ensureInstalled(),
      guard.ensureInstalled(),
      guard.ready,
    ]);
    await guard.ready;

    expect(calls, 1);
  });

  test('ready waits for the install to finish', () async {
    final install = Completer<void>();
    var installed = false;
    final guard = CloseGuard(install: () {
      return install.future.whenComplete(() => installed = true);
    });

    var ready = false;
    final waiting = guard.ready.then((_) => ready = true);

    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect(installed, isFalse);

    install.complete();
    await waiting;

    expect(installed, isTrue);
    expect(ready, isTrue);
  });

  test('a failed install does not throw from ready', () async {
    final guard = CloseGuard(install: () async => throw StateError('no wm'));

    await expectLater(guard.ready, completes);
    // The failure is still visible to the startup step that installs it.
    await expectLater(guard.ensureInstalled(), throwsStateError);
  });
}
