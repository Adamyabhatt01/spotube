part of 'theme_ui_node.dart';

const _themeUiMaxVirtualItems = 10000;
const _themeUiMaxStaticRows = 500;
const _themeUiMaxTableColumns = 32;
const _themeUiMaxTreeNodes = 500;
const _themeUiMaxAccordionItems = 32;
const _themeUiMaxCarouselItems = 50;
const _themeUiMaxBreadcrumbItems = 16;

typedef _ThemeUiFilterSpec = ({String bind, List<String> fields});

extension _ThemeUiDataNodes on ThemeUiNodeView {
  Widget _virtualList(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final raw = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final nodes = _itemTemplateNodes(runtime, props, children);
    if (nodes.isEmpty) return const SizedBox.shrink();

    final limit = _int(
      props['limit'],
      fallback: _themeUiMaxVirtualItems,
      min: 1,
      max: _themeUiMaxVirtualItems,
    );
    final extent = _px(context, props['itemExtent'], fallback: 56)
        .clamp(8.0, 400.0)
        .toDouble();
    final overscan = _int(props['overscan'], fallback: 4, min: 0, max: 64);
    final templateName = props['itemTemplate'] is String
        ? props['itemTemplate'] as String
        : null;
    final filter = _listFilter(props);

    Widget buildList(String? query) {
      final all = raw.cast<Object?>().toList();
      final visible = query == null
          ? all
          : _filterItems(all, query, filter?.fields ?? const []);
      final items = visible.take(limit).toList();
      if (items.isEmpty) return const SizedBox.shrink();

      return ListView.builder(
        itemCount: items.length,
        itemExtent: extent,
        cacheExtent: overscan * extent,
        itemBuilder: (context, index) {
          final rowRuntime =
              _rowRuntime(runtime, items[index], index, items, templateName);
          return _itemNodeView(rowRuntime, nodes, depth);
        },
      );
    }

    final spec = filter;
    if (spec == null) return buildList(null);
    return _ThemeUiDebouncedText(
      value: runtime.bindings.display(spec.bind),
      builder: (context, settled) => buildList(settled),
    );
  }

  Widget _table(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final raw = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final columns = _tableColumns(props);
    if (columns.isEmpty) return const SizedBox.shrink();

    final nodes = _itemTemplateNodes(
      runtime,
      props,
      children,
      prop: 'rowTemplate',
    );
    final sticky = props['stickyHeader'] == true;
    final limit = sticky ? _themeUiMaxVirtualItems : _themeUiMaxStaticRows;
    final items = raw.cast<Object?>().take(limit).toList();
    final templateName =
        props['rowTemplate'] is String ? props['rowTemplate'] as String : null;

    return _ThemeUiTable(
      runtime: runtime,
      columns: columns,
      items: items,
      rowNodes: nodes,
      templateName: templateName,
      stickyHeader: sticky,
      sortable: props['sortable'] == true,
      depth: depth,
    );
  }

  Widget _tree(BuildContext context, Map<String, dynamic> props) {
    final raw = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    return _ThemeUiTree(
      runtime: runtime,
      items: raw.cast<Object?>(),
      labelKey:
          props['labelKey'] is String ? props['labelKey'] as String : 'label',
      childrenKey: props['childrenKey'] is String
          ? props['childrenKey'] as String
          : 'children',
      expandedKey: props['expandedKey'] is String
          ? props['expandedKey'] as String
          : 'expanded',
      depth: depth,
    );
  }

  Widget _accordion(BuildContext context, Map<String, dynamic> props) {
    final raw = props['items'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final items = <Map<String, dynamic>>[];
    for (final entry in raw.take(_themeUiMaxAccordionItems)) {
      if (entry is Map) items.add(entry.cast<String, dynamic>());
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return _ThemeUiAccordion(
      runtime: runtime,
      items: items,
      multiple: props['multiple'] == true,
      depth: depth,
    );
  }

  Widget _collapsible(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();

    final openBind =
        props['openBind'] is String ? props['openBind'] as String : null;
    return _ThemeUiCollapsible(
      runtime: runtime,
      title: props['title'] is String ? props['title'] as String : '',
      openBind: openBind,
      boundOpen: openBind == null ? null : runtime.bindings.isTruthy(openBind),
      children: children,
      depth: depth,
    );
  }

  Widget _carousel(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final raw = props['bind'] is String
        ? runtime.bindings.raw(props['bind'] as String)
        : null;
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final nodes = _itemTemplateNodes(runtime, props, children);
    if (nodes.isEmpty) return const SizedBox.shrink();

    final items = raw.cast<Object?>().take(_themeUiMaxCarouselItems).toList();
    final height = _px(context, props['height'], fallback: 200)
        .clamp(40.0, 800.0)
        .toDouble();
    final templateName = props['itemTemplate'] is String
        ? props['itemTemplate'] as String
        : null;

    return _ThemeUiCarousel(
      runtime: runtime,
      items: items,
      nodes: nodes,
      templateName: templateName,
      height: height,
      autoplay: props['autoplay'] == true,
      depth: depth,
    );
  }

  Widget _breadcrumb(BuildContext context, Map<String, dynamic> props) {
    final raw = props['items'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    final entries = raw.take(_themeUiMaxBreadcrumbItems).toList();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map) continue;
      final label = entry['label'] is String
          ? entry['label'] as String
          : entry['id'] is String
              ? entry['id'] as String
              : '';
      if (label.isEmpty) continue;
      final action = ThemeUiAction.tryParse(entry['action']);
      final last = i == entries.length - 1;
      children.add(
        MouseRegion(
          cursor: action == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: action == null ? null : () => _fire(context, [action]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: last ? scheme.foreground : scheme.mutedForeground,
                  fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
      if (!last) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.chevron_right,
            size: 14,
            color: scheme.mutedForeground,
          ),
        ));
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _pagination(
    BuildContext context,
    Map<String, dynamic> props,
    List<ThemeUiAction> actions,
  ) {
    final pageCount = _int(props['pageCount'], fallback: 1, min: 1, max: 1000);
    final pageBind =
        props['pageBind'] is String ? props['pageBind'] as String : null;
    final rawPage = runtime.bindings.raw(pageBind);
    final current = rawPage is num ? rawPage.toInt().clamp(1, pageCount) : 1;

    void go(int page) {
      final value = page.clamp(1, pageCount);
      _fire(
        context,
        [for (final action in actions) action.withValue(value)],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    Widget button(String label, int? page, {bool selected = false}) {
      final enabled = page != null;
      return GestureDetector(
        onTap: enabled ? () => go(page) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? scheme.primaryForeground
                  : enabled
                      ? scheme.foreground
                      : scheme.mutedForeground,
            ),
          ),
        ),
      );
    }

    final numbers = <int>{1, pageCount};
    for (var page = current - 1; page <= current + 1; page++) {
      if (page >= 1 && page <= pageCount) numbers.add(page);
    }
    final ordered = numbers.toList()..sort();

    final children = <Widget>[
      button('‹', current > 1 ? current - 1 : null),
    ];
    int? previous;
    for (final page in ordered) {
      if (previous != null && page - previous > 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('…', style: TextStyle(color: scheme.mutedForeground)),
        ));
      }
      children.add(button('$page', page, selected: page == current));
      previous = page;
    }
    children.add(button('›', current < pageCount ? current + 1 : null));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ThemeUiTableColumn {
  final String key;
  final String label;
  final num? width;
  final String? align;

  const _ThemeUiTableColumn({
    required this.key,
    required this.label,
    this.width,
    this.align,
  });
}

List<_ThemeUiTableColumn> _tableColumns(Map<String, dynamic> props) {
  final raw = props['columns'];
  if (raw is! List) return const [];
  final columns = <_ThemeUiTableColumn>[];
  for (final entry in raw.take(_themeUiMaxTableColumns)) {
    if (entry is! Map) continue;
    final key = entry['key'];
    if (key is! String || key.isEmpty) continue;
    columns.add(_ThemeUiTableColumn(
      key: key,
      label: entry['label'] is String ? entry['label'] as String : key,
      width: entry['width'] is num ? entry['width'] as num : null,
      align: entry['align'] is String ? entry['align'] as String : null,
    ));
  }
  return columns;
}

class _ThemeUiTable extends StatefulWidget {
  final ThemeUiRuntime runtime;
  final List<_ThemeUiTableColumn> columns;
  final List<Object?> items;
  final List<Map<String, dynamic>> rowNodes;
  final String? templateName;
  final bool stickyHeader;
  final bool sortable;
  final int depth;

  const _ThemeUiTable({
    required this.runtime,
    required this.columns,
    required this.items,
    required this.rowNodes,
    required this.templateName,
    required this.stickyHeader,
    required this.sortable,
    required this.depth,
  });

  @override
  State<_ThemeUiTable> createState() => _ThemeUiTableState();
}

class _ThemeUiTableState extends State<_ThemeUiTable> {
  String? _sortKey;
  bool _ascending = true;

  void _sort(String key) {
    setState(() {
      if (_sortKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        _ascending = true;
      }
    });
  }

  List<Object?> _sorted() {
    final key = _sortKey;
    if (key == null) return widget.items;
    final sorted = [...widget.items];
    sorted.sort((a, b) {
      final result = _compareValues(
        _columnValue(a, key),
        _columnValue(b, key),
      );
      return _ascending ? result : -result;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final items = _sorted();
    final header = _header(context);
    if (widget.stickyHeader) {
      return CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _ThemeUiTableHeaderDelegate(
              height: _headerHeight(context),
              child: header,
            ),
          ),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _row(context, items[index], index, items),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        for (var i = 0; i < items.length; i++)
          _row(context, items[i], i, items),
      ],
    );
  }

  double _headerHeight(BuildContext context) {
    return (34 * Theme.of(context).scaling).clamp(24.0, 72.0).toDouble();
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _headerHeight(context),
      decoration: BoxDecoration(
        color: scheme.background,
        border: Border(bottom: BorderSide(color: scheme.border)),
      ),
      child: Row(
        children: [
          for (final column in widget.columns)
            _cell(
              context,
              column,
              MouseRegion(
                cursor: widget.sortable
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: widget.sortable ? () => _sort(column.key) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          column.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.mutedForeground,
                          ),
                        ),
                      ),
                      if (widget.sortable)
                        Icon(
                          _sortKey != column.key
                              ? Icons.unfold_more
                              : _ascending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                          size: 13,
                          color: scheme.mutedForeground,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Object? item,
    int index,
    List<Object?> items,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget content;
    if (widget.rowNodes.isNotEmpty) {
      final rowRuntime =
          _rowRuntime(widget.runtime, item, index, items, widget.templateName);
      content = _itemNodeView(rowRuntime, widget.rowNodes, widget.depth);
    } else {
      content = _defaultRow(context, item);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.border)),
      ),
      child: content,
    );
  }

  Widget _defaultRow(BuildContext context, Object? item) {
    final bindings = themeItemBindings(item);
    return Row(
      children: [
        for (final column in widget.columns)
          _cell(
            context,
            column,
            Text(
              _cellText(bindings['item.${column.key}']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.foreground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    _ThemeUiTableColumn column,
    Widget child,
  ) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Align(
        alignment: _tableAlignment(column.align),
        child: child,
      ),
    );
    final width = column.width;
    if (width is num) {
      return SizedBox(
        width: (width.toDouble() * Theme.of(context).scaling)
            .clamp(0.0, 2000.0)
            .toDouble(),
        child: content,
      );
    }
    return Expanded(child: content);
  }
}

class _ThemeUiTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _ThemeUiTableHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(covariant _ThemeUiTableHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _ThemeUiTree extends StatefulWidget {
  final ThemeUiRuntime runtime;
  final List<Object?> items;
  final String labelKey;
  final String childrenKey;
  final String expandedKey;
  final int depth;

  const _ThemeUiTree({
    required this.runtime,
    required this.items,
    required this.labelKey,
    required this.childrenKey,
    required this.expandedKey,
    required this.depth,
  });

  @override
  State<_ThemeUiTree> createState() => _ThemeUiTreeState();
}

class _ThemeUiTreeState extends State<_ThemeUiTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _seed(widget.items, '');
  }

  void _seed(List<Object?> items, String path) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;
      final nodePath = '$path.$i';
      if (item[widget.expandedKey] == true) _expanded.add(nodePath);
      final children = item[widget.childrenKey];
      if (children is List) _seed(children.cast<Object?>(), nodePath);
    }
  }

  void _toggle(String path) {
    setState(() {
      if (!_expanded.remove(path)) _expanded.add(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    var count = 0;

    List<Widget> rows(List<Object?> items, String path, int level) {
      final result = <Widget>[];
      if (level > 8) return result;
      for (var i = 0; i < items.length && count < _themeUiMaxTreeNodes; i++) {
        final item = items[i];
        final nodePath = '$path.$i';
        final label = _label(item);
        final rawChildren = item is Map ? item[widget.childrenKey] : null;
        final children = rawChildren is List
            ? rawChildren.cast<Object?>().toList()
            : const <Object?>[];
        final expanded = _expanded.contains(nodePath);
        count++;
        result.add(_row(label, level, children.isNotEmpty, expanded, nodePath));
        if (children.isNotEmpty && expanded) {
          result.addAll(rows(children, nodePath, level + 1));
        }
      }
      return result;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows(widget.items, '', 0),
    );
  }

  Widget _row(
    String label,
    int level,
    bool hasChildren,
    bool expanded,
    String path,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: hasChildren ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasChildren ? () => _toggle(path) : null,
        child: Padding(
          padding: EdgeInsets.only(
            left: 6 + level * 16,
            top: 6,
            bottom: 6,
            right: 6,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: hasChildren
                    ? AnimatedRotation(
                        turns: expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: scheme.mutedForeground,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: scheme.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(Object? item) {
    if (item is Map) {
      final value = item[widget.labelKey] ??
          item['title'] ??
          item['name'] ??
          item['label'];
      return value?.toString() ?? '';
    }
    final bindings = themeItemBindings(item);
    final value = bindings['item.title'] ??
        bindings['item.name'] ??
        bindings['item.label'] ??
        bindings['item.value'];
    return value?.toString() ?? '';
  }
}

class _ThemeUiAccordion extends StatefulWidget {
  final ThemeUiRuntime runtime;
  final List<Map<String, dynamic>> items;
  final bool multiple;
  final int depth;

  const _ThemeUiAccordion({
    required this.runtime,
    required this.items,
    required this.multiple,
    required this.depth,
  });

  @override
  State<_ThemeUiAccordion> createState() => _ThemeUiAccordionState();
}

class _ThemeUiAccordionState extends State<_ThemeUiAccordion> {
  final Set<int> _expanded = {};

  void _toggle(int index) {
    setState(() {
      if (_expanded.remove(index)) return;
      if (!widget.multiple) _expanded.clear();
      _expanded.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggle(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.items[i]['title'] is String
                                  ? widget.items[i]['title'] as String
                                  : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.foreground,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _expanded.contains(i) ? 0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: scheme.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_expanded.contains(i))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _itemNodeView(
                      widget.runtime,
                      _nodeList(widget.items[i]['children']),
                      widget.depth,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ThemeUiCollapsible extends StatefulWidget {
  final ThemeUiRuntime runtime;
  final String title;
  final String? openBind;
  final bool? boundOpen;
  final List<Map<String, dynamic>> children;
  final int depth;

  const _ThemeUiCollapsible({
    required this.runtime,
    required this.title,
    required this.openBind,
    required this.boundOpen,
    required this.children,
    required this.depth,
  });

  @override
  State<_ThemeUiCollapsible> createState() => _ThemeUiCollapsibleState();
}

class _ThemeUiCollapsibleState extends State<_ThemeUiCollapsible> {
  late bool _open = widget.boundOpen ?? false;

  @override
  void didUpdateWidget(covariant _ThemeUiCollapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bound = widget.boundOpen;
    if (bound != null && bound != oldWidget.boundOpen) _open = bound;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.foreground,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _itemNodeView(
              widget.runtime,
              widget.children,
              widget.depth,
            ),
          ),
      ],
    );
  }
}

class _ThemeUiCarousel extends StatefulWidget {
  final ThemeUiRuntime runtime;
  final List<Object?> items;
  final List<Map<String, dynamic>> nodes;
  final String? templateName;
  final double height;
  final bool autoplay;
  final int depth;

  const _ThemeUiCarousel({
    required this.runtime,
    required this.items,
    required this.nodes,
    required this.templateName,
    required this.height,
    required this.autoplay,
    required this.depth,
  });

  @override
  State<_ThemeUiCarousel> createState() => _ThemeUiCarouselState();
}

class _ThemeUiCarouselState extends State<_ThemeUiCarousel> {
  late final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _syncAutoplay();
  }

  @override
  void didUpdateWidget(covariant _ThemeUiCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoplay != widget.autoplay) _syncAutoplay();
  }

  void _syncAutoplay() {
    _timer?.cancel();
    if (!widget.autoplay || widget.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final rowRuntime = _rowRuntime(
                widget.runtime,
                widget.items[index],
                index,
                widget.items,
                widget.templateName,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _itemNodeView(rowRuntime, widget.nodes, widget.depth),
              );
            },
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  GestureDetector(
                    onTap: () => _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? scheme.foreground
                            : scheme.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

_ThemeUiFilterSpec? _listFilter(Map<String, dynamic> props) {
  final raw = props['filter'];
  if (raw is! Map) return null;
  final bind = raw['bind'];
  if (bind is! String || bind.isEmpty) return null;
  final fields = raw['fields'];
  return (
    bind: bind,
    fields: fields is List
        ? fields.whereType<String>().take(32).toList()
        : const <String>[],
  );
}

List<Object?> _filterItems(
  List<Object?> items,
  String query,
  List<String> fields,
) {
  final needle = _foldText(query.trim());
  if (needle.isEmpty) return items;
  return items.where((item) {
    for (final value in _filterValues(item, fields)) {
      if (value == null) continue;
      if (_foldText(value.toString()).contains(needle)) return true;
    }
    return false;
  }).toList();
}

Iterable<Object?> _filterValues(Object? item, List<String> fields) sync* {
  if (item is Map) {
    if (fields.isEmpty) {
      yield* item.values;
    } else {
      for (final field in fields) {
        yield item[field];
      }
    }
    return;
  }
  final bindings = themeItemBindings(item);
  for (final entry in bindings.entries) {
    if (entry.key == 'item.index' ||
        entry.key == 'item.number' ||
        entry.key == 'item.playing') {
      continue;
    }
    yield entry.value;
  }
}

const _foldMap = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ł': 'l',
  'ľ': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ť': 't',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'æ': 'ae',
  'œ': 'oe',
  'ß': 'ss',
};

String _foldText(String value) {
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    buffer.write(_foldMap[char] ?? char);
  }
  return buffer.toString();
}

List<Map<String, dynamic>> _itemTemplateNodes(
  ThemeUiRuntime runtime,
  Map<String, dynamic> props,
  List<Map<String, dynamic>> children, {
  String prop = 'itemTemplate',
}) {
  final name = props[prop];
  if (name is String) {
    final template = runtime.templates[name];
    if (template != null) return template.children;
  }
  return children;
}

ThemeUiRuntime _rowRuntime(
  ThemeUiRuntime runtime,
  Object? item,
  int index,
  List<Object?> items,
  String? templateName,
) {
  final scoped = _itemRuntime(runtime, item, index, items);
  if (templateName != null && runtime.templates.containsKey(templateName)) {
    return scoped.descendTemplate(templateName);
  }
  return scoped;
}

Widget _itemNodeView(
  ThemeUiRuntime runtime,
  List<Map<String, dynamic>> nodes,
  int depth,
) {
  if (nodes.isEmpty) return const SizedBox.shrink();
  if (nodes.length == 1) {
    return ThemeUiNodeView(
        node: nodes.first, runtime: runtime, depth: depth + 1);
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final node in nodes)
        ThemeUiNodeView(node: node, runtime: runtime, depth: depth + 1),
    ],
  );
}

List<Map<String, dynamic>> _nodeList(Object? raw) {
  if (raw is Map) return [raw.cast<String, dynamic>()];
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map) entry.cast<String, dynamic>(),
  ];
}

Object? _columnValue(Object? item, String key) {
  if (item is Map) return item[key];
  return themeItemBindings(item)['item.$key'];
}

int _compareValues(Object? a, Object? b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is bool && b is bool) {
    return (a ? 1 : 0).compareTo(b ? 1 : 0);
  }
  return _cellText(a).toLowerCase().compareTo(_cellText(b).toLowerCase());
}

String _cellText(Object? value) {
  return switch (value) {
    null => '',
    Duration duration => formatDuration(duration),
    bool boolean => boolean ? 'Yes' : 'No',
    double number when number == number.roundToDouble() =>
      number.toInt().toString(),
    _ => value.toString(),
  };
}

Alignment _tableAlignment(String? raw) {
  return switch (raw) {
    'center' => Alignment.center,
    'end' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}
