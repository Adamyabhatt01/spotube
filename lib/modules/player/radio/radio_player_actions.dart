import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/radio_playback.dart';

/// The radio player's settings menu — the counterpart to the music player's
/// [PlayerActions], but exposing only live-stream options (no queue, lyrics,
/// download or sleep timer). A popover on desktop, a bottom sheet on mobile.
class RadioPlayerActions extends ConsumerWidget {
  const RadioPlayerActions({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final station = ref.watch(
      radioPlaybackControllerProvider.select((s) => s.activeStation),
    );
    if (station == null) return const SizedBox.shrink();

    final controller = ref.read(radioPlaybackControllerProvider.notifier);
    final favorited =
        ref.watch(radioFavoriteKeysProvider).contains(station.favoriteKey);

    final detail = [
      if (station.codec case final String c when c.isNotEmpty) 'Codec: $c',
      if (station.bitrate case final int b when b > 0) 'Bitrate: ${b}kbps',
      if (station.country case final String country
          when country.isNotEmpty)
        'Country: $country',
    ].join('  ·  ');

    return AdaptivePopSheetList<String>(
      tooltip: 'Radio options',
      icon: const Icon(SpotubeIcons.moreVertical),
      items: (context) => [
        AdaptiveMenuButton<String>(
          leading: Icon(
            favorited ? SpotubeIcons.heartFilled : SpotubeIcons.heart,
          ),
          onPressed: (_) => ref.read(radioFavoritesProvider.notifier).toggle(station),
          child: Text(favorited ? 'Remove from favorites' : 'Add to favorites'),
        ),
        AdaptiveMenuButton<String>(
          leading: const Icon(SpotubeIcons.radio),
          onPressed: (_) => context.navigateTo(const RadioRoute()),
          child: const Text('Open Radio'),
        ),
        if (detail.isNotEmpty)
          AdaptiveMenuButton<String>(
            value: 'details',
            enabled: false,
            child: Text(detail),
          ),
        AdaptiveMenuButton<String>(
          leading: const Icon(SpotubeIcons.connect),
          onPressed: (_) {
            Clipboard.setData(ClipboardData(text: station.streamUrl));
          },
          child: const Text('Copy stream URL'),
        ),
        AdaptiveMenuButton<String>(
          leading: const Icon(SpotubeIcons.stop),
          onPressed: (_) => controller.stop(),
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
