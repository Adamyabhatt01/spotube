import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:spotube/services/control/control_protocol.dart';
import 'package:spotube/services/control/control_server.dart';

/// The MCP server that exposes a running Spotube instance.
///
/// Started with `spotube --mcp`. It runs as its own process and talks to
/// the app over the local control channel, so:
///
///  - it costs the running app **no** memory (the app does not host it),
///  - it is never reachable from the network (the control channel is a
///    Unix socket or a loopback port),
///  - and the same command vocabulary backs the CLI (`spotube --play ...`)
///    and the MCP tools, so there is one definition of "what can be
///    controlled".
///
/// If no instance is running, the tools report that rather than failing
/// obscurely: the answer is "start Spotube", not a stack trace.
base class SpotubeMcpServer extends MCPServer with ToolsSupport {
  SpotubeMcpServer(super.channel)
      : super.fromStreamChannel(
          implementation: Implementation(
            name: 'spotube',
            version: '1.0.0',
          ),
          instructions: 'Control the running Spotube instance: query the '
              'playback state, search the library, and drive playback.',
        ) {
    registerTool(stateTool, _state);
    registerTool(searchTool, _search);
    registerTool(playTool, _play);
    registerTool(controlTool, _control);
  }

  /// Reads the playback state.
  final stateTool = Tool(
    name: 'spotube_state',
    description:
        'The current playback state: the active track, position, duration, '
        'volume, shuffle/loop, and the queue.',
    inputSchema: Schema.object(properties: {}),
  );

  /// Searches the metadata provider.
  final searchTool = Tool(
    name: 'spotube_search',
    description: 'Search the music library for tracks, albums, artists or '
        'playlists.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(description: 'What to search for.'),
        'type': UntitledSingleSelectEnumSchema(
          description: 'What to search for.',
          values: ['track', 'album', 'artist', 'playlist'],
        ),
      },
      required: ['query'],
    ),
  );

  /// Searches and plays the best match.
  final playTool = Tool(
    name: 'spotube_play',
    description:
        'Search for a track and play it in the running instance. Picks the '
        'best matching title.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(description: 'The track to play.'),
      },
      required: ['query'],
    ),
  );

  /// Drives playback.
  final controlTool = Tool(
    name: 'spotube_control',
    description:
        'Control playback: play, pause, stop, next, previous, seek, shuffle, '
        'loop, or set the volume.',
    inputSchema: Schema.object(
      properties: {
        'action': UntitledSingleSelectEnumSchema(
          description: 'The action to perform.',
          values: [
            'play',
            'pause',
            'stop',
            'next',
            'previous',
            'seek',
            'shuffle',
            'loop',
            'volume',
          ],
        ),
        'value': Schema.string(
          description:
              'The action\'s argument: seconds for seek, true/false for '
              'shuffle, off/all/one for loop, 0.0-1.0 for volume.',
        ),
      },
      required: ['action'],
    ),
  );

  FutureOr<CallToolResult> _state(CallToolRequest request) {
    return _call('state.get', const {});
  }

  FutureOr<CallToolResult> _search(CallToolRequest request) {
    final query = request.arguments?['query'];
    if (query is! String || query.trim().isEmpty) {
      return _error('spotube_search needs a non-empty "query"');
    }
    return _call('search', {'query': query.trim()});
  }

  FutureOr<CallToolResult> _play(CallToolRequest request) {
    final query = request.arguments?['query'];
    if (query is! String || query.trim().isEmpty) {
      return _error('spotube_play needs a non-empty "query"');
    }
    return _call('search.play', {'query': query.trim()});
  }

  FutureOr<CallToolResult> _control(CallToolRequest request) {
    final action = request.arguments?['action'];
    final value = request.arguments?['value'];
    if (action is! String) {
      return _error('spotube_control needs an "action"');
    }

    switch (action) {
      case 'play':
        return _call('playback.play', const {});
      case 'pause':
        return _call('playback.pause', const {});
      case 'stop':
        return _call('playback.stop', const {});
      case 'next':
        return _call('playback.next', const {});
      case 'previous':
        return _call('playback.previous', const {});
      case 'seek':
        final seconds = double.tryParse('$value');
        if (seconds == null) {
          return _error('seek needs a numeric "value" (seconds)');
        }
        return _call('playback.seek', {'seconds': seconds});
      case 'shuffle':
        final enabled = value is bool ? value : '$value' == 'true';
        return _call('playback.shuffle', {'enabled': enabled});
      case 'loop':
        return _call('playback.loop', {'mode': '$value'});
      case 'volume':
        final level = double.tryParse('$value');
        if (level == null) {
          return _error('volume needs a numeric "value" (0.0-1.0)');
        }
        return _call('volume.set', {'volume': level});
      default:
        return _error('unknown action "$action"');
    }
  }

  /// Sends a command to the running instance and renders the answer.
  Future<CallToolResult> _call(
    String command,
    Map<String, dynamic> arguments,
  ) async {
    final response = await ControlClient.send(
      ControlRequest(command, arguments),
      timeout: const Duration(seconds: 20),
    );

    if (response == null) {
      return _error(
        'No running Spotube instance was reachable on the local control '
        'channel. Start Spotube, then try again.',
      );
    }

    if (!response.ok) {
      return _error(response.error ?? 'the command failed');
    }

    return CallToolResult(
      content: [TextContent(text: _render(response.data))],
    );
  }

  /// Renders a command's result as text.
  String _render(Object? data) {
    if (data == null) return 'ok';
    if (data is Map || data is List) {
      return const JsonEncoder.withIndent('  ').convert(data);
    }
    return '$data';
  }

  /// Renders a failure as a tool error.
  CallToolResult _error(String message) {
    return CallToolResult(
      content: [TextContent(text: message)],
      isError: true,
    );
  }
}

/// Runs the MCP server on stdio until the client closes the connection.
///
/// The protocol's stdout is the process's real stdout, and the native
/// runner has already saved it: when `--mcp` is in the arguments, the C
/// runner duplicates the original stdout to a dedicated descriptor and
/// points fd 1 at stderr, so nothing else can write into the JSON-RPC
/// stream. (The media_kit native plugin prints
/// "package:media_kit_libs_linux registered." to stdout when it loads, and
/// the Hetu VM prints its module timings — either would corrupt the
/// stream, and the native one happens before Dart even starts.)
///
/// The saved descriptor arrives through [mcpProtocolStdoutFd].
Future<void> runSpotubeMcpServer() async {
  final output = _openProtocolStdout();

  final server = SpotubeMcpServer(
    stdioChannel(input: io.stdin, output: output),
  );
  await server.done;
}

/// The environment variable the C runner uses to hand over the saved
/// stdout descriptor.
const mcpProtocolStdoutEnv = 'SPOTUBE_CONTROL_STDOUT_FD';

/// Opens the protocol's stdout.
///
/// The C runner saved the original stdout at a known descriptor when it
/// saw a control flag; this reopens it through /proc. When the variable is
/// missing (a platform whose runner does not do this, or a test), the
/// process's stdout is used directly.
io.IOSink _openProtocolStdout() {
  final fd = io.Platform.environment[mcpProtocolStdoutEnv];
  if (fd != null) {
    final parsed = int.tryParse(fd);
    if (parsed != null && parsed > 0) {
      try {
        // /proc/self/fd is the portable way back to an inherited
        // descriptor on Linux; opening it for writing writes to the same
        // open file description, so the client sees the bytes.
        final file = io.File('/proc/self/fd/$parsed');
        return file.openWrite(mode: io.FileMode.write);
      } catch (_) {
        // Fall through to the plain stdout.
      }
    }
  }
  return io.stdout;
}
