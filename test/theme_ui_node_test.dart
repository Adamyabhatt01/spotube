import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/track_tile/track_context_menu.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_items.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

SpotubeFullTrackObject _track(String id, String name, String artist) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-$artist',
        name: artist,
        externalUri: 'https://example.test/artist/$artist',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-$id',
      name: 'Album $name',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000002',
    explicit: false,
  );
}

ThemeDefinition _theme({
  Map<String, dynamic> typography = const {},
  Map<String, dynamic> icons = const {},
  Map<String, dynamic> components = const {},
}) {
  return ThemeDefinition(
    specVersion: 3,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
    typography: typography,
    icons: icons,
    components: components,
  );
}

ThemeUiRuntime _runtime({
  Map<String, dynamic> bindings = const {},
  Map<String, ThemeUiTemplate> templates = const {},
  ThemeDefinition? theme,
  ThemeUiActionCallback? onAction,
  int specVersion = 3,
}) {
  return ThemeUiRuntime(
    theme: theme ?? _theme(),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: templates,
    specVersion: specVersion,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    home: Scaffold(
      child: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  group('bindings', () {
    test('duration and volume read as UI text, raw values stay raw', () {
      const bindings = ThemeUiBindings({
        'player.position': Duration(seconds: 83),
        'player.volume': 0.72,
        'player.loop': 'single',
        'player.playing': true,
      });

      expect(bindings.display('player.position'), '1:23');
      expect(bindings.display('player.volume'), '72%');
      expect(bindings.display('player.loop'), 'ONE');
      expect(bindings.display('player.playing'), 'ON');
      expect(bindings.raw('player.loop'), 'single');
    });

    test('conditional comparisons accept the values themes actually write', () {
      const bindings = ThemeUiBindings({
        'player.playing': true,
        'player.loop': 'loop',
        'player.volume': 0.72,
      });

      expect(bindings.matches('player.playing', true), isTrue);
      expect(bindings.matches('player.playing', 'true'), isTrue);
      expect(bindings.matches('player.loop', 'loop'), isTrue);
      expect(bindings.matches('player.loop', 'single'), isFalse);
      expect(bindings.matches('player.volume', 0.72), isTrue);
    });
  });

  group('item bindings', () {
    test('a track flattens its fields and marks the active row', () {
      final values = themeItemBindings(
        _track('t2', 'Second', 'Grace'),
        index: 2,
        activeTrackId: 't2',
      );

      expect(values['item.title'], 'Second');
      expect(values['item.name'], 'Second');
      expect(values['item.artist'], 'Grace');
      expect(values['item.album'], 'Album Second');
      expect(values['item.number'], 3);
      expect(values['item.kind'], 'track');
      expect(values['item.playing'], isTrue);
    });

    test('a map entry publishes its keys under item.*', () {
      final values = themeItemBindings({'title': 'Raw', 'count': 4});

      expect(values['item.title'], 'Raw');
      expect(values['item.count'], 4);
      expect(values['item.kind'], isNull);
    });

    test('an album reports a total only when the object carries one', () {
      final artist = SpotubeSimpleArtistObject(
        id: 'artist',
        name: 'Artist',
        externalUri: 'https://example.test/artist',
      );
      final simple = SpotubeSimpleAlbumObject(
        id: 'album',
        name: 'Album',
        externalUri: 'https://example.test/album',
        artists: [artist],
        albumType: SpotubeAlbumType.album,
      );

      expect(
        themeItemBindings(simple).containsKey('item.trackCount'),
        isFalse,
        reason: 'a saved-album row has no total; a 0 read as an empty album',
      );
      expect(
        themeItemBindings(
          SpotubeFullAlbumObject(
            id: 'album',
            name: 'Album',
            artists: [artist],
            releaseDate: '2024-01-01',
            externalUri: 'https://example.test/album',
            totalTracks: 11,
            albumType: SpotubeAlbumType.album,
          ),
        )['item.trackCount'],
        11,
      );
    });
  });

  group('the node frost', () {
    Widget frost(Map<String, dynamic> node, {required bool frozen}) {
      return ProviderScope(
        overrides: [
          chromeBlurFrozen.overrideWith((ref) => frozen),
        ],
        child: _app(
          ThemeUiNodeView(node: node, runtime: _runtime()),
        ),
      );
    }

    const frostedBox = <String, dynamic>{
      'type': 'box',
      'radius': 16,
      'blur': 12,
      'blurTint': '#0f172a',
      'children': [
        {'type': 'text', 'text': 'frosted'},
      ],
    };

    testWidgets('a blurred box blurs what is behind it, inside its radius',
        (tester) async {
      await tester.pumpWidget(frost(frostedBox, frozen: false));

      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(
        filter.filter,
        ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        reason: 'the theme writes sigma, the host paints it',
      );
      final scaling = Theme.of(tester.element(find.text('frosted'))).scaling;
      expect(
        tester
            .widgetList<ClipRRect>(
              find.ancestor(
                of: find.byType(BackdropFilter),
                matching: find.byType(ClipRRect),
              ),
            )
            .map((clip) => clip.borderRadius),
        contains(BorderRadius.circular(16 * scaling)),
        reason: 'the frost is clipped to the box it sits under',
      );
      expect(
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .map((box) => box.color)
            .where((color) => color.a > 0),
        isNotEmpty,
        reason: 'glass is tinted, not merely transparent',
      );
      expect(find.text('frosted'), findsOneWidget);
    });

    testWidgets('a scroll takes the blur off and keeps the tint',
        (tester) async {
      await tester.pumpWidget(frost(frostedBox, frozen: true));

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'a filter mounted at sigma zero still runs a backdrop pass',
      );
      expect(
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .map((box) => box.color)
            .where((color) => color.a > 0),
        isNotEmpty,
        reason: 'the panel does not lose its frost mid-scroll',
      );
      expect(find.text('frosted'), findsOneWidget);
    });

    testWidgets('a card frosts the same way, and zero costs nothing',
        (tester) async {
      await tester.pumpWidget(frost(
        const {
          'type': 'card',
          'radius': 8,
          'blur': 20,
        },
        frozen: false,
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(frost(
        const {
          'type': 'card',
          'radius': 8,
          'blur': 0,
        },
        frozen: false,
      ));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('sigma past the ceiling lands on it', (tester) async {
      await tester.pumpWidget(frost(
        const {'type': 'box', 'blur': 5000},
        frozen: false,
      ));

      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
        ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
      );
    });
  });

  group('node vocabulary', () {
    testWidgets(
        'an expand stack in a scroll view does not demand infinite height',
        (tester) async {
      final runtime = _runtime(bindings: {'player.artwork': ''});
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'stack',
          'fit': 'expand',
          'align': 'center',
          'children': [
            {
              'type': 'image',
              'src': 'player.artwork',
              'width': 80,
              'height': 80,
              'shape': 'circle',
            },
            {'type': 'text', 'text': 'over the record'},
          ],
        },
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('over the record'), findsOneWidget);
    });

    testWidgets('an animated node keeps the subtree it wraps', (tester) async {
      final runtime = _runtime(bindings: {'player.playing': false});
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'animate',
          'kind': 'rotate',
          'bind': 'player.playing',
          'children': [
            {'type': 'text', 'text': 'spinning record'},
          ],
        },
      )));

      expect(find.text('spinning record'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bound text and roles render', (tester) async {
      final runtime = _runtime(bindings: {
        'player.title': 'Nightfall',
        'player.artist': 'Ada',
      });
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'column',
          'gap': 4,
          'children': [
            {'type': 'text', 'bind': 'player.title', 'size': 'lg'},
            {
              'type': 'text',
              'bind': 'player.artist',
              'color': '@mutedForeground',
            },
          ],
        },
      )));

      expect(find.text('Nightfall'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a conditional picks the branch that matches the binding',
        (tester) async {
      final runtime = _runtime(bindings: {'player.loop': 'single'});
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'conditional',
          'bind': 'player.loop',
          'equals': 'loop',
          'children': [
            {'type': 'text', 'text': 'looping'},
            {'type': 'text', 'text': 'one track'},
          ],
        },
      )));

      expect(find.text('one track'), findsOneWidget);
      expect(find.text('looping'), findsNothing);
    });

    testWidgets('a template expands and substitutes its arguments',
        (tester) async {
      final runtime = _runtime(
        bindings: {'player.artist': 'Ada'},
        templates: {
          'byline': const ThemeUiTemplate(
            params: ['name'],
            children: [
              {'type': 'text', 'text': 'by {{name}}'},
              {'type': 'text', 'bind': 'player.artist'},
            ],
          ),
        },
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'template',
          'name': 'byline',
          'args': {'name': 'the artist'},
        },
      )));

      expect(find.text('by the artist'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('a button fires every action it carries', (tester) async {
      final fired = <ThemeUiAction>[];
      final runtime = _runtime(
        onAction: fired.add,
        bindings: {'player.playing': false},
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'button',
          'label': 'play',
          'icon': 'play',
          'action': {'type': 'playPause'},
          'actions': [
            {'type': 'playPause'},
            {
              'type': 'toast',
              'args': {'message': 'hello'}
            },
          ],
        },
      )));

      await tester.tap(find.text('play'));
      await tester.pump();

      expect(fired.map((action) => action.type), ['playPause', 'toast']);
      expect(fired.last.args['message'], 'hello');
    });

    testWidgets('disabledWhen stops the action', (tester) async {
      final fired = <ThemeUiAction>[];
      final runtime = _runtime(
        onAction: fired.add,
        bindings: {'player.playing': true},
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'button',
          'label': 'next',
          'action': {'type': 'next'},
          'disabledWhen': 'player.playing',
        },
      )));

      await tester.tap(find.text('next'), warnIfMissed: false);
      await tester.pump();

      expect(fired, isEmpty);
    });

    testWidgets('a list repeats its template over a bound collection',
        (tester) async {
      final runtime = _runtime(bindings: {
        'collection.tracks': [
          _track('t1', 'First', 'Ada'),
          _track('t2', 'Second', 'Grace'),
        ],
      });
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.tracks',
          'gap': 4,
          'children': [
            {
              'type': 'row',
              'gap': 8,
              'children': [
                {'type': 'text', 'bind': 'item.number'},
                {'type': 'text', 'bind': 'item.title'},
                {'type': 'text', 'bind': 'item.artist'},
                {
                  'type': 'image',
                  'src': 'item.artwork',
                  'width': 32,
                  'height': 32
                },
              ],
            },
          ],
        },
      )));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a host item menu wraps a track row in the host menu',
        (tester) async {
      // A theme that draws its own track row still gets the host's right-click
      // menu: the same verbs, the same user configuration, the same row.
      final runtime = _runtime(
        specVersion: 4,
        bindings: {
          'collection.tracks': [_track('t1', 'First', 'Ada')],
        },
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.tracks',
          'children': [
            {
              'type': 'contextMenu',
              'hostItem': true,
              'children': [
                {'type': 'text', 'bind': 'item.title'},
              ],
            },
          ],
        },
      )));
      await tester.pump();

      expect(find.byType(TrackContextMenu), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a host item menu leaves a row that is not a track alone',
        (tester) async {
      // Only the host's own item surfaces have a menu to lend. Anything else
      // keeps the row exactly as the theme drew it.
      final runtime = _runtime(
        specVersion: 4,
        bindings: {
          'collection.tracks': [
            {'title': 'Not a track'},
          ],
        },
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.tracks',
          'children': [
            {
              'type': 'contextMenu',
              'hostItem': true,
              'children': [
                {'type': 'text', 'bind': 'item.title'},
              ],
            },
          ],
        },
      )));
      await tester.pump();

      expect(find.byType(TrackContextMenu), findsNothing);
      expect(find.text('Not a track'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a list caps at its limit', (tester) async {
      final runtime = _runtime(bindings: {
        'collection.tracks': [
          _track('t1', 'First', 'Ada'),
          _track('t2', 'Second', 'Grace'),
        ],
      });
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.tracks',
          'limit': 1,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      )));
      await tester.pump();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsNothing);
    });

    testWidgets('a horizontal list is a sideways shelf', (tester) async {
      final runtime = _runtime(bindings: {
        'home.recent': [
          _track('t1', 'First', 'Ada'),
          _track('t2', 'Second', 'Grace'),
        ],
      });
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'home.recent',
          'direction': 'horizontal',
          'gap': 8,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      )));
      await tester.pump();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
      // Side by side, not stacked: the second card starts to the right.
      final first = tester.getTopLeft(find.text('First'));
      final second = tester.getTopLeft(find.text('Second'));
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx));
    });

    testWidgets('a vertical list wraps into equal-width columns',
        (tester) async {
      final runtime = _runtime(bindings: {
        'home.recent': [
          _track('t1', 'First', 'Ada'),
          _track('t2', 'Second', 'Grace'),
          _track('t3', 'Third', 'Lin'),
          _track('t4', 'Fourth', 'Alan'),
        ],
      });
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'home.recent',
          'columns': 2,
          'gap': 8,
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      )));
      await tester.pump();

      final first = tester.getTopLeft(find.text('First'));
      final second = tester.getTopLeft(find.text('Second'));
      final third = tester.getTopLeft(find.text('Third'));
      // Two cells per row, then a new run.
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy));
      expect(third.dx, first.dx);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a childless card is a sized shape', (tester) async {
      final runtime = _runtime();
      await tester.pumpWidget(_app(Align(
        alignment: Alignment.topLeft,
        child: ThemeUiNodeView(
          runtime: runtime,
          node: const {
            'type': 'card',
            'width': 36,
            'height': 36,
            'radius': 999,
            'padding': 0,
          },
        ),
      )));
      await tester.pump();

      final shape = find.descendant(
        of: find.byType(ThemeUiNodeView),
        matching: find.byType(ClipRRect),
      );
      expect(shape, findsOneWidget);
      final scaling = Theme.of(tester.element(shape)).scaling;
      expect(tester.getSize(shape), Size(36 * scaling, 36 * scaling));
    });

    testWidgets('a list renders nothing for a missing binding', (tester) async {
      final runtime = _runtime();
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.missing',
          'children': [
            {'type': 'text', 'bind': 'item.title'},
          ],
        },
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('First'), findsNothing);
    });

    testWidgets('an item action carries the entry, index and list',
        (tester) async {
      final fired = <ThemeUiAction>[];
      final tracks = [
        _track('t1', 'First', 'Ada'),
        _track('t2', 'Second', 'Grace'),
      ];
      final runtime = _runtime(
        onAction: fired.add,
        bindings: {'collection.tracks': tracks},
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'collection.tracks',
          'children': [
            {
              'type': 'button',
              'label': 'Play',
              'action': {'type': 'playItem'},
            },
          ],
        },
      )));

      await tester.tap(find.text('Play').first);
      await tester.pump();

      expect(fired, hasLength(1));
      expect(fired.single.type, 'playItem');
      expect(fired.single.args['item'], same(tracks.first));
      expect(fired.single.args['index'], 0);
      expect(fired.single.args['items'], equals(tracks));
    });

    testWidgets('a nested list carries the inner entry, not the outer section',
        (tester) async {
      final fired = <ThemeUiAction>[];
      final first = _track('t1', 'First', 'Ada');
      final second = _track('t2', 'Second', 'Grace');
      final sections = [
        {
          'id': 's1',
          'items': [first, second]
        },
      ];
      final runtime = _runtime(
        onAction: fired.add,
        bindings: {'home.browse': sections},
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'list',
          'bind': 'home.browse',
          'children': [
            {
              'type': 'column',
              'children': [
                {
                  'type': 'button',
                  'label': 'Section',
                  'action': {'type': 'openItem'},
                },
                {
                  'type': 'list',
                  'bind': 'item.items',
                  'children': [
                    {
                      'type': 'button',
                      'label': 'Open',
                      'action': {'type': 'openItem'},
                    },
                  ],
                },
              ],
            },
          ],
        },
      )));

      await tester.tap(find.text('Section'));
      await tester.pump();
      await tester.tap(find.text('Open').last);
      await tester.pump();

      expect(fired, hasLength(2));
      // The outer row still acts on its own section.
      expect(fired.first.args['item'], same(sections.first));
      expect(fired.first.args['items'], equals(sections));
      // The inner row acts on the entry it draws, not the section above it.
      expect(fired.last.args['item'], same(second));
      expect(fired.last.args['index'], 1);
      expect(fired.last.args['items'], equals([first, second]));
    });

    testWidgets('theme icon overrides fall back safely when the file is absent',
        (tester) async {
      final runtime = _runtime(
        theme: _theme(
          icons: {
            'overrides': {
              'play': {'asset': 'asset://icons/play.png', 'size': 24},
            },
          },
        ),
      );
      await tester.pumpWidget(_app(ThemeUiNodeView(
        runtime: runtime,
        node: const {
          'type': 'button',
          'icon': 'play',
          'action': {'type': 'playPause'},
        },
      )));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
    });
  });

  testWidgets('the progress node turns a tap into a seek fraction',
      (tester) async {
    final fired = <ThemeUiAction>[];
    final runtime = _runtime(
      bindings: {
        'player.position': const Duration(seconds: 30),
        'player.duration': const Duration(seconds: 120),
      },
      onAction: fired.add,
    );

    await tester.pumpWidget(_app(
      SizedBox(
        width: 200,
        child: ThemeUiNodeView(
          runtime: runtime,
          node: const {
            'type': 'progress',
            'height': 8,
            'hitHeight': 24,
            'thumbSize': 12,
          },
        ),
      ),
    ));

    final progress = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector && widget.onHorizontalDragUpdate != null,
    );
    expect(progress, findsOneWidget);
    final rect = tester.getRect(progress);
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump();

    expect(fired, hasLength(1));
    expect(fired.single.type, 'seek');
    expect(fired.single.args['fraction'], closeTo(0.75, 0.02));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the progress node survives a scaffold footer intrinsic query',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final runtime = _runtime(
      bindings: {
        'player.position': const Duration(seconds: 30),
        'player.duration': const Duration(seconds: 120),
      },
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          floatingFooter: true,
          footers: [
            SurfaceCard(
              borderRadius: BorderRadius.zero,
              child: SizedBox(
                key: key,
                child: ThemeUiNodeView(
                  runtime: runtime,
                  node: const {
                    'type': 'progress',
                    'height': 8,
                    'hitHeight': 26,
                    'thumbSize': 12,
                  },
                ),
              ),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final box = tester.renderObject<RenderBox>(find.byKey(key));
    expect(
      () => box.getMaxIntrinsicHeight(double.infinity),
      returnsNormally,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('spacer and expanded keep their Flex parent data',
      (tester) async {
    final runtime = _runtime();

    await tester.pumpWidget(_app(
      Row(
        children: [
          ThemeUiNodeView(
            runtime: runtime,
            node: const {'type': 'spacer', 'flex': 1},
          ),
          ThemeUiNodeView(
            runtime: runtime,
            node: const {
              'type': 'expanded',
              'flex': 2,
              'children': [
                {
                  'type': 'switch',
                  'kit': 'material',
                  'label': 'Enabled',
                },
              ],
            },
          ),
        ],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(material.Switch), findsOneWidget);
  });

  testWidgets('conditional flex keeps its Flex parent data', (tester) async {
    final runtime = _runtime(
      bindings: const {'collection.kind': 'playlist'},
    );

    await tester.pumpWidget(_app(
      Row(
        children: [
          ThemeUiNodeView(
            runtime: runtime,
            node: const {
              'type': 'conditional',
              'bind': 'collection.kind',
              'equals': 'album',
              'invert': true,
              'children': [
                {
                  'type': 'expanded',
                  'flex': 3,
                  'children': [
                    {'type': 'text', 'text': 'Album'},
                  ],
                },
              ],
            },
          ),
        ],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Album'), findsOneWidget);
  });

  testWidgets('action and semantics wrappers stay inside expanded content',
      (tester) async {
    final fired = <ThemeUiAction>[];
    final runtime = _runtime(
      onAction: fired.add,
    );

    await tester.pumpWidget(_app(
      Row(
        children: [
          ThemeUiNodeView(
            runtime: runtime,
            node: const {
              'type': 'expanded',
              'action': {'type': 'playPause'},
              'children': [
                {'type': 'text', 'text': 'Tap me'},
              ],
            },
          ),
          ThemeUiNodeView(
            runtime: runtime,
            node: const {
              'type': 'expanded',
              'semantics': {'label': 'spoken content'},
              'children': [
                {'type': 'text', 'text': 'Spoken'},
              ],
            },
          ),
        ],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tap me'));
    expect(fired.map((action) => action.type), ['playPause']);
  });

  testWidgets(
      'the reference theme\'s player slot renders through the real model',
      (tester) async {
    final payload = jsonDecode(
      File('themes/conformance/spotify-shell-v4.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final theme = ThemeDefinition.fromJson(payload);
    final slot = theme.ui!.slots['player.leading']!;
    final runtime = ThemeUiRuntime(
      theme: theme,
      bindings: const ThemeUiBindings({
        'player.title': 'Nightfall',
        'player.artist': 'Ada',
        'player.artwork': 'assets/images/album-placeholder.png',
        'player.playing': false,
        'player.loop': 'loop',
        'player.volume': 0.72,
        'app.version': '4.6.0',
      }),
      assets: const ThemeUiAssets(),
      templates: theme.ui!.templates,
      specVersion: theme.ui!.specVersion,
      onAction: (_) {},
    );

    await tester.pumpWidget(_app(
      Column(
        children: slot.children
            .map((node) => ThemeUiNodeView(node: node, runtime: runtime))
            .toList(),
      ),
    ));
    await tester.pump();

    expect(find.text('Nightfall'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
