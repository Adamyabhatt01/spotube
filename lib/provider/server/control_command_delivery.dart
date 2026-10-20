import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/server/control_server_provider.dart';
import 'package:spotube/services/control/control_protocol.dart';
import 'package:spotube/services/control/control_server.dart';
import 'package:spotube/services/logger/logger.dart';

/// The control command this process was started to deliver, if any.
///
/// Set when the CLI was asked to drive an instance and no instance was
/// reachable: this process becomes the instance, and the command is
/// answered once the providers it needs are up.
final pendingControlRequestProvider = Provider<ControlRequest?>((ref) {
  return null;
});

/// Delivers a pending control command once the app is up.
///
/// The command is answered by the same handler the control channel uses,
/// so `spotube --play "x"` behaves the same whether it reaches a running
/// instance or starts one.
Future<void> deliverPendingControlRequest(
  WidgetRef ref,
  ControlRequest request,
) async {
  // The providers the commands touch are all available once the first
  // frame has been built; a command that needs the metadata plugin waits
  // for it on its own (the search provider is a FutureProvider).
  await Future<void>.delayed(const Duration(milliseconds: 500));

  try {
    final server = await ref.read(controlServerProvider.future);
    final response = await ControlClient.send(request);
    if (response != null) {
      // The instance answered its own request over the channel. Nothing
      // more to do: the result is already in the app's log.
      AppLogger.log.t(() => 'Control: delivered ${request.command}');
      return;
    }
    // The channel was not reachable (it may not have bound); answer
    // directly so the command still takes effect.
    final data = await server.handler(request);
    AppLogger.log.t(() => 'Control: delivered ${request.command}: $data');
  } catch (e, stack) {
    AppLogger.reportError(
        e, stack, 'Control: could not deliver ${request.command}');
  }
}
