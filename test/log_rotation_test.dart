import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/logger/logger.dart';

/// `.spotube_logs` had no cap, so an error repeating in a loop wrote a stack
/// trace per iteration forever. [reportError] itself only writes in
/// `kReleaseMode` — which a test run is not — so these exercise the rotation
/// step it calls, which is the part with the behavior.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('spotube_log_rotation');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeLines(int count) async {
    final file = File('${temp.path}/.spotube_logs');
    final sink = await file.open(mode: FileMode.writeOnlyAppend);
    for (var i = 0; i < count; i++) {
      await sink.writeString('-- report $i\n');
    }
    await sink.close();
    return file;
  }

  test('a file under the cap is left alone', () async {
    final file = await writeLines(3);
    final before = await file.readAsString();

    await AppLogger.rotateLogFile(file);

    expect(await file.readAsString(), before);
  });

  test('rotation keeps the newest bytes and starts on a line boundary',
      () async {
    // One byte over the cap so the length gate in reportError would fire.
    final filler = File('${temp.path}/.spotube_logs');
    final sink = await filler.open(mode: FileMode.writeOnlyAppend);
    await sink.writeString('OLD LINE THAT MUST GO\n');
    // A partial line at the cut point: everything before the first newline of
    // the retained window is dropped, so the survivor decodes cleanly.
    final junk = List<int>.filled(AppLogger.logTailKeepBytes - 3, 0x41);
    await sink.writeFrom(junk);
    await sink.writeString('\nNEW LINE THAT MUST STAY\n');
    await sink.close();

    expect(await filler.length(), greaterThan(AppLogger.logTailKeepBytes));

    await AppLogger.rotateLogFile(filler);

    final after = await filler.readAsString();
    expect(after.length, lessThanOrEqualTo(AppLogger.logTailKeepBytes));
    expect(after, isNot(contains('OLD LINE')));
    expect(after.endsWith('NEW LINE THAT MUST STAY\n'), isTrue);
    // The retained window began mid-line; that fragment is gone, so the file
    // starts at a real line rather than a torn one.
    expect(after, isNot(startsWith('A')));
  });

  test('the cap leaves room for many reports before the next rotation',
      () async {
    // Rotation must not run on every write: a file truncated to the tail is
    // below the cap, so the next report is a plain append.
    final file = File('${temp.path}/.spotube_logs');
    await file.writeAsString('x' * (AppLogger.logFileMaxBytes + 1));

    await AppLogger.rotateLogFile(file);
    final size = await file.length();

    expect(size, lessThan(AppLogger.logFileMaxBytes));
    expect(size, greaterThan(AppLogger.logTailKeepBytes - 1024));
  });
}
