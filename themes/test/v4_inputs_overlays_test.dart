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
      'sidebar.content': {'children': children},
    },
  },
};

List<String> _errors(ValidationReport report) => [
  for (final issue in report.issues)
    if (issue.severity == Severity.error) issue.path,
];

ValidationReport _validate(List<Map<String, dynamic>> children) =>
    validateThemePayload(_payload(children));

void main() {
  test('accepts every Phase 2 input and overlay node', () {
    final report = _validate([
      {
        'type': 'slider',
        'bind': 'player.volume',
        'min': 0,
        'max': 1,
        'step': 0.05,
        'label': 'Volume',
        'showValue': true,
        'orientation': 'horizontal',
        'action': {
          'type': 'setVolume',
          'args': {'volume': r'$value'},
        },
      },
      {'type': 'switch', 'label': 'Shuffle', 'bind': 'player.shuffled'},
      {'type': 'checkbox', 'label': 'Mute', 'bind': 'player.muted'},
      {
        'type': 'radioGroup',
        'bind': 'player.loop',
        'options': [
          {'value': 'off', 'label': 'Off'},
          {'value': 'all', 'label': 'All'},
        ],
      },
      {
        'type': 'textField',
        'placeholder': 'Search',
        'debounceMs': 200,
        'clearable': true,
        'icon': 'search',
      },
      {
        'type': 'textArea',
        'placeholder': 'Notes',
        'debounceMs': 0,
        'clearable': false,
        'icon': 'edit',
        'minLines': 3,
        'maxLines': 6,
      },
      {
        'type': 'select',
        'placeholder': 'Crossfade',
        'options': [
          {'value': '0', 'label': 'Off'},
          {'value': '3', 'label': '3 seconds'},
        ],
      },
      {
        'type': 'segmented',
        'valueBind': 'app.themeMode',
        'options': [
          'system',
          {'value': 'light', 'label': 'Light'},
        ],
      },
      {
        'type': 'tabs',
        'bind': 'queue.currentIndex',
        'items': [
          {'id': 'queue', 'label': 'Queue', 'icon': 'list'},
          {'id': 'lyrics', 'label': 'Lyrics'},
        ],
        'panels': [
          [
            {'type': 'text', 'text': 'Queue panel'},
          ],
          [
            {'type': 'text', 'text': 'Lyrics panel'},
          ],
        ],
      },
      {
        'type': 'menu',
        'trigger': 'More',
        'placement': 'bottomEnd',
        'items': [
          {
            'label': 'Settings',
            'icon': 'settings',
            'action': {'type': 'openSettings'},
          },
          {
            'label': 'Muted',
            'checked': true,
            'disabled': false,
            'actions': [
              {
                'type': 'setMuted',
                'args': {'value': true},
              },
            ],
          },
        ],
      },
      {
        'type': 'contextMenu',
        'items': [
          {
            'label': 'Copy',
            'action': {'type': 'copy'},
          },
        ],
        'children': [
          {'type': 'text', 'text': 'Row'},
        ],
      },
      {
        'type': 'popover',
        'trigger': 'Details',
        'placement': 'bottomStart',
        'children': [
          {'type': 'text', 'text': 'Body'},
        ],
      },
      {
        'type': 'tooltip',
        'text': 'Hint',
        'placement': 'top',
        'children': [
          {'type': 'text', 'text': 'Hover'},
        ],
      },
      {
        'type': 'dialog',
        'title': 'Clear queue?',
        'description': 'This cannot be undone.',
        'openBind': 'app.asideOpen',
        'actions': [
          {
            'label': 'Cancel',
            'action': {'type': 'dismiss'},
          },
          {
            'label': 'Clear',
            'action': {
              'type': 'setQuery',
              'args': {'query': ''},
            },
          },
        ],
        'children': [
          {'type': 'text', 'text': 'Body'},
        ],
      },
      {
        'type': 'sheet',
        'side': 'right',
        'width': 320,
        'openBind': 'app.asideOpen',
        'children': [
          {'type': 'text', 'text': 'Sheet'},
        ],
      },
    ]);

    expect(_errors(report), isEmpty, reason: report.issues.join('\n'));
  });

  test('slider rejects an unknown orientation and non-numeric bounds', () {
    final report = _validate([
      {
        'type': 'slider',
        'orientation': 'diagonal',
        'min': 'low',
        'max': 1,
        'step': -1,
      },
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].orientation'));
    expect(errors, contains('ui.slots.sidebar.content[0].min'));
    expect(errors, isNot(contains('ui.slots.sidebar.content[0].step')));
    expect(
      report.issues.where(
        (issue) =>
            issue.severity == Severity.warning &&
            issue.path == 'ui.slots.sidebar.content[0].step',
      ),
      hasLength(1),
      reason: 'an out-of-range number is clamped, not rejected',
    );
  });

  test('text inputs reject a negative debounce and bad line counts', () {
    final report = _validate([
      {'type': 'textField', 'debounceMs': -1},
      {'type': 'textArea', 'minLines': 0, 'maxLines': 9},
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].debounceMs'));
    expect(errors, contains('ui.slots.sidebar.content[1].minLines'));
    expect(errors, contains('ui.slots.sidebar.content[1].maxLines'));
  });

  test('radioGroup and select need objects with unique values', () {
    final report = _validate([
      {
        'type': 'radioGroup',
        'options': ['off', 'on'],
      },
      {
        'type': 'select',
        'options': [
          {'value': 'a', 'label': 'A'},
          {'value': 'a', 'label': 'Again'},
          {'label': 'No value'},
        ],
      },
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].options[0]'));
    expect(errors, contains('ui.slots.sidebar.content[1].options[1].value'));
    expect(errors, contains('ui.slots.sidebar.content[1].options[2].value'));
  });

  test('segmented accepts bare string options', () {
    final report = _validate([
      {
        'type': 'segmented',
        'options': ['list', 'grid'],
      },
    ]);

    expect(_errors(report), isEmpty);
  });

  test('a select needs at least one option', () {
    final report = _validate([
      {'type': 'select', 'options': []},
    ]);

    expect(_errors(report), contains('ui.slots.sidebar.content[0].options'));
  });

  test('tabs ids are unique and panels match the items', () {
    final report = _validate([
      {
        'type': 'tabs',
        'items': [
          {'id': 'one', 'label': 'One'},
          {'id': 'one', 'label': 'Again'},
        ],
        'panels': [
          [
            {'type': 'text', 'text': 'first'},
          ],
        ],
      },
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].items[1].id'));
    expect(errors, contains('ui.slots.sidebar.content[0].panels'));
  });

  test('tabs panels may be omitted', () {
    final report = _validate([
      {
        'type': 'tabs',
        'items': [
          {'id': 'one', 'label': 'One'},
        ],
      },
    ]);

    expect(_errors(report), isEmpty);
  });

  test('tabs panels are checked as node lists', () {
    final report = _validate([
      {
        'type': 'tabs',
        'items': [
          {'id': 'one', 'label': 'One'},
        ],
        'panels': [
          [
            {'type': 'mystery'},
          ],
        ],
      },
    ]);

    expect(
      _errors(report),
      contains('ui.slots.sidebar.content[0].panels[0][0]'),
    );
  });

  test('a menu item list is capped at 32', () {
    final report = _validate([
      {
        'type': 'menu',
        'items': [
          for (var i = 0; i < 33; i++) {'label': 'Item $i'},
        ],
      },
    ]);

    final warning = report.issues.where(
      (issue) => issue.severity == Severity.warning && issue.resolved == 32,
    );
    expect(warning, hasLength(1));
  });

  test('menu placement and trigger are checked', () {
    final report = _validate([
      {
        'type': 'menu',
        'placement': 'sideways',
        'trigger': 7,
        'items': [
          {'label': 'Item'},
        ],
      },
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].placement'));
    expect(errors, contains('ui.slots.sidebar.content[0].trigger'));
  });

  test('dialog actions are button descriptors, capped at four', () {
    final report = _validate([
      {
        'type': 'dialog',
        'actions': [
          {'label': 'One'},
          {'label': 'Two'},
          {'label': 'Three'},
          {'label': 'Four'},
          {'label': 'Five'},
          {
            'action': {'type': 'dismiss'},
          },
          {
            'label': 'Bad',
            'action': {'type': 'notAVerb'},
          },
        ],
        'children': const [],
      },
    ]);

    final issues = report.issues;
    expect(
      issues.where(
        (issue) => issue.severity == Severity.warning && issue.resolved == 4,
      ),
      hasLength(1),
    );
    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].actions[5].label'));
    expect(
      errors,
      contains('ui.slots.sidebar.content[0].actions[6].action.type'),
    );
  });

  test('sheet side and width are checked', () {
    final report = _validate([
      {'type': 'sheet', 'side': 'diagonal', 'width': -1, 'children': const []},
    ]);

    final errors = _errors(report);
    expect(errors, contains('ui.slots.sidebar.content[0].side'));
    expect(errors, isNot(contains('ui.slots.sidebar.content[0].width')));
    expect(
      report.issues.where(
        (issue) =>
            issue.severity == Severity.warning &&
            issue.path == 'ui.slots.sidebar.content[0].width',
      ),
      hasLength(1),
    );
  });

  test('overlay openBind must be a known binding', () {
    final report = _validate([
      {'type': 'dialog', 'openBind': 'dialog.open', 'children': const []},
    ]);

    expect(_errors(report), contains('ui.slots.sidebar.content[0].openBind'));
  });
}
