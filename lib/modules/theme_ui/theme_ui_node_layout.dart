part of 'theme_ui_node.dart';

extension _ThemeUiLayoutNodes on ThemeUiNodeView {
  // ---------------------------------------------------------------- layout

  Widget _row(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final gap = _gapSize(context, props['gap']);
    return Row(
      mainAxisAlignment: _main(props['justify']),
      crossAxisAlignment: _cross(props['align']),
      children: _withGaps(context, children, gap, Axis.horizontal),
    );
  }

  Widget _column(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final gap = _gapSize(context, props['gap']);
    return Column(
      mainAxisAlignment: _main(props['justify']),
      crossAxisAlignment: _cross(props['align']),
      mainAxisSize: MainAxisSize.min,
      children: _withGaps(context, children, gap, Axis.vertical),
    );
  }

  Widget _stack(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final alignment = _alignment(props['align']);
    final nodes = _nodes(context, children);
    if (props['fit'] != 'expand') {
      return Stack(alignment: alignment, children: nodes);
    }
    // Expand can only fill a bounded axis. A stack inside a scroll view (the
    // home stage) gets unbounded height, and StackFit.expand would forward
    // that infinity to fixed-size children such as a circular image.
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        alignment: alignment,
        fit: constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? StackFit.expand
            : StackFit.loose,
        children: nodes,
      ),
    );
  }

  Widget _wrap(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    return Wrap(
      spacing: _gapSize(context, props['gap']),
      runSpacing: _gapSize(context, props['runGap'] ?? props['gap']),
      alignment: _wrapMain(props['justify']),
      crossAxisAlignment: _wrapCross(props['align']),
      children: _nodes(context, children),
    );
  }

  Widget _padding(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final all = _px(context, props['all']);
    final horizontal = _px(context, props['horizontal']);
    final vertical = _px(context, props['vertical']);
    final top = _px(context, props['top']);
    final right = _px(context, props['right']);
    final bottom = _px(context, props['bottom']);
    final left = _px(context, props['left']);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        props['left'] != null
            ? left
            : (props['horizontal'] != null ? horizontal : all),
        props['top'] != null
            ? top
            : (props['vertical'] != null ? vertical : all),
        props['right'] != null
            ? right
            : (props['horizontal'] != null ? horizontal : all),
        props['bottom'] != null
            ? bottom
            : (props['vertical'] != null ? vertical : all),
      ),
      child: _columnOf(context, children),
    );
  }

  Widget _align(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final width = _pxOrNull(context, props['widthFactor']);
    final height = _pxOrNull(context, props['heightFactor']);
    return Align(
      alignment: _alignment(props['align']),
      widthFactor: width == null || width <= 0 ? null : width,
      heightFactor: height == null || height <= 0 ? null : height,
      child: _columnOf(context, children),
    );
  }

  Widget _expanded(
      Map<String, dynamic> props, List<Map<String, dynamic>> children) {
    final flex = _int(props['flex'], fallback: 1, min: 1, max: 12);
    return Expanded(
      flex: flex,
      child: _columnOfWithoutContext(children),
    );
  }

  Widget _scroll(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final horizontal = props['direction'] == 'horizontal';
    return SingleChildScrollView(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      padding: EdgeInsets.all(_px(context, props['padding'])),
      child: horizontal
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: _nodes(context, children),
            )
          : _columnOf(context, children),
    );
  }

  /// A surface that can carry a colour, gradient, border, radius and size.
  ///
  /// `box` exists so a theme can build hero banners and framed panels without
  /// shipping bitmaps: the same node is the skeleton of every styled section.
  Widget _box(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final width = _pxOrNull(context, props['width']);
    final height = _pxOrNull(context, props['height']);
    final radius =
        _px(context, props['radius'], fallback: 0).clamp(0.0, 999.0).toDouble();
    // `border` is either a colour string or `{color, width}`. A bare colour
    // gets a one-pixel rule, which is the smallest border a theme can see.
    final borderRaw = props['border'];
    final borderSpec = _map(borderRaw is Map ? borderRaw : null);
    final borderWidth = borderRaw == null
        ? 0.0
        : _px(
            context,
            borderSpec['width'] ?? props['borderWidth'],
            fallback: 1,
          ).clamp(0.0, 8.0).toDouble();
    final borderColor = _color(
      context,
      borderSpec['color'] ?? (borderRaw is String ? borderRaw : null),
      fallback: scheme.border,
    );
    final background =
        _color(context, props['background'], fallback: Colors.transparent);
    final gradient = _gradient(context, props['gradient']);
    final padding = _px(context, props['padding'], fallback: 0);
    final opacity = _clamp(props['opacity'], 0, 1, fallback: 1);

    Widget box = Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
        border: borderWidth > 0
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
      ),
      child: _columnOf(context, children),
    );

    final clip = props['clip'];
    if (clip == true ||
        clip == 'hardEdge' ||
        clip == 'antiAlias' ||
        clip == 'antiAliasWithSaveLayer') {
      box = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: clip == 'antiAliasWithSaveLayer'
            ? Clip.antiAliasWithSaveLayer
            : Clip.antiAlias,
        child: box,
      );
    }

    return opacity < 1 ? Opacity(opacity: opacity, child: box) : box;
  }

  /// A linear gradient from the contract's `gradient` object.
  ///
  /// `["@palette.darkMuted", "@background"]` is the shape a theme writes; a
  /// colour role the host cannot resolve yet falls back to the accent colour
  /// so the box still paints instead of disappearing.
  Gradient? _gradient(BuildContext context, Object? raw) {
    if (raw is! Map) return null;
    final colors = raw['colors'];
    if (colors is! List || colors.length < 2) return null;

    final scheme = Theme.of(context).colorScheme;
    final resolved = <Color>[];
    for (final value in colors.take(8)) {
      if (value is! String || value.isEmpty) return null;
      resolved.add(_color(context, value, fallback: scheme.primary));
    }

    final stops = raw['stops'];
    List<double>? parsedStops;
    if (stops is List && stops.length == resolved.length) {
      final values = [
        for (final stop in stops)
          if (stop is num && stop.isFinite)
            stop.toDouble().clamp(0.0, 1.0).toDouble(),
      ];
      if (values.length == resolved.length && !_hasDecreasingStop(values)) {
        parsedStops = values;
      }
    }

    return LinearGradient(
      colors: resolved,
      begin: _alignment(raw['begin']),
      end: _alignment(raw['end']),
      stops: parsedStops,
    );
  }

  bool _hasDecreasingStop(List<double> stops) {
    for (var i = 1; i < stops.length; i++) {
      if (stops[i] < stops[i - 1]) return true;
    }
    return false;
  }

  /// A fixed column count whose cells keep their intrinsic height.
  ///
  /// A `GridView` would force a child aspect ratio the contract does not
  /// declare; `Wrap` with computed cell widths lets a card grid grow to the
  /// height of its content and still line up in columns.
  Widget _grid(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();
    final columns = _int(props['columns'], fallback: 2, min: 1, max: 12);
    final gap = _gapSize(context, props['gap']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: _nodes(context, children),
          );
        }

        final cellWidth = ((width - gap * (columns - 1)) / columns)
            .clamp(0.0, width)
            .toDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(
                width: cellWidth,
                child: ThemeUiNodeView(
                  node: child,
                  runtime: runtime,
                  depth: depth + 1,
                ),
              ),
          ],
        );
      },
    );
  }

  /// A two-pane split the user can drag.
  ///
  /// `direction: horizontal` (the default) fixes the first pane's width and
  /// `vertical` its height. `storageKey` persists the dragged size across
  /// launches through [KVStoreService]; without one the size is session-only.
  /// The second pane always keeps at least 120 logical px, so a drag cannot
  /// hide the content the split is meant to sit beside.
  Widget _resizable(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    if (children.length < 2) return _columnOf(context, children);
    final storageKey = props['storageKey'];
    return _ThemeUiResizable(
      horizontal: props['direction'] != 'vertical',
      initial: _px(context, props['initial'], fallback: 240),
      min: _px(context, props['min'], fallback: 120),
      max: _px(context, props['max'], fallback: 480),
      storageKey:
          storageKey is String && storageKey.isNotEmpty ? storageKey : null,
      first: ThemeUiNodeView(
        node: children[0],
        runtime: runtime,
        depth: depth + 1,
      ),
      second: ThemeUiNodeView(
        node: children[1],
        runtime: runtime,
        depth: depth + 1,
      ),
    );
  }

  /// Inset the subtree away from the platform's unsafe regions.
  ///
  /// `edges` is a list of `top`/`right`/`bottom`/`left`; omitting it insets
  /// every edge, which is what a full-page theme slot wants.
  Widget _safeArea(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final raw = props['edges'];
    final edges = <String>{
      if (raw is List) ...raw.whereType<String>(),
    };
    final all = edges.isEmpty;

    return SafeArea(
      top: all || edges.contains('top'),
      right: all || edges.contains('right'),
      bottom: all || edges.contains('bottom'),
      left: all || edges.contains('left'),
      child: _columnOf(context, children),
    );
  }

  /// Constrain the subtree to a width/height ratio.
  Widget _aspectRatio(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final ratio = _clamp(props['ratio'], 0.1, 10, fallback: 1);
    return AspectRatio(
      aspectRatio: ratio,
      child: _columnOf(context, children),
    );
  }

  /// Put a kit in scope for the subtree.
  Widget _kitScope(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final child = _columnOf(context, children);
    final kit = ThemeUiKit.tryParse(props['kit']);
    if (kit == null) return child;
    return ThemeUiKitScope(kit: kit, child: child);
  }

  Widget _spacer(Map<String, dynamic> props) {
    return Expanded(
      flex: _int(props['flex'], fallback: 1, min: 1, max: 12),
      child: const SizedBox.shrink(),
    );
  }

  Widget _gap(BuildContext context, Map<String, dynamic> props) {
    final size = _px(context, props['size']);
    return SizedBox(width: size, height: size);
  }

  Widget _divider(BuildContext context, Map<String, dynamic> props) {
    final thickness = _px(context, props['thickness'], fallback: 1)
        .clamp(0.5, 16.0)
        .toDouble();
    final color = _color(context, props['color'],
        fallback: Theme.of(context).colorScheme.border);
    if (props['orientation'] == 'vertical') {
      return Container(
          width: thickness,
          constraints: const BoxConstraints(minHeight: 16),
          color: color);
    }
    return Divider(height: thickness, thickness: thickness, color: color);
  }

  /// A playhead themed by the plugin.
  ///
  /// The host owns the player state; this node only turns a fraction of the
  /// bar into a `seek` action. Dragging keeps a local value so the fill tracks
  /// the pointer instead of waiting for the next position tick, then commits
  /// once on release. Tapping commits immediately.
  Widget _progress(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final height =
        _px(context, props['height'], fallback: 6).clamp(2.0, 48.0).toDouble();
    final hitHeight = _px(
      context,
      props['hitHeight'],
      fallback: math.max(24, height),
    ).clamp(height, 64.0).toDouble();
    final radius =
        _px(context, props['radius'], fallback: 0).clamp(0.0, 999.0).toDouble();
    final borderWidth = _px(context, props['borderWidth'], fallback: 0)
        .clamp(0.0, 8.0)
        .toDouble();
    final thumbSize = _px(context, props['thumbSize'], fallback: 12)
        .clamp(0.0, 48.0)
        .toDouble();
    final width = props['width'] is num
        ? _px(context, props['width'], fallback: 0)
            .clamp(0.0, 4000.0)
            .toDouble()
        : null;
    final color = _color(context, props['color'], fallback: colors.primary);
    final trackColor =
        _color(context, props['trackColor'], fallback: colors.border);
    final thumbColor = _color(context, props['thumbColor'], fallback: color);
    final borderColor =
        _color(context, props['borderColor'], fallback: colors.border);

    final position = _bindingDuration(
      runtime.bindings.raw(
        props['bind'] is String ? props['bind'] as String : 'player.position',
      ),
    );
    final duration = _bindingDuration(
      runtime.bindings.raw(
        props['maxBind'] is String
            ? props['maxBind'] as String
            : 'player.duration',
      ),
    );
    final positionMs = position?.inMilliseconds ?? 0;
    final durationMs = duration?.inMilliseconds ?? 0;
    final fraction = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
    final enabled =
        props['interactive'] != false && (duration?.inMilliseconds ?? 0) > 0;

    final variant =
        props['variant'] is String ? props['variant'] as String : null;
    final kit = _kitForComponent(
      context,
      component: 'progress',
      nodeType: 'progress',
      nodeKit: props['kit'],
      variant: variant,
    );
    void onSeek(double value) {
      runtime.onAction(ThemeUiAction('seek', {'fraction': value}));
    }

    final wavy = props['style'] == 'wavy';

    if (!wavy && kit == ThemeUiKit.material) {
      return _ThemeUiMaterialProgress(
        fraction: fraction,
        height: height,
        width: width,
        enabled: enabled,
        onSeek: onSeek,
      );
    }
    if (!wavy && kit == ThemeUiKit.cupertino) {
      return _ThemeUiCupertinoProgress(
        fraction: fraction,
        height: height,
        width: width,
        enabled: enabled,
        onSeek: onSeek,
      );
    }

    return _ThemeUiProgress(
      fraction: fraction,
      height: height,
      hitHeight: hitHeight,
      radius: radius,
      borderWidth: borderWidth,
      borderColor: borderColor,
      color: color,
      trackColor: trackColor,
      thumbColor: thumbColor,
      thumbSize: thumbSize,
      width: width,
      enabled: enabled,
      wavy: wavy,
      onSeek: onSeek,
    );
  }

  Duration? _bindingDuration(Object? raw) {
    if (raw is Duration) return raw;
    if (raw is num && raw.isFinite) {
      return Duration(milliseconds: (raw * 1000).round());
    }
    return null;
  }

  /// Repeats one subtree per entry of a collection binding.
  ///
  /// Each pass gets its own runtime, which is what makes `item.title`,
  /// `item.artwork` and friends resolve and what lets `playItem`, `openItem`,
  /// `likeItem` and `downloadItem` carry the typed entry to the dispatcher.
  /// The item list is capped: a theme can render a page of rows, not an
  /// unbounded virtualized feed the declarative vocabulary cannot express.
  Widget _list(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final source = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    if (source is! List || source.isEmpty || children.isEmpty) {
      return const SizedBox.shrink();
    }

    final limit = _int(props['limit'], fallback: 200, min: 1, max: 500);
    final gap = _gapSize(context, props['gap']);
    final crossAxisAlignment = _cross(props['align']);
    // A shelf is a list that scrolls sideways. The repeated entry is the same
    // subtree; only the axis changes, so cards and rows share one vocabulary.
    final horizontal = props['direction'] == 'horizontal';
    final filter = _listFilter(props);

    Widget buildRows(String? query) {
      final all = source.cast<Object?>().toList();
      final visible = query == null
          ? all
          : _filterItems(all, query, filter?.fields ?? const []);
      final items = visible.take(limit).toList();

      final rows = <Widget>[];
      for (var i = 0; i < items.length; i++) {
        if (i > 0 && gap > 0) {
          rows.add(SizedBox(
            width: horizontal ? gap : 0,
            height: horizontal ? 0 : gap,
          ));
        }
        final itemRuntime = _itemRuntime(runtime, items[i], i, items);
        rows.add(
          children.length == 1
              ? ThemeUiNodeView(
                  node: children.first,
                  runtime: itemRuntime,
                  depth: depth + 1,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    for (final child in children)
                      ThemeUiNodeView(
                        node: child,
                        runtime: itemRuntime,
                        depth: depth + 1,
                      ),
                  ],
                ),
        );
      }

      if (horizontal) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: rows,
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: rows,
      );
    }

    final spec = filter;
    if (spec == null) return buildRows(null);
    return _ThemeUiDebouncedText(
      value: runtime.bindings.display(spec.bind),
      builder: (context, settled) => buildRows(settled),
    );
  }
}

/// The interactive half of the `resizable` node: a fixed first pane, a drag
/// handle and a second pane that takes the rest.
class _ThemeUiResizable extends StatefulWidget {
  final bool horizontal;
  final double initial;
  final double min;
  final double max;
  final String? storageKey;
  final Widget first;
  final Widget second;

  const _ThemeUiResizable({
    required this.horizontal,
    required this.initial,
    required this.min,
    required this.max,
    required this.storageKey,
    required this.first,
    required this.second,
  });

  @override
  State<_ThemeUiResizable> createState() => _ThemeUiResizableState();
}

class _ThemeUiResizableState extends State<_ThemeUiResizable> {
  static const _handleBase = 6.0;
  static const _minSecondPane = 120.0;

  /// Cross-axis extent of the handle when the surrounding axis is unbounded,
  /// so it stays grabbable instead of collapsing to zero.
  static const _unboundedHandle = 24.0;

  late double _size;

  @override
  void initState() {
    super.initState();
    final key = widget.storageKey;
    final stored = key == null
        ? widget.initial
        : KVStoreService.resizableSize(key, widget.initial);
    _size = _bounded(stored, widget.min, widget.max);
  }

  @override
  void didUpdateWidget(covariant _ThemeUiResizable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A responsive override or a theme swap can move the bounds; keep the
    // user's chosen size but pull it back into the new range.
    if (oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _size = _bounded(_size, widget.min, widget.max);
    }
  }

  double _bounded(double value, double min, double max) {
    if (!value.isFinite) return min;
    if (max < min) return min;
    return value.clamp(min, max).toDouble();
  }

  /// The largest the first pane may get without eating the second one.
  double _maxFor(double available) {
    if (!available.isFinite) return widget.max;
    final room = available - _handleBase * _scaling - _minSecondPane;
    if (room < widget.min) return widget.min;
    return math.min(widget.max, room);
  }

  double get _scaling => Theme.of(context).scaling;

  void _drag(double delta, double available) {
    final next = _bounded(_size + delta, widget.min, _maxFor(available));
    if (next == _size) return;
    setState(() => _size = next);
  }

  void _commit() {
    final key = widget.storageKey;
    if (key == null) return;
    unawaited(KVStoreService.setResizableSize(key, _size));
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handleBase * _scaling;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            widget.horizontal ? constraints.maxWidth : constraints.maxHeight;
        final size = _bounded(_size, widget.min, _maxFor(available));
        final border = Theme.of(context).colorScheme.border;

        final splitter = MouseRegion(
          cursor: widget.horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: widget.horizontal
                ? (details) => _drag(details.delta.dx, available)
                : null,
            onHorizontalDragEnd:
                widget.horizontal ? (details) => _commit() : null,
            onVerticalDragUpdate: widget.horizontal
                ? null
                : (details) => _drag(details.delta.dy, available),
            onVerticalDragEnd:
                widget.horizontal ? null : (details) => _commit(),
            child: SizedBox(
              width: widget.horizontal
                  ? handle
                  : (constraints.hasBoundedWidth
                      ? null
                      : _unboundedHandle * _scaling),
              height: widget.horizontal
                  ? (constraints.hasBoundedHeight
                      ? null
                      : _unboundedHandle * _scaling)
                  : handle,
              child: Center(
                child: Container(
                  width: widget.horizontal ? 1 : null,
                  height: widget.horizontal ? null : 1,
                  color: border,
                ),
              ),
            ),
          ),
        );

        // A page slot can be scrollable, so the cross axis is not guaranteed
        // to be bounded. Stretch would force an infinite extent onto the
        // children; without it they size to their own content instead.
        if (widget.horizontal) {
          return Row(
            crossAxisAlignment: constraints.hasBoundedHeight
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              SizedBox(width: size, child: widget.first),
              splitter,
              Expanded(child: widget.second),
            ],
          );
        }
        return Column(
          crossAxisAlignment: constraints.hasBoundedWidth
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: [
            SizedBox(height: size, child: widget.first),
            splitter,
            if (constraints.hasBoundedHeight)
              Expanded(child: widget.second)
            else
              widget.second,
          ],
        );
      },
    );
  }
}

/// A Material slider for a theme that chose the Material kit.
///
/// The drag value stays local so the thumb follows the pointer, and the seek
/// action fires once on release — the same commit semantics as the host's own
/// progress bar.
class _ThemeUiMaterialProgress extends StatefulWidget {
  final double fraction;
  final double height;
  final double? width;
  final bool enabled;
  final ValueChanged<double> onSeek;

  const _ThemeUiMaterialProgress({
    required this.fraction,
    required this.height,
    required this.width,
    required this.enabled,
    required this.onSeek,
  });

  @override
  State<_ThemeUiMaterialProgress> createState() =>
      _ThemeUiMaterialProgressState();
}

class _ThemeUiMaterialProgressState extends State<_ThemeUiMaterialProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.fraction).clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: widget.width,
      height: math.max(widget.height, 32),
      child: material.SliderTheme(
        data: material.SliderTheme.of(context).copyWith(
          trackHeight: widget.height.clamp(3.0, 12.0).toDouble(),
          thumbShape: const material.RoundSliderThumbShape(
            enabledThumbRadius: 7,
          ),
          overlayShape: const material.RoundSliderOverlayShape(
            overlayRadius: 14,
          ),
        ),
        child: material.Slider(
          value: value,
          onChanged: widget.enabled
              ? (next) => setState(() => _dragValue = next)
              : null,
          onChangeEnd: widget.enabled
              ? (next) {
                  setState(() => _dragValue = null);
                  widget.onSeek(next);
                }
              : null,
        ),
      ),
    );
  }
}

/// A Cupertino slider for a theme that chose the Cupertino kit.
class _ThemeUiCupertinoProgress extends StatefulWidget {
  final double fraction;
  final double height;
  final double? width;
  final bool enabled;
  final ValueChanged<double> onSeek;

  const _ThemeUiCupertinoProgress({
    required this.fraction,
    required this.height,
    required this.width,
    required this.enabled,
    required this.onSeek,
  });

  @override
  State<_ThemeUiCupertinoProgress> createState() =>
      _ThemeUiCupertinoProgressState();
}

class _ThemeUiCupertinoProgressState extends State<_ThemeUiCupertinoProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.fraction).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: widget.width,
      height: math.max(widget.height, 32),
      child: cupertino.CupertinoSlider(
        value: value,
        onChanged:
            widget.enabled ? (next) => setState(() => _dragValue = next) : null,
        onChangeEnd: widget.enabled
            ? (next) {
                setState(() => _dragValue = null);
                widget.onSeek(next);
              }
            : null,
      ),
    );
  }
}
