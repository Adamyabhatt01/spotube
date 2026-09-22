import 'dart:math' as math;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/duration.dart';
import 'package:spotube/modules/player/use_progress.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

/// Everything a seek row gives up before the bar starts, so the row cannot
/// overflow: its two labels, its gutters, and the inset the player's card puts
/// around it.
///
/// A footer cannot measure the width it was given — that needs a
/// `LayoutBuilder`, and no subtree of the scaffold footer may contain one (see
/// `test/player_progress_intrinsic_test.dart`). The window width is the only
/// bound it can read, so this overshoots and leaves the difference as slack in
/// the row's `spaceBetween` gaps.
const double _progressRowAllowance = 216;

/// The side padding the row puts between itself and the player's edge.
const double kProgressRowGutter = 14;

/// The two time labels get a fixed width rather than whatever their glyphs
/// happen to need: the row's arithmetic has to close without measuring them.
const double _progressTimeLabelWidth = 64;

/// The bar's share of the row.
double progressSeekBarWidth(double availableWidth, double scaling) {
  final leftover = availableWidth - _progressRowAllowance * scaling;
  // Never let the floor exceed the window, or clamp() gets an inverted range.
  return leftover
      .clamp(math.min(140.0, availableWidth), availableWidth)
      .toDouble();
}

/// Where the listener wants the playhead, as a fraction of the track.
typedef SeekToPosition = void Function(double fraction);

/// The seek bar and its two time labels, in either shape a theme can ask for.
///
/// [inline] is Spotube's own: a fixed-width bar over the transport controls with
/// the elapsed and remaining times underneath. `false` is the
/// `progress: "below"` shape — the bar stretched across the player with the
/// times at its ends.
///
/// Pure layout, no providers, which is what lets
/// `test/player_progress_intrinsic_test.dart` put the real widget into a real
/// `Scaffold` footer and ask it the question shadcn will ask.
class PlayerSeekLine extends StatelessWidget {
  final bool inline;
  final double value;
  final double buffered;
  final String elapsed;
  final String total;
  final bool enabled;
  final SeekToPosition onScrub;
  final SeekToPosition onSeek;

  const PlayerSeekLine({
    required this.inline,
    required this.value,
    required this.buffered,
    required this.elapsed,
    required this.total,
    required this.enabled,
    required this.onScrub,
    required this.onSeek,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaling = theme.scaling;

    final slider = Slider(
      hintValue: SliderValue.single(buffered),
      value: SliderValue.single(value),
      onChanged: enabled ? (v) => onScrub(v.value) : null,
      onChangeEnd: (value) => onSeek(value.value),
    );

    Text time(String label, {TextAlign? align}) => Text(
          label,
          style: theme.typography.xSmall,
          maxLines: 1,
          textAlign: align,
        );

    if (!inline) {
      final width = MediaQuery.sizeOf(context).width;
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: kProgressRowGutter * scaling,
          vertical: 6 * scaling,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: _progressTimeLabelWidth * scaling,
              child: time(elapsed),
            ),
            SizedBox(
              height: 16 * scaling,
              width: progressSeekBarWidth(width, scaling),
              child: slider,
            ),
            SizedBox(
              width: _progressTimeLabelWidth * scaling,
              child: time(total, align: TextAlign.end),
            ),
          ],
        ),
      );
    }

    final mediaQuery = MediaQuery.sizeOf(context);
    return Column(
      children: [
        Tooltip(
          tooltip: TooltipContainer(
            child: Text(context.l10n.slide_to_seek),
          ).call,
          child: SizedBox(
            width: mediaQuery.xlAndUp ? 600 : 500,
            child: slider,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              time(elapsed),
              time(total),
            ],
          ),
        ),
      ],
    );
  }
}

/// The seek bar, reading its own position from the player.
///
/// The transport column used to grow this inline; a theme that asks for
/// `progress: "below"` gets [PlayerSeekLine] in the non-inline shape instead,
/// placed by whoever owns the player.
class PlayerProgress extends HookConsumerWidget {
  final bool inline;

  const PlayerProgress({required this.inline, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final (:bufferProgress, :duration, :position, :progressStatic) =
        useProgress(ref);

    // The scrub value is local while the thumb is moving, and follows the
    // player again whenever the real position advances underneath it.
    final progress = useState<num>(useMemoized(() => progressStatic, []));

    useEffect(() {
      progress.value = progressStatic;
      return null;
    }, [progressStatic]);

    return PlayerSeekLine(
      inline: inline,
      value: progress.value.toDouble(),
      buffered: bufferProgress,
      elapsed: position.toHumanReadableString(),
      total: duration.toHumanReadableString(),
      enabled: !isFetchingActiveTrack,
      onScrub: (fraction) => progress.value = fraction,
      onSeek: (fraction) async {
        await audioPlayer.seek(
          Duration(seconds: (fraction * duration.inSeconds).toInt()),
        );
      },
    );
  }
}
