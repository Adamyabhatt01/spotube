import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'package:flutter/painting.dart'
    show HSLColor, ImageProvider, MemoryImage, ResizeImage, ResizeImagePolicy;
import 'package:palette_generator/palette_generator.dart';
import 'package:spotube/utils/service_utils.dart';

/// Side of the square bitmap the palette is computed from.
///
/// The quantizer walks every pixel it is handed, on the UI isolate, so this
/// is the knob that decides what a palette costs: a 640x640 cover spends
/// ~81 ms of pure quantizer time on a desktop host (and proportionally more
/// on a phone), while a 50x50 sample spends ~2 ms.
const themeUiPaletteSampleSide = 50.0;

/// The provider the palette is computed from: the artwork, downscaled by the
/// decode itself to [themeUiPaletteSampleSide].
///
/// `MemoryImage` ignores a `size:` hint, so the only way to keep the
/// quantizer off the full-size cover is to resize in the decode.
ImageProvider themeUiPaletteSampleProvider(Uint8List bytes) => ResizeImage(
      MemoryImage(bytes),
      width: themeUiPaletteSampleSide.toInt(),
      height: themeUiPaletteSampleSide.toInt(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );

/// The six colours a theme may bind to for one piece of artwork.
///
/// Values are concrete: a theme can write `@palette.dominant` without a null
/// check, and a cover the generator cannot classify still yields a stable
/// neutral palette instead of dropping the gradient. [bindings] is the
/// `palette.*` namespace the node renderer reads.
class ArtworkPalette {
  final Color dominant;
  final Color vibrant;
  final Color muted;
  final Color darkMuted;
  final Color lightMuted;
  final Color onDominant;

  const ArtworkPalette({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.darkMuted,
    required this.lightMuted,
    required this.onDominant,
  });

  /// The neutral a missing or unreadable artwork resolves to.
  static const neutral = ArtworkPalette(
    dominant: Color(0xFF9E9E9E),
    vibrant: Color(0xFF9E9E9E),
    muted: Color(0xFF9E9E9E),
    darkMuted: Color(0xFF616161),
    lightMuted: Color(0xFFE0E0E0),
    onDominant: Color(0xFFFFFFFF),
  );

  factory ArtworkPalette.fromGenerator(PaletteGenerator palette) {
    // `palette_generator` can return null for any role on a low-contrast
    // cover. Fall back along the strongest-to-weakest chain rather than
    // publishing gaps: a missing `darkMuted` used to be the difference
    // between a gradient and a transparent box.
    final dominant = palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        palette.mutedColor?.color ??
        neutral.dominant;
    final vibrant = palette.vibrantColor?.color ?? dominant;
    final muted = palette.mutedColor?.color ?? dominant;
    final darkMuted = palette.darkMutedColor?.color ??
        palette.darkVibrantColor?.color ??
        _darken(dominant);
    final lightMuted = palette.lightMutedColor?.color ??
        palette.lightVibrantColor?.color ??
        _lighten(dominant);

    return ArtworkPalette(
      dominant: dominant,
      vibrant: vibrant,
      muted: muted,
      darkMuted: darkMuted,
      lightMuted: lightMuted,
      onDominant: _readableOn(dominant),
    );
  }

  /// `palette.*` bindings, as the hex strings the node renderer parses.
  Map<String, String> get bindings => {
        'palette.dominant': _hex(dominant),
        'palette.vibrant': _hex(vibrant),
        'palette.muted': _hex(muted),
        'palette.darkMuted': _hex(darkMuted),
        'palette.lightMuted': _hex(lightMuted),
        'palette.onDominant': _hex(onDominant),
      };
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Color _readableOn(Color background) => background.computeLuminance() > 0.5
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

Color _darken(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
}

Color _lighten(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + 0.28).clamp(0.0, 1.0)).toColor();
}

typedef ArtworkPaletteExtractor = Future<ArtworkPalette?> Function(String url);

/// Computes the palette of one artwork URL.
///
/// Bytes come from the shared artwork memo (one fetch per URL) and the
/// bitmap is downscaled by the decode before it is quantised. A failed fetch
/// or decode is "no palette", never an exception the caller has to handle.
Future<ArtworkPalette?> extractArtworkPalette(String url) async {
  final Uint8List? bytes;
  try {
    bytes = await ServiceUtils.artworkBytes(url);
  } catch (_) {
    return null;
  }
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      themeUiPaletteSampleProvider(bytes),
      size: const Size(
        themeUiPaletteSampleSide,
        themeUiPaletteSampleSide,
      ),
    );
    return ArtworkPalette.fromGenerator(palette);
  } catch (_) {
    return null;
  }
}

/// URL-keyed LRU of artwork palettes.
///
/// Replaces the single shared colour slot the lyrics page used to write to:
/// keying by URL means two widgets showing different covers cannot overwrite
/// each other's colour, and an in-flight fetch for a track the user already
/// skipped past cannot publish over the current one. The cache is capped so
/// a long session cannot grow it without bound.
///
/// [changes] emits the revision after an entry is stored, which is what lets
/// a slot rebuild once a palette it asked for arrives without polling.
class ArtworkPaletteCache {
  static const defaultMaxEntries = 32;

  final int maxEntries;
  final ArtworkPaletteExtractor _extractor;
  final LinkedHashMap<String, ArtworkPalette> _entries = LinkedHashMap();
  final Map<String, Future<ArtworkPalette?>> _inFlight = {};
  final StreamController<int> _changes = StreamController<int>.broadcast();
  int _revision = 0;
  bool _disposed = false;

  ArtworkPaletteCache({
    ArtworkPaletteExtractor? extractor,
    this.maxEntries = defaultMaxEntries,
  }) : _extractor = extractor ?? extractArtworkPalette;

  Stream<int> get changes => _changes.stream;

  int get length => _entries.length;

  Iterable<String> get urls => _entries.keys;

  /// The cached palette for [url], or null when it has not been extracted.
  ///
  /// A hit refreshes the entry's LRU position.
  ArtworkPalette? operator [](String? url) {
    if (url == null || url.isEmpty) return null;
    final cached = _entries.remove(url);
    if (cached == null) return null;
    _entries[url] = cached;
    return cached;
  }

  /// Extracts [url] once and stores the result.
  ///
  /// Concurrent callers share one extraction. A caller that is no longer
  /// interested passes [isCancelled] and gets null instead of the late
  /// result; the palette may still be stored for whoever asked first, which
  /// is safe because the entry is keyed by the URL it belongs to.
  Future<ArtworkPalette?> load(
    String url, {
    bool Function()? isCancelled,
  }) {
    if (_disposed) return Future.value(null);
    final key = url.trim();
    if (key.isEmpty || (isCancelled?.call() ?? false)) {
      return Future.value(null);
    }

    final cached = this[key];
    if (cached != null) return Future.value(cached);

    final existing = _inFlight[key];
    if (existing != null) return _resolve(existing, isCancelled);

    // Block body, not an arrow: `remove` returns the future being tracked and
    // `whenComplete` would wait on it, deadlocking this completion.
    final future = _extract(key).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return _resolve(future, isCancelled);
  }

  Future<ArtworkPalette?> _resolve(
    Future<ArtworkPalette?> future,
    bool Function()? isCancelled,
  ) async {
    final palette = await future;
    if (palette == null || (isCancelled?.call() ?? false)) return null;
    return palette;
  }

  Future<ArtworkPalette?> _extract(String url) async {
    ArtworkPalette? palette;
    try {
      palette = await _extractor(url);
    } catch (_) {
      palette = null;
    }
    if (palette == null || _disposed) return null;
    _store(url, palette);
    return palette;
  }

  void _store(String url, ArtworkPalette palette) {
    _entries.remove(url);
    _entries[url] = palette;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    if (!_changes.isClosed) _changes.add(++_revision);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inFlight.clear();
    _entries.clear();
    await _changes.close();
  }
}
