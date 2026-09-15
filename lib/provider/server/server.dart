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

    // When connect port is -1, we need to generate a random port
    // but we shouldn't reset it if it's already been set (caused by a state change)
    if (connectPort == -1) {
      if (SpotubeMedia.serverPort == 0) {
        final port = Random().nextInt(17500) + 5000;
        SpotubeMedia.serverPort = port;
      }
    } else {
      SpotubeMedia.serverPort = connectPort;
    }

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

    final server = await serve(
      pipeline.addHandler(router.call),
      enabledRemoteConnect
          ? InternetAddress.anyIPv4
          : InternetAddress.loopbackIPv4,
      SpotubeMedia.serverPort,
    );
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
      port: SpotubeMedia.serverPort,
    );
  },
);
