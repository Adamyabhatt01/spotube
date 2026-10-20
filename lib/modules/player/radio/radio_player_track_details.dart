import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';

/// Radio counterpart to [PlayerTrackDetails]: the live station's favicon, name
/// and a now-playing line, sized to match the music bar so switching sources
/// does not change the footer's height. Reads only the radio controller.
class RadioPlayerTrackDetails extends HookConsumerWidget {
  /// Edge length of the cover. The docked bar passes 80 (matching the music
  /// bar's artwork) and the mobile collapsed strip passes a smaller value so it
  /// fits the 63px mini-player.
  final double coverSize;
  final VoidCallback? onTap;

  const RadioPlayerTrackDetails({
    this.coverSize = 80,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final playback = ref.watch(radioPlaybackControllerProvider);
    final station = playback.activeStation;
    if (station == null) return const SizedBox.shrink();

    final secondary = radioStatusLine(playback);

    Widget content = Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: RadioStationCover(station: station, size: coverSize),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.small.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Gap(6),
                  _LivePill(state: _livePillState(playback)),
                ],
              ),
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.xSmall.copyWith(
                  color: playback.error != null
                      ? theme.colorScheme.destructive
                      : theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }
}

enum _PillState { live, connecting, paused, offline }

_PillState _livePillState(RadioPlaybackState s) {
  if (s.error != null) return _PillState.offline;
  if (s.buffering && !s.playing) return _PillState.connecting;
  if (s.playing) return _PillState.live;
  return _PillState.paused;
}

/// The now-playing second line: the live ICY title when present, otherwise a
/// status word, otherwise the station's own subtitle.
String radioStatusLine(RadioPlaybackState s) {
  if (s.error != null) return 'Station unavailable';
  if (s.liveTitle case final String title when title.isNotEmpty) return title;
  if (s.buffering && !s.playing) return 'Connecting…';
  if (!s.playing) return 'Paused';
  return s.activeStation?.subtitle ?? '';
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.state});

  final _PillState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      _PillState.live => ('LIVE', theme.colorScheme.destructive),
      _PillState.connecting => ('···', theme.colorScheme.mutedForeground),
      _PillState.paused => ('PAUSED', theme.colorScheme.mutedForeground),
      _PillState.offline => ('OFFLINE', theme.colorScheme.destructive),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: theme.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == _PillState.live) ...[
            Icon(SpotubeIcons.radio, size: 10, color: color),
            const Gap(3),
          ],
          Text(
            label,
            style: theme.typography.xSmall
                .copyWith(color: color, fontWeight: FontWeight.bold)
                .copyWith(fontSize: 10 * theme.scaling),
          ),
        ],
      ),
    );
  }
}
