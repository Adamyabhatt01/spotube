import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/logger/logger.dart';

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

  final stream = file.openRead().transform(utf8.decoder);

  await for (final line in stream) {
    yield line;
  }
});
