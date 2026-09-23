import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/utils/use_palette_color.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/pages/lyrics/plain_lyrics.dart';
import 'package:spotube/pages/lyrics/synced_lyrics.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/provider/scroll_motion.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class LyricsPage extends HookConsumerWidget {
  static const name = "lyrics";

  const LyricsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final activeTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    final images = activeTrack?.album.images;
    final hasArtwork = images != null && images.isNotEmpty;
    String albumArt = useMemoized(
      () => (activeTrack?.album.images).asUrlString(
        index: (activeTrack?.album.images.length ?? 1) - 1,
        placeholder: ImagePlaceholder.albumArt,
      ),
      [activeTrack?.album.images],
    );
    final palette = usePaletteColor(albumArt, ref);
    final selectedIndex = useState(0);

    Widget tabbar = Padding(
      padding: const EdgeInsets.all(10),
      child: Tabs(
        index: selectedIndex.value,
        onChanged: (index) => selectedIndex.value = index,
        children: [
          TabItem(child: Text(context.l10n.synced)),
          TabItem(child: Text(context.l10n.plain)),
        ],
      ),
    );

    tabbar = Row(
      children: [
        tabbar,
        const Spacer(),
        Consumer(
          builder: (context, ref, child) {
            final activeTrackForProvider = ref.watch(
              audioPlayerProvider.select((s) => s.activeTrack),
            );
            final lyric = ref.watch(syncedLyricsProvider(activeTrackForProvider));
            final providerName = lyric.asData?.value.provider;

            if (providerName == null) {
              return const SizedBox.shrink();
            }

            return Align(
              alignment: Alignment.bottomRight,
              child: Text(context.l10n.powered_by_provider(providerName)),
            );
          },
        ),
        const Gap(5),
      ],
    );

    // The backdrop covers the whole page, but the provider's cache key
    // includes the decode size — rounding the window up in steps keeps a
    // resize from re-decoding for every pixel it moves.
    final backdropSide =
        (MediaQuery.sizeOf(context).longestSide / 256).ceilToDouble() * 256;

    return SafeArea(
      bottom: false,
      child: Scaffold(
        floatingHeader: true,
        headers: [
          !kIsMacOS
              ? TitleBar(
                  backgroundColor: Colors.transparent,
                  title: tabbar,
                  height: 58 * context.theme.scaling,
                  surfaceBlur: 0,
                  automaticallyImplyLeading: false,
                )
              : tabbar
        ],
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            image: hasArtwork
                ? DecorationImage(
                    image: UniversalImage.imageProvider(
                      albumArt,
                      width: backdropSide,
                      height: backdropSide,
                    ),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            // Frozen while the lyrics scroll (sigma 0 draws plain until
            // settle); blur and opacity at rest are unchanged.
            surfaceBlur:
                ref.watch(scrollInFlightProvider) ? 0 : context.theme.surfaceBlur,
            surfaceOpacity: context.theme.surfaceOpacity,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.zero,
            borderWidth: 0,
            child: ColoredBox(
              color: hasArtwork
                  ? palette.color.withValues(alpha: .7)
                  : Colors.transparent,
              child: SafeArea(
                child: IndexedStack(
                  index: selectedIndex.value,
                  children: [
                    SyncedLyrics(
                      palette: palette,
                      isModal: false,
                      hasArtwork: hasArtwork,
                    ),
                    PlainLyrics(
                      palette: palette,
                      isModal: false,
                      hasArtwork: hasArtwork,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
