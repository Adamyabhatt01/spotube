part of 'theme_ui_node.dart';

extension _ThemeUiContentNodes on ThemeUiNodeView {
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

}
