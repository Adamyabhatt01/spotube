// Phase 3: data display and virtualization.
//
// These tests pin the parts a screenshot cannot show: only visible rows are
// built, filtering is debounced and folds case/diacritics, a table sorts in
// the host and pins its header, and the open/page state of tree, accordion,
// collapsible and carousel lives in the host rather than in a theme action.
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme({String uiKit = 'shadcn'}) {
  return ThemeDefinition(
    specVersion: 4,
    uiKit: uiKit,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime({
  Map<String, dynamic> bindings = const {},
  ThemeUiActionCallback? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(Widget child, {bool scrollable = true}) {
  return ShadcnApp(
    // Pin desktop scaling so the logical pixels in these tests are stable.
    scaling: const AdaptiveScaling(1),
    home: Scaffold(
      child: scrollable ? SingleChildScrollView(child: child) : child,
    ),
  );
}

Widget _node(ThemeUiRuntime runtime, Map<String, dynamic> node) {
  return ThemeUiNodeView(runtime: runtime, node: node);
}

Map<String, dynamic> _action(String type, [Map<String, dynamic>? args]) {
  return {
    'type': type,
    if (args != null) 'args': args,
  };
}

List<Map<String, dynamic>> _rows(int count) {
  return [
    for (var i = 0; i < count; i++) {'title': 'Row $i'},
  ];
}

double _top(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text)).dy;
}

void main() {
  setUp(() {
    ThemeUiDiagnostics.enabled = true;
    ThemeUiDiagnostics.reset();
  });

  tearDown(() {
    ThemeUiDiagnostics.reset();
  });

  group('virtualList', () {
    testWidgets('builds only the visible slice of 10,000 rows', (tester) async {
      final items = _rows(10000);
      final watch = Stopwatch()..start();

      await tester.pumpWidget(_app(
        SizedBox(
          height: 400,
          child: _node(_runtime(bindings: {'tracks': items}), {
            'type': 'virtualList',
            'bind': 'tracks',
            'itemExtent': 32,
            'overscan': 2,
            'children': [
              {'type': 'text', 'bind': 'item.title'},
            ],
          }),
        ),
        scrollable: false,
      ));
      watch.stop();

      final list = tester.widget<material.ListView>(
        find.byType(material.ListView),
      );
      expect(list.itemExtent, 32);
      expect(list.cacheExtent, 64, reason: 'overscan is in row extents');

      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 5000'), findsNothing);
      // A virtual list builds the viewport and its cache, not 10,000 rows.
      final built = tester.widgetList<Text>(find.byType(Text)).length;
      expect(built, lessThan(40));

      // The build budget is generous because this runs in debug; the claim
      // under test is that the tree stays virtualized at the contract's cap.
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 1)),
        reason: '10,000 rows took ${watch.elapsed} to build',
      );

      final scrollable = tester.state<material.ScrollableState>(
        find.byType(material.Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();

      expect(find.text('Row 9999'), findsOneWidget);
      expect(find.text('Row 0'), findsNothing);
    });

    testWidgets('honours limit, itemTemplate and the empty fallback',
        (tester) async {
      final runtime = ThemeUiRuntime(
        theme: _theme(),
        bindings: ThemeUiBindings({'tracks': _rows(5)}),
        assets: const ThemeUiAssets(),
        templates: {
          'row': const ThemeUiTemplate(children: [
            {'type': 'text', 'bind': 'item.title'},
          ]),
        },
        specVersion: 4,
        onAction: (_) {},
      );

      await tester.pumpWidget(_app(
        SizedBox(
          height: 200,
          child: _node(runtime, const {
            'type': 'virtualList',
            'bind': 'tracks',
            'limit': 2,
            'itemExtent': 32,
            'itemTemplate': 'row',
          }),
        ),
        scrollable: false,
      ));

      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsNothing);

      final scrollable = tester.state<material.ScrollableState>(
        find.byType(material.Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
    });

    testWidgets('columns lays the rows out as a grid of equal cells',
        (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          height: 200,
          child: _node(_runtime(bindings: {'tracks': _rows(5)}), {
            'type': 'virtualList',
            'bind': 'tracks',
            'columns': 2,
            'itemExtent': 32,
            'children': [
              {'type': 'text', 'bind': 'item.title'},
            ],
          }),
        ),
        scrollable: false,
      ));

      // Five entries in two columns is three rows, and the extent is per row:
      // the lazy path keeps its fixed-height assumption either way.
      final list = tester.widget<material.ListView>(
        find.byType(material.ListView),
      );
      expect(list.itemExtent, 32);

      expect(_top(tester, 'Row 1'), _top(tester, 'Row 0'));
      expect(
        tester.getTopLeft(find.text('Row 1')).dx,
        greaterThan(tester.getTopLeft(find.text('Row 0')).dx),
      );
      // Row 4 is the third row's first cell — two row extents below the top,
      // which only holds if the extent counts a row of cells, not a cell.
      expect(_top(tester, 'Row 2'), 32);
      expect(_top(tester, 'Row 4'), 64);
    });

    testWidgets('an empty binding renders nothing', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          height: 200,
          child: _node(_runtime(bindings: {'tracks': const []}), const {
            'type': 'virtualList',
            'bind': 'tracks',
            'children': [
              {'type': 'text', 'text': 'never'},
            ],
          }),
        ),
        scrollable: false,
      ));

      expect(find.text('never'), findsNothing);
      expect(find.byType(material.ListView), findsNothing);
    });
  });

  group('list filtering', () {
    testWidgets('matches case and diacritics after the debounce',
        (tester) async {
      final items = <Map<String, dynamic>>[
        {'title': 'Café'},
        {'title': 'Tea'},
        {'title': 'Cafeteria'},
      ];

      Widget build(String query) {
        return _app(_node(
          _runtime(bindings: {'query': query, 'tracks': items}),
          {
            'type': 'list',
            'bind': 'tracks',
            'filter': {
              'bind': 'query',
              'fields': ['title'],
            },
            'children': [
              {'type': 'text', 'bind': 'item.title'},
            ],
          },
        ));
      }

      await tester.pumpWidget(build(''));
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('Cafeteria'), findsOneWidget);

      await tester.pumpWidget(build('CAFE'));
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.text('Tea'), findsOneWidget,
          reason: 'the previous query is still applied while typing');

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Cafeteria'), findsOneWidget);
      expect(find.text('Tea'), findsNothing);

      await tester.pumpWidget(build('ZZZ'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Café'), findsNothing);
      expect(find.text('Cafeteria'), findsNothing);
      expect(find.text('Tea'), findsNothing);
    });

    testWidgets('virtualList filters the same way', (tester) async {
      final items = <Map<String, dynamic>>[
        {'title': 'Éclair'},
        {'title': 'Muffin'},
      ];

      Widget build(String query) {
        return _app(
          SizedBox(
            height: 200,
            child: _node(
              _runtime(bindings: {'query': query, 'tracks': items}),
              {
                'type': 'virtualList',
                'bind': 'tracks',
                'filter': {
                  'bind': 'query',
                  'fields': ['title'],
                },
                'children': [
                  {'type': 'text', 'bind': 'item.title'},
                ],
              },
            ),
          ),
          scrollable: false,
        );
      }

      await tester.pumpWidget(build(''));
      expect(find.text('Muffin'), findsOneWidget);

      await tester.pumpWidget(build('eclair'));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Éclair'), findsOneWidget);
      expect(find.text('Muffin'), findsNothing);
    });
  });

  group('table', () {
    Map<String, dynamic> table(List<Map<String, dynamic>> items,
        {bool sticky = false, bool sortable = false}) {
      return {
        'type': 'table',
        'bind': 'rows',
        'stickyHeader': sticky,
        'sortable': sortable,
        'columns': [
          {'key': 'title', 'label': 'Name'},
          {'key': 'count', 'label': 'Count', 'align': 'end'},
        ],
      };
    }

    testWidgets('sorts on a header tap and flips direction', (tester) async {
      final items = <Map<String, dynamic>>[
        {'title': 'beta', 'count': 2},
        {'title': 'alpha', 'count': 3},
        {'title': 'gamma', 'count': 1},
      ];
      await tester.pumpWidget(_app(
        _node(
          _runtime(bindings: {'rows': items}),
          table(items, sortable: true),
        ),
      ));

      expect(_top(tester, 'beta'), lessThan(_top(tester, 'alpha')));

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(_top(tester, 'alpha'), lessThan(_top(tester, 'beta')));
      expect(_top(tester, 'beta'), lessThan(_top(tester, 'gamma')));
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(_top(tester, 'gamma'), lessThan(_top(tester, 'beta')));
      expect(_top(tester, 'beta'), lessThan(_top(tester, 'alpha')));
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('a sticky header stays pinned while rows scroll',
        (tester) async {
      final items = [
        for (var i = 0; i < 40; i++) {'title': 'Item $i', 'count': i},
      ];
      await tester.pumpWidget(_app(
        SizedBox(
          height: 220,
          child: _node(
            _runtime(bindings: {'rows': items}),
            table(items, sticky: true),
          ),
        ),
        scrollable: false,
      ));

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Item 0'), findsOneWidget);

      await tester.drag(
        find.byType(material.CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pump();

      expect(find.text('Name'), findsOneWidget);
      expect(_top(tester, 'Name'), lessThan(40));
      expect(find.text('Item 0'), findsNothing);
    });
  });

  group('tree', () {
    testWidgets('expands and collapses host-side', (tester) async {
      final nodes = <Map<String, dynamic>>[
        {
          'label': 'Playlists',
          'children': [
            {'label': 'Roadtrip'},
            {
              'label': 'Focus',
              'children': [
                {'label': 'Deep work'},
              ],
            },
          ],
        },
      ];

      await tester.pumpWidget(_app(
        _node(_runtime(bindings: {'nodes': nodes}), const {
          'type': 'tree',
          'bind': 'nodes',
        }),
      ));

      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Roadtrip'), findsNothing);

      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Roadtrip'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Deep work'), findsNothing);

      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();
      expect(find.text('Deep work'), findsOneWidget);

      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Roadtrip'), findsNothing);
      expect(find.text('Focus'), findsNothing);
    });

    testWidgets('seeds open branches from the expanded key', (tester) async {
      final nodes = <Map<String, dynamic>>[
        {
          'label': 'Open',
          'expanded': true,
          'children': [
            {'label': 'Visible'},
          ],
        },
      ];

      await tester.pumpWidget(_app(
        _node(_runtime(bindings: {'nodes': nodes}), const {
          'type': 'tree',
          'bind': 'nodes',
        }),
      ));

      expect(find.text('Visible'), findsOneWidget);
    });
  });

  group('accordion and collapsible', () {
    testWidgets('an accordion keeps one panel open unless multiple is set',
        (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(), const {
          'type': 'accordion',
          'items': [
            {
              'title': 'One',
              'children': [
                {'type': 'text', 'text': 'Body one'},
              ],
            },
            {
              'title': 'Two',
              'children': [
                {'type': 'text', 'text': 'Body two'},
              ],
            },
          ],
        }),
      ));

      expect(find.text('Body one'), findsNothing);

      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(find.text('Body one'), findsOneWidget);

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(find.text('Body one'), findsNothing);
      expect(find.text('Body two'), findsOneWidget);
    });

    testWidgets('multiple accordion panels stay open together', (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(), const {
          'type': 'accordion',
          'multiple': true,
          'items': [
            {
              'title': 'One',
              'children': [
                {'type': 'text', 'text': 'Body one'},
              ],
            },
            {
              'title': 'Two',
              'children': [
                {'type': 'text', 'text': 'Body two'},
              ],
            },
          ],
        }),
      ));

      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();

      expect(find.text('Body one'), findsOneWidget);
      expect(find.text('Body two'), findsOneWidget);
    });

    testWidgets('collapsible opens by tap and follows openBind',
        (tester) async {
      Widget build(bool open) {
        return _app(_node(
          _runtime(bindings: {'details.open': open}),
          const {
            'type': 'collapsible',
            'title': 'Details',
            'openBind': 'details.open',
            'children': [
              {'type': 'text', 'text': 'Hidden body'},
            ],
          },
        ));
      }

      await tester.pumpWidget(build(false));
      expect(find.text('Hidden body'), findsNothing);

      await tester.pumpWidget(build(true));
      expect(find.text('Hidden body'), findsOneWidget);

      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(find.text('Hidden body'), findsNothing);
    });
  });

  group('carousel', () {
    testWidgets('pages horizontally and keeps its dots in sync',
        (tester) async {
      final items = <Map<String, dynamic>>[
        {'title': 'Slide A'},
        {'title': 'Slide B'},
      ];

      await tester.pumpWidget(_app(
        _node(_runtime(bindings: {'slides': items}), const {
          'type': 'carousel',
          'bind': 'slides',
          'height': 160,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        }),
      ));

      expect(find.text('Slide A'), findsOneWidget);
      expect(find.text('Slide B'), findsNothing);

      await tester.drag(
        find.byType(material.PageView),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Slide B'), findsOneWidget);
      expect(find.text('Slide A'), findsNothing);
    });
  });

  group('small displays', () {
    testWidgets('badge, chip and avatar render their data', (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(bindings: {'selected': true}), const {
          'type': 'column',
          'gap': 12,
          'children': [
            {'type': 'badge', 'text': 'NEW'},
            {'type': 'chip', 'label': 'Rock', 'selectedBind': 'selected'},
            {'type': 'avatar', 'fallback': 'ada', 'size': 48},
          ],
        }),
      ));

      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('an empty badge or chip renders nothing', (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(), const {
          'type': 'column',
          'children': [
            {'type': 'badge', 'text': ''},
            {'type': 'chip', 'label': ''},
          ],
        }),
      ));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('skeleton draws one pulsing block per row', (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(), const {
          'type': 'skeleton',
          'width': 120,
          'height': 16,
          'count': 3,
        }),
      ));

      expect(find.byType(Opacity), findsNWidgets(3));
      final sized = tester.widgetList<Container>(find.byType(Container));
      expect(sized.length, greaterThanOrEqualTo(3));

      // The pulse is an animation, not a timer; one frame is enough and the
      // test must not wait for it to settle.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('spinner paints a custom arc', (tester) async {
      await tester.pumpWidget(_app(
        _node(_runtime(), const {
          'type': 'spinner',
          'size': 24,
        }),
      ));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is material.CustomPaint &&
              widget.painter.runtimeType.toString().contains('SpinnerPainter'),
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a wavy progress paints instead of using the kit bar',
        (tester) async {
      await tester.pumpWidget(_app(
        _node(
          _runtime(bindings: {
            'player.position': const Duration(seconds: 30),
            'player.duration': const Duration(minutes: 2),
          }),
          const {
            'type': 'progress',
            'style': 'wavy',
            'height': 10,
            'width': 200,
          },
        ),
      ));

      expect(find.byType(material.LinearProgressIndicator), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is material.CustomPaint &&
              widget.painter.runtimeType.toString().contains('ProgressPainter'),
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('breadcrumb and pagination', () {
    testWidgets('breadcrumb fires the tapped crumb', (tester) async {
      final fired = <ThemeUiAction>[];

      await tester.pumpWidget(_app(
        _node(_runtime(onAction: fired.add), {
          'type': 'breadcrumb',
          'items': [
            {
              'label': 'Home',
              'action': _action('plugin', {'id': 'home'}),
            },
            {'label': 'Library'},
          ],
        }),
      ));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pump();

      expect(fired.single.type, 'plugin');
      expect(fired.single.args['id'], 'home');
    });

    testWidgets(r'pagination fires the chosen page with $value',
        (tester) async {
      final fired = <ThemeUiAction>[];

      await tester.pumpWidget(_app(
        _node(
          _runtime(bindings: {'page': 2}, onAction: fired.add),
          {
            'type': 'pagination',
            'pageCount': 5,
            'pageBind': 'page',
            'action': _action('plugin', {'page': r'$value'}),
          },
        ),
      ));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('4'), findsNothing);

      await tester.tap(find.text('3'));
      await tester.pump();

      expect(fired.single.args['page'], 3);
    });
  });

  group('caps', () {
    testWidgets('a table keeps at most 500 static rows', (tester) async {
      final items = [
        for (var i = 0; i < 600; i++) {'title': 'Item $i'},
      ];
      await tester.pumpWidget(_app(
        _node(_runtime(bindings: {'rows': items}), const {
          'type': 'table',
          'bind': 'rows',
          'columns': [
            {'key': 'title', 'label': 'Name'},
          ],
        }),
      ));

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 499'), findsOneWidget);
      expect(find.text('Item 500'), findsNothing);
    });
  });
}
