import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// A complete, minimal v4 payload that each test puts one node under.
Map<String, dynamic> validPayload() {
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
    'specVersion': 4,
    'light': palette('#ffffff', '#121212'),
    'dark': palette('#121212', '#ffffff'),
  };
}

Map<String, dynamic> withUi(List<Map<String, dynamic>> children) {
  final payload = validPayload();
  payload['ui'] = {
    'specVersion': 2,
    'slots': {
      'home.content': {'children': children},
    },
  };
  return payload;
}

List<String> errorsOf(ValidationReport report) => [
  for (final issue in report.issues)
    if (issue.severity == Severity.error) issue.path,
];

List<String> warningsOf(ValidationReport report) => [
  for (final issue in report.issues)
    if (issue.severity == Severity.warning) issue.path,
];

void main() {
  group('the data-display vocabulary', () {
    test('accepts every new node with its current props', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'virtualList',
            'bind': 'library.playlists',
            'limit': 10000,
            'itemExtent': 32,
            'overscan': 4,
            'itemTemplate': 'row',
            'filter': {
              'bind': 'search.query',
              'fields': ['title', 'artist'],
            },
            'children': [
              {'type': 'text', 'bind': 'item.title'},
            ],
          },
          {
            'type': 'table',
            'bind': 'library.playlists',
            'columns': [
              {'key': 'title', 'label': 'Name'},
              {'key': 'count', 'label': 'Tracks', 'width': 90, 'align': 'end'},
            ],
            'rowTemplate': 'row',
            'stickyHeader': true,
            'sortable': true,
          },
          {
            'type': 'tree',
            'bind': 'library.playlists',
            'labelKey': 'title',
            'childrenKey': 'children',
            'expandedKey': 'expanded',
          },
          {
            'type': 'accordion',
            'multiple': true,
            'items': [
              {
                'title': 'One',
                'children': [
                  {'type': 'text', 'text': 'Body'},
                ],
              },
            ],
          },
          {
            'type': 'collapsible',
            'title': 'Details',
            'openBind': 'player.playing',
            'children': [
              {'type': 'text', 'text': 'Body'},
            ],
          },
          {
            'type': 'carousel',
            'bind': 'library.playlists',
            'itemTemplate': 'row',
            'height': 180,
            'autoplay': true,
            'children': [
              {'type': 'text', 'bind': 'item.title'},
            ],
          },
          {'type': 'badge', 'text': 'NEW', 'variant': 'outline'},
          {'type': 'chip', 'label': 'Rock', 'selectedBind': 'player.playing'},
          {'type': 'avatar', 'fallback': 'ada', 'size': 48},
          {'type': 'skeleton', 'width': 120, 'height': 16, 'count': 3},
          {'type': 'spinner', 'size': 24, 'color': '#ff0000'},
          {
            'type': 'breadcrumb',
            'items': [
              {'label': 'Home'},
              {'label': 'Library'},
            ],
          },
          {
            'type': 'pagination',
            'pageCount': 10,
            'pageBind': 'queue.currentIndex',
            'action': {
              'type': 'plugin',
              'args': {'id': 'pager', 'page': r'$value'},
            },
          },
          {'type': 'progress', 'style': 'wavy'},
        ]),
      );

      expect(
        report.hasErrors,
        isFalse,
        reason: report.issues.map((issue) => issue.toString()).join('\n'),
      );
      expect(
        report.warningCount,
        0,
        reason: report.issues.map((issue) => issue.toString()).join('\n'),
      );
    });

    test('filter rejects unknown keys and bad fields', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'virtualList',
            'bind': 'library.playlists',
            'filter': {
              'bind': 'search.query',
              'fields': ['title', 'title', 'not a field'],
              'mode': 'fuzzy',
            },
          },
        ]),
      );

      final errors = errorsOf(report);
      expect(errors, contains('ui.slots.home.content[0].filter.mode'));
      expect(errors, contains('ui.slots.home.content[0].filter.fields[1]'));
      expect(errors, contains('ui.slots.home.content[0].filter.fields[2]'));
    });

    test('filter caps fields with a warning', () {
      final fields = [for (var i = 0; i < 33; i++) 'field$i'];
      final report = validateThemePayload(
        withUi([
          {
            'type': 'list',
            'bind': 'library.playlists',
            'filter': {'bind': 'search.query', 'fields': fields},
          },
        ]),
      );

      expect(report.hasErrors, isFalse);
      expect(
        warningsOf(report),
        contains('ui.slots.home.content[0].filter.fields'),
      );
    });

    test('columns reject duplicates, unknown keys and bad alignment', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'table',
            'bind': 'library.playlists',
            'columns': [
              {'key': 'title', 'label': 'Name'},
              {'key': 'title', 'align': 'middle', 'sort': 'asc'},
            ],
          },
        ]),
      );

      final errors = errorsOf(report);
      expect(errors, contains('ui.slots.home.content[0].columns[1].key'));
      expect(errors, contains('ui.slots.home.content[0].columns[1].sort'));
      expect(errors, contains('ui.slots.home.content[0].columns[1].align'));
    });

    test('columns cap at 32 with a warning', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'table',
            'bind': 'library.playlists',
            'columns': [
              for (var i = 0; i < 33; i++) {'key': 'column$i'},
            ],
          },
        ]),
      );

      expect(warningsOf(report), contains('ui.slots.home.content[0].columns'));
    });

    test('progress style is linear or wavy', () {
      for (final style in ['linear', 'wavy']) {
        final report = validateThemePayload(
          withUi([
            {'type': 'progress', 'style': style},
          ]),
        );
        expect(report.hasErrors, isFalse, reason: '$style was rejected');
      }

      final radial = validateThemePayload(
        withUi([
          {'type': 'progress', 'style': 'radial'},
        ]),
      );
      expect(errorsOf(radial), contains('ui.slots.home.content[0].style'));
    });

    test('virtualList limits, extents and overscan stay in range', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'virtualList',
            'bind': 'library.playlists',
            'limit': 10001,
            'itemExtent': 401,
            'overscan': 65,
          },
        ]),
      );

      final errors = errorsOf(report);
      expect(errors, contains('ui.slots.home.content[0].limit'));
      expect(
        warningsOf(report),
        contains('ui.slots.home.content[0].itemExtent'),
      );
      expect(errors, contains('ui.slots.home.content[0].overscan'));
    });

    test('a static list still caps at 500', () {
      final report = validateThemePayload(
        withUi([
          {'type': 'list', 'bind': 'library.playlists', 'limit': 501},
        ]),
      );

      expect(errorsOf(report), contains('ui.slots.home.content[0].limit'));
    });

    test('small-display sizes and counts are closed', () {
      final report = validateThemePayload(
        withUi([
          {'type': 'spinner', 'size': 4},
          {'type': 'skeleton', 'count': 51, 'height': 2},
          {'type': 'pagination', 'pageCount': 1001},
          {'type': 'avatar', 'fallback': 'x' * 65},
        ]),
      );

      final errors = errorsOf(report);
      expect(warningsOf(report), contains('ui.slots.home.content[0].size'));
      expect(errors, contains('ui.slots.home.content[1].count'));
      expect(errors, contains('ui.slots.home.content[2].pageCount'));
      expect(warningsOf(report), contains('ui.slots.home.content[3].fallback'));
    });

    test('template and tree keys are names, not arbitrary values', () {
      final report = validateThemePayload(
        withUi([
          {'type': 'table', 'bind': 'library.playlists', 'rowTemplate': 4},
          {'type': 'carousel', 'bind': 'library.playlists', 'itemTemplate': ''},
          {'type': 'tree', 'bind': 'library.playlists', 'labelKey': '2bad'},
        ]),
      );

      final errors = errorsOf(report);
      expect(errors, contains('ui.slots.home.content[0].rowTemplate'));
      expect(errors, contains('ui.slots.home.content[1].itemTemplate'));
      expect(errors, contains('ui.slots.home.content[2].labelKey'));
    });
  });
}
