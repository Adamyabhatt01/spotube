import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide join;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotube/utils/platform.dart';
import 'package:logging/logging.dart' as logging;

final _loggingToLoggerLevel = {
  logging.Level.ALL: Level.all,
  logging.Level.FINEST: Level.trace,
  logging.Level.FINER: Level.debug,
  logging.Level.FINE: Level.info,
  logging.Level.CONFIG: Level.info,
  logging.Level.INFO: Level.info,
  logging.Level.WARNING: Level.warning,
  logging.Level.SEVERE: Level.error,
  logging.Level.SHOUT: Level.fatal,
  logging.Level.OFF: Level.off,
};

class AppLogger {
  static late final Logger log;

  /// The logger, or null when [initialize] has not run yet.
  ///
  /// The reporting path must never be the thing that throws: an error
  /// reported before the logger exists used to die with a
  /// LateInitializationError here, which hid the very error it was
  /// supposed to report — and turned a warning into a crash.
  static Logger? get _safeLog {
    try {
      return log;
    } catch (_) {
      // The `late final` was never assigned. Nothing to log through.
      return null;
    }
  }

  static Future<File>? _logFile;

  /// Resolved on first use rather than cached eagerly: the previous
  /// `late final logFile` was assigned by a fire-and-forget future, so a
  /// startup error reported before it completed hit a
  /// LateInitializationError inside [reportError] and the report was
  /// dropped — the file never got the line that explained the crash.
  ///
  /// A failed resolution is forgotten instead of cached: the first call can
  /// run before plugins are registered (startup phases log before the
  /// Flutter binding exists, so path_provider throws), and caching that
  /// failure would make every later [reportError] and [logStartupLine]
  /// fail forever on the same dead future.
  static Future<File> get logFile {
    final cached = _logFile;
    if (cached != null) return cached;
    final future = getLogsPath();
    _logFile = future;
    // ignore: discarded_futures — cleanup only; callers await `future`.
    future.then((_) {}, onError: (_) {
      if (identical(_logFile, future)) _logFile = null;
    });
    return future;
  }

  /// `.spotube_logs` grew without bound: an error repeating in a loop wrote
  /// a full stack trace per iteration, in a file the log viewer only ever
  /// reads the tail of. Past this size the file is rewritten to its last
  /// [logTailKeepBytes].
  static const logFileMaxBytes = 5 * 1024 * 1024;
  static const logTailKeepBytes = 1 * 1024 * 1024;

  /// Keep the newest [logTailKeepBytes] of [file], dropping the older part.
  /// The partial line at the cut is discarded so the survivor is a whole
  /// sequence of reports, which is also what the tail reader (the
  /// `logsViewerMaxBytes` window in `logs_provider.dart`) decodes.
  @visibleForTesting
  static Future<void> rotateLogFile(File file) async {
    final size = await file.length();
    if (size <= logTailKeepBytes) return;

    final List<int> body;
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(size - logTailKeepBytes);
      final tail = await raf.read(logTailKeepBytes);
      final cut = tail.indexOf(0x0A);
      body = cut == -1 ? tail : tail.sublist(cut + 1);
    } finally {
      await raf.close();
    }

    // dart:io has no read-write-without-truncate mode, so the rewrite goes
    // through a truncating open once the tail is already in memory.
    await file.writeAsBytes(body, mode: FileMode.write);
  }

  static initialize(bool verbose) {
    log = Logger(
      level: kDebugMode || (verbose && kReleaseMode) ? Level.all : Level.info,
    );
  }

  /// One-line startup phase record, visible in release logs too. The
  /// startup harness (`_startupLog` in `main.dart`) used to return early in
  /// release builds, so a slow launch on a user device left no trace to
  /// attribute. Lines are short and few (~15 per start); the same 5 MB
  /// rotation caps the file. Fire-and-forget: must never block startup,
  /// and a failure here is dropped silently (a logging path that throws
  /// would be worse than a missing line).
  static void logStartupLine(String line) {
    _safeLog?.i(line);
    if (kReleaseMode) {
      // Startup must never await logging; the shared queue keeps this line
      // from interleaving with a concurrent error report.
      unawaited(_appendLog('$line\n'));
    }
  }

  /// One-line record of something that happened at runtime, visible in the
  /// on-device log (Settings → Logs) on a release build.
  ///
  /// The log file otherwise only receives error reports, so an operation
  /// that fails *quietly* — a library re-read that never lands, a playlist
  /// that is created but never reaches the account's library — leaves
  /// nothing to look at. These lines are the difference between "it did not
  /// work" and "here is what it did".
  ///
  /// Fire-and-forget for the same reason as [logStartupLine]: logging must
  /// never block the caller, and a failure to write is dropped.
  static void logEvent(String line) {
    _safeLog?.i(line);
    if (kReleaseMode) {
      unawaited(
        _appendLog('[${DateTime.now()}] $line\n'),
      );
    }
  }

  /// Serializes writes to the on-device log file.
  ///
  /// Startup lines are fire-and-forget and error reports can arrive at the
  /// same moment. Two concurrent appends used to interleave mid-line
  /// (`[startup] splashReady (them[startup] step ...`), which made the
  /// startup harness unreadable on devices without adb.
  static Future<void> _logWriteQueue = Future.value();

  static Future<void> _appendLog(String contents) {
    final next = _logWriteQueue.then((_) async {
      try {
        final file = await logFile;
        await file.writeAsString(contents, mode: FileMode.writeOnlyAppend);
        if (await file.length() > logFileMaxBytes) {
          await rotateLogFile(file);
        }
      } catch (writeError, writeStackTrace) {
        // The log sink must never be the thing that breaks error reporting.
        // Drop the cached path so the next report retries resolution (the
        // first one can run before plugins are registered).
        _logFile = null;
        _safeLog?.w(
          "Could not write to the log file",
          error: writeError,
          stackTrace: writeStackTrace,
        );
      }
    });
    _logWriteQueue = next;
    return next;
  }

  static void _initInternalPackageLoggers() {
    if (!kDebugMode) return;
    logging.hierarchicalLoggingEnabled = true;
    logging.Logger('YoutubeExplode.StreamsClient')
      ..level = logging.Level.SEVERE
      ..onRecord.listen(
        (record) {
          log.log(
            _loggingToLoggerLevel[record.level] ?? Level.info,
            record.message,
            error: record.error,
            stackTrace: record.stackTrace,
            time: record.time,
          );
        },
      );
  }

  static R? runZoned<R>(R Function() body) {
    return runZonedGuarded<R>(
      () {
        WidgetsFlutterBinding.ensureInitialized();

        FlutterError.onError = (details) {
          reportError(details.exception, details.stack ?? StackTrace.current);
        };

        PlatformDispatcher.instance.onError = (error, stackTrace) {
          reportError(error, stackTrace);
          return true;
        };

        if (!kIsWeb) {
          Isolate.current.addErrorListener(
            RawReceivePort((pair) async {
              final isolateError = pair as List<dynamic>;
              reportError(
                isolateError.first.toString(),
                isolateError.last,
              );
            }).sendPort,
          );
        }

        _initInternalPackageLoggers();

        return body();
      },
      (error, stackTrace) {
        reportError(error, stackTrace);
      },
    );
  }

  static Future<File> getLogsPath() async {
    String dir = (await getApplicationDocumentsDirectory()).path;
    if (kIsAndroid) {
      dir = (await getExternalStorageDirectory())?.path ?? "";
    }

    if (kIsMacOS) {
      dir = join((await getLibraryDirectory()).path, "Logs");
    }

    if (kIsLinux) {
      dir = join(_getXdgStateHome(), "spotube");
    }

    final file = File(join(dir, ".spotube_logs"));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  static Future<void> reportError(
    dynamic error, [
    StackTrace? stackTrace,
    message = "",
  ]) async {
    _safeLog?.e(message, error: error, stackTrace: stackTrace);

    if (kReleaseMode) {
      await _appendLog(
        "[${DateTime.now()}]---------------------\n"
        "$error\n$stackTrace\n"
        "----------------------------------------\n",
      );
    }
  }

  static String _getXdgStateHome() {
    // path_provider seems does not support XDG_STATE_HOME,
    // which is the specification to store application logs on Linux.
    // See https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
    // TODO: Use path_provider once it supports XDG_STATE_HOME
    if (const bool.hasEnvironment("XDG_STATE_HOME")) {
      String xdgStateHomeRaw = Platform.environment["XDG_STATE_HOME"] ?? "";
      if (xdgStateHomeRaw.isNotEmpty) {
        return xdgStateHomeRaw;
      }
    }
    return join(Platform.environment["HOME"] ?? "", ".local", "state");
  }
}

class AppLoggerProviderObserver extends ProviderObserver {
  const AppLoggerProviderObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    AppLogger.reportError(error, stackTrace);
  }
}
