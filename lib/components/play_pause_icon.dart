import 'package:flutter/material.dart';
import 'package:spotube/collections/spotube_icons.dart';

/// A play/pause icon that cross-fades (and slightly scales) when the state
/// flips.
///
/// The play and pause glyphs are two different [Icon] widgets, so
/// [AnimatedSwitcher] genuinely transitions between them — a bare
/// `Icon(icon: playing ? pause : play)` snaps with no motion at all, which
/// is what made the icon look "stuck" when playback was paused from
/// somewhere else.
class AnimatedPlayPauseIcon extends StatelessWidget {
  /// Whether the audio is currently sounding.
  final bool isPlaying;

  final double? size;
  final Color? color;

  /// How long the transition takes.
  final Duration duration;

  const AnimatedPlayPauseIcon({
    super.key,
    required this.isPlaying,
    this.size,
    this.color,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: Icon(
        isPlaying ? SpotubeIcons.pause : SpotubeIcons.play,
        size: size,
        color: color,
        // Distinct key per state, so the switcher always animates instead
        // of reusing the previous element.
        key: ValueKey(isPlaying),
      ),
    );
  }
}
