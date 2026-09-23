import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/logger/logger.dart';

/// How much of the log file the viewer (and the copy button, which reads the
/// same future) loads. Multi-MB logs used to stream the whole file through
/// one widget; the tail is what anyone opens this page for.
const logsViewerMaxBytes = 256 * 1024;

/// Reads at most the last [maxBytes] of [file] as text.
///
/// Starts on a line boundary (a partial first line is dropped) and tolerates
/// a split multi-byte sequence at the cut, so the result is always complete
/// lines of valid text. Pure for testing.
Future<String> readLogTail(File file, {int maxBytes = logsViewerMaxBytes}) async {
  final length = await file.length();
  if (length == 0) return '';
  final start = length > maxBytes ? length - maxBytes : 0;
  final access = await file.open(mode: FileMode.read);
  try {
    await access.setPosition(start);
    final bytes = await access.read(length - start);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (start == 0) return text;
    final firstNewline = text.indexOf('\n');
    return firstNewline < 0 ? '' : text.substring(firstNewline + 1);
  } finally {
    await access.close();
  }
}

final logsProvider = StreamProvider.autoDispose((ref) async* {
  final file = await AppLogger.getLogsPath();

  // An empty or not-yet-created log file is normal (fresh install, no
  // errors logged yet) — emit empty data instead of surfacing an error or
  // hanging in AsyncLoading (a StreamProvider that yields nothing never
  // resolves out of the loading state).
  if (!await file.exists() || await file.length() == 0) {
    yield '';
    return;
  }

  yield await readLogTail(file);
});
