import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/constrains.dart';

class AdaptiveMenuButton<T> extends MenuButton {
  final T? value;
  const AdaptiveMenuButton({
    super.key,
    this.value,
    required super.child,
    super.subMenu,
    super.onPressed,
    super.trailing,
    super.leading,
    super.enabled = true,
    super.focusNode,
    super.autoClose = true,
    super.popoverController,
  }) : assert(
          value != null || onPressed != null,
          'Either value or onPressed must be provided',
        );
}

/// Maps menu entries whose value drives selection into plain [MenuButton]s.
///
/// Shared by the trigger menu and the pointer/long-press context menu so both
/// report through `onSelected` the same way.
List<MenuButton> buildAdaptiveMenuButtons<T>(
  BuildContext context,
  List<AdaptiveMenuButton<T>> items,
  ValueChanged<T>? onSelected,
) {
  return items.map((s) {
    if (s.onPressed == null) {
      return MenuButton(
        key: s.key,
        autoClose: s.autoClose,
        enabled: s.enabled,
        leading: s.leading,
        focusNode: s.focusNode,
        onPressed: (context) {
          if (s.value != null) {
            onSelected?.call(s.value as T);
          }
        },
        popoverController: s.popoverController,
        subMenu: s.subMenu,
        trailing: s.trailing,
        child: s.child,
      );
    }
    return s;
  }).toList();
}

/// Desktop dropdown anchored at a global position.
///
/// Pass `follow: false` when [position] must win (pointer or long-press
/// menus); the default re-anchors to the caller's render box every frame.
OverlayCompleter<T?> showAdaptiveMenuDropdown<T>({
  required BuildContext context,
  required Offset position,
  required List<AdaptiveMenuButton<T>> Function(BuildContext context) items,
  ValueChanged<T>? onSelected,
  bool rootOverlay = true,
  bool follow = true,
  AlignmentGeometry? alignment,
  Offset? offset,
}) {
  return showDropdown<T?>(
    context: context,
    rootOverlay: rootOverlay,
    position: position,
    follow: follow,
    alignment: alignment,
    offset: offset,
    builder: (context) {
      return WidgetStatesProvider.boundary(
        child: DropdownMenu(
          children: buildAdaptiveMenuButtons(
            context,
            items(context),
            onSelected,
          ),
        ),
      );
    },
  );
}

/// Bottom drawer presentation of the same entries, used on compact touch UIs.
Future<T?> openAdaptiveMenuSheet<T>({
  required BuildContext context,
  required List<AdaptiveMenuButton<T>> Function(BuildContext context) items,
  ValueChanged<T>? onSelected,
}) {
  return openDrawer<T>(
    context: context,
    draggable: true,
    showDragHandle: true,
    position: OverlayPosition.bottom,
    borderRadius: context.theme.borderRadiusMd,
    transformBackdrop: false,
    builder: (context) {
      final children = buildAdaptiveMenuButtons(
        context,
        items(context),
        onSelected,
      );
      return ListView.builder(
        itemCount: children.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final data = children[index];

          return Button(
            enabled: data.enabled,
            style: ButtonVariance.ghost.copyWith(
              padding: (context, state, value) => const EdgeInsets.all(16),
            ),
            onPressed: () {
              data.onPressed?.call(context);
              if (data.autoClose) {
                closeDrawer(context);
              }
            },
            leading: data.leading,
            trailing: data.trailing,
            alignment: Alignment.centerLeft,
            child: data.child,
          );
        },
      );
    },
  );
}

/// An adaptive widget that shows a [PopupMenuButton] when screen size is above
/// or equal to 640px
/// In smaller screen, a [IconButton] with a [openDrawer] is shown
class AdaptivePopSheetList<T> extends StatelessWidget {
  final List<AdaptiveMenuButton<T>> Function(BuildContext context) items;
  final Widget? icon;
  final Widget? child;
  final bool useRootNavigator;

  final List<Widget>? headings;
  final String tooltip;
  final ValueChanged<T>? onSelected;

  final Offset offset;

  final AbstractButtonStyle variance;

  /// Size of the trigger button. Lets a menu sit in a row of small icon
  /// buttons without standing taller than its neighbours.
  final ButtonSize size;

  const AdaptivePopSheetList({
    super.key,
    required this.items,
    this.icon,
    this.child,
    this.useRootNavigator = true,
    this.headings,
    this.onSelected,
    required this.tooltip,
    this.offset = Offset.zero,
    this.variance = ButtonVariance.ghost,
    this.size = ButtonSize.normal,
  }) : assert(
          !(icon != null && child != null),
          'Either icon or child must be provided',
        );

  Future<void> showDropdownMenu(BuildContext context, Offset position) async {
    if (MediaQuery.of(context).mdAndUp) {
      await showAdaptiveMenuDropdown<T>(
        context: context,
        position: position,
        items: items,
        onSelected: onSelected,
        rootOverlay: useRootNavigator,
      ).future;
      return;
    }

    await openAdaptiveMenuSheet<T>(
      context: context,
      items: items,
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    if (mediaQuery.mdAndUp) {
      return Tooltip(
        tooltip: TooltipContainer(
          child: Text(tooltip),
        ).call,
        child: IconButton(
          variance: variance,
          size: size,
          icon: icon ?? const Icon(SpotubeIcons.moreVertical),
          onPressed: () {
            final renderBox = context.findRenderObject() as RenderBox;
            final position = RelativeRect.fromRect(
              Rect.fromPoints(
                renderBox.localToGlobal(Offset.zero,
                    ancestor: context.findRenderObject()),
                renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero),
                    ancestor: context.findRenderObject()),
              ),
              Offset.zero & mediaQuery.size,
            );
            final offset = Offset(position.left, position.top);
            showDropdownMenu(context, offset);
          },
        ),
      );
    }

    if (child != null) {
      return Tooltip(
        tooltip: TooltipContainer(child: Text(tooltip)).call,
        child: Button(
          onPressed: () => showDropdownMenu(context, Offset.zero),
          style: variance,
          child: IgnorePointer(child: child),
        ),
      );
    }

    return Tooltip(
      tooltip: TooltipContainer(child: Text(tooltip)).call,
      child: IconButton(
        variance: variance,
        size: size,
        icon: icon ?? const Icon(SpotubeIcons.moreVertical),
        onPressed: () => showDropdownMenu(context, Offset.zero),
      ),
    );
  }
}
