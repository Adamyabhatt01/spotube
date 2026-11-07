// PR 1 / R-19: `SpotubeMedia.serverPort` re-derivation on rebind.
//
// Old behavior: the process-global kept whatever port was ever derived —
// the "random port" path was effectively once-per-process, and a fresh
// bind against a stale-but-occupied port failed permanently (the provider
// stayed an AsyncError). New behavior:
//   - in-place rebuild (a live socket exists) keeps the current port so
//     URIs already handed to the backend stay valid,
//   - a fresh bind re-derives,
//   - a port that cannot bind is abandoned for a fresh random one.
//
// pipeline/router are overridden to bare shelf objects; the server binding
// itself is real (loopback).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/server/pipeline.dart';
import 'package:spotube/provider/server/router.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

void main() {
  AppLogger.initialize(false);

  late StubPrefsNotifier prefs;

  setUp(() {
    SpotubeMedia.serverPort = 0;
    prefs = StubPrefsNotifier(PreferencesTable.defaults());
  });

  ProviderContainer makeContainer({UserPreferencesNotifier? preferences}) {
    final container = ProviderContainer(
      overrides: [
        userPreferencesProvider.overrideWith(() => preferences ?? prefs),
        pipelineProvider.overrideWith((ref) => const Pipeline()),
        serverRouterProvider.overrideWith(
          (ref) => Router()
            ..get(
              '/ping',
              (Request request) => Response.ok('pong'),
            ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a fixed connect port binds exactly that port', () async {
    prefs.stub = prefs.stub.copyWith(connectPort: 21913);
    final container = makeContainer();
    final bound = await container.read(serverProvider.future);
    expect(bound.port, 21913);
    expect(SpotubeMedia.serverPort, 21913);
  });

  test('random mode binds inside the legacy 5000..22500 window', () async {
    final container = makeContainer();
    final bound = await container.read(serverProvider.future);
    expect(bound.port, inInclusiveRange(5000, 22499));
    expect(SpotubeMedia.serverPort, bound.port);
    expect(bound.server.port, bound.port);
  });

  test('an in-place rebuild keeps the port the backend is using', () async {
    final container = makeContainer();
    final first = await container.read(serverProvider.future);

    // enableConnect is watched by the provider: flipping it rebuilds the
    // bind (loopback -> anyIPv4) without a dispose in between.
    prefs.state = prefs.stub.copyWith(enableConnect: true);
    final second = await container.read(serverProvider.future);

    expect(
      second.port,
      first.port,
      reason: 'a live rebuild must not move the port under in-flight URIs',
    );
    expect(SpotubeMedia.serverPort, first.port);
  });

  test('a fresh bind re-derives instead of reusing a stale occupied port',
      () async {
    // Occupy a port and pretend it is the remembered one — exactly the
    // state a process-global leaves behind. The old code kept it, failed
    // to bind, and the provider stayed a permanent AsyncError.
    final squatter = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => squatter.close(force: true));
    SpotubeMedia.serverPort = squatter.port;

    final container = makeContainer();
    final bound = await container.read(serverProvider.future);

    expect(
      bound.port,
      isNot(squatter.port),
      reason: 'the stale port must be abandoned on a fresh bind',
    );
    expect(SpotubeMedia.serverPort, bound.port);
  });

  test('a playback port waiter binds after the persisted preferences load',
      () async {
    final delayed = _DelayedPrefsNotifier(PreferencesTable.defaults());
    final container = makeContainer(preferences: delayed);

    final portFuture = container.read(playbackServerPortProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(
      SpotubeMedia.serverPort,
      0,
      reason: 'nothing may bind while the persisted port is still loading',
    );

    delayed.state = PreferencesTable.defaults().copyWith(connectPort: 21914);
    delayed.load.complete();

    expect(await portFuture, 21914);
    expect(SpotubeMedia.serverPort, 21914);
  });

  test('the bound server answers', () async {
    final container = makeContainer();
    final bound = await container.read(serverProvider.future);
    final client = HttpClient();
    final request = await client.get('127.0.0.1', bound.port, '/ping');
    final res = await request.close();
    await res.drain();
    expect(res.statusCode, 200);
    client.close();
  });
}

/// Preferences that expose a pending [initialLoad], so the test can observe
/// what happens between app start (defaults) and the persisted row arriving.
class _DelayedPrefsNotifier extends UserPreferencesNotifier {
  _DelayedPrefsNotifier(this.initial);

  final PreferencesTableData initial;
  final load = Completer<void>();

  @override
  Future<void>? get initialLoad => load.future;

  @override
  PreferencesTableData build() => initial;
}
