part of 'theme_ui_node.dart';

extension _ThemeUiOverlayNodes on ThemeUiNodeView {
  /// Wraps overlay content in the kit that invoked it.
  ///
  /// shadcn overlays capture the inherited shadcn theme, but a plain
  /// inherited widget such as `ThemeUiKitScope` is not captured, and a
  /// Material or Cupertino node inside the overlay still needs the bridged
  /// theme from the anchor context. Both are installed here, once, so every
  /// overlay path behaves the same.
  Widget _scopedOverlay(
    BuildContext anchor,
    Object? nodeKit,
    Widget child, {
    VoidCallback? onDismiss,
  }) {
    final kit = _kit(anchor, nodeKit: nodeKit);
    final theme = Theme.of(anchor);
    Widget content = child;
    if (kit == ThemeUiKit.material) {
      content = material.Theme(
        data: buildMaterialKitTheme(
          scheme: theme.colorScheme,
          typography: theme.typography,
          brightness: theme.brightness,
        ),
        child: content,
      );
    } else if (kit == ThemeUiKit.cupertino) {
      content = cupertino.CupertinoTheme(
        data: buildCupertinoKitTheme(
          scheme: theme.colorScheme,
          typography: theme.typography,
          brightness: theme.brightness,
        ),
        child: content,
      );
    }
    if (onDismiss != null) {
      content = Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onDismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: content,
      );
    }
    return ThemeUiKitScope(kit: kit, child: content);
  }

  Alignment _menuAlignment(Object? raw) => switch (raw) {
        'top' || 'topStart' || 'topLeft' => Alignment.topLeft,
        'topEnd' || 'topRight' => Alignment.topRight,
        'left' || 'start' => Alignment.topLeft,
        'right' || 'end' => Alignment.topRight,
        'bottomStart' || 'bottomLeft' => Alignment.bottomLeft,
        'bottomEnd' || 'bottomRight' => Alignment.bottomRight,
        _ => Alignment.bottomCenter,
      };

  Alignment _popoverAlignment(Object? raw) => switch (raw) {
        'top' || 'topCenter' => Alignment.topCenter,
        'left' || 'centerLeft' || 'start' => Alignment.centerLeft,
        'right' || 'centerRight' || 'end' => Alignment.centerRight,
        'bottomLeft' => Alignment.bottomLeft,
        'bottomRight' => Alignment.bottomRight,
        _ => Alignment.bottomCenter,
      };

  /// The per-item action list of a menu item.
  List<ThemeUiAction> _itemActions(Map<String, dynamic> item) {
    final actions = <ThemeUiAction>[];
    final single = ThemeUiAction.tryParse(item['action']);
    if (single != null) actions.add(single);
    final list = item['actions'];
    if (list is List) {
      for (final raw in list.take(ThemeUiAction.maxPerNode)) {
        final action = ThemeUiAction.tryParse(raw);
        if (action != null) actions.add(action);
      }
    }
    return actions;
  }

  List<MenuItem> _menuItems(BuildContext context, Object? raw) {
    if (raw is! List) return const [];
    final entries = raw.take(32).toList();
    final result = <MenuItem>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry is! Map) continue;
      final item = entry.cast<String, dynamic>();
      final label = item['label'] is String
          ? item['label'] as String
          : item['id'] is String
              ? item['id'] as String
              : null;
      if (label == null || label.isEmpty) continue;
      final disabled = item['disabled'] == true;
      final icon = item['icon'] is String ? item['icon'] as String : null;
      final actions = _itemActions(item);
      final checked = item['checked'];

      // The host keeps activation and keyboard navigation; a theme may
      // replace the row's pixels through the item render point.
      final resolution = resolveThemeUiRenderPoint(
        renderPoints: runtime.renderPoints,
        templates: runtime.templates,
        renderPoint: 'contextMenu.item',
      );
      reportThemeUiRenderPointFallback(resolution);
      final hasTemplate = resolution.hasTemplate;
      final labelWidget = hasTemplate
          ? ThemeUiTemplateHost(
              runtime: runtime,
              renderPoint: 'contextMenu.item',
              resolution: resolution,
              bindings: {
                'menu.id': item['id'] is String ? item['id'] : label,
                'menu.label': label,
                'menu.icon': icon ?? '',
                'menu.checked': checked is bool ? checked : false,
                'menu.disabled': disabled,
                'menu.destructive': item['destructive'] == true,
                'menu.hasSubmenu': _hasSubmenu(item),
                'menu.selected':
                    item['selected'] == true || (checked is bool && checked),
                'menu.index': index,
                'menu.count': entries.length,
              },
              fallback: Text(label),
            )
          : Text(label);

      if (checked is bool) {
        result.add(
          MenuCheckbox(
            value: checked,
            enabled: !disabled,
            child: labelWidget,
            onChanged: (menuContext, next) {
              _fireValue(menuContext, actions, next);
              closeOverlay(menuContext);
            },
          ),
        );
      } else {
        result.add(
          MenuButton(
            enabled: !disabled,
            leading: hasTemplate || icon == null
                ? null
                : Icon(_fallbackIcon(icon), size: 16),
            child: labelWidget,
            onPressed: (menuContext) {
              _fire(menuContext, actions);
              closeOverlay(menuContext);
            },
          ),
        );
      }
    }
    return result;
  }

  bool _hasSubmenu(Map<String, dynamic> item) {
    final submenu = item['submenu'];
    return switch (submenu) {
      String value => value.isNotEmpty,
      List value => value.isNotEmpty,
      Map value => value.isNotEmpty,
      _ => false,
    };
  }

  Widget _overlayTrigger(
    BuildContext context,
    Object? trigger,
    VoidCallback onPressed, {
    bool chevron = false,
  }) {
    if (trigger is Map) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ThemeUiNodeView(
          node: trigger.cast<String, dynamic>(),
          runtime: runtime,
          depth: depth + 1,
        ),
      );
    }
    final label = trigger is String && trigger.isNotEmpty ? trigger : null;
    return Button.outline(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(label)
          else
            const Icon(SpotubeIcons.moreVertical, size: 16),
          if (chevron) ...[
            const SizedBox(width: 6),
            const Icon(SpotubeIcons.angleDown, size: 14),
          ],
        ],
      ),
    );
  }

  Widget _menu(
    BuildContext context,
    Map<String, dynamic> props,
  ) {
    void open() {
      showDropdown<void>(
        context: context,
        alignment: _menuAlignment(props['placement']),
        builder: (_) => DropdownMenu(
          children: _menuItems(context, props['items']),
        ),
      );
    }

    return _overlayTrigger(
      context,
      props['trigger'],
      open,
      chevron: true,
    );
  }

  Widget _contextMenu(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final items = _menuItems(context, props['items']);
    if (items.isEmpty) return _columnOf(context, children);
    return ContextMenu(
      items: items,
      child: _columnOf(context, children),
    );
  }

  Widget _popover(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    void open() {
      final anchor = context;
      showPopover<void>(
        context: anchor,
        alignment: _popoverAlignment(props['placement']),
        builder: (overlayContext) {
          void dismiss() => closeOverlay(overlayContext);
          return _scopedOverlay(
            anchor,
            props['kit'],
            ThemeUiDismissScope(
              onDismiss: dismiss,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _columnOf(overlayContext, children),
              ),
            ),
            onDismiss: dismiss,
          );
        },
      );
    }

    return _overlayTrigger(context, props['trigger'], open);
  }

  Widget _tooltip(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();
    final text = props['text'] is String ? props['text'] as String : '';
    if (text.isEmpty) return _columnOf(context, children);
    return Tooltip(
      alignment: _popoverAlignment(props['placement']),
      tooltip: (_) => Text(text),
      child: _columnOf(context, children),
    );
  }

  Widget _dialog(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
    Map<String, dynamic> node,
  ) {
    final openBind = props['openBind'];
    return _ThemeUiDialogHost(
      open: openBind is String ? runtime.bindings.isTruthy(openBind) : null,
      title: props['title'] is String ? props['title'] as String : null,
      description: props['description'] is String
          ? props['description'] as String
          : null,
      actions: node['actions'],
      children: children,
      owner: this,
      nodeKit: props['kit'],
    );
  }

  Widget _sheet(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final openBind = props['openBind'];
    final side = props['side'] is String ? props['side'] as String : 'bottom';
    return _ThemeUiSheetHost(
      open: openBind is String ? runtime.bindings.isTruthy(openBind) : null,
      side: side,
      width: props['width'] is num ? (props['width'] as num).toDouble() : null,
      children: children,
      owner: this,
      nodeKit: props['kit'],
    );
  }
}

/// A dialog whose lifetime is controlled by `openBind`.
///
/// The host cannot write the binding back, so dismissal is local: the dialog
/// shows while the binding is truthy and stays closed after the user closes it
/// until the binding goes false and true again. A dialog without `openBind`
/// shows once when its subtree is mounted, which is how a `conditional` opens
/// one. The host itself stays mounted while closed so a false→true edge can
/// reopen it without remounting the surrounding page.
class _ThemeUiDialogHost extends StatefulWidget {
  final bool? open;
  final String? title;
  final String? description;
  final Object? actions;
  final List<Map<String, dynamic>> children;
  final ThemeUiNodeView owner;
  final Object? nodeKit;

  const _ThemeUiDialogHost({
    required this.open,
    required this.title,
    required this.description,
    required this.actions,
    required this.children,
    required this.owner,
    required this.nodeKit,
  });

  @override
  State<_ThemeUiDialogHost> createState() => _ThemeUiDialogHostState();
}

class _ThemeUiDialogHostState extends State<_ThemeUiDialogHost> {
  bool _showing = false;
  bool _dismissed = false;
  VoidCallback? _dismissOverlay;

  bool get _open => widget.open ?? true;

  @override
  void initState() {
    super.initState();
    if (_open) _schedule();
  }

  @override
  void didUpdateWidget(covariant _ThemeUiDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasOpen = oldWidget.open ?? true;
    if (wasOpen && !_open) {
      _dismissed = true;
      final dismiss = _dismissOverlay;
      if (dismiss != null) {
        // The binding changed during a build; closing the route synchronously
        // would mutate the overlay tree mid-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          dismiss();
        });
      }
      return;
    }
    if (!wasOpen && _open) {
      _dismissed = false;
      _schedule();
      return;
    }
    _schedule();
  }

  void _schedule() {
    if (_showing || _dismissed || !mounted || !_open) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _show();
    });
  }

  Future<void> _show() async {
    if (!_open) {
      _showing = false;
      return;
    }
    final anchor = context;
    await showDialog<void>(
      context: anchor,
      builder: (overlayContext) {
        void dismiss() {
          _dismissed = true;
          closeOverlay(overlayContext);
        }

        _dismissOverlay = dismiss;

        // The route can be pushed after the binding already went false (the
        // parent rebuilds between the post-frame schedule and the overlay's
        // first build). Closing it here prevents a dialog that the binding
        // says is closed from appearing for a frame.
        if (!_open) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            dismiss();
          });
        }

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.description!),
              ),
            widget.owner._columnOf(overlayContext, widget.children),
          ],
        );

        return widget.owner._scopedOverlay(
          anchor,
          widget.nodeKit,
          ThemeUiDismissScope(
            onDismiss: dismiss,
            child: AlertDialog(
              title: widget.title == null ? null : Text(widget.title!),
              content: content,
              actions:
                  widget.owner._dialogActions(overlayContext, widget.actions),
            ),
          ),
          onDismiss: dismiss,
        );
      },
    );
    _dismissOverlay = null;
    if (!mounted) return;
    setState(() {
      _showing = false;
      // Barrier taps and the host's Escape handler close the route without
      // going through [dismiss], so every way the dialog can end leaves it
      // dismissed; only a false→true openBind edge reopens it.
      _dismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A sheet/drawer whose lifetime is controlled by `openBind`.
///
/// Same contract as the dialog host: it opens on mount when there is no
/// binding, closes when the binding goes false, and reopens only on a
/// false→true edge. The host stays mounted while closed.
class _ThemeUiSheetHost extends StatefulWidget {
  final bool? open;
  final String side;
  final double? width;
  final List<Map<String, dynamic>> children;
  final ThemeUiNodeView owner;
  final Object? nodeKit;

  const _ThemeUiSheetHost({
    required this.open,
    required this.side,
    required this.width,
    required this.children,
    required this.owner,
    required this.nodeKit,
  });

  @override
  State<_ThemeUiSheetHost> createState() => _ThemeUiSheetHostState();
}

class _ThemeUiSheetHostState extends State<_ThemeUiSheetHost> {
  bool _showing = false;
  bool _dismissed = false;
  VoidCallback? _dismissOverlay;

  bool get _open => widget.open ?? true;

  @override
  void initState() {
    super.initState();
    if (_open) _schedule();
  }

  @override
  void didUpdateWidget(covariant _ThemeUiSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasOpen = oldWidget.open ?? true;
    if (wasOpen && !_open) {
      _dismissed = true;
      final dismiss = _dismissOverlay;
      if (dismiss != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          dismiss();
        });
      }
      return;
    }
    if (!wasOpen && _open) {
      _dismissed = false;
      _schedule();
      return;
    }
    _schedule();
  }

  void _schedule() {
    if (_showing || _dismissed || !mounted || !_open) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _show();
    });
  }

  Future<void> _show() async {
    if (!_open) {
      _showing = false;
      return;
    }
    final anchor = context;
    final width = widget.width;
    Widget builder(BuildContext overlayContext) {
      void dismiss() {
        _dismissed = true;
        closeOverlay(overlayContext);
      }

      _dismissOverlay = dismiss;

      if (!_open) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          dismiss();
        });
      }

      final content = Padding(
        padding: const EdgeInsets.all(16),
        child: widget.owner._columnOf(overlayContext, widget.children),
      );
      return widget.owner._scopedOverlay(
        anchor,
        widget.nodeKit,
        ThemeUiDismissScope(
          onDismiss: dismiss,
          child:
              width == null || widget.side == 'bottom' || widget.side == 'top'
                  ? content
                  : SizedBox(width: width, child: content),
        ),
        onDismiss: dismiss,
      );
    }

    final position = switch (widget.side) {
      'left' || 'start' => OverlayPosition.left,
      'right' || 'end' => OverlayPosition.right,
      'top' => OverlayPosition.top,
      'bottom' => OverlayPosition.bottom,
      _ => OverlayPosition.right,
    };
    final constraints = width == null ? null : BoxConstraints(maxWidth: width);

    if (position == OverlayPosition.bottom) {
      await openSheet<void>(
        context: anchor,
        position: OverlayPosition.bottom,
        builder: builder,
        constraints: constraints,
      );
    } else {
      await openDrawer<void>(
        context: anchor,
        position: position,
        constraints: constraints,
        builder: builder,
      );
    }
    _dismissOverlay = null;
    if (!mounted) return;
    setState(() {
      _showing = false;
      // Barrier taps close the route without going through [dismiss]; a
      // false→true openBind edge is the only thing that reopens it.
      _dismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Builds the footer buttons of a dialog.
///
/// `actions` on a dialog are button descriptors (`{label, action|actions}`),
/// not the node-level action list the dispatcher reads. A descriptor without a
/// label is skipped rather than drawing an empty button.
extension _ThemeUiDialogActions on ThemeUiNodeView {
  List<Widget> _dialogActions(BuildContext context, Object? raw) {
    if (raw is! List) return const [];
    final buttons = <Widget>[];
    for (final entry in raw.take(4)) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final label = map['label'];
      if (label is! String || label.isEmpty) continue;
      final actions = _itemActions(map);
      buttons.add(
        // The Builder context sits below the dialog's dismiss scope, which
        // `context` (the route builder's own context) does not; without it a
        // `dismiss` footer action would be forwarded to the host instead of
        // closing the dialog it belongs to.
        Builder(
          builder: (buttonContext) => Button.outline(
            onPressed: () {
              final localDismiss =
                  ThemeUiDismissScope.maybeOf(buttonContext) != null;
              _fire(buttonContext, actions);
              if (!(localDismiss &&
                  actions.any((action) => action.type == 'dismiss'))) {
                closeOverlay(buttonContext);
              }
            },
            child: Text(label),
          ),
        ),
      );
    }
    return buttons;
  }
}
