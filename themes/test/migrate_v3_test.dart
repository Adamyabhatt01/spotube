import 'package:spotube_themes/migrate_v3.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// A v3 payload with one of each thing the migration has to touch.
Map<String, dynamic> v3Payload() {
  const roles = <String>[
    'background',
    'foreground',
    'card',
    'cardForeground',
    'primary',
    'primaryForeground',
    'secondary',
    'secondaryForeground',
    'muted',
    'mutedForeground',
    'accent',
    'accentForeground',
    'destructive',
    'destructiveForeground',
    'border',
    'input',
    'ring',
  ];
  Map<String, dynamic> palette(String background, String foreground) => {
    for (final role in roles) role: background,
    'foreground': foreground,
    'cardForeground': foreground,
    'primaryForeground': background,
    'secondaryForeground': foreground,
    'mutedForeground': foreground,
    'accentForeground': foreground,
    'destructiveForeground': background,
  };

  return {
    'specVersion': 3,
    'light': palette('#ffffff', '#121212'),
    'dark': palette('#121212', '#ffffff'),
    'capabilities': ['ui.pages'],
    'dynamic': {'source': 'albumArt', 'algorithm': 'palette'},
    'layout': {
      'enforce': ['playerDock'],
      'player': {'dock': 'floating'},
      'responsive': {
        'xs': {'nav': 'rail'},
        'md': {'nav': 'labels'},
      },
    },
    'components': {
      'card': {
        'radius': 12,
        'hover': {'surfaceOpacity': 1},
      },
    },
    'ui': {
      'specVersion': 3,
      'pages': [
        {'id': 'audio', 'title': 'Audio'},
      ],
      'slots': {
        'sidebar.content': {
          'children': [
            {
              'type': 'search',
              'props': {'placeholder': 'Search'},
            },
          ],
        },
      },
    },
  };
}

void main() {
  group('migrateV3Theme', () {
    late MigrationReport report;

    setUp(() {
      report = migrateV3Theme(v3Payload());
    });

    test('declares v4 and the default kit', () {
      expect(report.payload['specVersion'], 4);
      expect(report.payload['uiKit'], 'shadcn');
      expect(report.renamed, contains(contains('uiKit')));
    });

    test('removes the v3-only dynamic block and layout gate', () {
      expect(report.payload, isNot(contains('dynamic')));
      expect((report.payload['layout'] as Map), isNot(contains('enforce')));
      expect(report.removed, contains(contains('dynamic')));
      expect(report.removed, contains(contains('layout.enforce')));
    });

    test('rewrites the floating dock to compact', () {
      final player = (report.payload['layout'] as Map)['player'] as Map;
      expect(player['dock'], 'compact');
      expect(report.renamed, contains(contains('floating')));
    });

    test('folds the responsive aliases into the v4 breakpoints', () {
      final responsive = (report.payload['layout'] as Map)['responsive'] as Map;
      expect(responsive.keys, containsAll(['compact', 'medium']));
      expect(responsive, isNot(contains('xs')));
      expect(responsive, isNot(contains('md')));
    });

    test('drops the component sub-states v4 does not define', () {
      final card = (report.payload['components'] as Map)['card'] as Map;
      expect(card, isNot(contains('hover')));
      expect(report.removed, contains(contains('components.card.hover')));
    });

    test('keeps the v2 UI envelope', () {
      final ui = report.payload['ui'] as Map;
      expect(ui['specVersion'], 2);
      expect(report.renamed, contains(contains('ui.specVersion 3 → 2')));
    });

    test('copies ui.pages to the top level', () {
      expect(report.payload['pages'], isNotEmpty);
      expect(report.renamed, contains(contains('ui.pages')));
    });

    test('renames search to textField and flattens nested props', () {
      final node =
          (((report.payload['ui'] as Map)['slots'] as Map)['sidebar.content']
                  as Map)['children'][0]
              as Map;
      expect(node['type'], 'textField');
      expect(node['placeholder'], 'Search');
      expect(node, isNot(contains('props')));
      expect(report.manual, contains(contains('search')));
    });

    test('the migrated payload passes the v4 validator', () {
      final validation = validateThemePayload(report.payload);
      expect(
        validation.hasErrors,
        isFalse,
        reason: validation.issues.join('\n'),
      );
    });
  });
}
