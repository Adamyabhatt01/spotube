import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

/// Plan §10: v4 is a breaking contract and there is no runtime v3
/// compatibility layer. A `specVersion: 3` theme keeps its palette and loses
/// its UI, and the message the host says is the message the theme-side
/// validator says.
///
/// Both seams are pinned: `sanitizeThemeDefinition` (the inline tree, on the
/// plugin and the warm-start cache paths) and `themeUiProvider` (the seam that
/// can also call into the plugin, so a v3 theme's `getUi()` never runs).
ThemeDefinition _definition({required int specVersion, ThemeUiDocument? ui}) {
  return ThemeDefinition(
    specVersion: specVersion,
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
    ui: ui,
  );
}

const _tree = ThemeUiDocument(
  slots: {
    'sidebar.footer': ThemeUiSlot(
      children: [
        {'type': 'text', 'text': 'THEME FOOTER'},
      ],
    ),
  },
);

Map<String, dynamic> _payload(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('the version gate', () {
    test('refuses a v3 tree and keeps everything else', () {
      final raw = _definition(specVersion: 3, ui: _tree);
      final sanitized = sanitizeThemeDefinition(raw);

      expect(sanitized.ui, isNull);
      // The version itself is not rewritten: an author looking at the loaded
      // theme must be able to tell which contract it was published under.
      expect(sanitized.specVersion, 3);
      expect(sanitized.copyWith(ui: _tree), raw);
    });

    test('accepts the versions this host speaks', () {
      for (final specVersion in [2, 4]) {
        final sanitized = sanitizeThemeDefinition(
          _definition(specVersion: specVersion, ui: _tree),
        );
        expect(sanitized.ui, _tree, reason: 'specVersion $specVersion');
      }
    });

    test('the message is the migration instruction, not a finding list', () {
      expect(themeV3Rejection, 'specVersion 3 is not supported; migrate to 4');
    });
  });

  group('the v3 payloads users still hold', () {
    test('lose the tree a real plugin carries inline', () {
      for (final path in [
        'themes/conformance/legacy/obsidian.json',
        'themes/conformance/legacy/spotify-shell.json',
      ]) {
        final raw = ThemeDefinition.fromJson(_payload(path));
        expect(raw.ui, isNotNull, reason: '$path ships a tree');
        final theme = sanitizeThemeDefinition(raw);
        expect(theme.ui, isNull, reason: path);
        // The palette is what the user keeps: the colours, the background and
        // the presentation blocks all survive the gate.
        expect(theme.light, raw.light, reason: path);
        expect(theme.dark, raw.dark, reason: path);
        expect(theme.background, raw.background, reason: path);
        expect(theme.typography, raw.typography, reason: path);
        expect(theme.spacing, raw.spacing, reason: path);
      }
    });

    test('and the shipped themes no longer hit that gate', () {
      for (final path in [
        'themes/conformance/obsidian.json',
        'themes/conformance/spotify-shell.json',
      ]) {
        final raw = ThemeDefinition.fromJson(_payload(path));
        expect(raw.specVersion, 4, reason: path);
        expect(raw.ui, isNotNull, reason: path);
        expect(
          sanitizeThemeDefinition(raw).ui,
          isNotNull,
          reason: '$path lost its layout through the gate',
        );
      }
    });
  });

  group('themeUiProvider', () {
    test('refuses a v3 theme without asking its plugin for a tree', () async {
      var getUiWasCalled = false;
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider
              .overrideWith((ref) async => _definition(specVersion: 3)),
          pluginThemeUiProvider.overrideWith((ref) async {
            getUiWasCalled = true;
            return _tree;
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(themeUiProvider.future), isNull);
      expect(
        getUiWasCalled,
        isFalse,
        reason: 'a v3 theme has no UI here, so its VM is not spun up',
      );
    });

    test('takes the inline tree from a v4 theme', () async {
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider.overrideWith(
            (ref) async => _definition(specVersion: 4, ui: _tree),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(themeUiProvider.future), _tree);
    });

    test('asks the plugin only when a supported theme carries no tree',
        () async {
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider
              .overrideWith((ref) async => _definition(specVersion: 4)),
          pluginThemeUiProvider.overrideWith((ref) async => _tree),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(themeUiProvider.future), _tree);
    });

    test('reaches the plugin once per session, however often the UI recomputes',
        () async {
      // §8 budgets `getUi()` at one call per session. `pluginThemeUiProvider`
      // is keyed on the plugin VM, not on the theme definition, so a shell
      // refresh or an `onUiAction` reply must not spin the VM again.
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider
              .overrideWith((ref) async => _definition(specVersion: 4)),
          pluginThemeUiProvider.overrideWith((ref) async {
            calls++;
            return _tree;
          }),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(themeUiProvider, (_, __) {});
      await container.read(themeUiProvider.future);
      container.read(themeUiOverrideProvider.notifier).state = _tree;
      container.read(themeUiOverrideProvider.notifier).state = null;
      await container.read(themeUiProvider.future);

      expect(calls, 1);
      sub.close();
    });
  });
}
