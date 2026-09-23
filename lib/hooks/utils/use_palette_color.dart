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

/// Builds a palette for [imageUrl] from bytes this app already holds whenever
/// possible.
///
/// Previously every `imageUrl` change re-fetched and re-decoded the full
/// image through a fresh `CachedNetworkImageProvider`, even when the download
/// worker or the playback cache had just fetched the same URL — and a rapid
/// track change let a stale fetch overwrite the current track's color through
/// the shared [_paletteColorState] slot. Now the bytes come from the shared
/// [ServiceUtils.artworkBytes] memo (one fetch per URL), the generator works
/// on a 50px sample instead of full resolution, and a superseded fetch
/// returns null instead of publishing.
Future<PaletteGenerator?> _generatePalette(
  String imageUrl,
  bool Function() isCancelled,
) async {
  final bytes = await ServiceUtils.artworkBytes(imageUrl);
  if (isCancelled() || bytes == null || bytes.isEmpty) return null;
  final palette = await PaletteGenerator.fromImageProvider(
    MemoryImage(bytes),
    size: const Size(50, 50),
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
