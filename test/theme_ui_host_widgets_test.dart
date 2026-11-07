// Phase 9: `hostWidget` is a theme's one escape hatch out of the node
// vocabulary, and the registry is what keeps it a hatch and not a door. These
// tests pin the four things the contract promises an author: an id is either
// mounted or silently absent (never an error screen), a prop is typed and
// clamped by the host rather than trusted, a widget needs a capability to appear
// at all, and a theme's settings live in its own namespace — write one, read it
// back after a restart, reset only your own.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/components/playbutton_view/collection_row_policy.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/theme_ui/host_widgets/theme_ui_host_widgets.dart';
import 'package:spotube/modules/theme_ui/host_widgets/theme_ui_settings_body.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

const _namespace = (author: 'adamya', name: 'nebula');

ThemeDefinition _theme() {
  return ThemeDefinition(
    specVersion: 4,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
  );
}

ThemeUiRuntime _runtime({
  Set<String> capabilities = const {'ui.hostWidgets'},
  Map<String, dynamic> bindings = const {},
  void Function(ThemeUiAction)? onAction,
}) {
  return ThemeUiRuntime(
    theme: _theme(),
    bindings: ThemeUiBindings(bindings),
    assets: const ThemeUiAssets(),
    templates: const {},
    renderPoints: const {},
    specVersion: 4,
    capabilities: capabilities,
    onAction: onAction ?? (_) {},
  );
}

SpotubeSimplePlaylistObject _playlist(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'spotify:playlist:$id',
      owner: SpotubeUserObject(id: 'owner', name: 'Owner', externalUri: ''),
    );

SpotubeSimplePlaylistObject _searchable(String id, String description) =>
    SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: description,
      externalUri: 'spotify:playlist:$id',
      owner: SpotubeUserObject(id: 'owner', name: 'Owner', externalUri: ''),
    );

Map<String, dynamic> _hostNode(String id,
    [Map<String, dynamic> props = const {}]) {
  return {'type': 'hostWidget', 'id': id, 'props': props};
}

/// A preferences notifier that records equalizer writes instead of touching
/// drift, because a host widget's job is to make exactly one write per gesture.
class _RecordingPrefs extends UserPreferencesNotifier {
  _RecordingPrefs(this.stub);

  PreferencesTableData stub;
  final singleGain = <double>[];
  final gainSets = <List<double>>[];

  @override
  PreferencesTableData build() => stub;

  @override
  void setEqualizerGain(int index, double gain) {
    singleGain.add(gain);
    final gains = List<double>.of(stub.equalizerGains);
    if (index >= 0 && index < gains.length) gains[index] = gain;
    stub = stub.copyWith(equalizerGains: gains);
    state = stub;
  }

  @override
  void setEqualizerGains(List<double> gains) {
    gainSets.add(gains);
    stub = stub.copyWith(equalizerGains: gains);
    state = stub;
  }
}

class _Playlists extends MetadataPluginSavedPlaylistsNotifier {
  _Playlists(this.items);

  final List<SpotubeSimplePlaylistObject> items;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => SpotubePaginationResponseObject(
            limit: items.length,
            nextOffset: null,
            total: items.length,
            hasMore: false,
            items: items,
          );

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
    int offset,
    int limit,
  ) =>
      build();
}

List<Override> _baseOverrides({
  ThemeUiDocument? settings,
  List<SpotubeSimplePlaylistObject> playlists = const [],
  ThemeSettingsNamespace? namespace = _namespace,
  _RecordingPrefs? prefs,
}) {
  return [
    themeDefinitionProvider.overrideWith((ref) async => _theme()),
    themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
    themeSettingsNamespaceProvider.overrideWithValue(namespace),
    _settingsDocumentOverride(settings),
    userPreferencesProvider.overrideWith(
      () => prefs ?? _RecordingPrefs(PreferencesTable.defaults()),
    ),
    mirroredPlaylistsProvider.overrideWith(
      (ref) => const Stream<List<SpotubeSimplePlaylistObject>>.empty(),
    ),
    metadataPluginSavedPlaylistsProvider.overrideWith(
      () => _Playlists(playlists),
    ),
    metadataPluginUserProvider.overrideWith((ref) async => null),
  ];
}

/// `pluginThemeSettingsProvider` lives behind the metadata plugin, so a test
/// hands it the document `showSettings()` would have returned.
Override _settingsDocumentOverride(ThemeUiDocument? document) {
  return pluginThemeSettingsProvider.overrideWith((ref) async => document);
}

Widget _app(Widget child) {
  return ShadcnApp(
    scaling: const AdaptiveScaling(1),
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Scaffold(
      child: SingleChildScrollView(child: child),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: _app(child)),
  );
  await tester.pump();
}

void main() {
  group('the catalogue', () {
    test('is closed, twelve widgets deep', () {
      expect(ThemeUiHostWidgets.ids, hasLength(12));
      expect(
          ThemeUiHostWidgets.allowedProps.keys.toSet(), ThemeUiHostWidgets.ids);
    });

    test('gates only capabilities the contract does not grant by default', () {
      // §4.10 hands out `library.read` and `player.control` without asking; a
      // gate on either would hide the widget for a theme that never mentioned
      // them. Everything else in the table is an opt-in capability.
      const defaults = {'library.read', 'player.control'};
      const known = {
        ...defaults,
        'library.write',
        'audio.effects',
        'ui.pages',
        'ui.hostWidgets',
        'settings.write',
        'clipboard.write',
      };

      expect(
        ThemeUiHostWidgets.requiredCapabilities.values,
        everyElement(isIn(known.difference(defaults))),
      );
      expect(
        ThemeUiHostWidgets.requiredCapabilities.keys,
        everyElement(isIn(ThemeUiHostWidgets.ids)),
      );
    });

    test('a name outside the table is unknown', () {
      expect(ThemeUiHostWidgets.isKnown('audio.bass'), isTrue);
      expect(ThemeUiHostWidgets.isKnown('library.podcasts'), isFalse);
      expect(ThemeUiHostWidgets.isKnown('Audio.Bass'), isFalse);
    });

    test('a prop the widget never reads is reported', () {
      expect(
        ThemeUiHostWidgets.unknownProps(
          'audio.bass',
          {'compact': true, 'bands': 4},
        ),
        ['bands'],
      );
      expect(
        ThemeUiHostWidgets.unknownProps('audio.crossfade', {'compact': true}),
        ['compact'],
      );
      expect(
        ThemeUiHostWidgets.unknownProps('queue.list', {'compact': true}),
        isEmpty,
      );
      // An unknown widget has no prop table at all.
      expect(ThemeUiHostWidgets.allowedProps['library.podcasts'], isNull);
    });

    test('prop names are the camelCase vocabulary the validator mirrors', () {
      for (final entry in ThemeUiHostWidgets.allowedProps.entries) {
        for (final prop in entry.value) {
          expect(
            prop,
            matches(r'^[a-z][A-Za-z0-9]*$'),
            reason: '${entry.key}.$prop',
          );
        }
      }
    });

    test('every library widget may hide the row title', () {
      // The collapsed sidebar rail draws one cover per playlist. The title is
      // the only part of a row that does not fit in the rail, so the theme
      // asks for it to be gone rather than the host guessing from the width.
      for (final id in [
        'library.playlists',
        'library.pins',
        'library.albums',
        'library.artists',
      ]) {
        expect(
          ThemeUiHostWidgets.allowedProps[id],
          contains('showTitle'),
          reason: id,
        );
        expect(
          ThemeUiHostWidgets.unknownProps(id, {'showTitle': false}),
          isEmpty,
          reason: id,
        );
      }
    });
  });

  group('row chrome', () {
    test('the title shows unless the theme asks for it to go', () {
      expect(collectionRowPolicyFromProps(const {}).showTitle, isTrue);
      expect(
        collectionRowPolicyFromProps(const {'showTitle': true}).showTitle,
        isTrue,
      );
      expect(
        collectionRowPolicyFromProps(const {'showTitle': false}).showTitle,
        isFalse,
      );
    });

    test('a prop that is not a boolean leaves the default alone', () {
      // The host clamps rather than trusts: a theme that writes `false` as a
      // string keeps the title.
      expect(
        collectionRowPolicyFromProps(const {'showTitle': 'false'}).showTitle,
        isTrue,
      );
    });

    test('the cover-only row keeps the rest of the policy intact', () {
      final policy = collectionRowPolicyFromProps(const {
        'showTitle': false,
        'coverPlays': true,
        'coverSize': 48,
      });

      expect(policy.showTitle, isFalse);
      expect(policy.coverPlays, isTrue);
      expect(policy.coverSize, 48);
      // The title is gone, but the other chrome defaults are unchanged.
      expect(policy.showPin, isTrue);
      expect(policy.showQueue, isTrue);
      expect(policy.showPlay, isTrue);
    });
  });

  group('prop clamping', () {
    test('a boolean is a boolean or the default', () {
      expect(ThemeUiHostWidgets.boolProp(true), isTrue);
      expect(ThemeUiHostWidgets.boolProp(false), isFalse);
      expect(ThemeUiHostWidgets.boolProp(null), isFalse);
      expect(ThemeUiHostWidgets.boolProp('true'), isFalse);
      expect(ThemeUiHostWidgets.boolProp(1), isFalse);
      expect(
        ThemeUiHostWidgets.boolProp(null, fallback: true),
        isTrue,
      );
    });

    test('a count is rounded into the range the host can honor', () {
      int clamp(Object? raw) => ThemeUiHostWidgets.intProp(
            raw,
            min: 1,
            max: 200,
            fallback: 50,
          );

      expect(clamp(10), 10);
      expect(clamp(7.4), 7);
      expect(clamp(7.6), 8);
      expect(clamp(0), 1);
      expect(clamp(-30), 1);
      expect(clamp(5000), 200);
      expect(clamp(null), 50);
      // A string never reaches the widget as a number, so the default stands.
      expect(clamp('10'), 50);
      expect(clamp(double.nan), 50);
      expect(clamp(double.infinity), 50);
    });

    test('an enum is a value from the vocabulary or the default', () {
      const values = {'all', 'pins', 'recent'};
      expect(
        ThemeUiHostWidgets.enumProp(
          'pins',
          values: values,
          fallback: 'all',
        ),
        'pins',
      );
      for (final bad in ['ALL', 'favourites', '', null, 3]) {
        expect(
          ThemeUiHostWidgets.enumProp(bad, values: values, fallback: 'all'),
          'all',
          reason: '$bad',
        );
      }
    });

    test('a string is trimmed, capped, and empty is nothing', () {
      expect(ThemeUiHostWidgets.stringProp('  lofi  '), 'lofi');
      expect(ThemeUiHostWidgets.stringProp(''), isNull);
      expect(ThemeUiHostWidgets.stringProp('   '), isNull);
      expect(ThemeUiHostWidgets.stringProp(null), isNull);
      expect(ThemeUiHostWidgets.stringProp(7), isNull);
      expect(
        ThemeUiHostWidgets.stringProp('a' * 100, maxLength: 80)!.length,
        80,
      );
    });
  });

  group('mounting a widget', () {
    Widget mounted(String id,
        {Set<String> capabilities = const {'ui.hostWidgets'},
        Map<String, dynamic> props = const {}}) {
      return ThemeUiHostWidgets.build(
        runtime: _runtime(capabilities: capabilities),
        id: id,
        props: props,
      );
    }

    test('every catalogue id mounts with ui.hostWidgets', () {
      for (final id in ThemeUiHostWidgets.ids) {
        final audio = id.startsWith('audio.');
        expect(
          mounted(
            id,
            capabilities: audio
                ? {'ui.hostWidgets', 'audio.effects'}
                : {'ui.hostWidgets'},
          ),
          isNot(isA<SizedBox>()),
          reason: id,
        );
      }
    });

    test('an unknown id mounts nothing', () {
      expect(mounted('library.podcasts'), isA<SizedBox>());
      expect(mounted(''), isA<SizedBox>());
      expect(mounted('Audio.Bass'), isA<SizedBox>());
    });

    test('a document without ui.hostWidgets mounts nothing at all', () {
      expect(
        mounted('library.playlists', capabilities: {'library.read'}),
        isA<SizedBox>(),
      );
      expect(mounted('audio.bass', capabilities: {}), isA<SizedBox>());
    });

    test('an audio widget needs audio.effects on top of the host gate', () {
      for (final id in [
        'audio.bass',
        'audio.equalizer',
        'audio.crossfade',
        'audio.sleepTimer',
      ]) {
        expect(
          mounted(id),
          isA<SizedBox>(),
          reason: '$id without audio.effects',
        );
        expect(
          mounted(id, capabilities: {'ui.hostWidgets', 'audio.effects'}),
          isNot(isA<SizedBox>()),
          reason: id,
        );
      }
    });

    test('library and player widgets need no extra capability', () {
      // §4.10 grants `library.read` and `player.control` to a theme that never
      // restates them, so gating on those would hide the widget in the common
      // case.
      for (final id in [
        'library.playlists',
        'library.pins',
        'library.albums',
        'library.artists',
        'player.controls',
        'queue.list',
        'search.field',
        'theme.settings',
      ]) {
        expect(mounted(id), isNot(isA<SizedBox>()), reason: id);
      }
    });

    test('a prop outside the table never reaches the widget', () {
      // The widget reads through the clamped helpers, so an ignored key cannot
      // change what mounts even when it survives the validator.
      expect(
        mounted('library.playlists', props: {'limit': 9000}),
        isNot(isA<SizedBox>()),
      );
    });
  });

  group('playlist selection', () {
    final all = [_playlist('a'), _playlist('b'), _playlist('c')];

    List<String> ids(List<SpotubeSimplePlaylistObject> items) =>
        [for (final item in items) item.id];

    List<String> select({
      String filter = 'all',
      String query = '',
      List<String> pinned = const [],
      int limit = 50,
      List<SpotubeSimplePlaylistObject>? from,
    }) {
      return ids(
        themeUiSelectPlaylists(
          all: from ?? all,
          pinnedIds: pinned,
          filter: filter,
          query: query,
          limit: limit,
        ),
      );
    }

    test('all keeps the plugin order', () {
      expect(select(), ['a', 'b', 'c']);
    });

    test('pins keeps the order the user pinned them in', () {
      expect(select(filter: 'pins', pinned: ['c', 'a']), ['c', 'a']);
    });

    test('pins drops a pinned id the library no longer has', () {
      expect(select(filter: 'pins', pinned: ['gone', 'b']), ['b']);
    });

    test('recent puts the pinned lists first and never twice', () {
      expect(select(filter: 'recent', pinned: ['b']), ['b', 'a', 'c']);
    });

    test('an unknown filter behaves like all', () {
      expect(select(filter: 'favourites'), ['a', 'b', 'c']);
    });

    test('the query matches name or description, case-insensitively', () {
      final mixed = [
        _searchable('a', 'Chill hits'),
        _searchable('b', 'workout'),
        _searchable('c', ''),
      ];

      expect(select(query: 'chill', from: mixed), ['a']);
      expect(select(query: 'PLAYLIST C', from: mixed), ['c']);
      expect(select(query: '  workout  ', from: mixed), ['b']);
      expect(select(query: '', from: mixed), ['a', 'b', 'c']);
      expect(select(query: '   ', from: mixed), ['a', 'b', 'c']);
    });

    test('the limit truncates after filtering', () {
      expect(select(limit: 2), ['a', 'b']);
      expect(select(filter: 'pins', pinned: ['c', 'b', 'a'], limit: 1), ['c']);
      expect(select(limit: 0), isEmpty);
    });
  });

  group('settings namespace', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await KVStoreService.initialize();
    });

    ProviderContainer newContainer() {
      final container = ProviderContainer(
        overrides: [
          themeSettingsNamespaceProvider.overrideWithValue(_namespace)
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a write lands under the theme prefix and reads back', () async {
      final container = newContainer();
      final notifier = container.read(themeUiSettingsProvider.notifier);

      notifier.set('showLyrics', true);
      notifier.set('greeting', 'hello');
      notifier.set('level', 3);
      await pumpEventQueue();

      final storage = await SharedPreferences.getInstance();
      expect(storage.getBool('theme.adamya.nebula.showLyrics'), isTrue);
      expect(storage.getString('theme.adamya.nebula.greeting'), 'hello');
      expect(storage.getInt('theme.adamya.nebula.level'), 3);
      expect(
        KVStoreService.themeSettings('adamya', 'nebula'),
        {'showLyrics': true, 'greeting': 'hello', 'level': 3},
      );
    });

    test('the state is the namespace, not the whole store', () async {
      await KVStoreService.setThemeSetting('adamya', 'nebula', 'flag', true);
      await KVStoreService.setThemeSetting('someone', 'else', 'flag', false);
      final storage = await SharedPreferences.getInstance();
      await storage.setBool('sidebarCollapsed', true);

      expect(
        KVStoreService.themeSettings('adamya', 'nebula'),
        {'flag': true},
      );
      expect(
        KVStoreService.themeSettings('someone', 'else'),
        {'flag': false},
      );
    });

    test('a value another version wrote is skipped, not fatal', () async {
      final storage = await SharedPreferences.getInstance();
      await storage.setStringList('theme.adamya.nebula.list', ['a']);
      await storage.setString('theme.adamya.nebula.ok', 'yes');

      expect(KVStoreService.themeSettings('adamya', 'nebula'), {'ok': 'yes'});
    });

    test('null removes the key', () async {
      final container = newContainer();
      final notifier = container.read(themeUiSettingsProvider.notifier);

      notifier.set('temp', 'value');
      await pumpEventQueue();
      notifier.set('temp', null);
      await pumpEventQueue();

      final storage = await SharedPreferences.getInstance();
      expect(storage.containsKey('theme.adamya.nebula.temp'), isFalse);
      expect(container.read(themeUiSettingsProvider), isEmpty);
    });

    test('a non-finite number is stored as zero', () async {
      final storage = await SharedPreferences.getInstance();

      await KVStoreService.setThemeSetting(
        'adamya',
        'nebula',
        'level',
        double.infinity,
      );

      expect(storage.getDouble('theme.adamya.nebula.level'), 0);
    });

    test('toggle flips a boolean and reads truthiness otherwise', () async {
      final container = newContainer();
      final notifier = container.read(themeUiSettingsProvider.notifier);

      notifier.set('flag', false);
      notifier.toggle('flag');
      expect(container.read(themeUiSettingsProvider)['flag'], isTrue);

      notifier.set('count', 0);
      notifier.toggle('count');
      expect(container.read(themeUiSettingsProvider)['count'], isTrue);

      notifier.set('name', '');
      notifier.toggle('name');
      expect(container.read(themeUiSettingsProvider)['name'], isTrue);

      // An unset key reads as false, so the first toggle turns it on.
      notifier.toggle('fresh');
      expect(container.read(themeUiSettingsProvider)['fresh'], isTrue);
      await pumpEventQueue();
    });

    test('reset clears this theme and only this theme', () async {
      final container = newContainer();
      final notifier = container.read(themeUiSettingsProvider.notifier);
      await KVStoreService.setThemeSetting(
        'other',
        'theme',
        'keep',
        'me',
      );

      notifier.set('flag', true);
      notifier.set('level', 2);
      await pumpEventQueue();
      expect(container.read(themeUiSettingsProvider), hasLength(2));

      notifier.reset();
      await pumpEventQueue();

      expect(container.read(themeUiSettingsProvider), isEmpty);
      expect(KVStoreService.themeSettings('adamya', 'nebula'), isEmpty);
      expect(KVStoreService.themeSettings('other', 'theme'), {'keep': 'me'});
    });

    test('without a selected theme nothing is persisted', () async {
      final container = ProviderContainer(
        overrides: [
          themeSettingsNamespaceProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      container.read(themeUiSettingsProvider.notifier).set('flag', true);
      await pumpEventQueue();

      final storage = await SharedPreferences.getInstance();
      expect(storage.getKeys(), isEmpty);
    });
  });

  group('hostWidget node', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await KVStoreService.initialize();
    });

    testWidgets('an unknown id leaves the slot empty without failing',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('library.podcasts'),
          runtime: _runtime(),
        ),
        overrides: _baseOverrides(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a missing capability hides the widget', (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('audio.bass'),
          runtime: _runtime(capabilities: {'ui.hostWidgets'}),
        ),
        overrides: _baseOverrides(),
      );

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('the id may sit in the props bag instead of the node',
        (tester) async {
      final recorded = <ThemeUiAction>[];
      await _pump(
        tester,
        ThemeUiNodeView(
          node: const {
            'type': 'hostWidget',
            'props': {'id': 'audio.equalizer', 'bands': 2},
          },
          runtime: _runtime(
            capabilities: {'ui.hostWidgets', 'audio.effects'},
            onAction: recorded.add,
          ),
        ),
        overrides: _baseOverrides(),
      );

      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('an out-of-range band count is clamped, not trusted',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('audio.equalizer', {'bands': 99}),
          runtime: _runtime(capabilities: {'ui.hostWidgets', 'audio.effects'}),
        ),
        overrides: _baseOverrides(),
      );

      expect(find.byType(Slider), findsNWidgets(kEqualizerBandCount));
    });

    testWidgets('bass writes once per gesture, on release', (tester) async {
      final recorder = _RecordingPrefs(PreferencesTable.defaults());
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('audio.bass', {'compact': true}),
          runtime: _runtime(capabilities: {'ui.hostWidgets', 'audio.effects'}),
        ),
        overrides: _baseOverrides(prefs: recorder),
      );

      // `compact` drops the label; the gain readout stays because it is the
      // value the drag is about.
      expect(find.text('Bass'), findsNothing);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged?.call(const SliderValue.single(4.0));
      await tester.pump();
      expect(recorder.singleGain, isEmpty);

      slider.onChangeEnd?.call(const SliderValue.single(4.0));
      await tester.pump();
      expect(recorder.singleGain, [4.0]);
    });

    testWidgets('an equalizer commit is one write for the whole band set',
        (tester) async {
      final recorder = _RecordingPrefs(PreferencesTable.defaults());
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('audio.equalizer', {'bands': 3}),
          runtime: _runtime(capabilities: {'ui.hostWidgets', 'audio.effects'}),
        ),
        overrides: _baseOverrides(prefs: recorder),
      );

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(3));
      // Band labels come from the host, so a theme cannot invent a frequency.
      expect(find.text('31'), findsOneWidget);
      expect(find.text('16k'), findsNothing);

      sliders[1].onChanged?.call(const SliderValue.single(2.0));
      await tester.pump();
      expect(recorder.gainSets, isEmpty);

      sliders[1].onChangeEnd?.call(const SliderValue.single(2.0));
      await tester.pump();
      expect(recorder.gainSets, hasLength(1));
      expect(recorder.gainSets.single[1], 2.0);
    });

    testWidgets('a search field without a scope is the host field',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('search.field', {'placeholder': 'Find anything'}),
          runtime: _runtime(),
        ),
        overrides: _baseOverrides(),
      );

      expect(find.byType(HomeSearchBar), findsOneWidget);
    });

    testWidgets('a scoped field publishes to its own query binding',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            ThemeUiNodeView(
              node: _hostNode('search.field', {'scope': 'albums'}),
              runtime: _runtime(),
            ),
          ),
        ),
      );
      await tester.pump();

      // The scoped field is the host's own text input, not HomeSearchBar: it
      // filters a theme list rather than navigating to search.
      expect(find.byType(HomeSearchBar), findsNothing);
      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      await tester.enterText(field, 'lof');
      await tester.pump(const Duration(milliseconds: 200));
      expect(
          container.read(themeUiQueryProvider).containsKey('albums'), isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(themeUiQueryProvider)['albums'], 'lof');

      // Submitting ends the edit deliberately, so it skips the remaining wait.
      await tester.enterText(field, 'jazz');
      tester.widget<TextField>(field).onSubmitted?.call('jazz');
      await tester.pump();
      expect(container.read(themeUiQueryProvider)['albums'], 'jazz');
    });

    testWidgets('a scope the host cannot bind falls back to the app field',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('search.field', {'scope': 'album list'}),
          runtime: _runtime(),
        ),
        overrides: _baseOverrides(),
      );

      expect(find.byType(HomeSearchBar), findsOneWidget);
    });

    testWidgets('a playlists widget with nothing in it stays quiet',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode(
            'library.playlists',
            {'showSearch': false, 'showCreate': false},
          ),
          runtime: _runtime(),
        ),
        overrides: _baseOverrides(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a playlists widget shows its own filter field',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(
          node: _hostNode('library.playlists', {'showCreate': false}),
          runtime: _runtime(),
        ),
        overrides: _baseOverrides(),
      );

      // `showCreate` is off, so the only chrome left is the filter field —
      // proof the prop reached the widget rather than being ignored.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('theme.settings mounts the theme document inline',
        (tester) async {
      const ui = ThemeUiDocument(
        specVersion: 4,
        capabilities: ['ui.hostWidgets', 'settings.write'],
        slots: {
          'settings.content': ThemeUiSlot(children: [
            {'type': 'text', 'bind': 'setting.flag'},
            {
              'type': 'button',
              'label': 'Toggle flag',
              'action': {
                'type': 'toggleSetting',
                'args': {'key': 'flag'}
              },
            },
          ]),
        },
      );

      await _pump(
        tester,
        ThemeUiNodeView(node: _hostNode('theme.settings'), runtime: _runtime()),
        overrides: [
          ..._baseOverrides(settings: ui),
          // The gate reads the live UI document, not the `showSettings()` one,
          // so a test that drives a settings verb has to answer for both.
          themeUiProvider.overrideWith((ref) async => ui),
        ],
      );

      // `showSettings()` is a plugin call: the first frame is still waiting.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('Toggle flag'), findsOneWidget);

      // Tapping goes through the real action dispatcher, lands in the
      // namespace, and comes back as a binding the same document reads.
      await tester.tap(find.text('Toggle flag'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('ON'), findsOneWidget);

      final storage = await SharedPreferences.getInstance();
      expect(storage.getBool('theme.adamya.nebula.flag'), isTrue);
    });

    testWidgets('a settings write the document did not declare is refused',
        (tester) async {
      // The build validator requires `settings.write` for these two verbs, but
      // an installed `.smplug` need not have been built by it, so the host
      // repeats the check. Without it the toggle is inert.
      const ui = ThemeUiDocument(
        specVersion: 4,
        capabilities: ['ui.hostWidgets'],
        slots: {
          'settings.content': ThemeUiSlot(children: [
            {'type': 'text', 'bind': 'setting.flag'},
            {
              'type': 'button',
              'label': 'Toggle flag',
              'action': {
                'type': 'toggleSetting',
                'args': {'key': 'flag'}
              },
            },
          ]),
        },
      );

      await _pump(
        tester,
        ThemeUiNodeView(node: _hostNode('theme.settings'), runtime: _runtime()),
        overrides: [
          ..._baseOverrides(settings: ui),
          themeUiProvider.overrideWith((ref) async => ui),
        ],
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Toggle flag'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('ON'), findsNothing);
      final storage = await SharedPreferences.getInstance();
      expect(storage.getBool('theme.adamya.nebula.flag'), isNull);
    });

    testWidgets('theme.settings says so when the theme has none',
        (tester) async {
      await _pump(
        tester,
        ThemeUiNodeView(node: _hostNode('theme.settings'), runtime: _runtime()),
        overrides: _baseOverrides(settings: null),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('This theme does not expose any settings.'),
        findsOneWidget,
      );
    });

    testWidgets('a settings widget inside the settings document is dropped',
        (tester) async {
      const ui = ThemeUiDocument(
        specVersion: 4,
        capabilities: ['ui.hostWidgets'],
        slots: {
          'settings.content': ThemeUiSlot(children: [
            {'type': 'text', 'text': 'ABOVE'},
            {'type': 'hostWidget', 'id': 'theme.settings'},
            {'type': 'text', 'text': 'BELOW'},
          ]),
        },
      );

      await _pump(
        tester,
        const ThemeSettingsBody(ui: ui),
        overrides: _baseOverrides(settings: ui),
      );

      // The document renders its own children, and the recursive widget is
      // gone instead of re-mounting the body.
      expect(find.text('ABOVE'), findsOneWidget);
      expect(find.text('BELOW'), findsOneWidget);
      expect(find.byType(ThemeUiSettingsScope), findsOneWidget);
    });
  });
}
