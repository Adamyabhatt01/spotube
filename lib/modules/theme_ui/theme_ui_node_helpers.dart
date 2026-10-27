part of 'theme_ui_node.dart';

extension _ThemeUiNodeHelpers on ThemeUiNodeView {
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

