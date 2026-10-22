import 'dart:typed_data';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:spotube/utils/service_utils.dart';

final _paletteColorState = StateProvider<PaletteColor>(
  (ref) {
    return PaletteColor(Colors.gray[300], 0);
  },
);

/// Side of the square bitmap the palette is computed from.
///
/// The quantizer walks every pixel it is handed, on the UI isolate, so this
/// is the knob that decides what a palette costs: a 640x640 cover spends
/// ~81 ms of pure quantizer time on a desktop host (and proportionally more
/// on a phone), while a 50x50 sample spends ~2 ms.
const _paletteSampleSide = 50.0;

/// The provider the palette is computed from: the artwork, downscaled by the
/// decode itself to [_paletteSampleSide].
///
/// Public so the sample size is pinned by a test rather than by a comment -
/// the whole point of the downscale is that the quantizer never sees the
/// full-size cover.
ImageProvider paletteSampleProvider(Uint8List bytes) => ResizeImage(
      MemoryImage(bytes),
      width: _paletteSampleSide.toInt(),
      height: _paletteSampleSide.toInt(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );

/// Builds a palette for [imageUrl] from bytes this app already holds whenever
/// possible.
///
/// Previously every `imageUrl` change re-fetched and re-decoded the full
/// image through a fresh `CachedNetworkImageProvider`, even when the download
/// worker or the playback cache had just fetched the same URL — and a rapid
/// track change let a stale fetch overwrite the current track's color through
/// the shared [_paletteColorState] slot. Now the bytes come from the shared
/// [ServiceUtils.artworkBytes] memo (one fetch per URL), the bitmap is
/// downscaled to [_paletteSampleSide] *before* it is quantised, and a
/// superseded fetch returns null instead of publishing.
Future<PaletteGenerator?> _generatePalette(
  String imageUrl,
  bool Function() isCancelled,
) async {
  final bytes = await ServiceUtils.artworkBytes(imageUrl);
  if (isCancelled() || bytes == null || bytes.isEmpty) return null;
  // The artwork has to be downscaled by the decode itself: `MemoryImage`
  // ignores the `size:` hint below (it decodes at the bytes' native
  // resolution), and the quantizer then walks every pixel of whatever it is
  // handed. Resizing first is what keeps the quantizer off the full-size
  // cover - the palette is a background tint, so a 50px sample is plenty.
  final palette = await PaletteGenerator.fromImageProvider(
    paletteSampleProvider(bytes),
    size: const Size(_paletteSampleSide, _paletteSampleSide),
  );
  if (isCancelled()) return null;
  return palette;
}

PaletteColor usePaletteColor(String imageUrl, WidgetRef ref) {
  final context = useContext();
  final theme = Theme.of(context);
  final paletteColor = ref.watch(_paletteColorState);

  useEffect(() {
    var cancelled = false;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      final palette = await _generatePalette(imageUrl, () => cancelled);
      if (palette == null || cancelled || !context.mounted) return;
      final color = theme.brightness == Brightness.light
          ? palette.lightMutedColor ?? palette.lightVibrantColor
          : palette.darkMutedColor ?? palette.darkVibrantColor;
      if (color != null) {
        ref.read(_paletteColorState.notifier).state = color;
      }
    });
    return () => cancelled = true;
  }, [imageUrl]);

  return paletteColor;
}

PaletteGenerator usePaletteGenerator(String imageUrl) {
  final palette = useState(PaletteGenerator.fromColors([]));
  final context = useContext();

  useEffect(() {
    var cancelled = false;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      final generated = await _generatePalette(imageUrl, () => cancelled);
      if (generated == null || cancelled || !context.mounted) return;
      palette.value = generated;
    });
    return () => cancelled = true;
  }, [imageUrl]);

  return palette.value;
}
