// Phase 5B: the shell descriptor's host half. These pump the real
// [ShellLayoutHost] with theme slots standing in for the host region widgets,
// so sizing, visibility and region bindings are exercised without standing up
// the audio player or the router.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/region_scope.dart';
import 'package:spotube/modules/root/shell_layout_host.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

import 'support/common_fakes.dart';

class _StubPlayer extends AudioPlayerNotifier {
  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
      );
}

ThemeDefinition _theme() => ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
    );

ThemeUiDocument _document(Map<String, String> slots) => ThemeUiDocument(
      slots: {
        for (final entry in slots.entries)
          entry.key: ThemeUiSlot(
            children: [
              {'type': 'text', 'text': entry.value},
            ],
          ),
      },
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required ThemeShellLayout shell,
  required ThemeUiDocument ui,
  Widget? content,
  bool settle = true,
  bool injectTitlebar = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => _theme()),
      themeUiProvider.overrideWith((ref) async => ui),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      userPreferencesProvider.overrideWith(
        () => StubPrefsNotifier(PreferencesTable.defaults()),
      ),
      audioPlayerProvider.overrideWith(_StubPlayer.new),
    ],
  );
  addTearDown(container.dispose);

  // Resolve the async theme providers before the first frame so the shell
  // sees its slots immediately; otherwise the fallback host player/navbar
  // mount for one frame and pull in the audio stack.
  await container.read(themeDefinitionProvider.future);
  await container.read(themeUiProvider.future);
  await container.read(themeUiAssetsProvider.future);
  await container.read(themeUiFontsProvider.future);

  await tester.binding.setSurfaceSize(const Size(1000, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        home: Scaffold(
          child: ShellLayoutHost(
            shell: shell,
            content: content ?? const Text('CONTENT'),
            injectTitlebar: injectTitlebar,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

Size _regionSize(WidgetTester tester, Finder inside) {
  final scope = find.ancestor(
    of: inside,
    matching: find.byType(RegionScope),
  );
  expect(scope, findsWidgets);
  return tester.getSize(scope.first);
}

void main() {
  testWidgets('row sizing: px, percent and flex share the parent',
      (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'row',
      'children': [
        {'region': 'custom', 'id': 'one', 'slot': 'bar.one', 'width': 200},
        {'region': 'content', 'flex': 1},
        {
          'region': 'custom',
          'id': 'two',
          'slot': 'bar.two',
          'width': '25%',
        },
      ],
    })!;

    await _pump(
      tester,
      shell: shell,
      ui: _document({'bar.one': 'ONE', 'bar.two': 'TWO'}),
    );

    expect(find.text('ONE'), findsOneWidget);
    expect(find.text('TWO'), findsOneWidget);
    expect(find.text('CONTENT'), findsOneWidget);
    expect(_regionSize(tester, find.text('ONE')).width, 200);
    expect(_regionSize(tester, find.text('TWO')).width, 250);
    expect(_regionSize(tester, find.text('CONTENT')).width, 550);
  });

  testWidgets('column sizing: player above content, navbar below',
      (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'column',
      'children': [
        {'region': 'player', 'slot': 'bar.player', 'height': 72},
        {'region': 'content', 'flex': 1},
        {
          'region': 'custom',
          'id': 'bar.nav',
          'slot': 'bar.nav',
          'height': 56,
        },
      ],
    })!;

    await _pump(
      tester,
      shell: shell,
      ui: _document({'bar.player': 'PLAYER', 'bar.nav': 'NAV'}),
    );

    expect(_regionSize(tester, find.text('PLAYER')).height, 72);
    expect(_regionSize(tester, find.text('NAV')).height, 56);
    expect(_regionSize(tester, find.text('CONTENT')).height, 572);

    final playerY = tester.getTopLeft(find.text('PLAYER')).dy;
    final contentY = tester.getTopLeft(find.text('CONTENT')).dy;
    final navY = tester.getTopLeft(find.text('NAV')).dy;
    expect(playerY, lessThan(contentY));
    expect(contentY, lessThan(navY));
  });

  testWidgets('hiddenWhen removes the region from layout', (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'column',
      'children': [
        {'region': 'content', 'flex': 1},
        {
          'region': 'custom',
          'id': 'queue',
          'slot': 'bar.queue',
          'height': 120,
          'hiddenWhen': 'queue.count == 0',
        },
      ],
    })!;

    await _pump(
      tester,
      shell: shell,
      ui: _document({'bar.queue': 'QUEUE'}),
    );

    expect(find.text('QUEUE'), findsNothing);
    expect(_regionSize(tester, find.text('CONTENT')).height, 700);
  });

  testWidgets('region bindings expose the rendered size', (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'row',
      'children': [
        {'region': 'custom', 'id': 'one', 'slot': 'bar.one', 'width': 200},
        {'region': 'content', 'flex': 1},
      ],
    })!;

    await _pump(
      tester,
      shell: shell,
      ui: _document({'bar.one': 'ONE'}),
      content: Builder(
        builder: (context) {
          final state = RegionScope.stateOf(context);
          return Text('WIDTH ${state?.size.width}');
        },
      ),
    );

    expect(find.text('WIDTH 800.0'), findsOneWidget);
  });

  testWidgets('a shell with no titlebar gets a desktop drag strip',
      (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'row',
      'children': [
        {'region': 'content', 'flex': 1},
      ],
    })!;

    await _pump(
      tester,
      shell: shell,
      ui: const ThemeUiDocument(),
      injectTitlebar: true,
    );

    expect(find.byType(DragToMoveArea), findsOneWidget);
  });

  testWidgets('collapsed regions take their collapsed size', (tester) async {
    final shell = ThemeShellLayout.parse({
      'type': 'row',
      'children': [
        {
          'region': 'custom',
          'id': 'one',
          'slot': 'bar.one',
          'width': 200,
          'collapsible': true,
          'collapsedSize': 24,
        },
        {'region': 'content', 'flex': 1},
      ],
    })!;

    final container = await _pump(
      tester,
      shell: shell,
      ui: _document({'bar.one': 'ONE'}),
    );

    expect(_regionSize(tester, find.text('ONE')).width, 200);

    final notifier = container.read(regionCollapseProvider.notifier);
    notifier.state = {'one': true};
    await tester.pumpAndSettle();

    expect(find.text('ONE'), findsOneWidget);
    expect(_regionSize(tester, find.text('ONE')).width, 24);
  });

  testWidgets('resizable regions lay out without an unbounded handle',
      (tester) async {
    // The resize handle is a Positioned strip whose infinite dimension must be
    // clamped by the region stack. Pinning only one cross end hands it an
    // unbounded axis and trips RenderBox's size.isFinite assertion, which the
    // Neon Maximalist shell hit live on both its sidebar and bottom deck.
    for (final axis in ['row', 'column']) {
      final shell = ThemeShellLayout.parse({
        'type': axis,
        'children': [
          {
            'region': 'custom',
            'id': 'edge',
            'slot': 'bar.edge',
            'width': 200,
            'height': 120,
            'resizable': true,
          },
          {'region': 'content', 'flex': 1},
        ],
      })!;

      await _pump(
        tester,
        shell: shell,
        ui: _document({'bar.edge': 'EDGE'}),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('EDGE'), findsOneWidget);
      final size = _regionSize(tester, find.text('EDGE'));
      expect(size.isFinite, isTrue);
    }
  });

  testWidgets('a scrollable content region keeps the router outlet bounded',
      (tester) async {
    // Content is the router outlet, and its root Overlay needs a finite size on
    // both axes. The host must hand it its flexed box as-is rather than wrap it
    // in a scroll view — which loosened one axis and blanked the whole window.
    final shell = ThemeShellLayout.parse({
      'type': 'column',
      'children': [
        {'region': 'content', 'flex': 1, 'overflow': 'scroll'},
      ],
    })!;

    await _pump(tester, shell: shell, ui: const ThemeUiDocument());

    expect(tester.takeException(), isNull);
    final size = _regionSize(tester, find.text('CONTENT'));
    expect(size.isFinite, isTrue);
    expect(size.width, 1000);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
