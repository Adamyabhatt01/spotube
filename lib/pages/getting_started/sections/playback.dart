import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/ui/button_tile.dart';
import 'package:spotube/modules/getting_started/blur_card.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

class GettingStartedPagePlaybackSection extends HookConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const GettingStartedPagePlaybackSection({
    super.key,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context, ref) {
    final preferences = ref.watch(userPreferencesProvider);
    final preferencesNotifier = ref.read(userPreferencesProvider.notifier);

    return Center(
      child: BlurCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(SpotubeIcons.album, size: 16),
                const Gap(8),
                Text(context.l10n.playback).semiBold().large(),
              ],
            ),
            const Gap(16),
            ButtonTile(
              title: Text(context.l10n.endless_playback),
              subtitle: Text(
                context.l10n.endless_playback_description,
              ).small().muted(),
              onPressed: () {
                preferencesNotifier
                    .setEndlessPlayback(!preferences.endlessPlayback);
              },
              trailing: Switch(
                value: preferences.endlessPlayback,
                onChanged: (value) {
                  preferencesNotifier.setEndlessPlayback(value);
                },
              ),
            ),
            const Gap(34),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Button.secondary(
                  leading: const Icon(SpotubeIcons.angleLeft),
                  onPressed: onPrevious,
                  child: Text(context.l10n.previous),
                ),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Button.primary(
                    leading: const Icon(SpotubeIcons.angleRight),
                    onPressed: onNext,
                    child: Text(context.l10n.next),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
