import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/image/frosted_artwork.dart';
import 'package:spotube/utils/platform.dart';

/// A valid 1x1 transparent PNG: the decoration has to decode for the subtree
/// to build the way it does in the app, and a failing load would be reported
/// as an unhandled image error rather than passing silently.
final _artwork = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
  ),
);

void main() {
  testWidgets('FrostedArtwork leaves the non-self-frosting platforms alone', (
    tester,
  ) async {
    // `kIsAndroid` is a top-level final over `Platform.isAndroid`, so this
    // asserts the branch the host actually runs: everywhere that is not Android
    // must keep handing the cover to a plain `DecoratedBox` and leave the blur
    // to the panel above it. The Android branch is verified on device, which is
    // the convention `test/yt_dlp_android_exec_test.dart` already follows.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FrostedArtwork(
            image: _artwork,
            borderRadius: BorderRadius.circular(12),
            sigma: 10,
            child: const SizedBox(height: 200, width: 200),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DecoratedBox), findsWidgets);
    if (!kIsAndroid) {
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    }
  });

  testWidgets('a zero or absent sigma bakes no blur', (tester) async {
    for (final sigma in [0.0, null]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: FrostedArtwork(
              image: _artwork,
              borderRadius: BorderRadius.circular(12),
              sigma: sigma,
              child: const SizedBox(height: 200, width: 200),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ImageFiltered),
        findsNothing,
        reason: 'sigma=$sigma means there is no frost to bake into the image',
      );
    }
  });

  test('the frost decision is one place', () {
    // The callers read `artworkIsSelfFrosted` rather than `kIsAndroid` so that
    // "does this platform frost its own artwork" has a single expression.
    expect(artworkIsSelfFrosted, kIsAndroid);
  });
}
