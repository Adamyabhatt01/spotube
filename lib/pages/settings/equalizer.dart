import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/button/back_button.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/modules/settings/equalizer/equalizer_curve_editor.dart';
import 'package:spotube/provider/audio_visualizer/audio_spectrum_provider.dart';
import 'package:spotube/provider/mono_audio_provider.dart';
import 'package:spotube/provider/spatial_audio_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/audio_visualizer/audio_spectrum.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class SettingsEqualizerPage extends StatelessWidget {
  static const name = "equalizer";

  const SettingsEqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: [
          TitleBar(
            leading: const [BackButton()],
            title: Text(context.l10n.audio_settings),
          ),
        ],
        child: const SettingsEqualizerView(),
      ),
    );
  }
}

/// The equalizer body without the route chrome, so it can be exercised
/// directly in widget tests.
class SettingsEqualizerView extends HookConsumerWidget {
  const SettingsEqualizerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(
      userPreferencesProvider.select((p) => (
            enabled: p.equalizerEnabled,
            preset: p.equalizerPreset,
            gains: p.equalizerGains,
            normalizeAudio: p.normalizeAudio,
          )),
    );
    final notifier = ref.read(userPreferencesProvider.notifier);
    final theme = Theme.of(context);
    final spatialAudio = ref.watch(spatialAudioProvider);
    final monoAudio = ref.watch(monoAudioProvider);

    // The drift emission creates a new list each time; key the memo on its
    // values so an unrelated preference write cannot reset the live draft.
    final gainsKey = preferences.gains.join(',');
    final persisted = useMemoized(
      () => EqualizerSettings.normalizeGains(preferences.gains),
      [gainsKey],
    );
    final draft = useState<List<double>>(persisted);
    final dragging = useRef(false);

    useEffect(() {
      if (!dragging.value) draft.value = persisted;
      return null;
    }, [persisted]);

    void resetAll() {
      dragging.value = false;
      draft.value = List<double>.filled(kEqualizerBandCount, 0);
      notifier.setEqualizerPreset(EqualizerPreset.flat);
    }

    void selectPreset(EqualizerPreset preset) {
      if (preset == EqualizerPreset.custom) return;
      dragging.value = false;
      draft.value = equalizerGainsForPreset(preset, current: draft.value);
      notifier.setEqualizerPreset(preset);
    }

    void updateBand(int index, double value) {
      dragging.value = true;
      final next = [...draft.value];
      next[index] = value;
      draft.value = next;
    }

    void commitBand(int index, double value) {
      dragging.value = false;
      final next = [...draft.value];
      next[index] = value;
      draft.value = next;
      // One write for the whole set: the effects listener rebuilds the mpv
      // filter chain once, not once per band.
      notifier.setEqualizerGains(next);
    }

    final bassStrength = preferences.enabled
        ? (draft.value.take(3).fold<double>(0, (a, b) => a + b) / 3 / 6)
            .clamp(0.0, 1.0)
        : 0.0;

    final presetTabs = _PresetTabs(
      preset: preferences.preset,
      onSelected: selectPreset,
    );

    final equalizerCard = Card(
      padding: EdgeInsets.all(16 * theme.scaling),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.equalizer,
                      style: theme.typography.large.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      context.l10n.equalizer_enable_description,
                      style: theme.typography.xSmall.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Switch(
                value: preferences.enabled,
                onChanged: notifier.setEqualizerEnabled,
              ),
            ],
          ),
          const Gap(16),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.muted.withValues(alpha: 0.22),
                  theme.colorScheme.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: theme.borderRadiusLg,
              border: Border.all(
                color: theme.colorScheme.border.withValues(
                  alpha: 0.55,
                ),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: EqualizerCurveEditor(
                        gains: draft.value,
                        bypassed: !preferences.enabled,
                        onChanged: updateBand,
                        onChangeEnd: commitBand,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 8,
                      child: _GraphStatus(
                        enabled: preferences.enabled,
                        preset: preferences.preset,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Tooltip(
                        tooltip: TooltipContainer(
                          child: Text(context.l10n.equalizer_reset),
                        ).call,
                        child: IconButton.ghost(
                          icon: const Icon(SpotubeIcons.refresh),
                          onPressed: resetAll,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(2),
                Text(
                  context.l10n.equalizer_drag_hint,
                  textAlign: TextAlign.center,
                  style: theme.typography.xSmall.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final effectTileList = [
      Tooltip(
        tooltip: TooltipContainer(
          child: Text(context.l10n.equalizer_preset_bass_boost),
        ).call,
        child: _EffectTile(
          icon: SpotubeIcons.equalizer,
          label: context.l10n.equalizer_preset_bass_boost,
          value: preferences.preset == EqualizerPreset.bassBoost,
          strength: bassStrength,
          onChanged: (enabled) {
            if (enabled) {
              selectPreset(EqualizerPreset.bassBoost);
            } else {
              resetAll();
            }
          },
        ),
      ),
      Tooltip(
        tooltip: TooltipContainer(
          child: Text(context.l10n.equalizer_loudness),
        ).call,
        child: _EffectTile(
          icon: SpotubeIcons.normalize,
          label: context.l10n.equalizer_loudness,
          value: preferences.normalizeAudio,
          strength: preferences.normalizeAudio ? 1 : 0,
          supported: kLibmpvSupportsDynaudnorm,
          onChanged: notifier.setNormalizeAudio,
        ),
      ),
      Tooltip(
        tooltip: TooltipContainer(
          child: Text(context.l10n.equalizer_virtual_surround),
        ).call,
        child: _EffectTile(
          icon: SpotubeIcons.surround,
          label: context.l10n.equalizer_virtual_surround,
          value: spatialAudio,
          strength: spatialAudio ? 1 : 0,
          supported: kLibmpvSupportsSpatialAudio,
          onChanged: (enabled) =>
              ref.read(spatialAudioProvider.notifier).setEnabled(enabled),
        ),
      ),
      Tooltip(
        tooltip: TooltipContainer(
          child: Text(context.l10n.equalizer_mono),
        ).call,
        child: _EffectTile(
          icon: SpotubeIcons.mono,
          label: context.l10n.equalizer_mono,
          value: monoAudio,
          strength: monoAudio ? 1 : 0,
          supported: kLibmpvSupportsMonoAudio,
          onChanged: (enabled) =>
              ref.read(monoAudioProvider.notifier).setEnabled(enabled),
        ),
      ),
    ];

    // Four tiles do not fit side by side on a phone. Keep the single row
    // where there is room and fall back to a 2x2 grid below that.
    final effectTiles = LayoutBuilder(
      builder: (context, constraints) {
        Widget row(List<Widget> tiles) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const Gap(12),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }

        if (constraints.maxWidth >= 640) {
          return row(effectTileList);
        }
        return Column(
          children: [
            row(effectTileList.sublist(0, 2)),
            const Gap(12),
            row(effectTileList.sublist(2)),
          ],
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the original single-column order, but stop capping it at
        // 620 px: that cap left ~1000 px of dead space in a 1920 px window.
        // 1600 px only guards very wide monitors; below it the column fills
        // the content area exactly like it does at half-screen widths.
        final maxContentWidth = math.min(
          math.max(constraints.maxWidth - 16, 0.0),
          1600.0,
        );

        // The floating player is painted over the page, so the last card needs
        // room to scroll clear of it instead of ending underneath the bar.
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return ListView(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    presetTabs,
                    const Gap(18),
                    equalizerCard,
                    const Gap(12),
                    const _VolumeCard(),
                    const Gap(12),
                    effectTiles,
                    const Gap(12),
                    const _VisualizerCard(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PresetTabs extends StatelessWidget {
  final EqualizerPreset preset;
  final ValueChanged<EqualizerPreset> onSelected;

  const _PresetTabs({
    required this.preset,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final candidate in EqualizerPreset.values)
            if (candidate != EqualizerPreset.custom)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Button(
                  key: ValueKey('equalizer-preset-${candidate.name}'),
                  style: ButtonVariance.link.copyWith(
                    padding: (context, states, style) =>
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    textStyle: (context, states, style) =>
                        theme.typography.small.copyWith(
                      color: preset == candidate
                          ? theme.colorScheme.primary
                          : theme.colorScheme.mutedForeground,
                      fontWeight: preset == candidate
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  onPressed: () => onSelected(candidate),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_presetLabel(context, candidate)),
                      const Gap(3),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        height: 2,
                        width: 16,
                        decoration: BoxDecoration(
                          color: preset == candidate
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (preset == EqualizerPreset.custom)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.equalizer_preset_custom,
                    style: theme.typography.small.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(3),
                  Container(
                    height: 2,
                    width: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small readout in the graph's top-left corner: bypass state or the active
/// preset. It replaces the old gain-axis labels, keeping the plot itself clean
/// like the reference.
class _GraphStatus extends StatelessWidget {
  final bool enabled;
  final EqualizerPreset preset;

  const _GraphStatus({required this.enabled, required this.preset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = !enabled
        ? context.l10n.equalizer_bypassed
        : preset == EqualizerPreset.custom
            ? context.l10n.equalizer_preset_custom
            : null;
    if (label == null) return const SizedBox.shrink();

    return Text(
      label,
      style: theme.typography.xSmall.copyWith(
        color: theme.colorScheme.mutedForeground,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _VolumeCard extends ConsumerWidget {
  const _VolumeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final volume = ref.watch(volumeProvider);

    return Card(
      padding: EdgeInsets.all(16 * theme.scaling),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                volume == 0
                    ? SpotubeIcons.volumeMute
                    : volume <= 0.5
                        ? SpotubeIcons.volumeMedium
                        : SpotubeIcons.volumeHigh,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
              const Gap(8),
              Text(
                context.l10n.equalizer_volume,
                style: theme.typography.normal.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(volume * 100).round()}%',
                style: theme.typography.xSmall.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          const Gap(4),
          Slider(
            value: SliderValue.single(volume),
            onChanged: (value) =>
                ref.read(volumeProvider.notifier).setVolume(value.value),
          ),
        ],
      ),
    );
  }
}

class _EffectTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final double strength;
  final bool supported;
  final ValueChanged<bool> onChanged;

  const _EffectTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.strength,
    required this.onChanged,
    this.supported = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = value && supported;
    final accent =
        active ? theme.colorScheme.primary : theme.colorScheme.mutedForeground;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * theme.scaling,
        vertical: 14 * theme.scaling,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: theme.borderRadiusLg,
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.55),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _EffectDialPainter(
                value: active ? strength : 0,
                color: accent,
                track: theme.colorScheme.border,
              ),
              child: Center(
                child: Icon(icon, size: 16, color: accent),
              ),
            ),
          ),
          const Gap(8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.xSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: active
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
          const Gap(8),
          Switch(
            value: value,
            enabled: supported,
            onChanged: supported ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _EffectDialPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;

  const _EffectDialPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final base = Paint()
      ..color = track.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, base);

    if (value <= 0) return;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _EffectDialPainter oldDelegate) {
    return value != oldDelegate.value ||
        color != oldDelegate.color ||
        track != oldDelegate.track;
  }
}

class _VisualizerCard extends ConsumerWidget {
  const _VisualizerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spectrum = ref.watch(audioSpectrumProvider);
    final state = spectrum.asData?.value;
    final live = state?.status == AudioSpectrumStatus.live;
    final unavailable =
        state != null && state.status == AudioSpectrumStatus.unavailable;

    return Card(
      padding: EdgeInsets.all(16 * theme.scaling),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                SpotubeIcons.equalizer,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  context.l10n.equalizer_visualizer,
                  style: theme.typography.normal.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (live) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Gap(6),
                Text(
                  context.l10n.equalizer_visualizer_live,
                  style: theme.typography.xSmall.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (unavailable)
                Flexible(
                  child: Text(
                    context.l10n.equalizer_visualizer_unavailable,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.typography.xSmall.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
          const Gap(12),
          SizedBox(
            height: 128,
            child: _AudioVisualizer(
              bands: state?.bands ?? const [],
              color: theme.colorScheme.primary,
              track: theme.colorScheme.border,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the live FFT bands published by [audioSpectrumProvider].
///
/// The bars are driven entirely by captured PCM; when nothing is playing they
/// fall back to the two-pixel baseline instead of animating on their own.
class _AudioVisualizer extends StatelessWidget {
  final List<double> bands;
  final Color color;
  final Color track;

  const _AudioVisualizer({
    required this.bands,
    required this.color,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VisualizerPainter(
        bands: bands,
        color: color,
        track: track,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final List<double> bands;
  final Color color;
  final Color track;

  const _VisualizerPainter({
    required this.bands,
    required this.color,
    required this.track,
  });

  /// Slightly saturated variant of the theme colour, so a muted accent still
  /// reads as a spectrum instead of a grey barcode.
  Color _vivid(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation >= 0.35) return color;
    return hsl
        .withSaturation(0.55)
        .withLightness(hsl.lightness.clamp(0.52, 0.72))
        .toColor();
  }

  /// Samples [bands] at [index] of [count] sticks.
  ///
  /// The captured spectrum only has [kAudioSpectrumBandCount] bands. A wider
  /// card must not just spread those few sticks apart, so the bands are
  /// interpolated across however many sticks fit the available width.
  double _bandValue(List<double> bands, int index, int count) {
    if (bands.isEmpty) return 0;
    if (count <= 1) return bands.first.clamp(0.0, 1.0).toDouble();

    final position = index * (bands.length - 1) / (count - 1);
    final lower = position.floor();
    final upper = position.ceil();
    final t = position - lower;
    final a = bands[lower].clamp(0.0, 1.0).toDouble();
    final b = bands[upper].clamp(0.0, 1.0).toDouble();
    return a + (b - a) * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Keep roughly one stick every 10 px instead of stretching the source
    // bands: a fullscreen card gets more sticks, not wider gaps.
    final count =
        (size.width / 10).round().clamp(kAudioSpectrumBandCount, 320).toInt();
    final slot = size.width / count;
    final barWidth = math.min(slot * 0.52, 8.0);
    final baseline = size.height * 0.86;
    final maxHeight = size.height * 0.72;
    final accent = _vivid(color);
    final second = HSLColor.fromColor(accent)
        .withHue((HSLColor.fromColor(accent).hue + 32) % 360)
        .toColor();
    final shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        accent.withValues(alpha: 0.30),
        accent,
        second,
      ],
    ).createShader(Rect.fromLTRB(0, 0, size.width, baseline));
    final barPaint = Paint()..shader = shader;
    final reflectionPaint = Paint()..color = accent.withValues(alpha: 0.10);

    for (var i = 0; i < count; i++) {
      final value = _bandValue(bands, i, count);
      // A two-pixel floor keeps silence visible as a flat line rather than a
      // blank card; the height above it is entirely real audio.
      final height = value * maxHeight + 2;
      final x = i * slot + (slot - barWidth) / 2;
      final radius = Radius.circular(barWidth / 2);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, baseline - height, x + barWidth, baseline),
          radius,
        ),
        barPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x,
            baseline + 4,
            x + barWidth,
            baseline + 4 + height * 0.16,
          ),
          radius,
        ),
        reflectionPaint,
      );
    }

    canvas.drawLine(
      Offset(0, baseline + 1),
      Offset(size.width, baseline + 1),
      Paint()
        ..color = track.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return !listEquals(bands, oldDelegate.bands) ||
        color != oldDelegate.color ||
        track != oldDelegate.track;
  }
}

String _presetLabel(BuildContext context, EqualizerPreset preset) {
  return switch (preset) {
    EqualizerPreset.flat => context.l10n.equalizer_preset_flat,
    EqualizerPreset.bassBoost => context.l10n.equalizer_preset_bass_boost,
    EqualizerPreset.trebleBoost => context.l10n.equalizer_preset_treble_boost,
    EqualizerPreset.vocal => context.l10n.equalizer_preset_vocal,
    EqualizerPreset.rock => context.l10n.equalizer_preset_rock,
    EqualizerPreset.electronic => context.l10n.equalizer_preset_electronic,
    EqualizerPreset.custom => context.l10n.equalizer_preset_custom,
  };
}
