import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/lyrics/zoom_controls.dart';
import 'package:spotube/components/shimmers/shimmer_lyrics.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';

import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/lyrics/synced.dart';

class PlainLyrics extends HookConsumerWidget {
  final PaletteColor palette;
  final bool? isModal;
  final int defaultTextZoom;

  /// Whether an artwork backdrop sits behind the lyrics. Palette text
  /// is only used over real artwork; otherwise theme roles apply so
  /// text stays readable on plain surfaces.
  final bool hasArtwork;

  const PlainLyrics({
    required this.palette,
    required this.hasArtwork,
    this.isModal,
    this.defaultTextZoom = 100,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final activeTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    final lyricsQuery = ref.watch(syncedLyricsProvider(activeTrack));
    final mediaQuery = MediaQuery.of(context);
    final typography = Theme.of(context).typography;
    final colorScheme = Theme.of(context).colorScheme;

    final textZoomLevel = useState<int>(defaultTextZoom);

    // One pass over the lines, keyed on the query result. The previous version
    // looked each line's successor up with `elementAtOrNull(i + 1)` inside
    // `mapIndexed`, and `elementAtOrNull` walks `i + 1` elements to do it -
    // quadratic in the number of lines, re-run on every build (each zoom tap
    // rebuilds this page and rejoins the whole file).
    final joinedLyrics = useMemoized(() {
      final lines = lyricsQuery.asData?.value.lyrics;
      if (lines == null) return null;

      const verseGap = Duration(milliseconds: 700);
      final buffer = StringBuffer();
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) buffer.write("\n");
        buffer.write(lines[i].text);
        if (i + 1 < lines.length &&
            lines[i].time - lines[i + 1].time > verseGap) {
          buffer.write("\n");
        }
      }
      return buffer.toString();
    }, [lyricsQuery]);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isModal != true) ...[
              Center(
                child: Text(
                  activeTrack?.name ?? "",
                  style: mediaQuery.mdAndUp
                      ? typography.h3
                      : typography.h4.copyWith(
                          color: hasArtwork
                              ? palette.titleTextColor
                              : colorScheme.foreground,
                        ),
                ),
              ),
              Center(
                child: Text(
                  activeTrack?.artists.asString() ?? "",
                  style: (mediaQuery.mdAndUp ? typography.h4 : typography.large)
                      .copyWith(
                    color: hasArtwork
                        ? palette.bodyTextColor
                        : colorScheme.mutedForeground,
                  ),
                ),
              )
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Builder(
                      builder: (context) {
                        if (lyricsQuery.isLoading || lyricsQuery.isRefreshing) {
                          return const ShimmerLyrics();
                        } else if (lyricsQuery.hasError) {
                          return Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.l10n.no_lyrics_available,
                                  style: typography.large.copyWith(
                                    color: hasArtwork
                                        ? palette.bodyTextColor
                                        : colorScheme.mutedForeground,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const Gap(26),
                                const Icon(SpotubeIcons.noLyrics, size: 60),
                              ],
                            ),
                          );
                        }

                        return AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isModal == true || !hasArtwork
                                ? context.theme.colorScheme.foreground
                                : palette.bodyTextColor,
                            fontSize: 24 * textZoomLevel.value / 100,
                            height: textZoomLevel.value < 70
                                ? 1.5
                                : textZoomLevel.value > 150
                                    ? 1.7
                                    : 2,
                          ),
                          child: SelectableText(
                            joinedLyrics == null && activeTrack == null
                                ? context.l10n.no_tracks_playing
                                : joinedLyrics ?? "",
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: ZoomControls(
            value: textZoomLevel.value,
            onChanged: (value) => textZoomLevel.value = value,
            min: 50,
            max: 200,
          ),
        ),
      ],
    );
  }
}
