import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:yt_dlp_dart/yt_dlp_dart.dart';

/// How long an abandoned yt-dlp gets to leave after SIGTERM before it is
/// SIGKILLed. Long enough for the binary's own cleanup, short enough that a
/// stuck Python process cannot outlive the call that gave up on it.
const ytDlpKillGrace = Duration(seconds: 2);

typedef YtDlpSpawner = Future<Process> Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required bool runInShell,
});

Future<Process> _defaultSpawn(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required bool runInShell,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: runInShell,
  );
}

/// yt-dlp's process layer, replacing the one inside `yt_dlp_dart`.
///
/// The package runs its binary with `Process.run`, which hands back no handle:
/// `withinEngineCallBudget` abandons the await when a call misses
/// `engineCallBudget`, but the yt-dlp process kept scraping YouTube for an
/// answer nobody was going to read, and a fallback cascade could stack several
/// of those at once. `YtDlp.setCustomExecutor` is the package's own seam, so
/// this swap needs no fork.
///
/// Everything else is deliberately identical to the package: same working
/// directory, same `runInShell` flag, same system-encoding decode, same
/// "stderr with empty stdout means failure" contract. This class exists to make
/// the process killable, not to change what a call returns.
class YtDlpProcess {
  YtDlpProcess({
    this.budget = engineCallBudget,
    this.grace = ytDlpKillGrace,
    String Function()? executable,
    bool Function()? runInShell,
    YtDlpSpawner? spawn,
  })  : _executable = executable ?? (() => YtDlp.instance.binaryLocation.path),
        _runInShell = runInShell ?? (() => YtDlp.instance.runInShell),
        _spawn = spawn ?? _defaultSpawn;

  static final YtDlpProcess shared = YtDlpProcess();

  final Duration budget;
  final Duration grace;
  final String Function() _executable;
  final bool Function() _runInShell;
  final YtDlpSpawner _spawn;

  final _live = <int>{};

  /// Pids of the children this runner owns right now.
  Set<int> get livePids => Set.unmodifiable(_live);

  /// Replaces the package's process layer with [runner].
  ///
  /// Call once, after the binary location has been resolved: the package's
  /// `binaryLocation` throws when unset, and no engine call can happen before
  /// that either (every entry point gates on `YtDlpEngine.isBinaryReady`).
  static void install([YtDlpProcess? runner]) {
    YtDlp.instance.setCustomExecutor((runner ?? shared).execute);
  }

  Future<String> execute(List<String> args) async {
    final process = await _spawn(
      _executable(),
      args,
      workingDirectory: Directory.systemTemp.path,
      runInShell: _runInShell(),
    );
    _live.add(process.pid);

    var exited = false;
    unawaited(process.exitCode.whenComplete(() => exited = true));

    // Both pipes are read to the end unconditionally: a child whose stderr
    // buffer fills stops writing stdout, which would turn a chatty yt-dlp into
    // a hang that outlasts the budget.
    final stdOut = _drain(process.stdout);
    final stdErr = _drain(process.stderr);

    try {
      await process.exitCode.timeout(budget, onTimeout: () {
        PerfCounters.note('engine.yt_dlp.killedOnBudget');
        AppLogger.log.d(
          () =>
              'yt-dlp (pid ${process.pid}) exceeded ${budget.inMilliseconds}ms '
              'and was terminated',
        );
        _terminate(process, () => exited, grace);
        throw TimeoutException('yt-dlp exceeded its call budget', budget);
      });
    } finally {
      _live.remove(process.pid);
    }

    final out = systemEncoding.decode(await stdOut);
    final err = systemEncoding.decode(await stdErr);
    if (err.isNotEmpty && out.isEmpty) {
      throw Exception(
        'yt-dlp command failed with exit code ${await process.exitCode}\n'
        'STDOUT: $out\n'
        'STDERR: $err',
      );
    }
    return out;
  }

  static void _terminate(
    Process process,
    bool Function() hasExited,
    Duration grace,
  ) {
    process.kill(ProcessSignal.sigterm);
    Timer(grace, () {
      if (hasExited()) return;
      process.kill(ProcessSignal.sigkill);
    });
  }

  /// Collects a pipe without ever completing with an error: a call that was
  /// abandoned must not turn a pipe read error into an unhandled zone error.
  static Future<List<int>> _drain(Stream<List<int>> stream) {
    final buffer = BytesBuilder(copy: false);
    final done = Completer<List<int>>();
    late StreamSubscription<List<int>> subscription;
    void finish() {
      if (!done.isCompleted) done.complete(buffer.takeBytes());
    }

    subscription = stream.listen(
      buffer.add,
      onDone: finish,
      onError: (Object _, StackTrace __) {
        unawaited(subscription.cancel());
        finish();
      },
      cancelOnError: true,
    );
    return done.future;
  }
}
