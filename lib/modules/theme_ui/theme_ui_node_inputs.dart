part of 'theme_ui_node.dart';

/// One entry of a `radioGroup`, `select` or `segmented` option list.
class _ThemeUiOption {
  final String value;
  final String label;
  final String? icon;

  const _ThemeUiOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

_ThemeUiOption? _themeUiOption(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return _ThemeUiOption(value: raw, label: raw);
  }
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final value = map['value'] ?? map['id'];
  if (value is! String || value.isEmpty) return null;
  final label = map['label'];
  return _ThemeUiOption(
    value: value,
    label: label is String && label.isNotEmpty ? label : value,
    icon: map['icon'] is String ? map['icon'] as String : null,
  );
}

extension _ThemeUiInputNodes on ThemeUiNodeView {
  List<_ThemeUiOption> _inputOptions(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .take(64)
        .map(_themeUiOption)
        .whereType<_ThemeUiOption>()
        .toList();
  }

  bool _inputDisabled(Map<String, dynamic> props) {
    final condition = props['disabledWhen'];
    return condition is String && runtime.bindings.isTruthy(condition);
  }

  String? _boundString(Object? raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is num || raw is bool) return '$raw';
    return null;
  }

  double? _boundNumber(Object? raw) {
    if (raw is num && raw.isFinite) return raw.toDouble();
    return null;
  }

  /// Fires the node's actions with `$value` replaced by the control's value.
  void _fireValue(
    BuildContext context,
    List<ThemeUiAction> actions,
    Object? value,
  ) {
    for (final action in actions) {
      _dispatch(context, action.withValue(value));
    }
  }

  Widget _slider(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final min = _clamp(props['min'], -100000, 100000, fallback: 0);
    final rawMax = _clamp(props['max'], -100000, 100000, fallback: 1);
    final max = rawMax <= min ? min + 1 : rawMax;
    final step = _clamp(props['step'], 0, 100000, fallback: 0);
    final divisions =
        step > 0 ? ((max - min) / step).round().clamp(1, 1000) : null;
    final binding = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    final initial = (_boundNumber(binding) ?? min).clamp(min, max).toDouble();
    final label = props['label'] is String ? props['label'] as String : null;
    final variant =
        props['variant'] is String ? props['variant'] as String : null;
    final kit = _kitForComponent(
      context,
      component: 'slider',
      nodeType: 'slider',
      nodeKit: props['kit'],
      variant: variant,
    );

    return _ThemeUiSlider(
      min: min,
      max: max,
      divisions: divisions,
      initial: initial,
      label: label,
      showValue: props['showValue'] == true,
      vertical: props['orientation'] == 'vertical',
      kit: kit,
      disabled: _inputDisabled(props),
      onCommit: (value) => _fireValue(context, actions, value),
    );
  }

  Widget _switch(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final value = runtime.bindings.isTruthy(
      props['bind'] is String ? props['bind'] as String : null,
    );
    final label = props['label'] is String ? props['label'] as String : null;
    return Opacity(
      opacity: _inputDisabled(props) ? 0.5 : 1,
      child: Switch(
        value: value,
        enabled: !_inputDisabled(props),
        leading: label == null ? null : Text(label),
        onChanged: (next) => _fireValue(context, actions, next),
      ),
    );
  }

  Widget _checkbox(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final value = runtime.bindings.isTruthy(
      props['bind'] is String ? props['bind'] as String : null,
    );
    final label = props['label'] is String ? props['label'] as String : null;
    return Opacity(
      opacity: _inputDisabled(props) ? 0.5 : 1,
      child: Checkbox(
        state: value ? CheckboxState.checked : CheckboxState.unchecked,
        enabled: !_inputDisabled(props),
        trailing: label == null ? null : Text(label),
        onChanged: (next) => _fireValue(
          context,
          actions,
          next == CheckboxState.checked,
        ),
      ),
    );
  }

  Widget _radioGroup(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final options = _inputOptions(props['options']);
    if (options.isEmpty) return const SizedBox.shrink();
    final current = _boundString(
      runtime.bindings
          .raw(props['bind'] is String ? props['bind'] as String : null),
    );
    final values = options.map((option) => option.value).toSet();
    return RadioGroup<String>(
      value: current != null && values.contains(current) ? current : null,
      enabled: !_inputDisabled(props),
      onChanged: (value) => _fireValue(context, actions, value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: RadioItem<String>(
                value: options[i].value,
                trailing: Text(options[i].label),
              ),
            ),
        ],
      ),
    );
  }

  Widget _textInput(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
    bool area,
  ) {
    final bind = props['bind'] is String ? props['bind'] as String : null;
    final initial = _boundString(runtime.bindings.raw(bind)) ?? '';
    final debounce = (props['debounceMs'] is num
            ? (props['debounceMs'] as num).toInt()
            : 150)
        .clamp(0, 5000);
    final icon = props['icon'] is String ? props['icon'] as String : null;
    return _ThemeUiTextInput(
      initial: initial,
      placeholder: props['placeholder'] is String
          ? props['placeholder'] as String
          : null,
      debounceMs: debounce,
      clearable: props['clearable'] == true,
      icon: icon == null ? null : _fallbackIcon(icon),
      area: area,
      minLines:
          area ? _int(props['minLines'], fallback: 3, min: 1, max: 12) : 1,
      maxLines:
          _int(props['maxLines'], fallback: area ? 8 : 1, min: 1, max: 12),
      disabled: _inputDisabled(props),
      onChanged: (value) => _fireValue(context, actions, value),
      onSubmitted: (value) => _fireValue(context, actions, value),
    );
  }

  Widget _select(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final options = _inputOptions(props['options']);
    if (options.isEmpty) return const SizedBox.shrink();
    final current = _boundString(
      runtime.bindings
          .raw(props['bind'] is String ? props['bind'] as String : null),
    );
    _ThemeUiOption? selected;
    for (final option in options) {
      if (option.value == current) {
        selected = option;
        break;
      }
    }
    final placeholder = props['placeholder'] is String
        ? props['placeholder'] as String
        : 'Select';

    return Align(
      alignment: Alignment.centerLeft,
      child: Button.outline(
        enabled: !_inputDisabled(props),
        onPressed: () {
          showDropdown<String>(
            context: context,
            alignment: Alignment.bottomCenter,
            builder: (overlayContext) {
              return DropdownMenu(
                children: [
                  for (final option in options)
                    MenuButton(
                      leading: option.icon == null
                          ? null
                          : Icon(_fallbackIcon(option.icon!), size: 16),
                      child: Text(option.label),
                      onPressed: (menuContext) {
                        _fireValue(context, actions, option.value);
                        closeOverlay(menuContext);
                      },
                    ),
                ],
              );
            },
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected?.icon != null) ...[
              Icon(_fallbackIcon(selected!.icon!), size: 16),
              const SizedBox(width: 8),
            ],
            Text(selected?.label ?? placeholder),
            const SizedBox(width: 8),
            const Icon(SpotubeIcons.angleDown, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _segmented(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final options = _inputOptions(props['options']);
    if (options.isEmpty) return const SizedBox.shrink();
    final bind = props['bind'] ?? props['valueBind'];
    final current = _boundString(
      runtime.bindings.raw(bind is String ? bind : null),
    );
    final scheme = Theme.of(context).colorScheme;
    final disabled = _inputDisabled(props);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: disabled
                    ? null
                    : () => _fireValue(context, actions, option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: option.value == current
                        ? scheme.background
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    option.label,
                    style: TextStyle(
                      color: option.value == current
                          ? scheme.foreground
                          : scheme.mutedForeground,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final items = _inputOptions(props['items']);
    if (items.isEmpty) return const SizedBox.shrink();
    final rawPanels = props['panels'];
    final panels = <List<Map<String, dynamic>>>[];
    if (rawPanels is List) {
      for (final panel in rawPanels) {
        if (panel is! List) continue;
        panels.add([
          for (final child in panel.take(_maxChildren))
            if (child is Map) child.cast<String, dynamic>(),
        ]);
      }
    }
    final bound = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    int? boundIndex;
    if (bound is num && bound.isFinite) {
      boundIndex = bound.toInt();
    } else if (bound is String) {
      final index = items.indexWhere((item) => item.value == bound);
      if (index >= 0) boundIndex = index;
    }

    return _ThemeUiNodeViewAccess(
      nodeView: this,
      child: _ThemeUiTabs(
        items: items,
        panels: panels.isEmpty ? null : panels,
        boundIndex: boundIndex,
        onSelected: (index) => _fireValue(context, actions, items[index].value),
      ),
    );
  }

  Widget _tabChild(_ThemeUiOption item) {
    if (item.icon == null) return Text(item.label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_fallbackIcon(item.icon!), size: 14),
        const SizedBox(width: 6),
        Text(item.label),
      ],
    );
  }
}

/// A slider that owns the value while it is being dragged.
///
/// The binding is the value the host currently reports; a drag must not wait
/// for the host round-trip, and the change action must fire once on release
/// rather than on every pixel. Tapping the track is a press and release in the
/// same gesture, so it commits immediately through the same path.
class _ThemeUiSlider extends StatefulWidget {
  final double min;
  final double max;
  final int? divisions;
  final double initial;
  final String? label;
  final bool showValue;
  final bool vertical;
  final ThemeUiKit kit;
  final bool disabled;
  final ValueChanged<double> onCommit;

  const _ThemeUiSlider({
    required this.min,
    required this.max,
    required this.divisions,
    required this.initial,
    required this.label,
    required this.showValue,
    required this.vertical,
    required this.kit,
    required this.disabled,
    required this.onCommit,
  });

  @override
  State<_ThemeUiSlider> createState() => _ThemeUiSliderState();
}

class _ThemeUiSliderState extends State<_ThemeUiSlider> {
  late double _value;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void didUpdateWidget(covariant _ThemeUiSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && widget.initial != oldWidget.initial) {
      _value = widget.initial;
    }
  }

  double _stepped(double raw) {
    final divisions = widget.divisions;
    final clamped = raw.clamp(widget.min, widget.max).toDouble();
    if (divisions == null || divisions <= 0) return clamped;
    final fraction = (clamped - widget.min) / (widget.max - widget.min);
    final rounded = (fraction * divisions).round();
    return (widget.min + rounded / divisions * (widget.max - widget.min))
        .clamp(widget.min, widget.max)
        .toDouble();
  }

  double _fromNormalized(SliderValue value) {
    return _stepped(widget.min + value.value * (widget.max - widget.min));
  }

  void _commit(double value) {
    setState(() {
      _value = _stepped(value);
      _dragging = false;
    });
    widget.onCommit(_value);
  }

  String get _displayValue {
    final step = widget.divisions == null
        ? 0.01
        : (widget.max - widget.min) / widget.divisions!;
    if (step >= 0.99) return _value.round().toString();
    return _value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final slider = switch (widget.kit) {
      ThemeUiKit.material => material.Slider(
          value: _value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: widget.showValue ? _displayValue : null,
          onChangeStart:
              widget.disabled ? null : (_) => setState(() => _dragging = true),
          onChanged: widget.disabled
              ? null
              : (value) => setState(() => _value = _stepped(value)),
          onChangeEnd: widget.disabled ? null : _commit,
        ),
      ThemeUiKit.cupertino => cupertino.CupertinoSlider(
          value: _value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChangeStart:
              widget.disabled ? null : (_) => setState(() => _dragging = true),
          onChanged: widget.disabled
              ? null
              : (value) => setState(() => _value = _stepped(value)),
          onChangeEnd: widget.disabled ? null : _commit,
        ),
      _ => Slider(
          value: SliderValue.single(_value),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          enabled: !widget.disabled,
          onChangeStart:
              widget.disabled ? null : (_) => setState(() => _dragging = true),
          onChanged: widget.disabled
              ? null
              : (value) => setState(() => _value = _fromNormalized(value)),
          onChangeEnd: widget.disabled
              ? null
              : (value) => _commit(_fromNormalized(value)),
        ),
    };

    final body = widget.vertical
        ? RotatedBox(
            quarterTurns: 3,
            child: SizedBox(width: 160, child: slider),
          )
        : slider;

    if (widget.label == null && !widget.showValue) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null) Expanded(child: Text(widget.label!)),
            if (widget.showValue)
              Text(
                _displayValue,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
        body,
      ],
    );
  }
}

/// A text input that keeps typing local until the debounce elapses.
///
/// The host owns the binding but not the caret: every keystroke updates the
/// controller synchronously and only the trailing action is debounced. Submit
/// and clear flush immediately because both are deliberate ends of an edit.
class _ThemeUiTextInput extends StatefulWidget {
  final String initial;
  final String? placeholder;
  final int debounceMs;
  final bool clearable;
  final IconData? icon;
  final bool area;
  final int minLines;
  final int maxLines;
  final bool disabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _ThemeUiTextInput({
    required this.initial,
    required this.placeholder,
    required this.debounceMs,
    required this.clearable,
    required this.icon,
    required this.area,
    required this.minLines,
    required this.maxLines,
    required this.disabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  State<_ThemeUiTextInput> createState() => _ThemeUiTextInputState();
}

class _ThemeUiTextInputState extends State<_ThemeUiTextInput> {
  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _ThemeUiTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial &&
        widget.initial != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initial,
        selection: TextSelection.collapsed(offset: widget.initial.length),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.debounceMs <= 0) {
      widget.onChanged(_controller.text);
      return;
    }
    _timer = Timer(Duration(milliseconds: widget.debounceMs), () {
      if (mounted) widget.onChanged(_controller.text);
    });
  }

  void _flush() {
    _timer?.cancel();
    widget.onSubmitted(_controller.text);
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.area
        ? TextArea(
            controller: _controller,
            placeholder:
                widget.placeholder == null ? null : Text(widget.placeholder!),
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            enabled: !widget.disabled,
            onChanged: (_) => _schedule(),
            onSubmitted: (_) => _flush(),
          )
        : TextField(
            controller: _controller,
            placeholder:
                widget.placeholder == null ? null : Text(widget.placeholder!),
            enabled: !widget.disabled,
            onChanged: (_) => _schedule(),
            onSubmitted: (_) => _flush(),
          );

    return Row(
      crossAxisAlignment:
          widget.area ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(widget.icon!, size: 16),
          ),
        ],
        Expanded(child: field),
        if (widget.clearable && _controller.text.isNotEmpty)
          IconButton.ghost(
            onPressed: _clear,
            icon: const Icon(SpotubeIcons.close, size: 16),
          ),
      ],
    );
  }
}

/// A tab strip with optional panels.
///
/// `bind` may hold an index or an item id; without a usable binding the strip
/// keeps its own selection so a panel-only theme still works.
class _ThemeUiTabs extends StatefulWidget {
  final List<_ThemeUiOption> items;
  final List<List<Map<String, dynamic>>>? panels;
  final int? boundIndex;
  final ValueChanged<int> onSelected;

  const _ThemeUiTabs({
    required this.items,
    required this.panels,
    required this.boundIndex,
    required this.onSelected,
  });

  @override
  State<_ThemeUiTabs> createState() => _ThemeUiTabsState();
}

class _ThemeUiTabsState extends State<_ThemeUiTabs> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ThemeUiTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.boundIndex != oldWidget.boundIndex) _sync();
  }

  void _sync() {
    final bound = widget.boundIndex;
    if (bound == null) return;
    _index = bound.clamp(0, widget.items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final nodeView = _ThemeUiNodeViewAccess.of(context).nodeView;
    final selected = _index.clamp(0, widget.items.length - 1);
    final panels = widget.panels;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tabs(
          index: selected,
          onChanged: (index) {
            setState(() => _index = index);
            widget.onSelected(index);
          },
          children: [
            for (final item in widget.items)
              TabItem(child: nodeView._tabChild(item)),
          ],
        ),
        if (panels != null && selected < panels.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: nodeView._columnOf(context, panels[selected]),
          ),
      ],
    );
  }
}

/// Gives the tab strip access to the node view that created it.
///
/// The strip is a separate StatefulWidget so it can hold a selection, but the
/// panel is still drawn by the same `ThemeUiNodeView` (and therefore the same
/// runtime and depth budget).
class _ThemeUiNodeViewAccess extends InheritedWidget {
  final ThemeUiNodeView nodeView;

  const _ThemeUiNodeViewAccess({
    required this.nodeView,
    required super.child,
  });

  static _ThemeUiNodeViewAccess of(BuildContext context) {
    final access =
        context.dependOnInheritedWidgetOfExactType<_ThemeUiNodeViewAccess>();
    assert(access != null, 'a theme UI tab strip must have a node view');
    return access!;
  }

  @override
  bool updateShouldNotify(_ThemeUiNodeViewAccess oldWidget) =>
      nodeView != oldWidget.nodeView;
}
