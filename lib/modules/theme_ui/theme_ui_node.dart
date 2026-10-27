import 'dart:math' as math;

import 'package:flutter/material.dart'
    show AnimatedContainer, InkWell, Material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_items.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/utils/theme_converter.dart';

typedef ThemeUiActionCallback = void Function(ThemeUiAction action);

/// Everything a node needs to render, independent of Riverpod and routing.
///
/// Keeping the runtime explicit is what makes the node vocabulary testable:
/// a widget test supplies a few bindings and a recording callback and checks
/// the tree, without a provider container, database or audio backend.
class ThemeUiRuntime {
  final ThemeDefinition theme;
  final ThemeUiBindings bindings;
  final ThemeUiAssets assets;
  final Map<String, ThemeUiTemplate> templates;
  final int specVersion;
  final ThemeUiActionCallback onAction;

  const ThemeUiRuntime({
    required this.theme,
    required this.bindings,
    required this.assets,
    required this.templates,
    required this.specVersion,
    required this.onAction,
  });
}

const _uiTypes = <String>{
  'row',
  'column',
  'stack',
  'wrap',
  'padding',
  'align',
  'expanded',
  'scroll',
  'text',
  'icon',
  'image',
  'button',
  'card',
  'search',
  'divider',
  'spacer',
  'gap',
  'conditional',
  'template',
  'animate',
  'progress',
  'list',
};

const _maxDepth = 12;
const _maxChildren = 200;

class ThemeUiNodeView extends StatelessWidget {
  final Map<String, dynamic> node;
  final ThemeUiRuntime runtime;
  final int depth;

  const ThemeUiNodeView({
    required this.node,
    required this.runtime,
    this.depth = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (depth > _maxDepth) return const SizedBox.shrink();
    final type = node['type'];
    if (type is! String || !_uiTypes.contains(type)) {
      return const SizedBox.shrink();
    }

    final props = _props(node);
    final children = _children(node);
    final actions = ThemeUiAction.fromNode(node);

    Widget result = switch (type) {
      'row' => _row(context, props, children),
      'column' => _column(context, props, children),
      'stack' => _stack(context, props, children),
      'wrap' => _wrap(context, props, children),
      'padding' => _padding(context, props, children),
      'align' => _align(context, props, children),
      'expanded' => _expanded(props, children),
      'scroll' => _scroll(context, props, children),
      'text' => _text(context, props),
      'icon' => _icon(context, props),
      'image' => _image(context, props),
      'button' => _button(context, props, node, children),
      'card' => _card(context, props, children),
      'search' => _search(context, props),
      'divider' => _divider(context, props),
      'spacer' => _spacer(props),
      'gap' => _gap(context, props),
      'conditional' => _conditional(context, props, children),
      'template' => _template(context, props, children),
      'animate' => _animate(context, props, children),
      'progress' => _progress(context, props),
      'list' => _list(context, props, children),
      _ => const SizedBox.shrink(),
    };

    if (actions.isNotEmpty && type != 'button' && type != 'progress') {
      result = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _fire(actions),
          child: result,
        ),
      );
    }
    return result;
  }

  /// Reads both the flat shape and the original `props` object. The build
  /// validator rejects unknown props; the host still ignores them rather
  /// than assuming the installed plugin was built by this checkout.
  Map<String, dynamic> _props(Map<String, dynamic> node) {
    final props = <String, dynamic>{};
    final legacy = node['props'];
    if (legacy is Map) props.addAll(legacy.cast<String, dynamic>());
    for (final entry in node.entries) {
      if (entry.key == 'type' ||
          entry.key == 'children' ||
          entry.key == 'props' ||
          entry.key == 'action' ||
          entry.key == 'actions') {
        continue;
      }
      props[entry.key] = entry.value;
    }
    return props;
  }

  List<Map<String, dynamic>> _children(Map<String, dynamic> node) {
    final raw = node['children'];
    if (raw is! List) return const [];
    final children = <Map<String, dynamic>>[];
    for (final child in raw.take(_maxChildren)) {
      if (child is Map) {
        children.add(child.cast<String, dynamic>());
      }
    }
    return children;
  }

  void _fire(List<ThemeUiAction> actions) {
    for (final action in actions) {
      runtime.onAction(action);
    }
  }

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

  // --------------------------------------------------------------- content

  Widget _text(BuildContext context, Map<String, dynamic> props) {
    final bind = props['bind'];
    final value = bind is String
        ? runtime.bindings.display(bind)
        : (props['text'] is String ? props['text'] as String : '');
    final text = value.length > 500 ? value.substring(0, 500) : value;
    final uppercase = props['uppercase'] == true;
    final color = _color(context, props['color'],
        fallback: Theme.of(context).colorScheme.foreground);
    final maxLines = _intOrNull(props['maxLines'], min: 1, max: 50);
    final family = _family(props['family']) ??
        _family(runtime.theme.typography['family']) ??
        runtime.theme.tokens.fontFamily;

    return Text(
      uppercase ? text.toUpperCase() : text,
      textAlign: _textAlign(props['align']),
      maxLines: maxLines,
      overflow: _overflow(props['overflow']),
      style: TextStyle(
        fontSize: _textSize(context, props['size']),
        fontWeight: _fontWeight(props['weight']),
        color: color,
        fontFamily: family,
        letterSpacing: _clamp(props['letterSpacing'], -2, 8),
        height: 1.25,
      ),
    );
  }

  Widget _icon(BuildContext context, Map<String, dynamic> props) {
    final name = props['icon'] is String ? props['icon'] as String : '';
    final override = _iconOverride(name);
    final size = _px(
      context,
      props['size'],
      fallback: _px(context, override?['size'], fallback: 18),
    ).clamp(8.0, 64.0).toDouble();
    final color = _color(context, props['color'],
        fallback: Theme.of(context).colorScheme.foreground);
    final asset = override?['asset'];
    if (asset is String) {
      final file = runtime.assets.resolve(asset);
      if (file != null && file.existsSync()) {
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          color: props['color'] == null ? null : color,
          colorBlendMode: props['color'] == null ? null : BlendMode.srcIn,
          errorBuilder: (_, __, ___) =>
              Icon(_fallbackIcon(name), size: size, color: color),
        );
      }
    }
    return Icon(_fallbackIcon(name), size: size, color: color);
  }

  Widget _image(BuildContext context, Map<String, dynamic> props) {
    final source = _imageSource(props);
    final width = _pxOrNull(context, props['width']);
    final height = _pxOrNull(context, props['height']);
    final radius = _pxOrNull(context, props['radius']);
    final circular = props['shape'] == 'circle';
    final fit = _fit(props['fit']);
    final filter = props['filter'] == 'nearest'
        ? FilterQuality.none
        : FilterQuality.medium;
    final opacity = _clamp(props['opacity'], 0, 1, fallback: 1);
    final provider = _provider(source, width: width, height: height);

    Widget placeholder = Container(
      width: width,
      height: height,
      constraints: width == null && height == null
          ? const BoxConstraints(minWidth: 24, minHeight: 24)
          : null,
      color: Theme.of(context).colorScheme.muted,
    );

    Widget image;
    if (provider == null) {
      image = placeholder;
    } else if (props['tile'] == true) {
      image = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: provider,
            repeat: ImageRepeat.repeat,
            fit: fit,
            filterQuality: filter,
          ),
        ),
      );
    } else {
      image = Image(
        image: provider,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filter,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    if (circular) {
      image = ClipOval(child: image);
    } else if (radius != null && radius > 0) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(radius.clamp(0, 999).toDouble()),
        child: image,
      );
    }
    return opacity < 1 ? Opacity(opacity: opacity, child: image) : image;
  }

  String? _imageSource(Map<String, dynamic> props) {
    final raw = props['src'] ?? props['bind'];
    if (raw is! String || raw.isEmpty) return null;
    if (raw == 'albumArt') return runtime.bindings.display('player.artwork');
    if (raw == 'player.artwork' || raw == 'player.album') {
      return runtime.bindings.display('player.artwork');
    }
    if (raw == 'user.avatar') {
      return runtime.bindings.display('user.avatar');
    }
    // Page and item scopes add bindings the vocabulary cannot enumerate
    // ahead of time (`collection.artwork`, `item.artwork`, ...).
    if (raw.contains('.') && runtime.bindings.raw(raw) != null) {
      return runtime.bindings.display(raw);
    }
    return raw;
  }

  ImageProvider? _provider(String? source, {double? width, double? height}) {
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('asset://')) {
      final file = runtime.assets.resolve(source);
      return file == null ? null : FileImage(file);
    }
    if (source.startsWith('assets/')) return AssetImage(source);
    if (source.startsWith('http')) {
      return UniversalImage.imageProvider(
        source,
        width: width,
        height: height,
      );
    }
    return null;
  }

  /// The host's own search field, mounted in a chrome slot.
  ///
  /// This is intentionally not a themed text input: the field owns focus,
  /// keyboard handling, recent searches and the suggestion portal, so a
  /// click focuses in place instead of navigating away.
  Widget _search(BuildContext context, Map<String, dynamic> props) {
    final placeholder =
        props['placeholder'] is String ? props['placeholder'] as String : null;
    return HomeSearchBar(compact: true, placeholder: placeholder);
  }

  Widget _button(
    BuildContext context,
    Map<String, dynamic> props,
    Map<String, dynamic> node,
    List<Map<String, dynamic>> children,
  ) {
    final style = _buttonStyle(props['variant']);
    final size = switch (props['size']) {
      'small' => 0.85,
      'lg' => 1.2,
      _ => 1.0,
    };
    final disabled = props['disabledWhen'] is String &&
        runtime.bindings.isTruthy(props['disabledWhen'] as String?);
    final actions = ThemeUiAction.fromNode(node);
    final foreground = _color(
      context,
      style['foreground'] ?? '@primaryForeground',
      fallback: Theme.of(context).colorScheme.primaryForeground,
    );
    final background = _color(
      context,
      style['background'] ?? '@primary',
      fallback: Theme.of(context).colorScheme.primary,
    );
    final border = _color(
      context,
      style['borderColor'] ?? background,
      fallback: background,
    );
    final radius = _px(
      context,
      style['radius'],
      fallback: 0,
    ).clamp(0.0, 999.0).toDouble();
    final borderWidth = _px(context, style['borderWidth'], fallback: 0)
        .clamp(0.0, 8.0)
        .toDouble();
    final padding = _px(context, style['padding'], fallback: 10) * size;
    final gap = _px(context, style['gap'], fallback: 8) * size;
    final fontFamily = _family(style['fontFamily']) ??
        _family(runtime.theme.typography['family']);
    final label = props['label'] is String ? props['label'] as String : null;
    var iconName = props['icon'] is String ? props['icon'] as String : null;

    // A theme names the stable verb ("play"), the host chooses the glyph
    // that matches the live state. Without this a playing theme would keep
    // showing a play triangle until the author duplicated every control.
    if (iconName == 'play' &&
        actions.any((action) => action.type == 'playPause') &&
        runtime.bindings.isTruthy('player.playing')) {
      iconName = 'pause';
    }

    final iconSize = _px(
          context,
          style['iconSize'],
          fallback: _px(
            context,
            _iconOverride(iconName ?? '')?['size'],
            fallback: 20,
          ),
        ) *
        size;

    final content = <Widget>[];
    if (iconName != null && iconName.isNotEmpty) {
      content.add(_buttonIcon(context, iconName, iconSize, foreground));
    }
    if (iconName != null && label != null && label.isNotEmpty) {
      content.add(SizedBox(width: gap));
    }
    if (label != null && label.isNotEmpty) {
      content.add(Text(
        label.length > 200 ? label.substring(0, 200) : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontFamily: fontFamily,
          fontSize: _px(context, style['fontSize'], fallback: 18) * size,
          fontWeight: _fontWeight(style['fontWeight']),
          letterSpacing: _clamp(style['letterSpacing'], -2, 8),
        ),
      ));
    }
    if (content.isEmpty) content.addAll(_nodes(context, children));

    final pixel = style['borderStyle'] == 'pixel' && borderWidth > 0;
    final decoration = BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: borderWidth > 0
          ? Border.all(color: border, width: borderWidth)
          : null,
      boxShadow: pixel
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ]
          : null,
    );

    final button = Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled
              ? null
              : () {
                  for (final action in actions) {
                    runtime.onAction(action);
                  }
                },
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: decoration,
            padding: EdgeInsets.symmetric(
              horizontal: padding,
              vertical: padding * 0.7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: content,
            ),
          ),
        ),
      ),
    );
    return disabled ? IgnorePointer(child: button) : button;
  }

  Widget _buttonIcon(
    BuildContext context,
    String name,
    double size,
    Color foreground,
  ) {
    final override = _iconOverride(name);
    final asset = override?['asset'];
    if (asset is String) {
      final file = runtime.assets.resolve(asset);
      if (file != null && file.existsSync()) {
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          color: foreground,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, __, ___) =>
              Icon(_fallbackIcon(name), size: size, color: foreground),
        );
      }
    }
    return Icon(_fallbackIcon(name), size: size, color: foreground);
  }

  Widget _card(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final component = _map(runtime.theme.components['card']);
    final radius = _px(
      context,
      props['radius'] ?? component['radius'],
      fallback: 0,
    ).clamp(0.0, 999.0).toDouble();
    final borderWidth = _px(
      context,
      props['borderWidth'] ?? component['borderWidth'],
      fallback: 0,
    ).clamp(0.0, 8.0).toDouble();
    final background = _color(
      context,
      props['background'] ?? component['background'] ?? '@card',
      fallback: Theme.of(context).colorScheme.card,
    );
    final border = _color(
      context,
      props['borderColor'] ?? component['borderColor'] ?? background,
      fallback: background,
    );
    final hoverRaw = props['hoverBackground'] ?? component['hoverBackground'];
    final hoverBackground = hoverRaw == null
        ? null
        : _color(context, hoverRaw, fallback: background);
    final opacity = _clamp(props['opacity'], 0, 1, fallback: 1);
    final padding = _px(
      context,
      props['padding'] ?? component['padding'],
      fallback: 0,
    );
    // A card without children is a shape, not a container. Width and height
    // are what let a theme draw its own mark — a circle avatar or logo — from
    // the same node instead of shipping a bitmap for it.
    final width = _pxOrNull(context, props['width']);
    final height = _pxOrNull(context, props['height']);
    final pixel = component['borderStyle'] == 'pixel' && borderWidth > 0;
    final motion = themeMotion(runtime.theme);

    return _ThemeUiHoverBuilder(
      hoverColor: hoverBackground,
      builder: (context, hovered) {
        final card = AnimatedContainer(
          duration: motion.fastDuration,
          curve: motion.curve,
          width: width,
          height: height,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: hovered ? hoverBackground : background,
            borderRadius: BorderRadius.circular(radius),
            border: borderWidth > 0
                ? Border.all(color: border, width: borderWidth)
                : null,
            boxShadow: pixel
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: _columnOf(context, children),
        );
        final clipped = radius > 0
            ? ClipRRect(
                borderRadius: BorderRadius.circular(radius), child: card)
            : card;
        return opacity < 1
            ? Opacity(opacity: opacity, child: clipped)
            : clipped;
      },
    );
  }

  Widget _conditional(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final bind = props['bind'] is String ? props['bind'] as String : null;
    var pass = runtime.bindings.matches(bind, props['equals']);
    if (props['invert'] == true) pass = !pass;
    final chosen = pass
        ? (children.isNotEmpty ? children.first : null)
        : (children.length > 1 ? children[1] : null);
    if (chosen == null) return const SizedBox.shrink();
    return ThemeUiNodeView(
      node: chosen,
      runtime: runtime,
      depth: depth + 1,
    );
  }

  Widget _template(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final name = props['name'];
    if (name is! String) return const SizedBox.shrink();
    final template = runtime.templates[name];
    if (template == null) return const SizedBox.shrink();
    final args = _map(props['args']);
    final expanded =
        template.children.map((child) => _substitute(child, args)).toList();
    return _columnOf(context, expanded);
  }

  Widget _animate(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    return _AnimatedNode(
      props: props,
      runtime: runtime,
      child: _columnOf(context, children),
    );
  }

  // --------------------------------------------------------------- helpers

  Widget _columnOf(BuildContext context, List<Map<String, dynamic>> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) {
      return ThemeUiNodeView(
        node: children.first,
        runtime: runtime,
        depth: depth + 1,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _nodes(context, children),
    );
  }

  Widget _columnOfWithoutContext(List<Map<String, dynamic>> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) {
      return ThemeUiNodeView(
        node: children.first,
        runtime: runtime,
        depth: depth + 1,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .map((child) => ThemeUiNodeView(
                node: child,
                runtime: runtime,
                depth: depth + 1,
              ))
          .toList(),
    );
  }

  List<Widget> _nodes(
    BuildContext context,
    List<Map<String, dynamic>> children,
  ) {
    return children
        .map((child) => ThemeUiNodeView(
              node: child,
              runtime: runtime,
              depth: depth + 1,
            ))
        .toList();
  }

  List<Widget> _withGaps(
    BuildContext context,
    List<Map<String, dynamic>> children,
    double gap,
    Axis axis,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && gap > 0) {
        widgets.add(SizedBox(
          width: axis == Axis.horizontal ? gap : 0,
          height: axis == Axis.horizontal ? 0 : gap,
        ));
      }
      widgets.add(ThemeUiNodeView(
        node: children[i],
        runtime: runtime,
        depth: depth + 1,
      ));
    }
    return widgets;
  }

  double _gapSize(BuildContext context, Object? value) {
    return _px(context, value, fallback: 0).clamp(0.0, 64.0).toDouble();
  }

  double _px(BuildContext context, Object? raw, {double? fallback}) {
    final value = raw is num ? raw.toDouble() : fallback;
    if (value == null || !value.isFinite) return 0;
    return (value * Theme.of(context).scaling).clamp(0.0, 2000.0).toDouble();
  }

  double? _pxOrNull(BuildContext context, Object? raw) {
    if (raw is! num || !raw.isFinite) return null;
    return (raw.toDouble() * Theme.of(context).scaling)
        .clamp(0.0, 2000.0)
        .toDouble();
  }

  double _textSize(BuildContext context, Object? raw) {
    final base = switch (raw) {
      'xs' => 11.0,
      'small' || 'sm' => 13.0,
      'md' => 16.0,
      'lg' => 19.0,
      'xl' => 24.0,
      '2xl' => 30.0,
      '3xl' => 38.0,
      '4xl' => 48.0,
      '5xl' => 60.0,
      '6xl' => 72.0,
      num value => value.toDouble(),
      _ => 16.0,
    };
    return (base * Theme.of(context).scaling).clamp(8.0, 96.0).toDouble();
  }

  FontWeight _fontWeight(Object? raw) {
    final weight = switch (raw) {
      'thin' => 100,
      'light' => 300,
      'normal' => 400,
      'medium' => 500,
      'semibold' => 600,
      'bold' => 700,
      'black' => 900,
      num value => value.toInt(),
      _ => 400,
    };
    final index = ((weight ~/ 100) - 1).clamp(0, 8);
    return FontWeight.values[index];
  }

  Color _color(BuildContext context, Object? raw, {required Color fallback}) {
    if (raw is! String || raw.isEmpty) return fallback;
    if (raw == 'transparent' || raw == 'none') return Colors.transparent;
    final scheme = Theme.of(context).colorScheme;
    if (raw.startsWith('@')) {
      return switch (raw.substring(1)) {
        'primary' => scheme.primary,
        'primaryForeground' => scheme.primaryForeground,
        'secondary' => scheme.secondary,
        'secondaryForeground' => scheme.secondaryForeground,
        'accent' => scheme.accent,
        'accentForeground' => scheme.accentForeground,
        'muted' => scheme.muted,
        'mutedForeground' => scheme.mutedForeground,
        'destructive' => scheme.destructive,
        // v3 keeps destructiveForeground as a role; shadcn still stores the
        // field but marks the getter deprecated. Keep the exact role colour.
        // ignore: deprecated_member_use
        'destructiveForeground' => scheme.destructiveForeground,
        'background' => scheme.background,
        'foreground' => scheme.foreground,
        'card' => scheme.card,
        'cardForeground' => scheme.cardForeground,
        'popover' => scheme.popover,
        'popoverForeground' => scheme.popoverForeground,
        'border' => scheme.border,
        'input' => scheme.input,
        'ring' => scheme.ring,
        'sidebar' => scheme.sidebar,
        'sidebarForeground' => scheme.sidebarForeground,
        'sidebarPrimary' => scheme.sidebarPrimary,
        'sidebarPrimaryForeground' => scheme.sidebarPrimaryForeground,
        'sidebarAccent' => scheme.sidebarAccent,
        'sidebarAccentForeground' => scheme.sidebarAccentForeground,
        'sidebarBorder' => scheme.sidebarBorder,
        'sidebarRing' => scheme.sidebarRing,
        'chart1' => scheme.chart1,
        'chart2' => scheme.chart2,
        'chart3' => scheme.chart3,
        'chart4' => scheme.chart4,
        'chart5' => scheme.chart5,
        'chart6' => context.chart6Color,
        'success' => context.successColor,
        'successForeground' => context.successForegroundColor,
        'warning' => context.warningColor,
        'warningForeground' => context.warningForegroundColor,
        'info' => context.infoColor,
        'infoForeground' => context.infoForegroundColor,
        _ => fallback,
      };
    }
    try {
      return ThemeConverter.parseColor(raw);
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic>? _iconOverride(String name) {
    final overrides = _map(runtime.theme.icons['overrides']);
    final entry = _map(overrides[name]);
    return entry.isEmpty ? null : entry;
  }

  Map<String, dynamic> _buttonStyle(Object? variant) {
    final buttons = _map(runtime.theme.components['buttons']);
    final style = _map(buttons[variant is String ? variant : 'primary']);
    return style;
  }

  Map<String, dynamic> _map(Object? raw) {
    if (raw is! Map) return const {};
    return raw.cast<String, dynamic>();
  }

  Map<String, dynamic> _substitute(
    Map<String, dynamic> node,
    Map<String, dynamic> args,
  ) {
    Object? replace(Object? value) {
      if (value is String) {
        var result = value;
        for (final entry in args.entries) {
          result = result.replaceAll('{{${entry.key}}}', '${entry.value}');
        }
        return result;
      }
      if (value is Map) {
        return {
          for (final entry in value.entries) entry.key: replace(entry.value),
        };
      }
      if (value is List) return value.map(replace).toList();
      return value;
    }

    return {
      for (final entry in node.entries) entry.key: replace(entry.value),
    };
  }

  int _int(Object? raw,
      {required int fallback, required int min, required int max}) {
    if (raw is! num || !raw.isFinite) return fallback;
    return raw.toInt().clamp(min, max);
  }

  int? _intOrNull(Object? raw, {required int min, required int max}) {
    if (raw is! num || !raw.isFinite) return null;
    return raw.toInt().clamp(min, max);
  }

  double _clamp(Object? raw, double min, double max, {double fallback = 0}) {
    if (raw is! num || !raw.isFinite) return fallback;
    return raw.toDouble().clamp(min, max).toDouble();
  }

  String? _family(Object? raw) {
    if (raw is! String) return null;
    final family = raw.trim();
    if (family.isEmpty || family.length > 64) return null;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$').hasMatch(family)) return null;
    return family;
  }

  MainAxisAlignment _main(Object? raw) => switch (raw) {
        'center' => MainAxisAlignment.center,
        'end' => MainAxisAlignment.end,
        'spaceBetween' => MainAxisAlignment.spaceBetween,
        'spaceAround' => MainAxisAlignment.spaceAround,
        'spaceEvenly' => MainAxisAlignment.spaceEvenly,
        _ => MainAxisAlignment.start,
      };

  CrossAxisAlignment _cross(Object? raw) => switch (raw) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        'stretch' => CrossAxisAlignment.stretch,
        'baseline' => CrossAxisAlignment.baseline,
        _ => CrossAxisAlignment.start,
      };

  WrapAlignment _wrapMain(Object? raw) => switch (raw) {
        'center' => WrapAlignment.center,
        'end' => WrapAlignment.end,
        'spaceBetween' => WrapAlignment.spaceBetween,
        'spaceAround' => WrapAlignment.spaceAround,
        'spaceEvenly' => WrapAlignment.spaceEvenly,
        _ => WrapAlignment.start,
      };

  WrapCrossAlignment _wrapCross(Object? raw) => switch (raw) {
        'center' => WrapCrossAlignment.center,
        'end' => WrapCrossAlignment.end,
        _ => WrapCrossAlignment.start,
      };

  Alignment _alignment(Object? raw) => switch (raw) {
        'topLeft' => Alignment.topLeft,
        'topCenter' || 'centerTop' => Alignment.topCenter,
        'topRight' => Alignment.topRight,
        'centerLeft' || 'start' => Alignment.centerLeft,
        'centerRight' || 'end' => Alignment.centerRight,
        'bottomLeft' => Alignment.bottomLeft,
        'bottomCenter' || 'centerBottom' => Alignment.bottomCenter,
        'bottomRight' => Alignment.bottomRight,
        _ => Alignment.center,
      };

  TextAlign _textAlign(Object? raw) => switch (raw) {
        'center' => TextAlign.center,
        'right' || 'end' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      };

  TextOverflow _overflow(Object? raw) => switch (raw) {
        'ellipsis' => TextOverflow.ellipsis,
        'clip' => TextOverflow.clip,
        'fade' => TextOverflow.fade,
        _ => TextOverflow.clip,
      };

  BoxFit _fit(Object? raw) => switch (raw) {
        'contain' => BoxFit.contain,
        'cover' => BoxFit.cover,
        'fill' => BoxFit.fill,
        'fitWidth' => BoxFit.fitWidth,
        'fitHeight' => BoxFit.fitHeight,
        'none' => BoxFit.none,
        'scaleDown' => BoxFit.scaleDown,
        _ => BoxFit.cover,
      };

  IconData _fallbackIcon(String name) => switch (name) {
        'play' => SpotubeIcons.play,
        'pause' => SpotubeIcons.pause,
        'previous' || 'skipPrevious' => SpotubeIcons.skipBack,
        'next' || 'skipNext' => SpotubeIcons.skipForward,
        'shuffle' => SpotubeIcons.shuffle,
        'repeat' => SpotubeIcons.repeat,
        'repeatOne' => SpotubeIcons.repeatOne,
        'liked' => SpotubeIcons.heartFilled,
        'like' => SpotubeIcons.heart,
        'lyrics' => SpotubeIcons.lyrics,
        'queue' => SpotubeIcons.queue,
        'volume' => SpotubeIcons.volumeHigh,
        'settings' => SpotubeIcons.settings,
        'search' => SpotubeIcons.search,
        'library' => SpotubeIcons.library,
        'download' => SpotubeIcons.download,
        'back' => SpotubeIcons.angleLeft,
        'close' => SpotubeIcons.close,
        'plus' => SpotubeIcons.add,
        'home' => SpotubeIcons.home,
        'radio' => SpotubeIcons.radio,
        'stats' => SpotubeIcons.chart,
        _ => Icons.circle_outlined,
      };
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
