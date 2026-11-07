// The palette cache's contract, without an image decoder: extraction is a
// seam here, so hit/miss, LRU eviction, cancellation and the change stream
// are all deterministic.

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/theme_ui/artwork_palette.dart';

ArtworkPalette _palette(int seed) {
  final color = Color(0xFF000000 | seed);
  return ArtworkPalette(
    dominant: color,
    vibrant: color,
    muted: color,
    darkMuted: color,
    lightMuted: color,
    onDominant: const Color(0xFFFFFFFF),
  );
}

void main() {
  test('a URL is extracted once and served from the cache afterwards',
      () async {
    var calls = 0;
    final cache = ArtworkPaletteCache(
      extractor: (url) async {
        calls++;
        return _palette(0x101010);
      },
    );

    expect(cache['art://a'], isNull);
    final first = await cache.load('art://a');
    expect(first, isNotNull);
    expect(cache['art://a'], same(first));

    final second = await cache.load('art://a');
    expect(second, same(first));
    expect(calls, 1, reason: 'a hit must not ask the extractor again');
  });

  test('a failed extraction is a miss, not a cached null', () async {
    var calls = 0;
    final cache = ArtworkPaletteCache(
      extractor: (url) async {
        calls++;
        return calls == 1 ? null : _palette(0x202020);
      },
    );

    expect(await cache.load('art://bad'), isNull);
    expect(cache['art://bad'], isNull);
    expect(cache.length, 0);

    final retry = await cache.load('art://bad');
    expect(retry, isNotNull, reason: 'a miss may become a hit later');
    expect(calls, 2);
  });

  test('the cache is a bounded LRU', () async {
    final cache = ArtworkPaletteCache(
      maxEntries: 3,
      extractor: (url) async => _palette(int.parse(url.substring(4))),
    );

    for (var i = 1; i <= 3; i++) {
      await cache.load('art:$i');
    }
    // Touch 1 so it is the most recently used, then overflow.
    expect(cache['art:1'], isNotNull);
    await cache.load('art:4');

    expect(cache.length, 3);
    expect(cache['art:2'], isNull, reason: 'least recently used is evicted');
    expect(cache['art:1'], isNotNull);
    expect(cache['art:4'], isNotNull);
  });

  test('a cancelled caller gets null and cannot poison another URL', () async {
    final slow = Completer<ArtworkPalette?>();
    final cache = ArtworkPaletteCache(
      extractor: (url) {
        if (url == 'art:slow') return slow.future;
        return Future.value(_palette(0x303030));
      },
    );

    var cancelled = false;
    final stale = cache.load('art:slow', isCancelled: () => cancelled);
    final fresh = await cache.load('art:fresh');
    expect(fresh, isNotNull);
    expect(cache['art:fresh'], same(fresh));

    cancelled = true;
    slow.complete(_palette(0x404040));
    expect(await stale, isNull,
        reason: 'the widget that asked is gone; it must not receive a colour');
    expect(cache['art:fresh'], same(fresh),
        reason: 'a late result for another URL must not overwrite this one');
  });

  test('storing a palette emits one revision', () async {
    final cache = ArtworkPaletteCache(
      extractor: (url) async => _palette(0x505050),
    );
    final revisions = <int>[];
    final subscription = cache.changes.listen(revisions.add);

    await cache.load('art:one');
    await cache.load('art:one');
    await pumpEventQueue();

    expect(revisions, [1], reason: 'a cache hit should not rebuild a slot');

    await cache.load('art:two');
    await pumpEventQueue();
    expect(revisions, [1, 2]);

    await subscription.cancel();
    await cache.dispose();
  });

  test('the palette binding namespace is complete and hex formatted', () {
    final bindings = ArtworkPalette.neutral.bindings;
    expect(bindings.keys, {
      'palette.dominant',
      'palette.vibrant',
      'palette.muted',
      'palette.darkMuted',
      'palette.lightMuted',
      'palette.onDominant',
    });
    for (final value in bindings.values) {
      expect(value, matches(RegExp(r'^#[0-9a-f]{6}$')));
    }
  });
}
