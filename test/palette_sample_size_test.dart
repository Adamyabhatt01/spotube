// What the artwork palette costs.
//
// The quantiser walks every pixel it is handed, on the UI isolate, so the
// size of the bitmap it is given is the whole cost of a palette. The code
// claimed a "50px sample"; it was not one - `MemoryImage` ignores the
// `size:` hint `PaletteGenerator` is given, so the artwork was decoded at its
// native size and every pixel of it was walked.
//
// Measured quantiser cost alone (host, JIT, warmed): 50x50 -> 2 ms,
// 300x300 -> 19 ms, 640x640 -> 81 ms. A phone CPU is several times slower,
// and this ran on the UI isolate on every artwork change while the lyrics
// page was open.
//
// The assertion is structural rather than a wall-clock time (a timing
// assertion would be flaky): the sample must be produced by the *decode*, at
// 50 px, so the quantiser never sees the full-size cover.
//
// The bitmap itself cannot be decoded in the test environment (there is no
// image codec there), so the sample is pinned through the provider that
// carries it.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/hooks/utils/use_palette_color.dart';

void main() {
  test('the palette sample is a 50px bitmap, not the full-size cover', () {
    final provider = paletteSampleProvider(Uint8List(0));

    expect(
      provider,
      isA<ResizeImage>(),
      reason: 'the sample has to be produced by the decode: `MemoryImage` '
          'ignores the `size:` hint `PaletteGenerator` is given, so the cover '
          'would be decoded at its native size and every pixel quantised',
    );

    final resize = provider as ResizeImage;
    expect(resize.width, 50);
    expect(resize.height, 50);
    expect(
      resize.allowUpscaling,
      isFalse,
      reason: 'a cover smaller than the sample must not be blown up',
    );
  });
}
