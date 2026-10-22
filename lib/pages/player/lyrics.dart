import 'package:auto_route/annotations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/button/back_button.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/utils/use_palette_color.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/pages/lyrics/plain_lyrics.dart';
import 'package:spotube/pages/lyrics/synced_lyrics.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';

@RoutePage()
class PlayerLyricsPage extends HookConsumerWidget {
  const PlayerLyricsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final activeTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    // The palette only needs a sample and is quantised on the UI isolate, so
    // it reads the smallest rendition instead of the full-size cover.
    String paletteArt = useMemoized(
      () => (activeTrack?.album.images).smallest(ImagePlaceholder.albumArt),
      [activeTrack?.album.images],
    );
    final selectedIndex = useState(0);
    // The Plain tab is one giant, non-lazy `SelectableText` — see the note in
    // `lib/pages/lyrics/lyrics.dart`: it only enters the tree once it has
    // been asked for, so opening this sheet does not lay out a paragraph as
    // tall as the whole lyric file.
    final plainRequested = useState(false);
    final palette = usePaletteColor(paletteArt, ref);

    final tabbar = TabList(
      index: selectedIndex.value,
      onChanged: (index) {
        selectedIndex.value = index;
        if (index == 1) plainRequested.value = true;
      },
      children: [
        TabItem(
          child: Text(context.l10n.synced),
        ),
        TabItem(
          child: Text(context.l10n.plain),
        ),
      ],
    );

    return Scaffold(
      headers: [
        AppBar(
          leading: [tabbar],
          trailing: const [
            BackButton(icon: SpotubeIcons.angleDown),
          ],
        ),
      ],
      child: IndexedStack(
        index: selectedIndex.value,
        children: [
          // No artwork backdrop on this page by design: palette text
          // over a plain surface risks unreadable contrast, so theme
          // roles apply unconditionally here.
          SyncedLyrics(palette: palette, isModal: false, hasArtwork: false),
          // Built on demand — see [plainRequested].
          if (plainRequested.value)
            PlainLyrics(palette: palette, isModal: false, hasArtwork: false)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
