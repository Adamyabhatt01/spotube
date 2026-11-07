// Context-menu builder contracts: the host defaults table is the source of
// every row, the theme's `ui.menus` rows append and obey the same user
// configuration, capability/`when` filtering fails closed, and the pin row
// toggles in place for one target or becomes a checkable submenu for several.
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';

ContextMenuBuilder _builder({
  ContextMenuConfig config = ContextMenuConfig.defaults,
  List<ThemePinTarget> pinTargets = const [],
  Set<String> capabilities = const {},
  Map<String, List<Map<String, dynamic>>> themeMenus = const {},
  Set<String>? availableActions,
}) {
  return ContextMenuBuilder(
    // Keeps assertions readable and proves the builder never resolves l10n
    // itself: every label is a key plus its interpolation values.
    label: (key, [args]) {
      final target = args?['target'];
      return target == null ? key : '$key:$target';
    },
    config: config,
    pinTargets: pinTargets,
    capabilities: capabilities,
    themeMenus: themeMenus,
    availableActions: availableActions,
  );
}

ContextMenuItemContext _item(
  ContextMenuTarget target, [
  Map<String, Object?> flags = const {},
]) {
  return ContextMenuItemContext(target: target, flags: flags);
}

List<String> _ids(List<ContextMenuAction> actions) =>
    [for (final action in actions) action.id];

Map<String, dynamic> _themeRow({
  String id = 'theme.hello',
  String label = 'Hello',
  String type = 'toast',
  String? capability,
  String? when,
  bool destructive = false,
}) {
  return {
    'id': id,
    'label': label,
    'action': {
      'type': type,
      'args': {'message': 'hi'},
    },
    if (capability != null) 'capability': capability,
    if (when != null) 'when': when,
    if (destructive) 'destructive': true,
  };
}

void main() {
  group('host defaults', () {
    test('playlist rows follow the shared table and the fallback sidebar pin',
        () {
      final actions = _builder().build(
        _item(ContextMenuTarget.playlist, const {'owner': true}),
      );

      expect(_ids(actions), [
        'play',
        'open',
        'pin:sidebar',
        'addToQueue',
        'download',
        'rename',
        'delete',
        'copyLink',
      ]);
      expect(actions[2].label, 'pin_to:sidebar');
      expect(actions[2].icon, 'pin');
      expect(actions[2].submenu, ContextMenuSubmenu.none);
    });

    test('owner-only rows disappear without the owner flag', () {
      final actions = _builder().build(_item(ContextMenuTarget.playlist));

      expect(_ids(actions), isNot(contains('rename')));
      expect(_ids(actions), isNot(contains('delete')));
    });

    test('state swaps the play label and icon', () {
      final actions = _builder(
        availableActions: const {'play'},
      ).build(_item(ContextMenuTarget.playlist, const {'playing': true}));

      expect(actions, hasLength(1));
      expect(actions.single.label, 'pause');
      expect(actions.single.icon, 'pause');
    });

    test('the track like row follows the liked flag', () {
      final actions = _builder(
        availableActions: const {'like'},
      ).build(_item(ContextMenuTarget.track, const {'liked': true}));

      expect(actions, hasLength(1));
      expect(actions.single.label, 'remove_from_favorites');
      expect(actions.single.icon, 'likeFilled');
    });

    test('availableActions filters host rows but never theme rows', () {
      final actions = _builder(
        availableActions: const {'play', 'copyLink'},
        themeMenus: {
          'playlist': [_themeRow()],
        },
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions), ['play', 'copyLink', 'theme.hello']);
    });
  });

  group('user configuration', () {
    test('hidden rows disappear from the live menu', () {
      final actions = _builder(
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(
            hidden: {'delete', 'copyLink'},
          ),
        }),
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions), isNot(contains('delete')));
      expect(_ids(actions), isNot(contains('copyLink')));
    });

    test('includeHidden keeps rows for the settings preview', () {
      final actions = _builder(
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(hidden: {'delete'}),
        }),
      ).build(
        _item(ContextMenuTarget.playlist, const {'owner': true}),
        includeHidden: true,
      );

      expect(_ids(actions), contains('delete'));
    });

    test('order moves listed ids and ignores unknown ids', () {
      final actions = _builder(
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(
            order: ['not-a-row', 'delete', 'play'],
          ),
        }),
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions).take(3), ['delete', 'open', 'play']);
      expect(_ids(actions), isNot(contains('not-a-row')));
      expect(_ids(actions), hasLength(8));
    });

    test('a hidden single-target pin stays hidden by its resolved id', () {
      final actions = _builder(
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(hidden: {'pin:sidebar'}),
        }),
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions), isNot(contains('pin:sidebar')));
    });
  });

  group('theme menus', () {
    test('theme rows append after the host rows', () {
      final actions = _builder(
        themeMenus: {
          'playlist': [
            _themeRow(id: 'theme.alpha', label: 'Alpha'),
            _themeRow(id: 'theme.beta', label: 'Beta'),
          ],
        },
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions).sublist(_ids(actions).length - 2),
          ['theme.alpha', 'theme.beta']);
      expect(actions.last.label, 'Beta');
      expect(actions.last.isThemeAction, isTrue);
    });

    test('user order can interleave theme rows with host rows', () {
      final actions = _builder(
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(order: ['theme.beta']),
        }),
        themeMenus: {
          'playlist': [
            _themeRow(id: 'theme.alpha'),
            _themeRow(id: 'theme.beta'),
          ],
        },
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(_ids(actions).first, 'theme.beta');
      expect(_ids(actions).last, 'theme.alpha');
    });

    test('invalid theme rows fail closed', () {
      final actions = _builder(
        themeMenus: {
          'playlist': [
            _themeRow(id: 'hostish'),
            _themeRow(id: 'theme.empty', label: ''),
            _themeRow(id: 'theme.verb', type: 'notAVerb'),
            _themeRow(id: 'theme.ok'),
            _themeRow(id: 'theme.ok'),
          ],
        },
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(
        _ids(actions).where((id) => id.startsWith('theme.')),
        ['theme.ok'],
      );
    });

    test('a declared capability must be granted by the document', () {
      final row = _themeRow(
        id: 'theme.write',
        capability: 'library.write',
      );

      final denied = _builder(
        themeMenus: {
          'playlist': [row],
        },
      ).build(_item(ContextMenuTarget.playlist));
      expect(_ids(denied), isNot(contains('theme.write')));

      final granted = _builder(
        themeMenus: {
          'playlist': [row],
        },
        capabilities: const {'library.write'},
      ).build(_item(ContextMenuTarget.playlist));
      expect(_ids(granted), contains('theme.write'));

      final preview = _builder(
        themeMenus: {
          'playlist': [row],
        },
      ).build(_item(ContextMenuTarget.playlist), enforceCapabilities: false);
      expect(_ids(preview), contains('theme.write'));
    });

    test('when filters theme rows unless the settings preview disables it', () {
      final row = _themeRow(
        id: 'theme.owned',
        when: 'item.owner == true',
      );

      final hidden = _builder(
        themeMenus: {
          'playlist': [row],
        },
      ).build(_item(ContextMenuTarget.playlist));
      expect(_ids(hidden), isNot(contains('theme.owned')));

      final shown = _builder(
        themeMenus: {
          'playlist': [row],
        },
      ).build(_item(ContextMenuTarget.playlist, {'owner': true}));
      expect(_ids(shown), contains('theme.owned'));

      final preview = _builder(
        themeMenus: {
          'playlist': [row],
        },
      ).build(_item(ContextMenuTarget.playlist), evaluateWhen: false);
      expect(_ids(preview), contains('theme.owned'));
    });

    test('the menu is capped at 32 rows', () {
      final actions = _builder(
        themeMenus: {
          'playlist': [
            for (var i = 0; i < 40; i++)
              _themeRow(id: 'theme.row$i', label: 'Row $i'),
          ],
        },
      ).build(_item(ContextMenuTarget.playlist, const {'owner': true}));

      expect(actions, hasLength(ContextMenuBuilder.maxItems));
      expect(
          _ids(actions).where((id) => id.startsWith('theme.')), hasLength(24));
    });
  });

  group('pin submenu', () {
    test('one target toggles in place', () {
      final unpinned = _builder(
        availableActions: const {'pin'},
      ).build(_item(ContextMenuTarget.playlist));
      expect(_ids(unpinned), ['pin:sidebar']);
      expect(unpinned.single.label, 'pin_to:sidebar');
      expect(unpinned.single.icon, 'pin');

      final pinned = _builder(
        availableActions: const {'unpin'},
      ).build(_item(ContextMenuTarget.playlist, const {
        'pinned': true,
        'pinnedTargets': {'sidebar'},
      }));
      expect(_ids(pinned), ['pin:sidebar']);
      expect(pinned.single.label, 'unpin_from:sidebar');
      expect(pinned.single.icon, 'unpin');
    });

    test('several targets become a checked submenu', () {
      final actions = _builder(
        availableActions: const {'pin'},
        pinTargets: const [
          ThemePinTarget(id: 'sidebar', label: 'Sidebar'),
          ThemePinTarget(id: 'bar', label: 'Top bar'),
        ],
      ).build(_item(ContextMenuTarget.playlist, const {
        'pinned': true,
        'pinnedTargets': {'sidebar'},
      }));

      final pin = actions.single;
      expect(pin.id, 'pin');
      expect(pin.label, 'pin_to_ellipsis');
      expect(pin.submenu, ContextMenuSubmenu.pinTargets);
      expect(pin.children, hasLength(2));

      expect(pin.children[0].id, 'pin:sidebar');
      expect(pin.children[0].label, 'unpin_from:Sidebar');
      expect(pin.children[0].checked, isTrue);
      expect(pin.children[0].icon, 'unpin');

      expect(pin.children[1].id, 'pin:bar');
      expect(pin.children[1].label, 'pin_to:Top bar');
      expect(pin.children[1].checked, isFalse);
      expect(pin.children[1].icon, 'pin');
    });

    test('hiding all but one target turns the submenu back into a toggle', () {
      final actions = _builder(
        availableActions: const {'pin'},
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(hiddenPinTargets: {'bar'}),
        }),
        pinTargets: const [
          ThemePinTarget(id: 'sidebar', label: 'Sidebar'),
          ThemePinTarget(id: 'bar', label: 'Top bar'),
        ],
      ).build(_item(ContextMenuTarget.playlist));

      expect(_ids(actions), ['pin:sidebar']);
      expect(actions.single.submenu, ContextMenuSubmenu.none);
    });

    test('an empty effective target list removes the row', () {
      final actions = _builder(
        availableActions: const {'pin'},
        config: const ContextMenuConfig(targets: {
          'playlist': ContextMenuTargetConfig(hiddenPinTargets: {'sidebar'}),
        }),
      ).build(_item(ContextMenuTarget.playlist));

      expect(actions, isEmpty);
    });
  });

  group('when grammar', () {
    test('evaluates flags, comparisons and the target id', () {
      final item = _item(ContextMenuTarget.playlist, const {
        'owner': true,
        'count': 3,
        'name': 'Mix',
      });

      expect(evaluateContextMenuWhen('item.owner', item), isTrue);
      expect(evaluateContextMenuWhen('item.owner == true', item), isTrue);
      expect(evaluateContextMenuWhen('item.owner == false', item), isFalse);
      expect(evaluateContextMenuWhen('item.count == 3', item), isTrue);
      expect(evaluateContextMenuWhen("item.name == 'Mix'", item), isTrue);
      expect(evaluateContextMenuWhen('item.name == "Mix"', item), isTrue);
      expect(evaluateContextMenuWhen("item.type == 'playlist'", item), isTrue);
      expect(evaluateContextMenuWhen("item.type == 'track'", item), isFalse);
    });

    test('malformed expressions fail closed', () {
      final item = _item(ContextMenuTarget.playlist);
      expect(evaluateContextMenuWhen('item.owner &&', item), isFalse);
      expect(evaluateContextMenuWhen('owner', item), isFalse);
      expect(evaluateContextMenuWhen('item.name == nope', item), isFalse);
      expect(evaluateContextMenuWhen(null, item), isTrue);
      expect(evaluateContextMenuWhen('', item), isTrue);
    });
  });

  group('configuration model', () {
    test('round-trips every knob', () {
      const config = ContextMenuConfig(targets: {
        'playlist': ContextMenuTargetConfig(
          order: ['b', 'a'],
          hidden: {'x'},
          hiddenPinTargets: {'bar'},
          showIcons: false,
          confirmDestructive: false,
        ),
      });

      expect(ContextMenuConfig.fromJson(config.toJson()).toJson(),
          config.toJson());
    });

    test('malformed values degrade to defaults', () {
      final config = ContextMenuConfig.fromJson(const {
        'playlist': {
          'order': ['ok', 3, ''],
          'hidden': ['hidden', null],
          'showIcons': 'yes',
          'confirmDestructive': 0,
        },
        'not-a-target': {
          'hidden': ['nope'],
        },
      });

      final playlist = config.forTarget(ContextMenuTarget.playlist);
      expect(playlist.order, ['ok']);
      expect(playlist.hidden, {'hidden'});
      expect(playlist.showIcons, isTrue);
      expect(playlist.confirmDestructive, isTrue);
      expect(config.targets.keys, ['playlist']);
    });

    test('resetting a target drops it from the stored map', () {
      const config = ContextMenuConfig(targets: {
        'playlist': ContextMenuTargetConfig(hidden: {'delete'}),
      });

      final reset = config.resetTarget(ContextMenuTarget.playlist);
      expect(reset.targets, isEmpty);
      expect(reset.toJson(), isEmpty);
    });
  });
}
