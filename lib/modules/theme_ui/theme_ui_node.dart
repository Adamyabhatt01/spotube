import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/track_tile/track_context_menu.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/modules/theme_ui/host_widgets/theme_ui_host_widgets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_anchors.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_condition.dart';
import 'package:spotube/modules/theme_ui/host_item_context_menu.dart';
import 'package:spotube/modules/theme_ui/theme_ui_runtime.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_items.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';
import 'package:spotube/modules/theme_ui/theme_ui_render_points.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/utils/theme_converter.dart';

export 'theme_ui_runtime.dart';

part 'theme_ui_node_layout.dart';
part 'theme_ui_node_content.dart';
part 'theme_ui_node_data.dart';
part 'theme_ui_node_helpers.dart';
part 'theme_ui_node_widgets.dart';
part 'theme_ui_node_inputs.dart';
part 'theme_ui_node_overlays.dart';
part 'theme_ui_node_render_points.dart';

const _uiTypes = <String>{
  'row',
  'column',
  'stack',
  'wrap',
  'padding',
  'align',
  'expanded',
  'scroll',
  'box',
  'grid',
  'resizable',
  'safeArea',
  'aspectRatio',
  'kitScope',
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
  'virtualList',
  'table',
  'tree',
  'accordion',
  'collapsible',
  'carousel',
  'badge',
  'chip',
  'avatar',
  'skeleton',
  'spinner',
  'breadcrumb',
  'pagination',
  'slider',
  'switch',
  'checkbox',
  'radioGroup',
  'textField',
  'textArea',
  'select',
  'segmented',
  'tabs',
  'menu',
  'contextMenu',
  'popover',
  'tooltip',
  'dialog',
  'sheet',
  'hostWidget',
};

/// Node types that fire their own actions from a control or overlay.
///
/// Everything else with an `action` is wrapped in a tap target; these types
/// carry the value that `$value` needs, so a generic tap would fire an
/// argument-less action over the top of the real control.
const _selfActionTypes = <String>{
  'button',
  'progress',
  'slider',
  'switch',
  'checkbox',
  'radioGroup',
  'textField',
  'textArea',
  'select',
  'segmented',
  'tabs',
  'menu',
  'contextMenu',
  'dialog',
  'sheet',
  'popover',
  'tooltip',
  'pagination',
  'breadcrumb',
};

const _maxDepth = 16;
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

    // `hiddenWhen` is the envelope guard: when it holds, the node does not
    // exist — uniformly, for every node type, including list rows with their
    // item-scoped bindings. (It used to be schema surface only.)
    if (evaluateThemeUiCondition(runtime.bindings, props['hiddenWhen'])) {
      return const SizedBox.shrink();
    }
    // `disabledWhen` is enforced for every node as pointer inertness. Control
    // nodes (button, inputs) also read it for their own visuals, so this
    // wrapper is the floor, not the only read.
    final disabled = evaluateThemeUiCondition(
      runtime.bindings,
      props['disabledWhen'],
    );

    Widget result = switch (type) {
      'row' => _row(context, props, children),
      'column' => _column(context, props, children),
      'stack' => _stack(context, props, children),
      'wrap' => _wrap(context, props, children),
      'padding' => _padding(context, props, children),
      'align' => _align(context, props, children),
      'expanded' => _expanded(props, children),
      'scroll' => _scroll(context, props, children),
      'box' => _box(context, props, children),
      'grid' => _grid(context, props, children),
      'resizable' => _resizable(context, props, children),
      'safeArea' => _safeArea(context, props, children),
      'aspectRatio' => _aspectRatio(context, props, children),
      'kitScope' => _kitScope(context, props, children),
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
      'virtualList' => _virtualList(context, props, children),
      'table' => _table(context, props, children),
      'tree' => _tree(context, props),
      'accordion' => _accordion(context, props),
      'collapsible' => _collapsible(context, props, children),
      'carousel' => _carousel(context, props, children),
      'badge' => _badge(context, props),
      'chip' => _chip(context, props),
      'avatar' => _avatar(context, props),
      'skeleton' => _skeleton(context, props),
      'spinner' => _spinner(context, props),
      'breadcrumb' => _breadcrumb(context, props),
      'pagination' => _pagination(context, props, actions),
      'slider' => _slider(context, props, actions),
      'switch' => _switch(context, props, actions),
      'checkbox' => _checkbox(context, props, actions),
      'radioGroup' => _radioGroup(context, props, actions),
      'textField' ||
      'textArea' =>
        _textInput(context, props, actions, type == 'textArea'),
      'select' => _select(context, props, actions),
      'segmented' => _segmented(context, props, actions),
      'tabs' => _tabs(context, props, actions),
      'menu' => _menu(context, props),
      'contextMenu' => _contextMenu(context, props, children),
      'popover' => _popover(context, props, children),
      'tooltip' => _tooltip(context, props, children),
      'dialog' => _dialog(context, props, children, node),
      'sheet' => _sheet(context, props, children),
      'hostWidget' => _hostWidget(context, props),
      _ => const SizedBox.shrink(),
    };

    if (actions.isNotEmpty && !_selfActionTypes.contains(type)) {
      result = MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : () => _fire(context, actions),
          child: result,
        ),
      );
    }

    if (disabled && type != 'expanded' && type != 'spacer') {
      result = IgnorePointer(ignoring: true, child: result);
    }

    // `anchor` names a spot a `scrollTo` action can reach. The keyed wrapper
    // is outermost so the anchor's context sits below every scrollable the
    // node itself might introduce.
    final anchor = props['anchor'];
    if (anchor is String && anchor.trim().isNotEmpty) {
      final registry = ThemeUiAnchorRegistryScope.maybeOf(context);
      if (registry != null) {
        result = KeyedSubtree(
          key: registry.keyFor(anchor.trim()),
          child: result,
        );
      }
    }
    // `Expanded` and `Spacer` carry parent data for their Flex; inserting a
    // Material between them and that Flex is a layout error. Their children
    // are separate nodes and get their own Material ancestor.
    if (type == 'expanded' || type == 'spacer') {
      return _applySemantics(props, result);
    }

    // Material kit widgets (Switch, TextField, buttons…) need a Material
    // ancestor for ink and semantics; the bridged Theme alone is not enough.
    // A transparency Material paints nothing, so shadcn nodes are unaffected.
    return _applySemantics(
      props,
      material.Material(
        type: material.MaterialType.transparency,
        child: result,
      ),
    );
  }

  /// Wraps the node in the `semantics` object the author declared.
  ///
  /// `excludeSemantics: true` hides the whole subtree from the semantic tree;
  /// otherwise `label`/`hint`/`value` become a single [Semantics] unit
  /// (`container: true`) so a screen reader speaks the authored text instead
  /// of the visual one.
  Widget _applySemantics(Map<String, dynamic> props, Widget child) {
    final raw = props['semantics'];
    if (raw is! Map) return child;
    final semantics = raw.cast<String, dynamic>();
    if (semantics['excludeSemantics'] == true) {
      return ExcludeSemantics(child: child);
    }
    final label = semantics['label'] is String
        ? (semantics['label'] as String)
        : null;
    final hint = semantics['hint'] is String
        ? (semantics['hint'] as String)
        : null;
    final value = semantics['value'] is String
        ? (semantics['value'] as String)
        : null;
    if (label == null && hint == null && value == null) return child;
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      container: true,
      child: child,
    );
  }

  /// Renders this node as a sliver.
  ///
  /// A vertical `list` (or a `padding` that wraps one) becomes a lazy
  /// `SliverList`; every other node keeps its box layout and is wrapped in a
  /// [SliverToBoxAdapter]. This is what lets `ThemePageContent` preserve the
  /// theme's page composition without eagerly building a 300-row `Column`.
  Widget buildSliver(BuildContext context) {
    return _asSliver(context) ??
        SliverToBoxAdapter(
          child: ThemeUiNodeView(
            node: node,
            runtime: runtime,
            depth: depth,
          ),
        );
  }

  Widget? _asSliver(BuildContext context) {
    if (depth > _maxDepth) return null;
    final type = node['type'];
    if (type is! String) return null;
    final props = _props(node);
    final children = _children(node);

    if (type == 'list') {
      return _listSliver(context, props, children);
    }
    if (type == 'virtualList') {
      return _virtualListSliver(context, props, children);
    }
    if (type == 'padding' && children.length == 1) {
      final inner = ThemeUiNodeView(
        node: children.first,
        runtime: runtime,
        depth: depth + 1,
      )._asSliver(context);
      if (inner == null) return null;
      return SliverPadding(
        padding: _paddingInsets(context, props),
        sliver: inner,
      );
    }
    return null;
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

  void _fire(BuildContext context, List<ThemeUiAction> actions) {
    for (final action in actions) {
      _dispatch(context, action);
    }
  }

  /// Dispatches one action, routing the UI-local `dismiss` verb to the
  /// enclosing overlay when there is one.
  ///
  /// `dismiss` is deliberately not a host capability: it only means "close
  /// this overlay", and an overlay that is not there must not turn it into a
  /// no-op that swallows the rest of an action list.
  void _dispatch(BuildContext context, ThemeUiAction action) {
    if (action.type == 'dismiss') {
      final dismiss = ThemeUiDismissScope.maybeOf(context);
      if (dismiss != null) {
        dismiss();
        return;
      }
    }
    if (action.type == 'scrollTo') {
      _scrollTo(context, action);
      return;
    }
    runtime.onAction(action);
  }

  /// Scrolls the nearest scrollable ancestor of the named `anchor` node into
  /// view. A missing anchor or registry is a theme bug, not a crash — the
  /// action simply does nothing, the same as any other unresolvable target.
  void _scrollTo(BuildContext context, ThemeUiAction action) {
    final raw = action.args['target'] ??
        action.args['anchor'] ??
        action.args['id'] ??
        action.args['value'];
    if (raw is! String || raw.isEmpty) return;
    final registry = ThemeUiAnchorRegistryScope.read(context);
    final target = registry?[raw]?.currentContext;
    if (target == null) return;
    unawaited(Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    ));
  }
}
