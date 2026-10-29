part of 'theme_ui_node.dart';

/// Settles a text value before rebuilding its child.
///
/// A list filter reads a binding the user types into; filtering on every
/// keystroke would rebuild a long list while the field is still updating.
/// The child only sees the value after the typing pause, the same 150 ms
/// default the text inputs use.
class _ThemeUiDebouncedText extends StatefulWidget {
  final String value;
  final Widget Function(BuildContext context, String value) builder;

  const _ThemeUiDebouncedText({
    required this.value,
    required this.builder,
  });

  @override
  State<_ThemeUiDebouncedText> createState() => _ThemeUiDebouncedTextState();
}

class _ThemeUiDebouncedTextState extends State<_ThemeUiDebouncedText> {
  late String _settled = widget.value;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant _ThemeUiDebouncedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _settled = widget.value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _settled);
}

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
  final bool wavy;
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
    this.wavy = false,
  });

  @override
  State<_ThemeUiProgress> createState() => _ThemeUiProgressState();
}

class _ThemeUiProgressState extends State<_ThemeUiProgress>
    with SingleTickerProviderStateMixin {
  double? _drag;
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _syncWave();
  }

  @override
  void didUpdateWidget(covariant _ThemeUiProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wavy != widget.wavy) _syncWave();
  }

  void _syncWave() {
    if (widget.wavy) {
      _wave.repeat();
    } else {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

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
          child: AnimatedBuilder(
            animation: _wave,
            builder: (context, _) => CustomPaint(
              painter: _ThemeUiProgressPainter(
                fraction: (_drag ?? widget.fraction).clamp(0.0, 1.0).toDouble(),
                height: widget.height,
                radius: widget.radius,
                borderWidth: widget.borderWidth,
                borderColor: widget.borderColor,
                color: widget.color,
                trackColor: widget.trackColor,
                thumbColor: widget.thumbColor,
                thumbSize: widget.thumbSize,
                wavy: widget.wavy,
                phase: widget.wavy ? _wave.value : 0,
              ),
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
  final bool wavy;
  final double phase;

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
    this.wavy = false,
    this.phase = 0,
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
      final filled = Rect.fromLTWH(
        innerLeft,
        innerTop,
        innerWidth * fraction,
        innerHeight,
      );
      if (wavy) {
        canvas.clipRect(filled);
        _paintWave(canvas, inner.outerRect);
      } else {
        canvas.drawRect(filled, paint..color = color);
      }
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
      canvas.drawRRect(
          thumb,
          paint
            ..style = PaintingStyle.fill
            ..color = thumbColor);
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

  /// A sine ribbon stroked across [inner], phase-shifted by [phase].
  ///
  /// A waveform reads as a bar at rest but stays one path to stroke, so a
  /// wavy progress costs the same as the flat one plus a repaint tick.
  void _paintWave(Canvas canvas, Rect inner) {
    final amplitude = math.min(inner.height * 0.28, 6.0);
    final wavelength = math.max(10.0, inner.height * 2.4);
    final mid = inner.center.dy;
    final path = Path();
    for (double x = inner.left; x <= inner.right; x += 1) {
      final y = mid +
          amplitude *
              math.sin(
                (x - inner.left) / wavelength * 2 * math.pi +
                    phase * 2 * math.pi,
              );
      if (x == inner.left) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final wave = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, inner.height * 0.55)
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawPath(path, wave);
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
      old.thumbSize != thumbSize ||
      old.wavy != wavy ||
      old.phase != phase;
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

/// Closes the overlay a `dismiss` action belongs to.
///
/// The runtime cannot know which overlay is asking; the widget that opened
/// the overlay installs this scope around its content and the action is
/// intercepted before it reaches the dispatcher. Outside an overlay the verb
/// falls through to the host like every other action.
class ThemeUiDismissScope extends InheritedWidget {
  final VoidCallback onDismiss;

  const ThemeUiDismissScope({
    required this.onDismiss,
    required super.child,
    super.key,
  });

  static VoidCallback? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeUiDismissScope>()
        ?.onDismiss;
  }

  @override
  bool updateShouldNotify(ThemeUiDismissScope oldWidget) =>
      onDismiss != oldWidget.onDismiss;
}

extension _ThemeUiDisplayNodes on ThemeUiNodeView {
  Widget _badge(BuildContext context, Map<String, dynamic> props) {
    final text = props['text'] is String ? props['text'] as String : '';
    if (text.isEmpty) return const SizedBox.shrink();
    final label = text.length > 64 ? text.substring(0, 64) : text;
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, border) = switch (props['variant']) {
      'secondary' => (scheme.secondary, scheme.secondaryForeground, null),
      'outline' => (Colors.transparent, scheme.foreground, scheme.border),
      'destructive' => (
          Colors.transparent,
          scheme.destructive,
          scheme.destructive
        ),
      _ => (scheme.primary, scheme.primaryForeground, null),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, Map<String, dynamic> props) {
    final raw = props['label'] is String ? props['label'] as String : '';
    if (raw.isEmpty) return const SizedBox.shrink();
    final label = raw.length > 80 ? raw.substring(0, 80) : raw;
    final bind = props['selectedBind'] is String
        ? props['selectedBind'] as String
        : null;
    final selected = bind != null && runtime.bindings.isTruthy(bind);
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primaryForeground : scheme.foreground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? scheme.primary : scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, Map<String, dynamic> props) {
    final size =
        _px(context, props['size'], fallback: 40).clamp(8.0, 256.0).toDouble();
    final fallback =
        props['fallback'] is String ? props['fallback'] as String : '';
    final provider = _provider(_imageSource(props), width: size, height: size);
    final scheme = Theme.of(context).colorScheme;

    Widget placeholder() {
      return Container(
        width: size,
        height: size,
        color: scheme.muted,
        alignment: Alignment.center,
        child: fallback.isEmpty
            ? Icon(
                Icons.person,
                size: size * 0.55,
                color: scheme.mutedForeground,
              )
            : Text(
                String.fromCharCode(fallback.runes.first).toUpperCase(),
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                  color: scheme.mutedForeground,
                ),
              ),
      );
    }

    final content = provider == null
        ? placeholder()
        : Image(
            image: provider,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder(),
          );

    return ClipOval(
      child: SizedBox(width: size, height: size, child: content),
    );
  }

  Widget _skeleton(BuildContext context, Map<String, dynamic> props) {
    final width = _pxOrNull(context, props['width']);
    final height = _px(context, props['height'], fallback: 14)
        .clamp(2.0, 800.0)
        .toDouble();
    final radius =
        _px(context, props['radius'], fallback: 6).clamp(0.0, 999.0).toDouble();
    final count = _int(props['count'], fallback: 1, min: 1, max: 50);
    if (count == 1) {
      return _ThemeUiSkeleton(
        width: width,
        height: height,
        radius: radius,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _ThemeUiSkeleton(
              width: width,
              height: height,
              radius: radius,
              phase: i * 0.12,
            ),
          ),
      ],
    );
  }

  Widget _spinner(BuildContext context, Map<String, dynamic> props) {
    final size =
        _px(context, props['size'], fallback: 20).clamp(8.0, 256.0).toDouble();
    final color = _color(
      context,
      props['color'],
      fallback: Theme.of(context).colorScheme.foreground,
    );
    return _ThemeUiSpinner(size: size, color: color);
  }
}

/// A pulsing placeholder block.
///
/// The shimmer is a plain opacity pulse rather than a moving gradient: it
/// repaints one solid colour per frame, so a screen full of skeletons stays
/// cheap, and it still reads as "not loaded yet" without motion.
class _ThemeUiSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final double phase;

  const _ThemeUiSkeleton({
    required this.height,
    required this.radius,
    this.width,
    this.phase = 0,
  });

  @override
  State<_ThemeUiSkeleton> createState() => _ThemeUiSkeletonState();
}

class _ThemeUiSkeletonState extends State<_ThemeUiSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return block;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + widget.phase) % 1.0;
        final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t);
        return Opacity(opacity: 0.45 + 0.35 * pulse, child: child);
      },
      child: block,
    );
  }
}

class _ThemeUiSpinner extends StatefulWidget {
  final double size;
  final Color color;

  const _ThemeUiSpinner({required this.size, required this.color});

  @override
  State<_ThemeUiSpinner> createState() => _ThemeUiSpinnerState();
}

class _ThemeUiSpinnerState extends State<_ThemeUiSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ThemeUiSpinnerPainter(
            color: widget.color,
            progress: still ? 0.25 : _controller.value,
          ),
        ),
      ),
    );
  }
}

class _ThemeUiSpinnerPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _ThemeUiSpinnerPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.shortestSide * 0.12).clamp(1.5, 5.0).toDouble();
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2 + progress * 2 * math.pi,
      math.pi * 1.35,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ThemeUiSpinnerPainter old) =>
      old.color != color || old.progress != progress;
}
