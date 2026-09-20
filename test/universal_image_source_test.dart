import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/components/image/universal_image.dart';

/// 1x1 PNG.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<ui.Image> _decode(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    completer.complete(info.image);
  }, onError: (e, s) {
    stream.removeListener(listener);
    completer.completeError(e, s);
  });
  stream.addListener(listener);
  return completer.future;
}

Future<Uint8List> _solidPng(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File bigArt;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('spotube-universal-image');
    bigArt = File('${dir.path}/art.png')
      ..writeAsBytesSync(await _solidPng(1000));
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  group('source resolution', () {
    test('http url -> CachedNetworkImageProvider', () {
      expect(
        UniversalImage.imageProvider('https://i.scdn.co/image/abcv123'),
        isA<CachedNetworkImageProvider>(),
      );
    });

    test('assets/ path -> AssetImage', () {
      expect(
        UniversalImage.imageProvider('assets/images/placeholder.png'),
        isA<AssetImage>(),
      );
    });

    test('file path -> FileImage, ResizeImage-wrapped when sized', () {
      expect(
        UniversalImage.imageProvider(bigArt.path),
        isA<FileImage>(),
      );
      expect(
        UniversalImage.imageProvider(bigArt.path, width: 80, height: 80),
        isA<ResizeImage>(),
      );
    });

    test(
      'base64 payload resolves to a file provider, not MemoryImage',
      () {
        // Pinned deliberately: a bare base64 string is a valid relative URI,
        // so `Uri.tryParse(path) != null` wins and the MemoryImage branch is
        // unreachable. Nothing in-repo feeds base64 artwork here, so the
        // ordering is left as-is rather than silently re-routed.
        final provider = UniversalImage.imageProvider(
          base64Encode(_tinyPng),
          width: 48,
          height: 48,
        );
        expect(provider, isA<ResizeImage>());
        expect(
          (provider as ResizeImage).imageProvider,
          isA<FileImage>(),
          reason: 'base64 never reaches the MemoryImage branch',
        );
      },
    );
  });

  group('decode sizing', () {
    test('display dimensions bound the decoded bitmap', () async {
      final image = await _decode(
        UniversalImage.imageProvider(bigArt.path, width: 80, height: 80),
      );
      addTearDown(image.dispose);
      expect(image.width, 80);
      expect(image.height, 80);
    });

    test('an unsized request still decodes at native resolution', () async {
      final image = await _decode(UniversalImage.imageProvider(bigArt.path));
      addTearDown(image.dispose);
      expect(image.width, 1000);
      expect(image.height, 1000);
    });

    test('never upscales a smaller source', () async {
      final small = File('${dir.path}/small.png')
        ..writeAsBytesSync(_tinyPng);
      final image = await _decode(
        UniversalImage.imageProvider(small.path, width: 300, height: 300),
      );
      addTearDown(image.dispose);
      expect(image.width, 1);
      expect(image.height, 1);
    });
  });
}
