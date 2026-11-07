import 'package:flutter_test/flutter_test.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';

Map<String, dynamic> _row(List<Map<String, dynamic>> children) => {
      'type': 'row',
      'children': children,
    };

void main() {
  group('ThemeShellLayout.parse', () {
    test('accepts a row with one content and sized regions', () {
      final shell = ThemeShellLayout.parse(_row([
        {'region': 'sidebar', 'width': 280, 'slot': 'sidebar.content'},
        {
          'type': 'column',
          'flex': 1,
          'children': [
            {'region': 'content', 'flex': 1},
            {'region': 'player', 'height': 88},
          ],
        },
      ]));

      expect(shell, isNotNull);
      expect(shell!.root.type, ThemeShellNodeType.row);
      expect(shell.root.leaves.length, 3);
      expect(
        shell.root.leaves.map((leaf) => leaf.region),
        containsAll([
          ThemeShellRegion.sidebar,
          ThemeShellRegion.content,
          ThemeShellRegion.player,
        ]),
      );
    });

    test('rejects a tree without exactly one content', () {
      expect(
        ThemeShellLayout.parse(_row([
          {'region': 'sidebar'},
          {'region': 'player'},
        ])),
        isNull,
      );
      expect(
        ThemeShellLayout.parse(_row([
          {'region': 'content'},
          {'region': 'content'},
        ])),
        isNull,
      );
    });

    test('rejects duplicate ids and duplicated host regions', () {
      expect(
        ThemeShellLayout.parse({
          'type': 'column',
          'children': [
            {'region': 'content', 'id': 'same'},
            {'region': 'custom', 'id': 'same', 'slot': 'bar.one'},
          ],
        }),
        isNull,
      );
      expect(
        ThemeShellLayout.parse(_row([
          {'region': 'sidebar'},
          {'region': 'sidebar'},
          {'region': 'content'},
        ])),
        isNull,
      );
    });

    test('rejects a custom region without slot or id', () {
      expect(
        ThemeShellLayout.parse(_row([
          {'region': 'content'},
          {'region': 'custom', 'slot': 'bar.one'},
        ])),
        isNull,
      );
      expect(
        ThemeShellLayout.parse(_row([
          {'region': 'content'},
          {'region': 'custom', 'id': 'bar.one'},
        ])),
        isNull,
      );
    });

    test('rejects trees deeper than the cap', () {
      Map<String, dynamic> nested = {'region': 'content'};
      for (var i = 0; i < 10; i++) {
        nested = {
          'type': 'column',
          'children': [nested],
        };
      }
      nested = {
        'type': 'row',
        'children': [
          nested,
          {'region': 'sidebar'},
        ],
      };
      expect(ThemeShellLayout.parse(nested), isNull);
    });

    test('parses sizes, clamps and defaults', () {
      final shell = ThemeShellLayout.parse(_row([
        {'region': 'content', 'flex': 1},
        {'region': 'sidebar', 'width': '30%'},
        {'region': 'aside', 'width': 5000},
      ]))!;

      final sidebar = shell.root.leaves
          .firstWhere((leaf) => leaf.region == ThemeShellRegion.sidebar);
      expect(sidebar.width!.percent, 30);
      final aside = shell.root.leaves
          .firstWhere((leaf) => leaf.region == ThemeShellRegion.aside);
      expect(aside.width!.pixels, 4000);
    });

    test('parses pin targets and drops malformed entries', () {
      final layout = ThemeLayout.fromJson({
        'pinTargets': [
          {'id': 'sidebar', 'label': 'Sidebar'},
          {'id': 'bar.bottom'},
          {'id': ''},
        ],
      });

      expect(layout.pinTargets.length, 2);
      expect(layout.pinTargets.last.label, 'bar.bottom');
    });

    test('round-trips through json', () {
      final shell = ThemeShellLayout.parse(_row([
        {'region': 'content', 'flex': 1},
        {
          'region': 'custom',
          'id': 'bar.queue',
          'slot': 'bar.queue',
          'height': 120,
          'hiddenWhen': 'queue.count == 0',
        },
      ]))!;

      final json = ThemeLayout(shell: shell).toJson();
      final decoded = ThemeLayout.fromJson(json);
      expect(decoded.shell, isNotNull);
      expect(decoded.shell!.root.leaves.length, 2);
    });
  });

  group('applyResponsiveLayout', () {
    test('swaps the shell tree for the matching breakpoint', () {
      final base = ThemeLayout(
        shell: ThemeShellLayout.parse(_row([
          {'region': 'sidebar'},
          {'region': 'content', 'flex': 1},
        ])),
        responsive: {
          'compact': {
            'shell': {
              'type': 'column',
              'children': [
                {'region': 'content', 'flex': 1},
                {'region': 'player', 'height': 72},
              ],
            },
          },
        },
      );

      final compact = applyResponsiveLayout(base, 700);
      expect(compact.shell!.root.type, ThemeShellNodeType.column);
      expect(
        compact.shell!.root.leaves.map((leaf) => leaf.region),
        containsAll([ThemeShellRegion.content, ThemeShellRegion.player]),
      );

      final expanded = applyResponsiveLayout(base, 1400);
      expect(expanded.shell!.root.type, ThemeShellNodeType.row);
    });

    test('keeps the base shell when a variant has none', () {
      final base = ThemeLayout(
        shell: ThemeShellLayout.parse(_row([
          {'region': 'content'},
        ])),
        responsive: {
          'compact': {'sidebarWidth': 200},
        },
      );
      expect(applyResponsiveLayout(base, 700).shell, same(base.shell));
    });
  });
}
