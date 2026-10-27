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
      enabled:
          props['interactive'] != false && (duration?.inMilliseconds ?? 0) > 0,
      onSeek: (value) => runtime.onAction(
        ThemeUiAction('seek', {'fraction': value}),
      ),
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
    final items = source.take(limit).toList();
    final activeTrackId = runtime.bindings.raw('player.trackId');
    final gap = _gapSize(context, props['gap']);
    final crossAxisAlignment = _cross(props['align']);
    // A shelf is a list that scrolls sideways. The repeated entry is the same
    // subtree; only the axis changes, so cards and rows share one vocabulary.
    final horizontal = props['direction'] == 'horizontal';

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0 && gap > 0) {
        rows.add(SizedBox(
          width: horizontal ? gap : 0,
          height: horizontal ? 0 : gap,
        ));
      }
      final item = items[i];
      final itemRuntime = ThemeUiRuntime(
        theme: runtime.theme,
        bindings: ThemeUiBindings({
          ...runtime.bindings.values,
          ...themeItemBindings(
            item,
            index: i,
            activeTrackId: activeTrackId is String ? activeTrackId : null,
          ),
        }),
        assets: runtime.assets,
        templates: runtime.templates,
        specVersion: runtime.specVersion,
        onAction: (action) {
          if (itemActionTypes.contains(action.type)) {
            runtime.onAction(ThemeUiAction(action.type, {
              ...action.args,
              'item': item,
              'index': i,
              'items': items,
            }));
          } else {
            runtime.onAction(action);
          }
        },
      );
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

}
