// Tests the Better Lyrics TTML parser: line-timed (Hindi), word-timed
// (English) documents, timestamp forms, entity decoding, and skipping of
// unparseable/empty lines.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/lyrics/better_lyrics_provider.dart';

void main() {
  group('parseTtmlTimestamp', () {
    test('parses ss.mmm form', () {
      expect(parseTtmlTimestamp('10.228'), const Duration(milliseconds: 10228));
    });

    test('parses m:ss.mmm form', () {
      expect(
        parseTtmlTimestamp('1:08.628'),
        const Duration(milliseconds: 68628),
      );
    });

    test('rejects malformed and negative input', () {
      expect(parseTtmlTimestamp(''), isNull);
      expect(parseTtmlTimestamp('abc'), isNull);
      expect(parseTtmlTimestamp('-5.0'), isNull);
      expect(parseTtmlTimestamp('1:2:3.0'), isNull);
    });
  });

  group('parseBetterLyricsTtml', () {
    test('parses line-timed document (Hindi)', () {
      const ttml = '''
<tt><body>
  <div begin="10.228" end="20.218">
    <p begin="10.228" end="15.128">Hum tere bin ab reh nahi sakte</p>
    <p begin="15.388" end="20.218">Tere bina kya wajood mera</p>
  </div>
  <div begin="25.508" end="46.168">
    <p begin="25.508" end="30.608">Tujhse judaa agar ho jayenge toh</p>
  </div>
</body></tt>
''';

      final lyrics = parseBetterLyricsTtml(ttml);
      expect(lyrics, hasLength(3));
      expect(lyrics[0].text, 'Hum tere bin ab reh nahi sakte');
      expect(lyrics[0].time, const Duration(milliseconds: 10228));
      expect(lyrics[1].time, const Duration(milliseconds: 15388));
      expect(lyrics[2].time, const Duration(milliseconds: 25508));
    });

    test('collapses word-level spans into one line', () {
      const ttml = '''
<tt><body>
  <p begin="33.642" end="35.909">
    <span begin="33.642" end="33.958">Look</span>
    <span begin="33.958" end="34.278">at</span>
    <span begin="34.278" end="34.577">the</span>
    <span begin="34.577" end="35.909">stars</span>
  </p>
</body></tt>
''';

      final lyrics = parseBetterLyricsTtml(ttml);
      expect(lyrics, hasLength(1));
      expect(lyrics[0].text, 'Look at the stars');
      expect(lyrics[0].time, const Duration(milliseconds: 33642));
    });

    test('decodes HTML entities in text', () {
      const ttml = '''
<tt><body>
  <p begin="1.000" end="2.000">I&amp;quot;m here &amp; you&amp;apos;re there</p>
</body></tt>
''';

      final lyrics = parseBetterLyricsTtml(ttml);
      expect(lyrics, hasLength(1));
      expect(lyrics[0].text, 'I"m here & you\'re there');
    });

    test('skips lines with missing or unparseable begin times', () {
      const ttml = '''
<tt><body>
  <p end="2.000">No begin here</p>
  <p begin="abc" end="3.000">bad time</p>
  <p begin="1.000" end="2.000">ok line</p>
  <p begin="5.000" end="6.000"><span>  </span></p>
</body></tt>
''';

      final lyrics = parseBetterLyricsTtml(ttml);
      expect(lyrics, hasLength(1));
      expect(lyrics[0].text, 'ok line');
    });

    test('empty or whitespace-only input yields no lines', () {
      expect(parseBetterLyricsTtml(''), isEmpty);
      expect(parseBetterLyricsTtml('  <tt></tt>  '), isEmpty);
    });
  });
}