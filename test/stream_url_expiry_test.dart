import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/stream_url_expiry.dart';

const _baseUrl = 'https://rr1.googlevideo.com/videoplayback';

String _urlWithExpire(Object expire) =>
    '$_baseUrl?expire=$expire&id=abc123&itag=251&ei=xyz';

void main() {
  test('past expire is expired', () {
    final pastSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
    expect(isStreamUrlExpired(_urlWithExpire(pastSeconds)), isTrue);
  });

  test('future expire is not expired', () {
    final futureSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    expect(isStreamUrlExpired(_urlWithExpire(futureSeconds)), isFalse);
  });

  test('expire equal to now is not expired (strictly-past semantics)', () {
    final now = DateTime.now();
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    expect(
      isStreamUrlExpired(_urlWithExpire(nowSeconds), now: now),
      isFalse,
    );
  });

  test('missing expire is unknown, not expired', () {
    expect(isStreamUrlExpired('$_baseUrl?id=abc123&itag=251'), isFalse);
  });

  test('malformed expire is unknown, not expired', () {
    expect(isStreamUrlExpired(_urlWithExpire('soon')), isFalse);
    expect(isStreamUrlExpired(_urlWithExpire('')), isFalse);
    expect(isStreamUrlExpired(_urlWithExpire('12.5')), isFalse);
  });

  test('non-positive expire is unknown, not expired', () {
    expect(isStreamUrlExpired(_urlWithExpire(0)), isFalse);
    expect(isStreamUrlExpired(_urlWithExpire(-100)), isFalse);
  });

  test('invalid URL string is unknown, not expired', () {
    expect(isStreamUrlExpired('not a url at all %%%'), isFalse);
    expect(isStreamUrlExpired(''), isFalse);
  });
  test('multiple query parameters and encoding handled deterministically', () {
    final futureSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200;
    final url =
        '$_baseUrl?ei=a%2Fb&id=abc123&expire=$futureSeconds&itag=251&sig=AB%2BCD';
    expect(isStreamUrlExpired(url), isFalse);

    final pastSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
    final multiExpire =
        '$_baseUrl?expire=$pastSeconds&expire=$futureSeconds&id=abc';
    // Must not throw; result follows deterministic query-parameter parsing.
    expect(() => isStreamUrlExpired(multiExpire), returnsNormally);
  });

  group('manifestMinExpireSeconds', () {
    test('empty manifest has no horizon', () {
      expect(manifestMinExpireSeconds(const []), isNull);
    });

    test('returns the earliest expire across urls', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        manifestMinExpireSeconds([
          _urlWithExpire(now + 3600),
          _urlWithExpire(now + 1800),
          _urlWithExpire(now + 7200),
        ]),
        now + 1800,
      );
    });

    test('one unknown url poisons the whole manifest', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        manifestMinExpireSeconds([
          _urlWithExpire(now + 3600),
          '$_baseUrl?id=abc123&itag=251',
        ]),
        isNull,
        reason: 'an unreasoned-about URL must not ride on siblings freshness',
      );
      expect(
        manifestMinExpireSeconds([_urlWithExpire('soon')]),
        isNull,
      );
    });

    test('past urls keep their timestamps (caller decides expiry)', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        manifestMinExpireSeconds([_urlWithExpire(now - 10)]),
        now - 10,
      );
    });
  });

  group('streamUrlExpireSeconds', () {
    test('parses usable values, null otherwise', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(streamUrlExpireSeconds(_urlWithExpire(now + 60)), now + 60);
      expect(streamUrlExpireSeconds('$_baseUrl?id=x'), isNull);
      expect(streamUrlExpireSeconds(_urlWithExpire(0)), isNull);
      expect(streamUrlExpireSeconds(_urlWithExpire('soon')), isNull);
    });
  });
}
