import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('theme-ui-assets-');
    await Directory('${root.path}/assets/images').create(recursive: true);
    await File('${root.path}/assets/images/logo.png').writeAsBytes([1, 2, 3]);
    await File('${root.path}/legacy.png').writeAsBytes([4, 5, 6]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('ThemeUiAssets', () {
    test('resolves a theme-relative path inside the plugin directory', () {
      final assets = ThemeUiAssets(pluginDirectory: root.path);

      final file = assets.resolve('asset://images/logo.png');

      expect(file, isNotNull);
      expect(file!.path, '${root.path}/assets/images/logo.png');
    });

    test('falls back to the plugin root for legacy archives', () {
      final assets = ThemeUiAssets(pluginDirectory: root.path);

      final file = assets.resolve('asset://legacy.png');

      expect(file, isNotNull);
      expect(file!.path, '${root.path}/legacy.png');
    });

    test('refuses traversal, absolute paths and drive letters', () {
      final assets = ThemeUiAssets(pluginDirectory: root.path);

      expect(assets.resolve('asset://../secret.png'), isNull);
      expect(assets.resolve('asset://images/../../secret.png'), isNull);
      expect(assets.resolve('asset:///etc/passwd'), isNull);
      expect(assets.resolve(r'asset://C:\Windows\win.ini'), isNull);
      expect(assets.resolve('asset://'), isNull);
    });

    test('does not resolve anything before a theme is installed', () {
      const assets = ThemeUiAssets();

      expect(assets.resolve('asset://images/logo.png'), isNull);
      expect(assets.resolve(null), isNull);
      expect(assets.resolve('https://example.com/logo.png'), isNull);
    });
  });
}
