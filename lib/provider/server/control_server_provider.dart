import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/control/control_commands.dart';
import 'package:spotube/services/control/control_server.dart';
import 'package:spotube/services/logger/logger.dart';

/// The running instance's control endpoint.
///
/// Started once the app is up, so the commands it answers can reach the
/// player and the metadata plugin. The endpoint is local only (a Unix
/// socket, or a loopback TCP port), so it is never reachable from the
/// network — turning Connect on does not expose it.
final controlServerProvider = FutureProvider<ControlServer>((ref) async {
  final server = ControlServer((request) {
    return ControlCommands.handler(ref)(request);
  });

  try {
    await server.start();
  } catch (e, stack) {
    // A control channel that cannot bind is not fatal: the app runs
    // exactly as before, it just cannot be driven from the command line.
    AppLogger.reportError(e, stack, 'Control: could not start');
    rethrow;
  }

  ref.onDispose(() {
    unawaited(server.stop());
  });

  return server;
});
