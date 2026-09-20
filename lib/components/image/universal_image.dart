import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spotube/collections/assets.gen.dart';

class UniversalImage extends HookWidget {
  final String path;
  final double? height;
  final double? width;
  final double scale;
  final String? placeholder;
  final BoxFit? fit;
  const UniversalImage({
    required this.path,
    this.height,
    this.width,
    this.placeholder,
    this.fit,
    this.scale = 1,
    super.key,
  });

  /// Bounded LRU cache of decoded base64 image bytes. Local-track embedded
  /// artwork can be full-resolution; decoding it on every widget build spikes
  /// CPU and RAM when scrolling long local-track lists. Bounded by total
  /// bytes (not entry count) so a few large artworks cannot accumulate
  /// unbounded memory.
  static final Map<String, Uint8List> _decodedMemoryCache = {};
  static const int _maxDecodedBytes = 24 * 1024 * 1024; // 24MB
  static int _decodedBytes = 0;

  static Uint8List _decodeMemory(String path) {
    final cached = _decodedMemoryCache.remove(path);
    if (cached != null) {
      _decodedMemoryCache[path] = cached;
      return cached;
    }

    final decoded = base64Decode(path);
    _decodedMemoryCache[path] = decoded;
    _decodedBytes += decoded.length;

    // Evict oldest entries until the total byte budget is respected.
    while (_decodedBytes > _maxDecodedBytes &&
        _decodedMemoryCache.isNotEmpty) {
      final oldest = _decodedMemoryCache.keys.first;
      final removed = _decodedMemoryCache.remove(oldest);
      if (removed != null) _decodedBytes -= removed.length;
    }

    return decoded;
  }

  static ImageProvider imageProvider(
    String path, {
    final double? height,
    final double? width,
    final double scale = 1,
  }) {
    if (path.startsWith("http")) {
      return CachedNetworkImageProvider(
        path,
        maxHeight: height?.toInt(),
        maxWidth: width?.toInt(),
        cacheKey: path,
        scale: scale,
      );
    } else if (path.startsWith("assets/")) {
      return AssetImage(path);
    } else if (Uri.tryParse(path) != null) {
      final fileImage = FileImage(File(path), scale: scale);
      // FileImage has no decode-size knob: an 80x80 request on a 1000x1000
      // sidecar used to put 4 MB in ImageCache instead of 25 kB.
      if (width == null && height == null) {
        return fileImage;
      }
      return ResizeImage(
        fileImage,
        width: width?.toInt(),
        height: height?.toInt(),
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );
    }
    // Decode at display size instead of full embedded-art resolution.
    final memoryImage = MemoryImage(_decodeMemory(path), scale: scale);
    if (width == null && height == null) {
      return memoryImage;
    }
    return ResizeImage(
      memoryImage,
      width: width?.toInt(),
      height: height?.toInt(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (path.startsWith("http")) {
      return FadeInImage(
        image: CachedNetworkImageProvider(
          path,
          maxHeight: height?.toInt(),
          maxWidth: width?.toInt(),
          cacheKey: path,
          scale: scale,
        ),
        height: height,
        width: width,
        placeholder: AssetImage(placeholder ?? Assets.images.placeholder.path),
        imageErrorBuilder: (context, error, stackTrace) {
          return Image.asset(
            placeholder ?? Assets.images.placeholder.path,
            width: width,
            height: height,
            cacheHeight: height?.toInt(),
            cacheWidth: width?.toInt(),
            scale: scale,
          );
        },
        fit: fit,
      );
    } else if (Uri.tryParse(path) != null && !path.startsWith("assets")) {
      return Image.file(
        File(path),
        width: width,
        height: height,
        cacheHeight: height?.toInt(),
        cacheWidth: width?.toInt(),
        scale: scale,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            placeholder ?? Assets.images.placeholder.path,
            width: width,
            height: height,
            cacheHeight: height?.toInt(),
            cacheWidth: width?.toInt(),
            scale: scale,
          );
        },
      );
    } else if (path.startsWith("assets")) {
      return Image.asset(
        path,
        width: width,
        height: height,
        cacheHeight: height?.toInt(),
        cacheWidth: width?.toInt(),
        scale: scale,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            placeholder ?? Assets.images.placeholder.path,
            width: width,
            height: height,
            cacheHeight: height?.toInt(),
            cacheWidth: width?.toInt(),
            scale: scale,
          );
        },
      );
    }

    return Image.memory(
      _decodeMemory(path),
      width: width,
      height: height,
      cacheHeight: height?.toInt(),
      cacheWidth: width?.toInt(),
      scale: scale,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          placeholder ?? Assets.images.placeholder.path,
          width: width,
          height: height,
          cacheHeight: height?.toInt(),
          cacheWidth: width?.toInt(),
          scale: scale,
        );
      },
    );
  }
}
