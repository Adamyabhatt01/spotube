// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/services/control/control_protocol.dart';
import 'package:spotube/services/control/control_server.dart';

/// The environment variable the C runner uses to hand over the saved
/// stdout descriptor (see `configure_control_stdout` in
/// `linux/my_application.cc`).
const controlStdoutFdEnv = 'SPOTUBE_CONTROL_STDOUT_FD';

/// What the CLI was asked to do.
class CliInvocation {
  /// The parsed arguments.
  final ArgResults arguments;

  /// The control command to send to a running instance, when the CLI was
  /// asked to drive one instead of starting the app.
  final ControlRequest? controlRequest;

  /// Whether the process should exit instead of starting the app.
  final bool exitAfter;

  const CliInvocation(this.arguments,
      {this.controlRequest, this.exitAfter = false});
}

/// Parses the command line.
///
/// The parser is permissive on purpose: the Flutter engine and the Linux
/// runner pass their own switches through the same argument list
/// (`--vm-service-port`, `--observatory-port`, ...), and a strict parser
/// turns an engine switch into a fatal `FormatException` before the app
/// ever starts. Unknown switches are therefore collected and ignored
/// rather than rejected.
Future<CliInvocation> startCLI(List<String> args) async {
  final parser = ArgParser();

  parser.addFlag(
    'verbose',
    abbr: 'v',
    help: 'Verbose mode',
    defaultsTo: !kReleaseMode,
  );
  parser.addFlag(
    "version",
    help: "Print version and exit",
    negatable: false,
  );
  parser.addFlag("help", abbr: "h", negatable: false);

  // Control commands: drive an already-running instance instead of
  // starting a second one.
  parser.addOption(
    'play',
    help: 'Search for a track and play it in the running instance',
    valueHelp: 'query',
  );
  parser.addOption(
    'search',
    help: 'Search in the running instance and print the matches',
    valueHelp: 'query',
  );
  parser.addFlag(
    'pause',
    help: 'Pause the running instance',
    negatable: false,
  );
  parser.addFlag(
    'resume',
    help: 'Resume the running instance',
    negatable: false,
  );
  parser.addFlag(
    'next',
    help: 'Skip to the next track in the running instance',
    negatable: false,
  );
  parser.addFlag(
    'previous',
    help: 'Skip to the previous track in the running instance',
    negatable: false,
  );
  parser.addFlag(
    'status',
    help: 'Print the running instance\'s playback state',
    negatable: false,
  );
  parser.addOption(
    'volume',
    help: 'Set the volume of the running instance (0.0 to 1.0)',
    valueHelp: 'level',
  );
  parser.addFlag(
    'mcp',
    help: 'Run as an MCP server on stdio, driving this instance',
    negatable: false,
  );

  ArgResults arguments;
  try {
    arguments = parser.parse(args);
  } on FormatException catch (e) {
    // An unknown switch is almost always an engine switch the host passed
    // through, not a user error. Report it and carry on with the
    // arguments we do understand.
    stderr.writeln('spotube: ignoring an unrecognized argument: ${e.message}');
    arguments = parser.parse(_withoutUnknownSwitches(args));
  }

  // --help and --version print to stdout. In a control-command mode the
  // runner has pointed the process's fd 1 at stderr (so the native
  // plugins' registration message cannot land in front of the answer), so
  // these go to the saved descriptor instead.
  if (arguments["help"] == true) {
    final out = controlCommandOutput();
    out.writeln(parser.usage);
    await out.flush();
    exit(0);
  }

  if (arguments["version"] == true) {
    final package = await PackageInfo.fromPlatform();
    final out = controlCommandOutput();
    out.writeln("Spotube v${package.version}");
    await out.flush();
    exit(0);
  }

  final controlRequest = _controlRequestFrom(arguments);
  if (controlRequest != null) {
    return CliInvocation(arguments, controlRequest: controlRequest);
  }

  if (arguments["mcp"] == true) {
    return CliInvocation(arguments,
        controlRequest: const ControlRequest('mcp.serve'));
  }

  return CliInvocation(arguments);
}

/// Builds the control command the arguments ask for, or null when they
/// do not ask for one.
ControlRequest? _controlRequestFrom(ArgResults arguments) {
  final play = arguments["play"] as String?;
  if (play != null) {
    return ControlRequest('search.play', {'query': play});
  }

  final search = arguments["search"] as String?;
  if (search != null) {
    return ControlRequest('search', {'query': search});
  }

  if (arguments["pause"] == true) {
    return const ControlRequest('playback.pause');
  }
  if (arguments["resume"] == true) {
    return const ControlRequest('playback.play');
  }
  if (arguments["next"] == true) {
    return const ControlRequest('playback.next');
  }
  if (arguments["previous"] == true) {
    return const ControlRequest('playback.previous');
  }
  if (arguments["status"] == true) {
    return const ControlRequest('state.get');
  }

  final volume = arguments["volume"] as String?;
  if (volume != null) {
    final level = double.tryParse(volume);
    if (level == null) {
      throw const FormatException(
          '--volume needs a number between 0.0 and 1.0');
    }
    return ControlRequest('volume.set', {'volume': level});
  }

  return null;
}

/// Drops the switches the parser does not know about.
///
/// Used when a strict parse failed: the engine's own switches are then
/// ignored rather than fatal, and the ones we do understand still work.
List<String> _withoutUnknownSwitches(List<String> args) {
  const known = {
    'verbose',
    'version',
    'help',
    'play',
    'search',
    'pause',
    'resume',
    'next',
    'previous',
    'status',
    'volume',
    'mcp',
  };

  final kept = <String>[];
  for (final arg in args) {
    if (!arg.startsWith('--')) {
      kept.add(arg);
      continue;
    }
    final name = arg.substring(2).split('=').first;
    if (known.contains(name)) kept.add(arg);
  }
  return kept;
}

/// Sends a control command to a running instance and prints the result.
///
/// Returns false when no instance was reachable, so the caller can decide
/// whether to start one.
Future<bool> sendControlCommand(ControlRequest request) async {
  final response = await ControlClient.send(request);
  if (response == null) {
    return false;
  }

  // The answer goes to the stdout the C runner reserved for it. In a
  // control-command mode the runner has pointed the process's fd 1 at
  // stderr (the native plugins and the VM print there), so writing to
  // `stdout` would land on stderr and be lost among the startup noise.
  final out = controlCommandOutput();

  if (!response.ok) {
    stderr.writeln('spotube: ${response.error}');
    return true;
  }

  final data = response.data;
  if (data is Map) {
    out.writeln(const JsonEncoder.withIndent('  ').convert(data));
  } else if (data != null) {
    out.writeln(data);
  } else {
    out.writeln('ok');
  }
  await out.flush();
  return true;
}

/// The stream a control command's answer is written to.
///
/// The C runner saves the process's original stdout on a dedicated
/// descriptor when it sees a control flag, and points fd 1 at stderr so
/// the native plugins' and the VM's own output cannot bury the answer.
/// This reopens the saved descriptor; without it (another platform, or a
/// test) the plain stdout is used.
IOSink controlCommandOutput() {
  final fd = Platform.environment[controlStdoutFdEnv];
  if (fd != null) {
    final parsed = int.tryParse(fd);
    if (parsed != null && parsed > 0) {
      try {
        return File('/proc/self/fd/$parsed').openWrite(mode: FileMode.write);
      } catch (_) {
        // Fall through to the plain stdout.
      }
    }
  }
  return stdout;
}
