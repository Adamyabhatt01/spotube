import 'dart:math' as math;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/region_scope.dart';
import 'package:spotube/modules/root/shell_regions.dart';
import 'package:spotube/modules/root/sidebar/sidebar_visibility.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';

/// Renders a theme's `layout.shell` tree.
///
/// The host supplies the region widgets (router outlet, sidebar, player, …)
/// and owns the sizing algorithm; the theme owns only the arrangement. A shell
/// that fails to parse never reaches this widget: [ThemeShellLayout.parse]
/// returns null and the legacy layout stands.
class ShellLayoutHost extends ConsumerWidget {
  final ThemeShellLayout shell;

  /// The keyed router outlet. Passed in from the root so its identity does not
  /// depend on where in the tree this widget places it.
  final Widget content;

  /// Whether to add a drag strip above the tree when the theme omitted a
  /// `titlebar` region. Desktop only; skipped when the system title bar is on.
  final bool injectTitlebar;

  const ShellLayoutHost({
    required this.shell,
    required this.content,
    this.injectTitlebar = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = _hiddenLeaves(context, ref);
    final root = shell.root;

    Widget tree = _buildNode(
      context,
      ref,
      root,
      hidden,
      parentAxis: Axis.vertical,
    );

    if (root.isRegion) {
      final key = root.effectiveId == null
          ? null
          : regionStorageKey(
              id: root.effectiveId!,
              storageKey: root.storageKey,
            );
      final collapseOverrides = ref.watch(regionCollapseProvider);
      final collapsed = root.collapsible &&
          key != null &&
          (collapseOverrides[key] ?? storedRegionCollapsed(key));
      tree = _decorateRegion(
        context,
        ref,
        root,
        tree,
        parentAxis: Axis.vertical,
        mainSize: null,
        collapsed: collapsed,
        storageKey: key,
      );
    }

    final hasTitlebar = shell.root.leaves
        .any((leaf) => leaf.region == ThemeShellRegion.titlebar);
    final systemTitleBar =
        ref.watch(userPreferencesProvider.select((s) => s.systemTitleBar));
    if (injectTitlebar && !hasTitlebar && kIsDesktop && !systemTitleBar) {
      // Pages own their own title bars, so this is a transparent drag band,
      // not a second one: it only exists so a page without a TitleBar can
      // still move the window.
      tree = Column(
        children: [
          const SizedBox(
            height: 28,
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          Expanded(child: tree),
        ],
      );
    }

    // A shell that hides every bar still has to let the router rebuild.
    return tree;
  }

  // ------------------------------------------------------------- visibility

  Set<ThemeShellNode> _hiddenLeaves(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPreferencesProvider);
    final layoutMode = prefs.layoutMode;
    final asideOpen = prefs.asideOpen;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final hidden = <ThemeShellNode>{};

    final hiddenWhen = <ThemeShellNode, bool>{};
    for (final leaf in shell.root.leaves) {
      final expression = leaf.hiddenWhen;
      if (expression == null || expression.trim().isEmpty) continue;
      hiddenWhen[leaf] = _evaluateHiddenWhen(context, ref, expression);
    }

    for (final leaf in shell.root.leaves) {
      if (hiddenWhen[leaf] == true) {
        hidden.add(leaf);
        continue;
      }
      switch (leaf.region!) {
        case ThemeShellRegion.content:
        case ThemeShellRegion.player:
        case ThemeShellRegion.titlebar:
        case ThemeShellRegion.navbar:
          break;
        case ThemeShellRegion.sidebar:
          if (!sidebarVisibleOf(context, layoutMode)) hidden.add(leaf);
        case ThemeShellRegion.aside:
          final slotFilled = leaf.slot != null
              ? themeUiSlotExists(ref, leaf.slot!)
              : themeUiSlotExists(ref, 'aside.content');
          if (!asideOpen || !slotFilled || windowWidth <= _asideBreakpoint) {
            hidden.add(leaf);
          }
        case ThemeShellRegion.custom:
          if (leaf.slot == null || !themeUiSlotExists(ref, leaf.slot!)) {
            hidden.add(leaf);
          }
      }
    }
    return hidden;
  }

  static const _asideBreakpoint = 820.0;

  /// Evaluates the small comparison vocabulary `hiddenWhen` uses.
  ///
  /// Deliberately fail-open: an expression the host cannot parse leaves the
  /// region visible rather than deleting a control the theme meant to keep.
  bool _evaluateHiddenWhen(
    BuildContext context,
    WidgetRef ref,
    String expression,
  ) {
    var raw = expression.trim();
    var negate = false;
    while (raw.startsWith('!')) {
      negate = !negate;
      raw = raw.substring(1).trim();
    }

    final comparison =
        RegExp(r'^(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+)$').firstMatch(raw);
    if (comparison == null) {
      final value = _bindingValues(context, ref, [raw])[raw];
      final truthy = _truthy(value);
      return negate ? !truthy : truthy;
    }

    final left = comparison.group(1)!.trim();
    final operator = comparison.group(2)!;
    final right = _literal(comparison.group(3)!.trim());
    final value = _bindingValues(context, ref, [left])[left];
    final result = switch (operator) {
      '==' => _equals(value, right),
      '!=' => !_equals(value, right),
      '>' => value is num && right is num && value > right,
      '<' => value is num && right is num && value < right,
      '>=' => value is num && right is num && value >= right,
      '<=' => value is num && right is num && value <= right,
      _ => true,
    };
    return negate ? !result : result;
  }

  Map<String, Object?> _bindingValues(
    BuildContext context,
    WidgetRef ref,
    Iterable<String> names,
  ) {
    final wanted = <String>{};
    for (final name in names) {
      for (final match in _bindingToken.allMatches(name)) {
        final token = match.group(0)!;
        if (!token.startsWith('region.')) wanted.add(token);
      }
    }
    if (wanted.isEmpty) return const {};
    final bindings = buildThemeUiBindings(
      ref,
      brightness: Theme.of(context).brightness,
      themeMode: ref.read(userPreferencesProvider).themeMode.name,
      demand: ThemeUiBindingDemand(wanted),
    );
    return bindings.values;
  }

  static final _bindingToken =
      RegExp(r'[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_-]+)+');

  Object? _literal(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw == 'null') return null;
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      return raw.substring(1, raw.length - 1);
    }
    return num.tryParse(raw) ?? raw;
  }

  bool _equals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is bool && b is bool) return a == b;
    return a == b;
  }

  bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }

  // ------------------------------------------------------------------ tree

  bool _visible(ThemeShellNode node, Set<ThemeShellNode> hidden) {
    if (node.isRegion) return !hidden.contains(node);
    return node.children.any((child) => _visible(child, hidden));
  }

  Widget _buildNode(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Set<ThemeShellNode> hidden, {
    required Axis parentAxis,
  }) {
    if (!_visible(node, hidden)) return const SizedBox.shrink();
    if (node.isRegion) return _buildLeaf(context, ref, node, parentAxis);
    switch (node.type!) {
      case ThemeShellNodeType.row:
        return _buildFlex(
          context,
          ref,
          node,
          hidden,
          horizontal: true,
        );
      case ThemeShellNodeType.column:
        return _buildFlex(
          context,
          ref,
          node,
          hidden,
          horizontal: false,
        );
      case ThemeShellNodeType.stack:
        return _buildStack(context, ref, node, hidden);
      case ThemeShellNodeType.grid:
        return _buildGrid(context, ref, node, hidden);
    }
  }

  Widget _buildStack(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Set<ThemeShellNode> hidden,
  ) {
    final children = node.children
        .where((child) => _visible(child, hidden))
        .toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    if (children.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final child in children)
          _buildNode(
            context,
            ref,
            child,
            hidden,
            parentAxis: Axis.vertical,
          ),
      ],
    );
  }

  /// A grid is a single equal-width row. The contract has no column count, and
  /// the shape themes actually use it for is a strip of equally sized bars.
  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Set<ThemeShellNode> hidden,
  ) {
    final children =
        node.children.where((child) => _visible(child, hidden)).toList();
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          Expanded(
            flex: child.flex > 0 ? child.flex : 1,
            child: _buildNode(
              context,
              ref,
              child,
              hidden,
              parentAxis: Axis.horizontal,
            ),
          ),
      ],
    );
  }

  Widget _buildFlex(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Set<ThemeShellNode> hidden, {
    required bool horizontal,
  }) {
    final children =
        node.children.where((child) => _visible(child, hidden)).toList();
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        var extent = horizontal ? constraints.maxWidth : constraints.maxHeight;
        if (!extent.isFinite) {
          extent = horizontal ? media.width : media.height;
        }

        final sizeOverrides = ref.watch(regionSizeProvider);
        final collapseOverrides = ref.watch(regionCollapseProvider);

        final placements = <_Placement>[];
        var fixedTotal = 0.0;
        var totalFlex = 0;

        for (final child in children) {
          final key = child.effectiveId == null
              ? null
              : regionStorageKey(
                  id: child.effectiveId!,
                  storageKey: child.storageKey,
                );
          final collapsed = child.collapsible &&
              key != null &&
              (collapseOverrides[key] ?? storedRegionCollapsed(key));
          final declaration = horizontal ? child.width : child.height;
          final defaultSize = child.isRegion && !collapsed
              ? _defaultMainSize(child.region!, horizontal)
              : null;

          double? fixed;
          if (collapsed) {
            fixed = _collapsedMainSize(child, horizontal);
          } else if (declaration != null) {
            if (declaration.pixels != null) {
              final stored = key == null
                  ? null
                  : sizeOverrides[key] ?? storedRegionSizeOrNull(key);
              fixed = stored ?? declaration.pixels;
            } else if (declaration.percent != null) {
              fixed = declaration.percent! * extent / 100;
            }
            // `auto` is left to the child's intrinsic size.
          } else if (defaultSize != null && defaultSize.pixels != null) {
            final stored = key == null
                ? null
                : sizeOverrides[key] ?? storedRegionSizeOrNull(key);
            fixed = stored ?? defaultSize.pixels;
          }

          final flex =
              collapsed ? 0 : _effectiveFlex(child, declaration, horizontal);
          if (fixed != null) {
            fixedTotal += fixed.clamp(
                _minMain(child, horizontal), _maxMain(child, horizontal));
          }
          if (flex > 0) totalFlex += flex;
          placements.add(
            _Placement(
              node: child,
              fixed: fixed,
              flex: flex,
              collapsed: collapsed,
              storageKey: key,
            ),
          );
        }

        final remaining = math.max(0.0, extent - fixedTotal);
        final built = <Widget>[];
        for (final placement in placements) {
          final child = placement.node;
          var main = placement.fixed;
          if (placement.flex > 0 && totalFlex > 0) {
            final share = remaining * placement.flex / totalFlex;
            main = (main ?? 0) + share;
          }
          if (main != null) {
            main = main
                .clamp(_minMain(child, horizontal), _maxMain(child, horizontal))
                .toDouble();
          }

          Widget childWidget = _buildNode(
            context,
            ref,
            child,
            hidden,
            parentAxis: horizontal ? Axis.horizontal : Axis.vertical,
          );

          if (child.isRegion) {
            childWidget = _decorateRegion(
              context,
              ref,
              child,
              childWidget,
              parentAxis: horizontal ? Axis.horizontal : Axis.vertical,
              mainSize: main,
              collapsed: placement.collapsed,
              storageKey: placement.storageKey,
            );
          }

          final crossDeclaration = horizontal ? child.height : child.width;
          final cross = crossDeclaration?.resolve(
            horizontal ? constraints.maxHeight : constraints.maxWidth,
          );

          if (main != null) {
            childWidget = horizontal
                ? SizedBox(width: main, child: childWidget)
                : SizedBox(height: main, child: childWidget);
          }
          if (cross != null) {
            childWidget = Align(
              alignment: Alignment.center,
              child: horizontal
                  ? SizedBox(height: cross, child: childWidget)
                  : SizedBox(width: cross, child: childWidget),
            );
          }
          built.add(childWidget);
        }

        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: built,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: built,
              );
      },
    );
  }

  // --------------------------------------------------------------- regions

  Widget _buildLeaf(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Axis parentAxis,
  ) {
    final slot = node.slot;
    final hasSlot = slot != null && themeUiSlotExists(ref, slot);
    final region = node.region!;

    Widget child;
    switch (region) {
      case ThemeShellRegion.content:
        // A slot on `content` is intentionally ignored: the router outlet is
        // the one thing a theme cannot replace without unmounting navigation.
        child = ContentRegion(content: content);
      case ThemeShellRegion.sidebar:
        child = SidebarRegion(slot: hasSlot ? slot : null);
      case ThemeShellRegion.aside:
        child = ShellAsideRegion(slot: hasSlot ? slot : null);
      case ThemeShellRegion.player:
        child = PlayerRegion(slot: hasSlot ? slot : null);
      case ThemeShellRegion.titlebar:
        child = TitlebarRegion(slot: hasSlot ? slot : null);
      case ThemeShellRegion.navbar:
        child = NavbarRegion(slot: hasSlot ? slot : null);
      case ThemeShellRegion.custom:
        child = slot == null
            ? const SizedBox.shrink()
            : CustomRegion(slot: slot, label: node.label);
    }

    child = _applySafeArea(node, child);
    final overflow = node.overflow;
    if (overflow == 'scroll') {
      child = SingleChildScrollView(
        scrollDirection:
            parentAxis == Axis.horizontal ? Axis.vertical : Axis.horizontal,
        child: child,
      );
    } else if (overflow != null) {
      // `wrap` and `menu` have no host chrome yet; clip is the safe default.
      child = ClipRect(child: child);
    }

    return child;
  }

  Widget _decorateRegion(
    BuildContext context,
    WidgetRef ref,
    ThemeShellNode node,
    Widget child, {
    required Axis parentAxis,
    required double? mainSize,
    required bool collapsed,
    required String? storageKey,
  }) {
    final id = node.effectiveId;
    Widget result = LayoutBuilder(
      builder: (context, constraints) {
        final state = RegionState(
          id: id ?? 'region',
          size: Size(constraints.maxWidth, constraints.maxHeight),
          collapsed: collapsed,
          visible: true,
        );
        return RegionScope(state: state, child: child);
      },
    );

    final hasHandle =
        node.resizable != null && storageKey != null && !collapsed;
    final canCollapse = node.collapsible && storageKey != null;
    if (hasHandle || canCollapse) {
      result = Stack(
        fit: StackFit.expand,
        children: [
          result,
          if (hasHandle)
            Positioned(
              right: parentAxis == Axis.horizontal ? 0 : null,
              bottom: parentAxis == Axis.horizontal ? null : 0,
              top: 0,
              left: parentAxis == Axis.horizontal ? null : 0,
              child: _ResizeHandle(
                node: node,
                storageKey: storageKey,
                horizontal: parentAxis == Axis.horizontal,
                current: mainSize,
              ),
            ),
          if (canCollapse)
            Positioned(
              top: 2,
              right: 2,
              child: _CollapseControl(
                storageKey: storageKey,
                collapsed: collapsed,
              ),
            ),
        ],
      );
    }

    final focusOrder = node.focusOrder;
    if (focusOrder != null) {
      result = FocusTraversalOrder(
        order: NumericFocusOrder(focusOrder.toDouble()),
        child: result,
      );
    }
    return ClipRect(child: result);
  }

  Widget _applySafeArea(ThemeShellNode node, Widget child) {
    if (node.safeArea.isEmpty) return child;
    return SafeArea(
      top: node.safeArea.contains('top'),
      right: node.safeArea.contains('right'),
      bottom: node.safeArea.contains('bottom'),
      left: node.safeArea.contains('left'),
      child: child,
    );
  }

  ThemeShellSize? _defaultMainSize(
    ThemeShellRegion region,
    bool horizontal,
  ) {
    if (region == ThemeShellRegion.custom) return const ThemeShellSize.px(0);
    if (horizontal) {
      return switch (region) {
        ThemeShellRegion.sidebar => const ThemeShellSize.px(280),
        ThemeShellRegion.aside => const ThemeShellSize.px(320),
        _ => null,
      };
    }
    return switch (region) {
      ThemeShellRegion.player => const ThemeShellSize.px(88),
      ThemeShellRegion.titlebar => const ThemeShellSize.px(36),
      ThemeShellRegion.navbar => const ThemeShellSize.px(56),
      _ => null,
    };
  }

  int _effectiveFlex(
    ThemeShellNode node,
    ThemeShellSize? declaration,
    bool horizontal,
  ) {
    if (node.flex > 0) return node.flex;
    if (node.isRegion) {
      if (node.region == ThemeShellRegion.content) return 1;
      if (declaration == null &&
          _defaultMainSize(node.region!, horizontal) == null) {
        return 1;
      }
      return 0;
    }
    return declaration == null ? 1 : 0;
  }

  double _collapsedMainSize(ThemeShellNode node, bool horizontal) {
    final declared = node.collapsedSize;
    if (declared != null) return declared;
    return switch (node.region) {
      ThemeShellRegion.sidebar ||
      ThemeShellRegion.aside ||
      ThemeShellRegion.custom =>
        0,
      _ => 32,
    };
  }

  double _minMain(ThemeShellNode node, bool horizontal) =>
      (horizontal ? node.minWidth : node.minHeight) ?? 0;

  double _maxMain(ThemeShellNode node, bool horizontal) =>
      (horizontal ? node.maxWidth : node.maxHeight) ?? double.infinity;
}

class _Placement {
  final ThemeShellNode node;
  final double? fixed;
  final int flex;
  final bool collapsed;
  final String? storageKey;

  const _Placement({
    required this.node,
    required this.fixed,
    required this.flex,
    required this.collapsed,
    required this.storageKey,
  });
}

class _ResizeHandle extends ConsumerWidget {
  final ThemeShellNode node;
  final String storageKey;
  final bool horizontal;
  final double? current;

  const _ResizeHandle({
    required this.node,
    required this.storageKey,
    required this.horizontal,
    required this.current,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final min = node.resizable?.min ??
        (horizontal ? node.minWidth : node.minHeight) ??
        0;
    final max = node.resizable?.max ??
        (horizontal ? node.maxWidth : node.maxHeight) ??
        double.infinity;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: horizontal
            ? (details) => _drag(ref, details.delta.dx, min, max)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => _drag(ref, details.delta.dy, min, max),
        onDoubleTap: () {
          ref.read(regionSizeProvider.notifier).update(
                (sizes) => {...sizes}..remove(storageKey),
              );
          clearStoredRegionSize(storageKey);
        },
        child: SizedBox(
          width: horizontal ? 8 : double.infinity,
          height: horizontal ? double.infinity : 8,
        ),
      ),
    );
  }

  void _drag(WidgetRef ref, double delta, double min, double max) {
    final base = current ?? 0;
    final next = (base + delta).clamp(min, max).toDouble();
    ref.read(regionSizeProvider.notifier).update(
          (sizes) => {...sizes, storageKey: next},
        );
    persistRegionSize(storageKey, next);
  }
}

class _CollapseControl extends ConsumerWidget {
  final String storageKey;
  final bool collapsed;

  const _CollapseControl({
    required this.storageKey,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.ghost(
      size: ButtonSize.xSmall,
      icon: Icon(
        collapsed ? SpotubeIcons.angleRight : SpotubeIcons.angleLeft,
        size: 14,
      ),
      onPressed: () {
        final next = !collapsed;
        ref.read(regionCollapseProvider.notifier).update(
              (states) => {...states, storageKey: next},
            );
        persistRegionCollapsed(storageKey, next);
      },
    );
  }
}
