part of 'theme_ui_node.dart';

class _ThemeUiProgress extends StatefulWidget {
  final double fraction;
  final double height;
  final double hitHeight;
  final double radius;
  final double borderWidth;
  final Color borderColor;
  final Color color;
  final Color trackColor;
  final Color thumbColor;
  final double thumbSize;
  final double? width;
  final bool enabled;
  final ValueChanged<double> onSeek;

  const _ThemeUiProgress({
    required this.fraction,
    required this.height,
    required this.hitHeight,
    required this.radius,
    required this.borderWidth,
    required this.borderColor,
    required this.color,
    required this.trackColor,
    required this.thumbColor,
    required this.thumbSize,
    required this.width,
    required this.enabled,
    required this.onSeek,
  });

  @override
  State<_ThemeUiProgress> createState() => _ThemeUiProgressState();
}

class _ThemeUiProgressState extends State<_ThemeUiProgress> {
  double? _drag;

  double _barWidth() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : 0;
  }

  double _valueAt(Offset position, double width) {
    if (width <= 0) return 0;
    return (position.dx / width).clamp(0.0, 1.0).toDouble();
  }

  void _update(Offset position) {
    if (!widget.enabled) return;
    setState(() => _drag = _valueAt(position, _barWidth()));
  }

  void _commit() {
    final value = _drag;
    if (!widget.enabled || value == null) return;
    widget.onSeek(value);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.fraction).clamp(0.0, 1.0).toDouble();
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            widget.enabled ? (details) => _update(details.localPosition) : null,
        onTapUp: widget.enabled
            ? (details) {
                _update(details.localPosition);
                _commit();
              }
            : null,
        onHorizontalDragStart:
            widget.enabled ? (details) => _update(details.localPosition) : null,
        onHorizontalDragUpdate:
            widget.enabled ? (details) => _update(details.localPosition) : null,
        onHorizontalDragEnd: widget.enabled ? (_) => _commit() : null,
        onHorizontalDragCancel:
            widget.enabled ? () => setState(() => _drag = null) : null,
        child: SizedBox(
          width: widget.width ?? double.infinity,
          height: widget.hitHeight,
          child: CustomPaint(
            painter: _ThemeUiProgressPainter(
              fraction: value,
              height: widget.height,
              radius: widget.radius,
              borderWidth: widget.borderWidth,
              borderColor: widget.borderColor,
              color: widget.color,
              trackColor: widget.trackColor,
              thumbColor: widget.thumbColor,
              thumbSize: widget.thumbSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the bar without a [LayoutBuilder].
///
/// A player footer is measured through `getMaxIntrinsicHeight`, and a
/// `LayoutBuilder` inside it cannot answer that query (shadcn's Scaffold does
/// exactly this) — the whole window goes blank. The pointer width is read
/// from the render box at gesture time instead.
class _ThemeUiProgressPainter extends CustomPainter {
  final double fraction;
  final double height;
  final double radius;
  final double borderWidth;
  final Color borderColor;
  final Color color;
  final Color trackColor;
  final Color thumbColor;
  final double thumbSize;

  const _ThemeUiProgressPainter({
    required this.fraction,
    required this.height,
    required this.radius,
    required this.borderWidth,
    required this.borderColor,
    required this.color,
    required this.trackColor,
    required this.thumbColor,
    required this.thumbSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    if (width <= 0 || height <= 0) return;
    final top = (size.height - height) / 2;
    final antiAlias = radius > 0;
    final paint = Paint()..isAntiAlias = antiAlias;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, width, height),
      Radius.circular(radius),
    );
    if (borderWidth > 0) {
      canvas.drawRRect(outer, paint..color = borderColor);
    }

    final innerLeft = borderWidth;
    final innerTop = top + borderWidth;
    final innerWidth = math.max(0.0, width - borderWidth * 2);
    final innerHeight = math.max(0.0, height - borderWidth * 2);
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(innerLeft, innerTop, innerWidth, innerHeight),
      Radius.circular(math.max(0, radius - borderWidth)),
    );
    canvas.drawRRect(inner, paint..color = trackColor);

    if (fraction > 0 && innerWidth > 0 && innerHeight > 0) {
      canvas.save();
      canvas.clipRRect(inner);
      canvas.drawRect(
        Rect.fromLTWH(
          innerLeft,
          innerTop,
          innerWidth * fraction,
          innerHeight,
        ),
        paint..color = color,
      );
      canvas.restore();
    }

    if (thumbSize > 0) {
      final left = (fraction * math.max(0, width - thumbSize))
          .clamp(0.0, math.max(0, width - thumbSize))
          .toDouble();
      final thumbTop = (size.height - thumbSize) / 2;
      final thumbRadius = math.min(radius, thumbSize / 2);
      final thumb = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, thumbTop, thumbSize, thumbSize),
        Radius.circular(thumbRadius),
      );
      canvas.drawRRect(thumb, paint..color = thumbColor);
      if (borderWidth > 0) {
        canvas.drawRRect(
          thumb,
          Paint()
            ..isAntiAlias = antiAlias
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.min(2, thumbSize / 4)
            ..color = borderColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ThemeUiProgressPainter old) =>
      old.fraction != fraction ||
      old.height != height ||
      old.radius != radius ||
      old.borderWidth != borderWidth ||
      old.borderColor != borderColor ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.thumbColor != thumbColor ||
      old.thumbSize != thumbSize;
}

/// Rebuilds one node with a hover flag when the theme gave it a hover colour.
///
/// Kept as a stateful wrapper rather than an [InkWell] highlight: the card's
/// fill, border and radius belong to the same decoration, so the hover hue has
/// to replace that fill instead of painting a translucent layer over it.
class _ThemeUiHoverBuilder extends StatefulWidget {
  final Color? hoverColor;
  final Widget Function(BuildContext context, bool hovered) builder;

  const _ThemeUiHoverBuilder({
    required this.hoverColor,
    required this.builder,
  });

  @override
  State<_ThemeUiHoverBuilder> createState() => _ThemeUiHoverBuilderState();
}

class _ThemeUiHoverBuilderState extends State<_ThemeUiHoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.hoverColor == null) return widget.builder(context, false);
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: widget.builder(context, _hovered),
    );
  }
}

class _AnimatedNode extends StatefulWidget {
  final Map<String, dynamic> props;
  final ThemeUiRuntime runtime;
  final Widget child;

  const _AnimatedNode({
    required this.props,
    required this.runtime,
    required this.child,
  });

  @override
  State<_AnimatedNode> createState() => _AnimatedNodeState();
}

class _AnimatedNodeState extends State<_AnimatedNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  String get _bind =>
      widget.props['bind'] is String ? widget.props['bind'] as String : '';

  bool get _gated => _bind.isNotEmpty;

  bool get _active => !_gated || widget.runtime.bindings.isTruthy(_bind);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration(),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant _AnimatedNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _duration();
    if (_controller.duration != next) {
      _controller.duration = next;
    }
    _sync();
  }

  Duration _duration() {
    final raw = widget.props['duration'];
    final fallback = widget.props['kind'] == 'rotate' ? 24000 : 2400;
    final millis = raw is num && raw.isFinite ? raw.toInt() : fallback;
    return Duration(milliseconds: millis.clamp(100, 60000));
  }

  void _sync() {
    if (_active) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final reverse = widget.props['reverse'] == true;
        final curved = _curve(widget.props['curve'])
            .transform(_controller.value.clamp(0.0, 1.0));
        final value = reverse ? 1 - curved : curved;
        final kind = widget.props['kind'];
        return switch (kind) {
          'pulse' => Transform.scale(
              scale: _active ? 1 + 0.06 * math.sin(2 * math.pi * value) : 1,
              child: child,
            ),
          'float' => Transform.translate(
              offset: Offset(
                0,
                _active ? -4 * math.sin(2 * math.pi * value) : 0,
              ),
              child: child,
            ),
          'fade' => Opacity(
              opacity: _active
                  ? (0.55 + 0.45 * (0.5 + 0.5 * math.sin(2 * math.pi * value)))
                  : 1,
              child: child,
            ),
          _ => Transform.rotate(
              angle: 2 * math.pi * value,
              child: child,
            ),
        };
      },
      child: widget.child,
    );
  }

  Curve _curve(Object? raw) => switch (raw) {
        'linear' => Curves.linear,
        'ease' => Curves.ease,
        'easeIn' => Curves.easeIn,
        'easeOut' => Curves.easeOut,
        'easeInOut' => Curves.easeInOut,
        'easeOutCubic' => Curves.easeOutCubic,
        'easeInOutCubic' => Curves.easeInOutCubic,
        _ => Curves.easeInOut,
      };
}
