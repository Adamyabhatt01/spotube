import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf_io.dart';
import 'package:spotube/provider/server/pipeline.dart';
import 'package:spotube/provider/server/router.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

/// The currently bound server across provider rebuilds. Lets a rebuild
/// close the previous socket before rebinding (no "address already in
/// use"), and lets dispose skip an already-closed server. Only ever
/// touched from [serverProvider]'s build/dispose.
HttpServer? _servingServer;

/// Rebind chain: overlapping rebuilds (e.g. a connect toggle plus a port
/// change in one burst) must not interleave their close/serve/assign
/// sections — otherwise the slower build assigns `_servingServer` after the
/// faster one (untracked socket) or loses the port to "address already in
/// use" and the provider stays a permanent AsyncError.
Future<void> _rebindChain = Future.value();

final serverProvider = FutureProvider(
  (ref) async {
    final enabledRemoteConnect = ref.watch(
      userPreferencesProvider.select((value) => value.enableConnect),
    );
    final connectPort = ref.watch(
      userPreferencesProvider.select((value) => value.connectPort),
    );
    final pipeline = ref.watch(pipelineProvider);
    final router = ref.watch(serverRouterProvider);

    final gate = Completer<void>();
    final previousRebind = _rebindChain;
    _rebindChain = gate.future;
    // Enter the serialized close-and-rebind critical section only after the
    // previous rebuild (if any) has fully finished binding.
    await previousRebind;
    try {
      // Close-before-rebind: a rebuild (e.g. toggling connect off/on on the
      // same port) must free the previous socket BEFORE binding, or serve()
      // fails with "address already in use". The onDispose close below is
      // async and would otherwise lose that race.
      final previous = _servingServer;
      _servingServer = null;
      if (previous != null) {
        try {
          await previous.close(force: true);
        } catch (_) {
          // Already closed (e.g. by dispose racing us here).
        }
      }

      final address = enabledRemoteConnect
          ? InternetAddress.anyIPv4
          : InternetAddress.loopbackIPv4;
      final handler = pipeline.addHandler(router.call);

      HttpServer server;
      if (connectPort != -1) {
        SpotubeMedia.serverPort = connectPort;
        server = await serve(handler, address, connectPort);
      } else {
        // connectPort == -1 means "random port". Riverpod runs onDispose
        // before every rebuild, so a rebuild cannot be told apart from a
        // true re-bind here — and moving the port on a rebuild would pull
        // it out from under URIs the backend is still streaming. So the
        // remembered port is TRIED first (preserving the old continuity),
        // and a port that cannot bind is abandoned for a fresh random one
        // — the gap that made the provider a permanent AsyncError, and
        // what made the random path effectively once-per-process when a
        // stale port outlived its socket.
        final attempts = [
          if (SpotubeMedia.serverPort != 0) SpotubeMedia.serverPort,
          for (var i = 0; i < 4; i++) Random().nextInt(17500) + 5000,
        ];
        HttpServer? bound;
        Object? lastError;
        StackTrace? lastStack;
        for (final port in attempts) {
          try {
            bound = await serve(handler, address, port);
            break;
          } on SocketException catch (e, stack) {
            lastError = e;
            lastStack = stack;
          }
        }
        if (bound == null) {
          Error.throwWithStackTrace(
            lastError!,
            lastStack ?? StackTrace.current,
          );
        }
        server = bound;
        SpotubeMedia.serverPort = server.port;
      }
      _servingServer = server;

      AppLogger.log.t(
        'Playback server at http://${server.address.host}:${server.port}',
      );

      ref.onDispose(() async {
        if (identical(_servingServer, server)) _servingServer = null;
        try {
          await server.close(force: true);
        } catch (_) {
          // Already closed by a rebuild racing dispose.
        }
      });

      return (
        server: server,
        port: server.port,
      );
    } finally {
      gate.complete();
    }
  },
);
