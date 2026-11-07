// The logs viewer reads at most the tail of the file: complete lines,
// valid text at the cut, empty input in and empty output out.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/logs/logs_provider.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('logs_tail_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> plant(String name, List<int> bytes) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('empty file reads as empty', () async {
    expect(await readLogTail(await plant('empty.log', [])), '');
  });

  test('small file reads whole', () async {
    final file = await plant(
      'small.log',
      utf8.encode('line one\nline two\n'),
    );
    expect(await readLogTail(file), 'line one\nline two\n');
  });

  test('large file reads the tail on a line boundary', () async {
    final lines = [for (var i = 0; i < 2000; i++) 'log line $i\n'];
    final file = await plant('big.log', utf8.encode(lines.join()));
    final text = await readLogTail(file, maxBytes: 1024);

    expect(utf8.encode(text).length, lessThanOrEqualTo(1024));
    // Starts on a boundary: first line is complete, never a fragment.
    final firstLine = text.split('\n').first;
    expect(firstLine, startsWith('log line '));
    // And it is the tail: the newest lines are present.
    expect(text, contains('log line 1999\n'));
    expect(text.endsWith('\n'), isTrue);
  });

  test('split multi-byte sequence at the cut decodes', () async {
    // A stray lead byte (0xC3) mid-tail: malformed head must not throw, and
    // the complete lines after it survive.
    final bytes = [
      ...utf8.encode('line one\n'),
      0xC3,
      ...utf8.encode('line two\nline three\n'),
    ];
    final file = await plant('uni.log', bytes);
    // Cut five bytes in: the head line fragments, the rest must survive.
    final text = await readLogTail(file, maxBytes: bytes.length - 5);

    expect(() => utf8.encode(text), returnsNormally);
    expect(text, contains('line two\n'));
    expect(text, contains('line three\n'));
    expect(text, isNot(contains('line one')));
  });
}
