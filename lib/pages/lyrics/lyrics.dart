import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/image/frosted_artwork.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/utils/use_palette_color.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
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
    // The backdrop wants the biggest rendition; the palette only needs a
    // sample, and it is quantised on the UI isolate - so it gets the smallest
    // one instead of pulling (and decoding) the full-size cover a second time.
    String paletteArt = useMemoized(
      () => (activeTrack?.album.images).smallest(ImagePlaceholder.albumArt),
      [activeTrack?.album.images],
    );
    final palette = usePaletteColor(paletteArt, ref);
    final selectedIndex = useState(0);

    // The Plain tab is one giant, non-lazy `SelectableText`: laying it out
    // costs a paragraph as tall as the whole lyric file, for a tab the user
    // may never open. `IndexedStack` lays out every child it holds, and
    // Flutter has no "mounted but never laid out" primitive (`Offstage` lays
    // its child out with the same constraints), so the Plain tab only enters
    // the tree once it has been asked for. It stays there afterwards, so
    // switching back and forth never re-pays that layout.
    final plainRequested = useState(false);
    final hasLyricsHeader = themeUiSlotExists(ref, 'lyrics.header');
    final hasLyricsAfterTabs = themeUiSlotExists(ref, 'lyrics.after_tabs');

    Widget tabbar = Padding(
      padding: const EdgeInsets.all(10),
      child: Tabs(
        index: selectedIndex.value,
        onChanged: (index) {
          selectedIndex.value = index;
          if (index == 1) plainRequested.value = true;
        },
        children: [
          TabItem(child: Text(context.l10n.synced)),
          TabItem(child: Text(context.l10n.plain)),
        ],
      ),
    );

    tabbar = Row(
      children: [
        tabbar,
        // The tabs keep their natural width and the attribution takes what is
        // left, right-aligned. A `Spacer` plus a non-flexible `Text` overflowed
        // this row by 33px on a phone-width page and pushed the label off the
        // screen.
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final activeTrackForProvider = ref.watch(
                audioPlayerProvider.select((s) => s.activeTrack),
              );
              final lyric =
                  ref.watch(syncedLyricsProvider(activeTrackForProvider));
              final providerName = lyric.asData?.value.provider;

              if (providerName == null) {
                return const SizedBox.shrink();
              }

              return Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  context.l10n.powered_by_provider(providerName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              );
            },
          ),
        ),
        const Gap(5),
      ],
    );

    // The backdrop covers the whole page, but the provider's cache key
    // includes the decode size — rounding the window up in steps keeps a
    // resize from re-decoding for every pixel it moves.
    //
    // Where the artwork frosts itself it is only ever seen through that blur
    // (and behind a translucent panel), so a screen-sized decode buys
    // nothing: the same picture at a fraction of the size is
    // indistinguishable under a sigma-10 blur, at a fraction of the decode
    // time and the texture memory. Where the artwork is shown as it is, it
    // keeps the full window.
    final frost = context.theme.surfaceBlur;
    final backdropSide = artworkIsSelfFrosted && frost != null && frost > 0
        ? 512.0
        : (MediaQuery.sizeOf(context).longestSide / 256).ceilToDouble() * 256;

    final panel = SurfaceCard(
      // Where the artwork frosts itself there is no backdrop left for this card
      // to sample, and no scroll worth freezing for. Elsewhere the blur is
      // frozen while the lyrics scroll (sigma 0 draws plain until settle); blur
      // and opacity at rest are unchanged.
      surfaceBlur: artworkIsSelfFrosted
          ? 0.0
          : ref.watch(scrollInFlightProvider)
              ? 0.0
              : context.theme.surfaceBlur,
      surfaceOpacity: context.theme.surfaceOpacity,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.zero,
      borderWidth: 0,
      child: ColoredBox(
        color:
            hasArtwork ? palette.color.withValues(alpha: .7) : Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              if (hasLyricsHeader)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ThemeSlot(
                    'lyrics.header',
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
                ),
              if (hasLyricsAfterTabs)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ThemeSlot(
                    'lyrics.after_tabs',
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: selectedIndex.value,
                  children: [
                    SyncedLyrics(
                      palette: palette,
                      isModal: false,
                      hasArtwork: hasArtwork,
                    ),
                    // Built on demand — see [plainRequested].
                    if (plainRequested.value)
                      PlainLyrics(
                        palette: palette,
                        isModal: false,
                        hasArtwork: hasArtwork,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

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
          margin: const EdgeInsets.only(bottom: 10),
          child: hasArtwork
              ? FrostedArtwork(
                  image: UniversalImage.imageProvider(
                    albumArt,
                    width: backdropSide,
                    height: backdropSide,
                  ),
                  borderRadius: BorderRadius.zero,
                  sigma: frost,
                  child: panel,
                )
              : panel,
        ),
      ),
    );
  }
}
