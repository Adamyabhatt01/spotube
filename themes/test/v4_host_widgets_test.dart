// Phase 9: `hostWidget` is the one place a v4 document escapes the node
// vocabulary, so the validator is what keeps the escape hatch closed. These
// tests pin the two severity levels the contract distinguishes — an id the host
// does not mount is survivable (warning), a prop the widget never reads is a
// typo that would hide (error) — plus the per-prop type rules and the pin-target
// cross-check against the document's own `layout.pinTargets`.
import 'package:spotube_themes/v4_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

const _roles = [
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

Map<String, dynamic> _colors(String background, String foreground) => {
  for (final role in _roles) role: background,
  'foreground': foreground,
  'cardForeground': foreground,
  'primaryForeground': background,
  'secondaryForeground': foreground,
  'mutedForeground': foreground,
  'accentForeground': foreground,
  'destructiveForeground': background,
};

/// The host's own band count, mirrored so the range test does not silently
/// follow a `bands` cap the validator invented.
const _bandCount = 10;

const _slotNode = 'ui.slots.home.content[0]';

Map<String, dynamic> _host(String id, [Map<String, dynamic> props = const {}]) {
  return {'type': 'hostWidget', 'id': id, 'props': props};
}

ValidationReport _validate(
  Map<String, dynamic> node, {
  List<String> capabilities = const ['ui.hostWidgets'],
  List<Map<String, dynamic>>? pinTargets,
}) {
  return validateThemePayload({
    'specVersion': 4,
    'light': _colors('#ffffff', '#121212'),
    'dark': _colors('#121212', '#ffffff'),
    'capabilities': capabilities,
    if (pinTargets != null) 'layout': {'pinTargets': pinTargets},
    'ui': {
      'specVersion': 2,
      'slots': {
        'home.content': {'children': [node]},
      },
    },
  });
}

/// Only the paths this suite is about: an unrelated complaint about the fixture
/// should not read as a registry bug.
List<String> _paths(ValidationReport report, Severity severity) => [
  for (final issue in report.issues)
    if (issue.severity == severity &&
        (issue.path.startsWith('ui.slots') || issue.path.startsWith(_slotNode)))
      issue.path,
];

List<String> _errors(ValidationReport report) => _paths(report, Severity.error);

List<String> _warnings(ValidationReport report) =>
    _paths(report, Severity.warning);

void main() {
  group('the registry tables', () {
    test('every mountable id has a prop row', () {
      expect(v4HostWidgetIds, hasLength(12));
      expect(v4HostWidgetProps.keys.toSet(), v4HostWidgetIds);
    });

    test('the widget count stays under the contract cap', () {
      // The plan caps the catalogue so `hostWidget` cannot grow into a second
      // UI framework. Raising this number is a contract change, not a fix.
      expect(v4HostWidgetIds.length, lessThanOrEqualTo(12));
    });

    test('every prop has a type rule', () {
      final typed = {for (final props in v4HostWidgetProps.values) ...props};

      expect(typed, _checkedProps);
    });
  });

  group('hostWidget capability', () {
    test('a declared capability and a known id is clean', () {
      expect(_validate(_host('library.playlists')).issues, isEmpty);
    });

    test('every catalogue id renders clean with its default props', () {
      for (final id in v4HostWidgetIds) {
        final report = _validate(_host(id));

        expect(
          report.issues,
          isEmpty,
          reason: '$id → ${report.issues.join('\n')}',
        );
      }
    });

    test('a widget node without ui.hostWidgets is an error', () {
      final report = _validate(_host('queue.list'), capabilities: []);

      expect(_errors(report), contains(_slotNode));
    });

    test('host widgets are not granted by default', () {
      expect(v4DefaultCapabilities, isNot(contains('ui.hostWidgets')));
    });
  });

  group('unknown ids', () {
    test('warn instead of failing, so the theme still loads', () {
      final report = _validate(_host('library.podcasts'));

      expect(_warnings(report), contains('$_slotNode.id'));
      expect(_errors(report), isEmpty);
    });

    test('a missing id is the same survivable case as an unknown one', () {
      final report = _validate({
        'type': 'hostWidget',
        'props': <String, dynamic>{},
      });

      expect(_warnings(report), contains('$_slotNode.id'));
      expect(_errors(report), isEmpty);
    });

    test('an unknown id does not also report its props', () {
      final report = _validate(_host('library.podcasts', {'compact': true}));

      expect(_warnings(report), hasLength(1));
      expect(_errors(report), isEmpty);
    });

    test('id casing is not a match', () {
      expect(
        _warnings(_validate(_host('Library.Playlists'))),
        contains('$_slotNode.id'),
      );
    });
  });

  group('unknown props', () {
    test('are errors, because the host would ignore them silently', () {
      expect(
        _errors(_validate(_host('library.playlists', {'compactted': true}))),
        contains('$_slotNode.props.compactted'),
      );
    });

    test('a prop borrowed from another widget is an error', () {
      expect(
        _errors(_validate(_host('audio.bass', {'bands': 4}))),
        contains('$_slotNode.props.bands'),
      );
    });

    test('a prop-free widget rejects anything', () {
      for (final id in [
        'audio.crossfade',
        'audio.sleepTimer',
        'theme.settings',
      ]) {
        final report = _validate(_host(id, {'compact': true}));

        expect(
          _errors(report),
          contains('$_slotNode.props.compact'),
          reason: id,
        );
      }
    });
  });

  group('prop types', () {
    test('booleans must be booleans', () {
      for (final value in ['true', 1, 0]) {
        final report = _validate(
          _host('library.playlists', {'compact': value}),
        );

        expect(
          _errors(report),
          contains('$_slotNode.props.compact'),
          reason: '$value',
        );
      }

      expect(
        _validate(_host('library.playlists', {'compact': false})).issues,
        isEmpty,
      );
    });

    test('counts must be whole numbers inside the host clamp', () {
      for (final limit in [0, 201, 12.5, '50', double.infinity]) {
        final report = _validate(
          _host('library.playlists', {'limit': limit}),
        );

        expect(
          _errors(report),
          contains('$_slotNode.props.limit'),
          reason: '$limit',
        );
      }

      expect(
        _validate(_host('library.playlists', {'limit': 200})).issues,
        isEmpty,
      );
    });

    test('bands share the host equalizer range', () {
      expect(
        _errors(_validate(_host('audio.equalizer', {'bands': _bandCount}))),
        isEmpty,
      );
      expect(
        _errors(_validate(_host('audio.equalizer', {'bands': 0}))),
        contains('$_slotNode.props.bands'),
      );
      expect(
        _errors(_validate(_host('audio.equalizer', {'bands': _bandCount + 1}))),
        contains('$_slotNode.props.bands'),
      );
    });

    test('enums are closed vocabularies', () {
      for (final bad in ['favourites', 'sideways', 'ALL']) {
        final report = _validate(
          _host('library.playlists', {'filter': bad, 'direction': bad}),
        );

        expect(
          _errors(report),
          contains('$_slotNode.props.filter'),
          reason: bad,
        );
        expect(
          _errors(report),
          contains('$_slotNode.props.direction'),
          reason: bad,
        );
      }

      expect(
        _validate(
          _host(
            'library.playlists',
            {'filter': 'recent', 'direction': 'horizontal'},
          ),
        ).issues,
        isEmpty,
      );
    });

    test('strings are capped', () {
      expect(
        _validate(_host('search.field', {'placeholder': 'a' * 80})).issues,
        isEmpty,
      );
      expect(
        _errors(_validate(_host('search.field', {'placeholder': 'a' * 81}))),
        contains('$_slotNode.props.placeholder'),
      );
    });

    test('a scope must be a binding key the host can publish', () {
      for (final bad in ['album name', 'scope!', 'a' * 33, '']) {
        final report = _validate(_host('search.field', {'scope': bad}));

        expect(
          _errors(report),
          contains('$_slotNode.props.scope'),
          reason: bad,
        );
      }

      expect(
        _validate(_host('search.field', {'scope': 'sidebar-filter'})).issues,
        isEmpty,
      );
    });

    // The collection row knobs a `library.*` widget takes. They are registered
    // in _checkedProps, which only asks that each one be *said* to hold
    // something; this is the saying.
    test('row toggles must be booleans', () {
      for (final prop in [
        'showPin',
        'showQueue',
        'showPlay',
        'coverPlays',
        'showTitle',
        'showSubtitle',
        'showDividers',
      ]) {
        for (final value in ['true', 1]) {
          expect(
            _errors(_validate(_host('library.playlists', {prop: value}))),
            contains('$_slotNode.props.$prop'),
            reason: '$prop: $value',
          );
        }
        expect(
          _validate(_host('library.playlists', {prop: false})).issues,
          isEmpty,
          reason: prop,
        );
      }
    });

    test('row geometry shares the host clamp', () {
      const clamps = {
        'coverSize': (min: 32, max: 96),
        'coverRadius': (min: 0, max: 24),
        'rowSpacing': (min: 0, max: 24),
      };
      for (final entry in clamps.entries) {
        final prop = entry.key;
        final range = entry.value;
        for (final good in [range.min, range.max]) {
          expect(
            _validate(_host('library.playlists', {prop: good})).issues,
            isEmpty,
            reason: '$prop: $good',
          );
        }
        for (final bad in [range.min - 1, range.max + 1, 12.5, '24']) {
          expect(
            _errors(_validate(_host('library.playlists', {prop: bad}))),
            contains('$_slotNode.props.$prop'),
            reason: '$prop: $bad',
          );
        }
      }
    });

    test('density is a closed vocabulary', () {
      for (final bad in ['cozy', 'COMPACT', 1]) {
        expect(
          _errors(_validate(_host('library.albums', {'density': bad}))),
          contains('$_slotNode.props.density'),
          reason: '$bad',
        );
      }
      expect(
        _validate(_host('library.albums', {'density': 'compact'})).issues,
        isEmpty,
      );
    });
  });

  group('pin targets', () {
    test('the sidebar target always exists', () {
      expect(
        _validate(_host('library.playlists', {'pinTarget': 'sidebar'})).issues,
        isEmpty,
      );
      expect(
        _validate(_host('library.pins', {'target': 'sidebar'})).issues,
        isEmpty,
      );
    });

    test('an undeclared target warns and does not fail', () {
      final report = _validate(
        _host('library.playlists', {'pinTarget': 'dock'}),
      );

      expect(_warnings(report), contains('$_slotNode.props.pinTarget'));
      expect(_errors(report), isEmpty);
    });

    test('a declared target is clean', () {
      final report = _validate(
        _host('library.playlists', {'pinTarget': 'dock'}),
        pinTargets: [
          {'id': 'sidebar', 'label': 'Sidebar'},
          {'id': 'dock', 'label': 'Dock'},
        ],
      );

      expect(_warnings(report), isEmpty);
    });

    test('library.pins checks its own target key', () {
      expect(
        _warnings(_validate(_host('library.pins', {'target': 'nope'}))),
        contains('$_slotNode.props.target'),
      );
    });
  });

  group('where a host widget may sit', () {
    test('a screen tree is walked too', () {
      final report = validateThemePayload({
        'specVersion': 4,
        'light': _colors('#ffffff', '#121212'),
        'dark': _colors('#121212', '#ffffff'),
        'capabilities': ['ui.hostWidgets'],
        'ui': {
          'specVersion': 2,
          'screens': {
            'now-playing': {
              'children': [_host('library.podcasts')],
            },
          },
        },
      });

      expect(
        report.issues.where(
          (issue) => issue.path.startsWith('ui.screens.now-playing'),
        ),
        isNotEmpty,
      );
    });

    test('a nested child is reached', () {
      final report = _validate({
        'type': 'box',
        'children': [_host('library.playlists', {'limit': 5000})],
      });

      expect(
        _errors(report),
        contains('$_slotNode.children[0].props.limit'),
      );
    });
  });
}

/// Every prop the catalogue exposes, asserted against the type tables so adding
/// a prop without saying what it holds fails here rather than shipping as an
/// untypechecked string.
const _checkedProps = <String>{
  'compact',
  'showSearch',
  'showCreate',
  'showProgress',
  'showVolume',
  'limit',
  'bands',
  'filter',
  'direction',
  'placeholder',
  'scope',
  'pinTarget',
  'target',
  'showPin',
  'showQueue',
  'showPlay',
  'coverPlays',
  'showTitle',
  'showSubtitle',
  'showDividers',
  'density',
  'coverSize',
  'coverRadius',
  'rowSpacing',
};
