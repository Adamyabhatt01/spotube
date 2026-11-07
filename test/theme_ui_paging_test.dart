// Paging (onEndReached), lazy sliver lists beyond the single-column
// vertical case, and the ephemeral state layer.
//
// These pin the virtualization work: filtered and multi-column lists now
// take the lazy sliver path too, virtualList joins the page scroll, and
// onEndReached fires the authored action near the end under the two
// binding gates. The state tests pin setLocal/toggleLocal/clearLocal and
// their per-theme scoping.
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    uiKit: 'shadcn',
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

List<Map<String, dynamic>> _rows(int count) {
  return [
    for (var i = 0; i < count; i++) {'title': 'Row $i'},
  ];
}

Widget _sliverApp(ThemeUiNodeView node) {
  return ShadcnApp(
    home: Scaffold(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: Builder(
              builder: (context) => node.buildSliver(context),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('lazy sliver lists', () {
    testWidgets('a filtered list filters in the sliver snapshot',
        (tester) async {
      final node = ThemeUiNodeView(
        runtime: _runtime(bindings: {
          'tracks': [
            {'title': 'alpha'},
            {'title': 'beta'},
            {'title': 'gamma'},
          ],
          'search.query': 'beta',
        }),
        node: const {
          'type': 'list',
          'bind': 'tracks',
          'filter': {
            'bind': 'search.query',
            'fields': ['title'],
          },
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      await tester.pumpWidget(_sliverApp(node));

      expect(find.text('beta'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('gamma'), findsNothing);
    });

    testWidgets('a fixed multi-column list lays cells in rows',
        (tester) async {
      final node = ThemeUiNodeView(
        runtime: _runtime(bindings: {'tracks': _rows(6)}),
        node: const {
          'type': 'list',
          'bind': 'tracks',
          'columns': 3,
          'gap': 6,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      await tester.pumpWidget(_sliverApp(node));

      // The first row holds Row 0..2 on the same band.
      double dy(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(dy('Row 0'), dy('Row 1'));
      expect(dy('Row 1'), dy('Row 2'));
      expect(dy('Row 3'), greaterThan(dy('Row 0')));
      expect(dy('Row 4'), dy('Row 3'));
      expect(dy('Row 5'), dy('Row 4'));
    });

    testWidgets('a responsive column map resolves against the viewport',
        (tester) async {
      final node = ThemeUiNodeView(
        runtime: _runtime(bindings: {'tracks': _rows(12)}),
        node: const {
          'type': 'list',
          'bind': 'tracks',
          'columns': {'compact': 2, 'expanded': 4},
          'gap': 6,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      // 800-wide surface is the compact tier: two per row.
      await tester.pumpWidget(_sliverApp(node));
      double dy(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(dy('Row 0'), dy('Row 1'));
      expect(dy('Row 2'), greaterThan(dy('Row 0')));

      // Widen into the expanded tier: four per row.
      tester.view.physicalSize = const Size(2280, 1360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pump();
      expect(dy('Row 0'), dy('Row 3'));
      expect(dy('Row 4'), greaterThan(dy('Row 0')));
    });

    testWidgets('virtualList joins the page scroll as a sliver',
        (tester) async {
      final node = ThemeUiNodeView(
        runtime: _runtime(bindings: {'tracks': _rows(10000)}),
        node: const {
          'type': 'virtualList',
          'bind': 'tracks',
          'itemExtent': 32,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      await tester.pumpWidget(_sliverApp(node));

      expect(find.byType(material.SliverList), findsOneWidget);
      expect(find.byType(material.ListView), findsNothing);
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 5000'), findsNothing);
      final built = tester.widgetList<Text>(find.byType(Text)).length;
      expect(built, lessThan(60), reason: 'sliver must stay lazy');

      final scrollable = tester.state<material.ScrollableState>(
        find.byType(material.Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(find.text('Row 9999'), findsOneWidget);
    });
  });

  group('onEndReached', () {
    Future<void> jumpToEnd(WidgetTester tester) async {
      final scrollable = tester.state<material.ScrollableState>(
        find.byType(material.Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }

    testWidgets('fires once with the visible count when near the end',
        (tester) async {
      final fired = <ThemeUiAction>[];
      final node = ThemeUiNodeView(
        runtime: _runtime(
          bindings: {'tracks': _rows(50)},
          onAction: fired.add,
        ),
        node: const {
          'type': 'list',
          'bind': 'tracks',
          'onEndReached': {
            'type': 'plugin',
            'args': {'id': 'loadMore', 'value': r'$value'},
          },
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      await tester.pumpWidget(_sliverApp(node));
      expect(fired, isEmpty);

      await jumpToEnd(tester);
      expect(fired.length, 1);
      expect(fired.single.type, 'plugin');
      expect(fired.single.args['value'], 50);

      // A scroll bounce at the same count does not refire.
      await jumpToEnd(tester);
      expect(fired.length, 1);
    });

    testWidgets('hasMoreBind gates the fire; loadingBind silences it',
        (tester) async {
      final fired = <ThemeUiAction>[];
      final node = ThemeUiNodeView(
        runtime: _runtime(
          bindings: {
            'tracks': _rows(50),
            'queue.hasMore': true,
            'queue.loading': true,
          },
          onAction: fired.add,
        ),
        node: const {
          'type': 'list',
          'bind': 'tracks',
          'onEndReached': {
            'type': 'plugin',
            'args': {'id': 'loadMore'},
          },
          'hasMoreBind': 'queue.hasMore',
          'loadingBind': 'queue.loading',
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      );

      await tester.pumpWidget(_sliverApp(node));
      await jumpToEnd(tester);
      expect(fired, isEmpty, reason: 'loading must silence onEndReached');
    });

    testWidgets('virtualList box path fires near its own end',
        (tester) async {
      final fired = <ThemeUiAction>[];
      await tester.pumpWidget(
        ShadcnApp(
          home: Scaffold(
            child: SizedBox(
              height: 200,
              child: ThemeUiNodeView(
                runtime: _runtime(
                  bindings: {'tracks': _rows(30)},
                  onAction: fired.add,
                ),
                node: const {
                  'type': 'virtualList',
                  'bind': 'tracks',
                  'itemExtent': 32,
                  'onEndReached': {
                    'type': 'plugin',
                    'args': {'id': 'loadMore', 'value': r'$value'},
                  },
                  'children': [
                    {'type': 'text', 'bind': 'item.title'},
                  ],
                },
              ),
            ),
          ),
        ),
      );

      final scrollable = tester.state<material.ScrollableState>(
        find.byType(material.Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(
        fired.map((action) => action.args['value']),
        contains(30),
      );
    });
  });

  group('ephemeral state layer', () {
    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [
          themeSettingsNamespaceProvider.overrideWith(
            (ref) => (author: 'acme', name: 'demo'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<BuildContext> context(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('setLocal/toggleLocal/clearLocal publish scoped keys',
        (tester) async {
      final refContainer = container();
      final ctx = await context(tester);
      final notifier =
          refContainer.read(themeUiLocalStateProvider.notifier);

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('setLocal', {'key': 'dialog.open', 'value': true}),
      );
      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('setLocal', {'key': 'greeting', 'value': 'hi'}),
      );
      expect(refContainer.read(themeUiLocalStateProvider), {
        'acme.demo.dialog.open': true,
        'acme.demo.greeting': 'hi',
      });

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('toggleLocal', {'key': 'dialog.open'}),
      );
      expect(
        refContainer.read(themeUiLocalStateProvider)['acme.demo.dialog.open'],
        isFalse,
      );

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('toggleLocal', {
          'key': 'dialog.open',
          'value': 'ignored',
        }),
      );
      expect(
        refContainer.read(themeUiLocalStateProvider)['acme.demo.dialog.open'],
        isTrue,
      );

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('clearLocal', {'key': 'dialog.open'}),
      );
      expect(refContainer.read(themeUiLocalStateProvider), {
        'acme.demo.greeting': 'hi',
      });

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('clearLocal'),
      );
      expect(refContainer.read(themeUiLocalStateProvider), isEmpty);

      notifier.clear(null);
      notifier.set('a', 1);
      notifier.clear(null);
      expect(refContainer.read(themeUiLocalStateProvider), isEmpty);
    });

    testWidgets('a bad key or non-scalar value is dropped', (tester) async {
      final refContainer = container();
      final ctx = await context(tester);

      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('setLocal', {'key': '1bad', 'value': true}),
      );
      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('setLocal', {
          'key': 'ok',
          'value': {'nested': true},
        }),
      );
      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('setLocal', {'value': true}),
      );
      await dispatchThemeUiAction(
        ctx,
        refContainer,
        const ThemeUiAction('clearLocal', {'key': 'bad key!'}),
      );

      expect(refContainer.read(themeUiLocalStateProvider), isEmpty);
    });
  });
}
