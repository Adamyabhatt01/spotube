// A shape guard, not a behaviour test.
//
// Wrapping an engine call in `withinEngineCallBudget` moves the closure that
// produces it, and the obvious-looking spelling of "await this, then cast"
// inside a closure is `api() as Future<List>` - which casts the *future*, not
// the value. `extractInfo` returns `Future<dynamic>`, and Dart generics are
// reified, so `Future<dynamic> is Future<List>` is false and it throws in
// production: two yt-dlp call sites did exactly that and broke manifest
// resolution 9 times in one session log.
//
// The analyzer cannot see it, and `YtDlp.instance` is a singleton with no test
// seam, so a unit test of the call site is not available. This is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no engine call casts a Future instead of its awaited value', () {
    final offenders = <String>[];
    for (final file in Directory('lib/services/youtube_engine')
        .listSync(recursive: true)
        .whereType<File>()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('as Future<')) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'cast inside an async closure: `() async => (await api()) as '
          'List`. A cast on the future itself fails at runtime because '
          'Future<dynamic> is not a subtype of Future<List>.\n'
          '${offenders.join('\n')}',
    );
  });
}
