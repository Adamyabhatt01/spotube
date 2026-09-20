import 'dart:async';

import 'package:flutter/foundation.dart';

/// Compile-time switch: `kReleaseMode` is a constant, so in a release build every
/// [PerfCounters] call below folds away and the counters are tree-shaken.
const bool kPerfCountersEnabled = !kReleaseMode;

/// Development-only performance counters.
///
/// Purpose: the performance roadmap requires before/after numbers per change, and
/// several hot paths (history row parsing, queue serialization, raw position
/// dispatches, upstream media requests, local-library metadata reads) have no
/// observable output. Counting at the choke points lets a unit test assert
/// "cost no longer grows with dataset size" and lets a running debug/profile app
/// dump the same numbers to the log.
///
/// Never put behaviour behind these counters — they only observe.
class PerfCounters {
  PerfCounters._();

  static final Map<String, _Accumulator> _entries = {};

  static void note(String name, [int amount = 1]) {
    if (!kPerfCountersEnabled) return;
    _entries.putIfAbsent(name, _Accumulator.new).count += amount;
  }

  /// One call plus the microseconds it took.
  static void time(String name, Duration elapsed) {
    if (!kPerfCountersEnabled) return;
    final acc = _entries.putIfAbsent(name, _Accumulator.new);
    acc.count += 1;
    acc.microseconds += elapsed.inMicroseconds;
  }

  /// Runs [body] and records its duration under [name]. Returns the body's value.
  static T measured<T>(String name, T Function() body) {
    if (!kPerfCountersEnabled) return body();
    final sw = Stopwatch()..start();
    try {
      return body();
    } finally {
      time(name, sw.elapsed);
    }
  }

  static int countOf(String name) => _entries[name]?.count ?? 0;

  static Duration totalOf(String name) =>
      Duration(microseconds: _entries[name]?.microseconds ?? 0);

  static void reset() {
    _entries.clear();
  }

  /// `name=count(µs)` per line, for logs and test output. Only [name]s that were
  /// touched since the last [reset] appear.
  static String snapshot() {
    if (_entries.isEmpty) return '(no counters recorded)';
    final lines = _entries.entries.map(
      (e) => '${e.key}=${e.value.count}'
          '${e.value.microseconds > 0 ? ' (${e.value.microseconds}us)' : ''}',
    ).toList()
      ..sort();
    return lines.join('\n');
  }

  static Timer? _dumpTimer;

  /// Periodically logs a snapshot and resets the counters. The caller decides
  /// when this is worth running (a debug/profile run with an env var set), so
  /// nothing here reads the environment itself.
  static void startDumpTimer({
    Duration interval = const Duration(seconds: 10),
    required void Function(String message) log,
  }) {
    if (kReleaseMode || _dumpTimer != null) return;
    _dumpTimer = Timer.periodic(interval, (_) {
      log('[perf]\n${snapshot()}');
      reset();
    });
  }

  @visibleForTesting
  static void stopDumpTimerForTest() {
    _dumpTimer?.cancel();
    _dumpTimer = null;
  }
}

class _Accumulator {
  int count = 0;
  int microseconds = 0;
}
