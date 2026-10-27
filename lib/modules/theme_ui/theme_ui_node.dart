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

part 'theme_ui_node_layout.dart';
part 'theme_ui_node_content.dart';
part 'theme_ui_node_helpers.dart';
part 'theme_ui_node_widgets.dart';

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
}
