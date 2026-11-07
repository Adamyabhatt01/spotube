// Phase 2B: render points are the seam between a host surface and a theme.
//
// The host keeps positioning, focus, keyboard handling and dispatch; a template
// only owns pixels. These tests pin the closed catalogue, the fallback rules,
// the recursion guard, and the search surface's keyboard behaviour with a
// custom row, because those are the parts a screenshot cannot show.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_kit_resolver.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/modules/theme_ui/theme_ui_render_points.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime({
  Map<String, String> renderPoints = const {},
  Map<String, ThemeUiTemplate> templates = const {},
  Map<String, dynamic> bindings = const {},
  ThemeUiActionCallback? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: templates,
    renderPoints: renderPoints,
    specVersion: 4,
    onAction: onAction ?? (_) {},
  );
}

Widget _app(Widget child) {
  return ShadcnApp(
    // Pin the desktop scale so the host's logical pixels are predictable.
    scaling: const AdaptiveScaling(1),
    home: Scaffold(child: child),
  );
}

Widget _host(
  ThemeUiRuntime runtime,
  String renderPoint, {
  Widget? fallback,
  Map<String, Object?> bindings = const {},
  ThemeUiRenderPointResolution? resolution,
}) {
  return ThemeUiTemplateHost(
    runtime: runtime,
    renderPoint: renderPoint,
    resolution: resolution,
    bindings: bindings,
    fallback: fallback ?? const Text('fallback'),
  );
}

ThemeUiTemplate _template(List<Map<String, dynamic>> children) =>
    ThemeUiTemplate(children: children);

void main() {
  setUp(() {
    ThemeUiDiagnostics.enabled = true;
    ThemeUiDiagnostics.reset();
  });

  tearDown(() {
    ThemeUiDiagnostics.reset();
  });

  group('render point resolution', () {
    test('the catalogue is closed and names every published surface', () {
      expect(themeUiRenderPoints, hasLength(19));
      expect(
        themeUiRenderPoints,
        containsAll([
          'search.field',
          'search.suggestions',
          'search.suggestion.item',
          'contextMenu.item',
          'contextMenu.container',
          'library.playlist.item',
          'queue.item',
          'table.row',
          'player.trackDetails',
          'toast.item',
        ]),
      );
    });

    test('a mapped, well-formed template resolves', () {
      final templates = {
        'row': _template([
          {'type': 'text', 'text': 'row'},
        ]),
      };
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.suggestion.item': 'row'},
        templates: templates,
        renderPoint: 'search.suggestion.item',
      );

      expect(resolved.hasTemplate, isTrue);
      expect(resolved.templateName, 'row');
      expect(resolved.problem, isNull);
    });

    test('an unmapped point leaves the host default alone', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {},
        templates: const {},
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.templateName, isNull);
      expect(resolved.problem, isNull);
    });

    test('an id outside the catalogue is ignored, even with a template', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.magic': 'row'},
        templates: {
          'row': _template([
            {'type': 'text', 'text': 'row'},
          ]),
        },
        renderPoint: 'search.magic',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, isNull);
    });

    test('an empty template name counts as no mapping', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': '  '},
        templates: const {},
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, isNull);
    });

    test('a missing template is a problem the host reports', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'missing'},
        templates: const {},
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.templateName, 'missing');
      expect(resolved.problem, contains('missing'));
    });

    test('hostWidget is forbidden inside a render-point template', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'chrome'},
        templates: {
          'chrome': _template([
            {'type': 'hostWidget', 'id': 'search.field'},
          ]),
        },
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, contains('hostWidget'));
    });

    test('a template that refers to itself is rejected', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'loop'},
        templates: {
          'loop': _template([
            {'type': 'template', 'name': 'loop'},
          ]),
        },
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, contains('refers to itself'));
    });

    test('a mutual reference is rejected', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'a'},
        templates: {
          'a': _template([
            {'type': 'template', 'name': 'b'},
          ]),
          'b': _template([
            {'type': 'template', 'name': 'a'},
          ]),
        },
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, contains('refers to itself'));
    });

    test('eight nested templates resolve; nine exceed the limit', () {
      Map<String, ThemeUiTemplate> chain(int length) {
        return {
          for (var i = 0; i < length; i++)
            't$i': _template([
              if (i == length - 1)
                {'type': 'text', 'text': 'bottom'}
              else
                {'type': 'template', 'name': 't${i + 1}'},
            ]),
        };
      }

      final eight = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 't0'},
        templates: chain(8),
        renderPoint: 'search.field',
      );
      final nine = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 't0'},
        templates: chain(9),
        renderPoint: 'search.field',
      );

      expect(eight.hasTemplate, isTrue);
      expect(eight.problem, isNull);
      expect(nine.hasTemplate, isFalse);
      expect(nine.problem, contains('deeper than 8'));
    });

    test('the fallback reporter ignores clean resolutions and dedupes', () {
      reportThemeUiRenderPointFallback(
        resolveThemeUiRenderPoint(
          renderPoints: const {},
          templates: const {},
          renderPoint: 'search.field',
        ),
      );
      expect(ThemeUiDiagnostics.renderPointEntries, isEmpty);

      final broken = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'gone'},
        templates: const {},
        renderPoint: 'search.field',
      );
      reportThemeUiRenderPointFallback(broken);
      reportThemeUiRenderPointFallback(broken);

      expect(ThemeUiDiagnostics.renderPointEntries, hasLength(1));
      expect(
        ThemeUiDiagnostics.renderPointEntries.single.renderPoint,
        'search.field',
      );
      expect(ThemeUiDiagnostics.renderPointEntries.single.template, 'gone');
    });

    test('a template reference in the legacy props object is found', () {
      final resolved = resolveThemeUiRenderPoint(
        renderPoints: const {'search.field': 'outer'},
        templates: {
          'outer': _template([
            {
              'type': 'template',
              'props': {'name': 'missing'},
            },
          ]),
        },
        renderPoint: 'search.field',
      );

      expect(resolved.hasTemplate, isFalse);
      expect(resolved.problem, contains('missing'));
    });
  });

  group('ThemeUiTemplateHost', () {
    testWidgets('renders the template with its context over the app bindings',
        (tester) async {
      final runtime = _runtime(
        renderPoints: const {'search.suggestion.item': 'row'},
        templates: {
          'row': _template([
            {'type': 'text', 'bind': 'item.title'},
            {'type': 'text', 'bind': 'app.name'},
          ]),
        },
        bindings: {'app.name': 'Spotube'},
      );

      await tester.pumpWidget(_app(_host(
        runtime,
        'search.suggestion.item',
        bindings: {'item.title': 'Midnight Circuit'},
      )));

      expect(find.text('Midnight Circuit'), findsOneWidget);
      expect(find.text('Spotube'), findsOneWidget);
      expect(find.text('fallback'), findsNothing);
    });

    testWidgets('a missing template falls back and reports exactly once',
        (tester) async {
      final runtime = _runtime(
        renderPoints: const {'search.field': 'gone'},
      );

      await tester.pumpWidget(_app(_host(runtime, 'search.field')));
      expect(find.text('fallback'), findsOneWidget);
      expect(ThemeUiDiagnostics.renderPointEntries, hasLength(1));
      expect(
        ThemeUiDiagnostics.renderPointEntries.single.renderPoint,
        'search.field',
      );
      expect(ThemeUiDiagnostics.renderPointEntries.single.template, 'gone');

      // A rebuild is the common case (every keystroke, every hover) and must
      // not turn one broken mapping into a log flood.
      await tester.pump();
      expect(ThemeUiDiagnostics.renderPointEntries, hasLength(1));
    });

    testWidgets('a hostWidget template falls back instead of rendering it',
        (tester) async {
      final runtime = _runtime(
        renderPoints: const {'search.field': 'chrome'},
        templates: {
          'chrome': _template([
            {'type': 'hostWidget', 'id': 'search.field'},
          ]),
        },
      );

      await tester.pumpWidget(_app(_host(runtime, 'search.field')));

      expect(find.text('fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(ThemeUiDiagnostics.renderPointEntries, hasLength(1));
      expect(
        ThemeUiDiagnostics.renderPointEntries.single.reason,
        contains('hostWidget'),
      );
    });

    testWidgets('a zero-child template draws nothing without a fallback',
        (tester) async {
      final runtime = _runtime(
        renderPoints: const {'search.empty': 'empty'},
        templates: {'empty': _template(const [])},
      );

      await tester.pumpWidget(_app(_host(runtime, 'search.empty')));

      expect(find.text('fallback'), findsNothing);
      expect(ThemeUiDiagnostics.renderPointEntries, isEmpty);
    });

    testWidgets('an unregistered point ignores its mapping', (tester) async {
      final runtime = _runtime(
        renderPoints: const {'search.magic': 'row'},
        templates: {
          'row': _template([
            {'type': 'text', 'text': 'template'},
          ]),
        },
      );

      await tester.pumpWidget(_app(_host(runtime, 'search.magic')));

      expect(find.text('template'), findsNothing);
      expect(find.text('fallback'), findsOneWidget);
      expect(ThemeUiDiagnostics.renderPointEntries, isEmpty);
    });

    testWidgets('templates are visual only: actions do not fire on render',
        (tester) async {
      final fired = <ThemeUiAction>[];
      final runtime = _runtime(
        renderPoints: const {'search.empty': 'empty'},
        templates: {
          'empty': _template([
            {
              'type': 'text',
              'text': 'nothing yet',
              'action': {
                'type': 'seek',
                'args': {'position': 1}
              },
            },
          ]),
        },
        onAction: fired.add,
      );

      await tester.pumpWidget(_app(_host(runtime, 'search.empty')));
      await tester.pump();

      expect(find.text('nothing yet'), findsOneWidget);
      expect(fired, isEmpty);
    });

    testWidgets('a self-referencing template stops instead of recursing',
        (tester) async {
      final runtime = _runtime(
        templates: {
          'loop': _template([
            {'type': 'text', 'text': 'once'},
            {'type': 'template', 'name': 'loop'},
          ]),
        },
      );

      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: runtime,
          node: const {'type': 'template', 'name': 'loop'},
        ),
      ));

      expect(find.text('once'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('eight template expansions render; the ninth is cut',
        (tester) async {
      Map<String, ThemeUiTemplate> chain(int length) {
        return {
          for (var i = 0; i < length; i++)
            't$i': _template([
              if (i == length - 1)
                {'type': 'text', 'text': 'bottom'}
              else
                {'type': 'template', 'name': 't${i + 1}'},
            ]),
        };
      }

      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(templates: chain(8)),
          node: const {'type': 'template', 'name': 't0'},
        ),
      ));
      expect(find.text('bottom'), findsOneWidget);

      await tester.pumpWidget(_app(
        ThemeUiNodeView(
          runtime: _runtime(templates: chain(9)),
          node: const {'type': 'template', 'name': 't0'},
        ),
      ));
      await tester.pump();
      expect(find.text('bottom'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a precomputed resolution is used without re-walking',
        (tester) async {
      final templates = {
        'row': _template([
          {'type': 'text', 'text': 'row'},
        ]),
      };
      final runtime = _runtime(
        renderPoints: const {'search.field': 'row'},
        templates: templates,
      );
      final resolution = resolveThemeUiRenderPoint(
        renderPoints: runtime.renderPoints,
        templates: runtime.templates,
        renderPoint: 'search.field',
      );

      await tester.pumpWidget(_app(_host(
        runtime,
        'search.field',
        resolution: resolution,
      )));

      expect(find.text('row'), findsOneWidget);
      expect(find.text('fallback'), findsNothing);
    });
  });

  group('search render points', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'recentSearches': ['lofi', 'jazz'],
      });
      await KVStoreService.initialize();
    });

    Future<ProviderContainer> pumpBar(
      WidgetTester tester, {
      ThemeUiRuntime? runtime,
    }) async {
      final container = ProviderContainer(
        overrides: [
          metadataPluginSavedPlaylistsProvider
              .overrideWith(() => _EmptyPlaylists()),
          metadataPluginSavedAlbumsProvider.overrideWith(() => _EmptyAlbums()),
          metadataPluginSavedArtistsProvider
              .overrideWith(() => _EmptyArtists()),
          metadataPluginSavedTracksProvider.overrideWith(() => _EmptyTracks()),
        ],
      );
      addTearDown(container.dispose);

      runtime ??= _runtime(
        renderPoints: const {
          'search.field': 'fieldChrome',
          'search.suggestions': 'panelChrome',
          'search.suggestion.item': 'rowContent',
        },
        templates: {
          'fieldChrome': _template([
            {'type': 'text', 'text': 'field-chrome'},
          ]),
          'panelChrome': _template([
            {'type': 'text', 'text': 'panel-chrome'},
          ]),
          'rowContent': _template([
            {'type': 'text', 'text': 'custom-row'},
            {'type': 'text', 'bind': 'item.title'},
          ]),
        },
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: Scaffold(
              child: SingleChildScrollView(
                child: HomeSearchBar(runtime: runtime),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return container;
    }

    Finder findField() => find.byType(TextField);

    testWidgets('a custom row template replaces the row but not activation',
        (tester) async {
      final container = await pumpBar(tester);

      await tester.tap(findField());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Chrome templates are painted behind the host field/panel.
      expect(find.text('field-chrome'), findsOneWidget);
      expect(find.text('panel-chrome'), findsOneWidget);

      // Both recents are drawn by the template, with their host bindings.
      expect(find.text('custom-row'), findsNWidgets(2));
      expect(find.text('lofi'), findsOneWidget);
      expect(find.text('jazz'), findsOneWidget);

      // Arrow selection and Enter still go through the host. One ArrowDown
      // highlights the first recent; Enter activates that same row.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(container.read(searchTermStateProvider), 'lofi');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the field behind a chrome template still accepts text',
        (tester) async {
      await pumpBar(tester);

      await tester.tap(findField());
      await tester.pump();
      await tester.enterText(findField(), 'a');
      await tester.pump();

      // The template is a background layer; the real field stays on top and
      // keeps its controller wiring.
      expect(find.text('field-chrome'), findsOneWidget);
      expect(tester.widget<TextField>(findField()).controller?.text, 'a');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a broken field mapping reports while the shipped field stays',
        (tester) async {
      await pumpBar(
        tester,
        runtime: _runtime(renderPoints: const {'search.field': 'gone'}),
      );

      // Falling back is not an error state: the host keeps its own field.
      expect(find.byType(TextField), findsOneWidget);

      // But the author still learns the mapping was ignored.
      final entry = ThemeUiDiagnostics.renderPointEntries.single;
      expect(entry.renderPoint, 'search.field');
      expect(entry.template, 'gone');
      expect(entry.reason, contains('missing'));
    });
  });
}

class _EmptyPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _empty();

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyAlbums extends MetadataPluginSavedAlbumNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build() async => _empty();

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyArtists extends MetadataPluginSavedArtistNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      build() async => _empty();

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
          int offset, int limit) =>
      build();
}

class _EmptyTracks extends MetadataPluginSavedTracksNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build() async => _empty();

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
          int offset, int limit) =>
      build();
}

SpotubePaginationResponseObject<T> _empty<T>() {
  return SpotubePaginationResponseObject<T>(
    limit: 0,
    nextOffset: null,
    total: 0,
    hasMore: false,
    items: const [],
  );
}
