// The static `theme.json` payload: read off disk, never through Hetu.
//
// A theme whose build-time payload is static must never boot the Hetu VM —
// `themeDefinitionProvider` prefers the file, `themeUiProvider` serves the
// inline tree from it, and the optional-method guards keep
// `showSettings()`/`onUiAction()`/`getUi()` from creating a VM only to
// answer "nothing". Any miss (no file, corrupt envelope, unknown format
// version) falls back to the live `getTheme()` path.
//
// Local-only (test/ is gitignored): it mounts the real provider graph with
// a stubbed VM provider and a temp extraction directory.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/metadata/static_theme.dart';
import 'package:spotube/services/theme_definition_cache.dart';

const _pluginKey = 'tester::static-theme::1.0.0';

final _config = PluginConfiguration(
  name: 'static-theme',
  description: 'lives in a temp extraction dir',
  version: '1.0.0',
  author: 'tester',
  entryPoint: 'StaticTheme',
  pluginApiVersion: '2.0.0',
  abilities: [PluginAbilities.theme],
);

Map<String, dynamic> _colors(String fill) => {
      for (final key in const [
        'background', 'foreground', 'card', 'cardForeground',
        'primary', 'primaryForeground', 'secondary', 'secondaryForeground',
        'muted', 'mutedForeground', 'accent', 'accentForeground',
        'destructive', 'destructiveForeground', 'border', 'input', 'ring',
      ])
        key: fill,
    };

Map<String, dynamic> _theme({bool withUi = true}) => {
      'specVersion': 4,
      'light': _colors('#ffffff'),
      'dark': _colors('#000000'),
      'capabilities': ['library.read'],
      if (withUi)
        'ui': {
          'specVersion': 2,
          'slots': {
            'home.content': {
              'children': [
                {'type': 'text', 'text': 'STATIC HOME'},
              ],
            },
          },
        },
    };

Map<String, dynamic> _envelope({
  Map<String, dynamic>? theme,
  List<String> methods = const ['getUi', 'showSettings', 'onUiAction'],
  int formatVersion = staticThemeFormatVersion,
}) =>
    {
      'formatVersion': formatVersion,
      'optionalMethods': methods,
      'theme': theme ?? _theme(),
    };

class _NullShellSource extends ThemeShellSource {
  @override
  String? getBackgroundPath() => null;

  @override
  Future<ThemeDefinition?> getTheme() async => null;
}

class _ThemeNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() async => MetadataPluginState(
        plugins: [_config],
        defaultThemePlugin: 0,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('spotube-static-theme');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await supportDir.exists()) await supportDir.delete(recursive: true);
  });

  Future<Directory> writeStaticTheme(String body) async {
    final dir = Directory(
      p.join(supportDir.path, 'metadata-plugins', 'tester-static-theme-1.0.0'),
    );
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'theme.json')).writeAsString(body);
    return dir;
  }

  group('parseStaticThemeJson', () {
    test('decodes a valid envelope and merges capabilities onto the ui',
        () {
      final parsed = parseStaticThemeJson(_envelope());
      expect(parsed, isNotNull);
      expect(parsed!.definition.specVersion, 4);
      expect(parsed.definition.ui, isNotNull);
      expect(parsed.definition.ui!.capabilities, contains('library.read'));
      expect(
        parsed.optionalMethods,
        {'getUi', 'showSettings', 'onUiAction'},
      );
    });

    test('refuses unknown format versions and malformed envelopes', () {
      expect(parseStaticThemeJson(_envelope(formatVersion: 99)), isNull);
      expect(
        parseStaticThemeJson({'formatVersion': 1, 'theme': _theme()}),
        isNull,
        reason: 'optionalMethods missing',
      );
      expect(parseStaticThemeJson('not a map'), isNull);
      expect(parseStaticThemeJson(null), isNull);
    });

    test('a theme that does not decode is a miss, not a throw', () {
      expect(
        parseStaticThemeJson(_envelope(theme: {'nope': true})),
        isNull,
      );
    });

    test('needsVmForUi is false for a palette-only theme without getUi',
        () {
      final parsed = parseStaticThemeJson(_envelope(
        theme: _theme(withUi: false),
        methods: const [],
      ));
      expect(parsed, isNotNull);
      expect(parsed!.needsVmForUi, isFalse);
      expect(parsed.needsVmForSettings, isFalse);
      expect(parsed.needsVmForActions, isFalse);
    });
  });

  group('readStaticThemePayload', () {
    test('reads a theme.json written into the extraction dir', () async {
      await writeStaticTheme(jsonEncode(_envelope()));
      final parsed = await readStaticThemePayload(_pluginKey);
      expect(parsed, isNotNull);
      expect(parsed!.definition.ui, isNotNull);
    });

    test('null key, unknown plugin and corrupt file all miss', () async {
      expect(await readStaticThemePayload(null), isNull);
      expect(await readStaticThemePayload('no::such::plugin'), isNull);

      await writeStaticTheme('{"formatVersion":1,"optionalMethods":[');
      expect(await readStaticThemePayload(_pluginKey), isNull);
    });
  });

  group('providers', () {
    test('a static theme resolves without booting the VM', () async {
      await writeStaticTheme(jsonEncode(_envelope()));
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_NullShellSource()),
          metadataPluginsProvider.overrideWith(_ThemeNotifier.new),
          storedThemePluginKeyProvider.overrideWith((ref) async => _pluginKey),
          themePluginProvider.overrideWith((ref) async {
            calls++;
            return null;
          }),
        ],
      );
      addTearDown(c.dispose);

      final definition = await c.read(themeDefinitionProvider.future);
      expect(definition, isNotNull);
      expect(definition!.ui, isNotNull);
      expect(calls, 0, reason: 'the VM must never boot for a static theme');

      final ui = await c.read(themeUiProvider.future);
      expect(ui, isNotNull);
      expect(ui!.slots, contains('home.content'));
      expect(calls, 0);
    });

    test('a palette-only static theme answers no UI without booting the VM',
        () async {
      await writeStaticTheme(
        jsonEncode(_envelope(theme: _theme(withUi: false), methods: const [])),
      );
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_NullShellSource()),
          metadataPluginsProvider.overrideWith(_ThemeNotifier.new),
          storedThemePluginKeyProvider.overrideWith((ref) async => _pluginKey),
          themePluginProvider.overrideWith((ref) async {
            calls++;
            return null;
          }),
        ],
      );
      addTearDown(c.dispose);

      final definition = await c.read(themeDefinitionProvider.future);
      expect(definition, isNotNull);
      expect(await c.read(themeUiProvider.future), isNull);
      expect(await c.read(pluginThemeSettingsProvider.future), isNull);
      expect(calls, 0);
    });

    test('a missing theme.json falls back to the live path', () async {
      final dir = Directory(p.join(
        supportDir.path,
        'metadata-plugins',
        'tester-static-theme-1.0.0',
      ));
      if (await dir.exists()) await dir.delete(recursive: true);

      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_NullShellSource()),
          metadataPluginsProvider.overrideWith(_ThemeNotifier.new),
          storedThemePluginKeyProvider.overrideWith((ref) async => _pluginKey),
          themePluginProvider.overrideWith((ref) async {
            calls++;
            return null;
          }),
        ],
      );
      addTearDown(c.dispose);

      // The live path resolves through the (stubbed) plugin provider.
      expect(await c.read(themeDefinitionProvider.future), isNull);
      expect(calls, greaterThan(0), reason: 'must boot for a live getTheme()');
    });

    test('a corrupt theme.json falls back to the live path', () async {
      await writeStaticTheme('{"formatVersion":1,"theme":{}}');
      expect(await readStaticThemePayload(_pluginKey), isNull);

      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_NullShellSource()),
          metadataPluginsProvider.overrideWith(_ThemeNotifier.new),
          storedThemePluginKeyProvider.overrideWith((ref) async => _pluginKey),
          themePluginProvider.overrideWith((ref) async {
            calls++;
            return null;
          }),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(themeDefinitionProvider.future), isNull);
      expect(calls, greaterThan(0));
    });
  });
}
