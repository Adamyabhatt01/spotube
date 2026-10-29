import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/equalizer/equalizer.dart';

/// Interactive 10-band equalizer curve.
///
/// The whole band is one chart: dragging a node adjusts that band, the curve
/// and its fill follow the live draft, and each frequency label sits directly
/// under its node. Gestures are owned by the nodes, so drag-end can never be
/// swallowed by a controlled-value equality check.
class EqualizerCurveEditor extends StatelessWidget {
  static const double gutter = 26;
  static const double plotHeight = 180;
  static const double hitSize = 30;

  final List<double> gains;
  final bool bypassed;
  final void Function(int index, double gain) onChanged;
  final void Function(int index, double gain) onChangeEnd;

  const EqualizerCurveEditor({
    super.key,
    required this.gains,
    required this.bypassed,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bandWidth = (width - gutter * 2) / kEqualizerBandCount;
        const plotTop = hitSize / 2;
        const stackHeight = plotHeight + hitSize;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: stackHeight,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CurvePainter(
                        gains: gains,
                        bypassed: bypassed,
                        primary: theme.colorScheme.primary,
                        muted: theme.colorScheme.mutedForeground,
                        grid: theme.colorScheme.border,
                      ),
                    ),
                  ),
                  for (var i = 0; i < kEqualizerBandCount; i++)
                    Positioned(
                      left: gutter + (i + 0.5) * bandWidth - hitSize / 2,
                      top: plotTop +
                          (kEqualizerMaxGain -
                                  (i < gains.length ? gains[i] : 0)) /
                              (kEqualizerMaxGain - kEqualizerMinGain) *
                              plotHeight -
                          hitSize / 2,
                      width: hitSize,
                      height: hitSize,
                      child: _BandNode(
                        key: ValueKey('equalizer-node-$i'),
                        label: kEqualizerBandLabels[i],
                        gain: i < gains.length ? gains[i] : 0,
                        plotHeight: plotHeight,
                        bypassed: bypassed,
                        onChanged: (gain) => onChanged(i, gain),
                        onChangeEnd: (gain) => onChangeEnd(i, gain),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(2),
            Row(
              children: [
                const SizedBox(width: gutter),
                for (var i = 0; i < kEqualizerBandCount; i++)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        kEqualizerBandLabels[i],
                        maxLines: 1,
                        style: theme.typography.xSmall.copyWith(
                          fontSize: 9 * theme.scaling,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: gutter),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BandNode extends StatefulWidget {
  final String label;
  final double gain;
  final double plotHeight;
  final bool bypassed;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BandNode({
    super.key,
    required this.label,
    required this.gain,
    required this.plotHeight,
    required this.bypassed,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_BandNode> createState() => _BandNodeState();
}

class _BandNodeState extends State<_BandNode> {
  late final FocusNode _focusNode;
  double _dragValue = 0;
  bool _dragChanged = false;
  bool _dragging = false;
  bool _hovered = false;
  bool _focused = false;
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'equalizer-${widget.label}');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double _snap(double value) {
    if (!value.isFinite) return 0;
    final snapped =
        (value / kEqualizerGainStep).roundToDouble() * kEqualizerGainStep;
    return snapped.clamp(kEqualizerMinGain, kEqualizerMaxGain).toDouble();
  }

  void _changeBy(double delta) {
    final next = _snap(widget.gain + delta);
    if (next == widget.gain) return;
    widget.onChanged(next);
    widget.onChangeEnd(next);
  }

  void _reset() {
    if (widget.gain == 0) return;
    widget.onChanged(0);
    widget.onChangeEnd(0);
  }

  /// Double-click and right-click reset live in a plain [Listener] so they
  /// never hold the gesture arena. A `DoubleTapGestureRecognizer` would delay
  /// the first drag update by its full timeout, which makes the nodes feel
  /// sticky.
  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      _reset();
      return;
    }
    if (event.buttons != kPrimaryMouseButton) return;

    _focusNode.requestFocus();
    final now = DateTime.now();
    final lastAt = _lastTapAt;
    final lastPosition = _lastTapPosition;
    if (lastAt != null &&
        lastPosition != null &&
        now.difference(lastAt) <= const Duration(milliseconds: 320) &&
        (event.position - lastPosition).distance <= 24) {
      _lastTapAt = null;
      _lastTapPosition = null;
      _reset();
      return;
    }
    _lastTapAt = now;
    _lastTapPosition = event.position;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _changeBy(kEqualizerGainStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _changeBy(-kEqualizerGainStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _reset();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.bypassed
        ? theme.colorScheme.mutedForeground
        : theme.colorScheme.primary;
    final emphasized = _hovered || _focused || _dragging;
    final dotSize = emphasized ? 16.0 : 12.0;

    return Semantics(
      label: widget.label,
      slider: true,
      value: '${_formatGain(widget.gain)} dB',
      increasedValue:
          '${_formatGain(_snap(widget.gain + kEqualizerGainStep))} dB',
      decreasedValue:
          '${_formatGain(_snap(widget.gain - kEqualizerGainStep))} dB',
      onIncrease: () => _changeBy(kEqualizerGainStep),
      onDecrease: () => _changeBy(-kEqualizerGainStep),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _onKeyEvent,
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            _changeBy(
              event.scrollDelta.dy > 0
                  ? -kEqualizerGainStep
                  : kEqualizerGainStep,
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                _dragValue = widget.gain;
                _dragChanged = false;
                _lastTapAt = null;
                _lastTapPosition = null;
                setState(() => _dragging = true);
              },
              onVerticalDragUpdate: (details) {
                final next = _snap(
                  _dragValue -
                      details.delta.dy /
                          widget.plotHeight *
                          (kEqualizerMaxGain - kEqualizerMinGain),
                );
                if (next == _dragValue) return;
                _dragValue = next;
                _dragChanged = true;
                widget.onChanged(next);
              },
              onVerticalDragEnd: (_) {
                setState(() => _dragging = false);
                if (_dragChanged) widget.onChangeEnd(_dragValue);
              },
              onVerticalDragCancel: () {
                setState(() => _dragging = false);
                if (_dragChanged) widget.onChangeEnd(_dragValue);
              },
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active,
                    border: Border.all(
                      color: theme.colorScheme.card,
                      width: 2,
                    ),
                    boxShadow: [
                      if (emphasized)
                        BoxShadow(
                          color: active.withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatGain(double gain) {
  if (gain == 0) return '0';
  final formatted = gain == gain.roundToDouble()
      ? gain.toInt().toString()
      : gain.toStringAsFixed(1);
  return gain > 0 ? '+$formatted' : formatted;
}

class _CurvePainter extends CustomPainter {
  final List<double> gains;
  final bool bypassed;
  final Color primary;
  final Color muted;
  final Color grid;

  const _CurvePainter({
    required this.gains,
    required this.bypassed,
    required this.primary,
    required this.muted,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const plotLeft = EqualizerCurveEditor.gutter;
    final plotRight = size.width - plotLeft;
    const plotTop = EqualizerCurveEditor.hitSize / 2;
    const plotBottom = plotTop + EqualizerCurveEditor.plotHeight;
    final plotWidth = plotRight - plotLeft;
    const plotHeight = plotBottom - plotTop;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final bandWidth = plotWidth / kEqualizerBandCount;
    final active = bypassed ? muted : primary;

    final points = <Offset>[
      for (var i = 0; i < kEqualizerBandCount; i++)
        Offset(
          plotLeft + (i + 0.5) * bandWidth,
          _yForGain(
            i < gains.length ? gains[i] : 0,
            plotTop,
            plotHeight,
          ),
        ),
    ];

    final curve = _smoothPath(points);

    // A soft wash under the curve carries the theme's hue into the mostly
    // monochrome chart. It is deliberately faint: the line and nodes stay the
    // focus, and the fill disappears entirely when the EQ is bypassed.
    final fill = Path.from(curve)
      ..lineTo(points.last.dx, plotBottom)
      ..lineTo(points.first.dx, plotBottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            active.withValues(alpha: bypassed ? 0.06 : 0.26),
            active.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromLTRB(plotLeft, plotTop, plotRight, plotBottom),
        ),
    );

    // Guides start at the band's dot and fall to the frequency axis, like the
    // reference, instead of crossing the whole plot.
    final guidePaint = Paint()
      ..color = grid.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (final point in points) {
      canvas.drawLine(
        point,
        Offset(point.dx, plotBottom),
        guidePaint,
      );
    }

    canvas.drawPath(
      curve,
      Paint()
        ..color = active
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  double _yForGain(double gain, double top, double height) {
    final clamped = gain.clamp(kEqualizerMinGain, kEqualizerMaxGain).toDouble();
    return top +
        (kEqualizerMaxGain - clamped) /
            (kEqualizerMaxGain - kEqualizerMinGain) *
            height;
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) {
    return !listEquals(gains, oldDelegate.gains) ||
        bypassed != oldDelegate.bypassed ||
        primary != oldDelegate.primary ||
        muted != oldDelegate.muted ||
        grid != oldDelegate.grid;
  }
}
