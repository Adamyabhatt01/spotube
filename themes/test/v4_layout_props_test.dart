import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

Map<String, dynamic> _palette(String background, String foreground) {
  final palette = <String, dynamic>{
    for (final role in colorRoles) role: background,
  };
  palette.addAll({
    'foreground': foreground,
    'cardForeground': foreground,
    'primaryForeground': background,
    'secondaryForeground': foreground,
    'mutedForeground': foreground,
    'accentForeground': foreground,
    'destructiveForeground': background,
  });
  return palette;
}

Map<String, dynamic> _payload(List<Map<String, dynamic>> children) => {
      'specVersion': 4,
      'light': _palette('#ffffff', '#121212'),
      'dark': _palette('#121212', '#ffffff'),
      'ui': {
        'slots': {
          'sidebar.content': {
            'children': children,
          },
        },
      },
    };

List<String> _errors(ValidationReport report) => [
      for (final issue in report.issues)
        if (issue.severity == Severity.error) issue.path,
    ];

void main() {
  ValidationReport validate(List<Map<String, dynamic>> children) =>
      validateThemePayload(_payload(children));

  List<String> errorsEndingWith(ValidationReport report, String suffix) => [
        for (final path in _errors(report))
          if (path.endsWith(suffix)) path,
      ];

  test('accepts the Phase 1 layout vocabulary', () {
    final report = validate([
      {
        'type': 'box',
        'background': '#123456',
        'border': {'color': '@border', 'width': 2},
        'gradient': {
          'colors': ['@primary', '@background'],
          'begin': 'topCenter',
          'end': 'bottomCenter',
          'stops': [0.0, 0.9],
        },
        'radius': 12,
        'width': 200,
        'height': 100,
        'clip': true,
        'padding': 8,
        'opacity': 0.9,
        'children': [
          {
            'type': 'grid',
            'columns': 2,
            'gap': 8,
            'children': [
              {
                'type': 'safeArea',
                'edges': ['top'],
                'children': [
                  {
                    'type': 'aspectRatio',
                    'ratio': 1.5,
                    'children': [
                      {
                        'type': 'kitScope',
                        'kit': 'material',
                        'children': [
                          {'type': 'text', 'text': 'ok'},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ]);

    expect(
      report.issues.where((issue) => issue.severity == Severity.error),
      isEmpty,
      reason: report.issues.join('\n'),
    );
  });

  test('a bare colour border is accepted', () {
    final report = validate([
      {
        'type': 'box',
        'border': '@border',
        'children': const [],
      },
    ]);

    expect(_errors(report), isEmpty);
  });

  test('the retired from/to gradient shape is rejected', () {
    final report = validate([
      {
        'type': 'box',
        'gradient': {'from': '@primary', 'to': '@background'},
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.gradient.from'), isNotEmpty);
    expect(errorsEndingWith(report, '.gradient.to'), isNotEmpty);
    expect(errorsEndingWith(report, '.gradient.colors'), isNotEmpty);
  });

  test('a gradient needs 2..8 colours', () {
    final report = validate([
      {
        'type': 'box',
        'gradient': {'colors': ['@primary']},
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.gradient.colors'), isNotEmpty);
  });

  test('gradient stops must match the colours and never decrease', () {
    final report = validate([
      {
        'type': 'box',
        'gradient': {
          'colors': ['@primary', '@background'],
          'stops': [0.8],
        },
        'children': const [],
      },
      {
        'type': 'box',
        'gradient': {
          'colors': ['@primary', '@background'],
          'stops': [0.8, 0.2],
        },
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.gradient.stops'), isNotEmpty);
    expect(errorsEndingWith(report, '.gradient.stops[1]'), isNotEmpty);
  });

  test('a border width is clamped to 0..8 and its keys are closed', () {
    final report = validate([
      {
        'type': 'box',
        'border': {'color': '@border', 'width': 9},
        'children': const [],
      },
      {
        'type': 'box',
        'border': {'colour': '@border'},
        'children': const [],
      },
    ]);

    expect(
      [
        for (final issue in report.issues)
          if (issue.severity == Severity.warning) issue.path,
      ].any((path) => path.endsWith('.border.width')),
      isTrue,
    );
    expect(errorsEndingWith(report, '.border.colour'), isNotEmpty);
  });

  test('safeArea only accepts the four platform edges, once each', () {
    final report = validate([
      {
        'type': 'safeArea',
        'edges': ['top', 'middle'],
        'children': const [],
      },
      {
        'type': 'safeArea',
        'edges': ['top', 'top'],
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.edges[1]'), isNotEmpty);
  });

  test('grid columns are an integer 1..12', () {
    final report = validate([
      {
        'type': 'grid',
        'columns': 0,
        'children': const [],
      },
      {
        'type': 'grid',
        'columns': 13,
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.columns'), isNotEmpty);
  });

  test('kitScope only accepts a known kit', () {
    final report = validate([
      {
        'type': 'kitScope',
        'kit': 'watchos',
        'children': const [],
      },
    ]);

    expect(errorsEndingWith(report, '.kit'), isNotEmpty);
  });
}
