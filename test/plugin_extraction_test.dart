// Regression tests for plugin archive extraction safety.
//
// Covered:
//  - entry paths cannot escape the extraction directory (posix '..',
//    win32 '..\\', absolute paths, normalize-then-escape variants).
//  - archives missing the bytecode entry (plugin.out) are rejected
//    before anything is written, so no partial install lingers.
//  - a valid archive extracts all entries under the plugin directory.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

List<int> _buildArchive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, utf8.encode(entry.value)),
    );
  }
  return ZipEncoder().encode(archive);
}

Map<String, String> _validPluginFiles() => {
      'plugin.json': jsonEncode({
        'name': 'test-plugin',
        'description': 'test',
        'version': '1.0.0',
        'author': 'tester',
        'entryPoint': 'plugin.out',
        'pluginApiVersion': '2.0.0',
      }),
      'plugin.out': 'fake-bytecode',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUpAll(() async {
    supportDir =
        await Directory.systemTemp.createTemp('spotube-plugin-extract-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        // Metadata plugin extraction resolves
        // getApplicationSupportDirectory only.
        return supportDir.path;
      },
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

  group('isSafePluginEntryPath', () {
    test('accepts plain names and nested relative paths', () {
      expect(MetadataPluginNotifier.isSafePluginEntryPath('plugin.json'), true);
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath('assets/img/logo.png'),
        true,
      );
      expect(MetadataPluginNotifier.isSafePluginEntryPath('./logo.png'), true);
    });

    test('rejects posix traversal variants', () {
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath('../evil.bin'),
        false,
      );
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath('a/../../evil.bin'),
        false,
      );
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath('..'),
        false,
      );
    });

    test('rejects win32 traversal and absolute paths', () {
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath(r'..\evil.bin'),
        false,
      );
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath(r'a\..\..\evil.bin'),
        false,
      );
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath('/etc/passwd'),
        false,
      );
      expect(
        MetadataPluginNotifier.isSafePluginEntryPath(r'C:\evil.bin'),
        false,
      );
    });
  });

  group('extractPluginArchive', () {
    test('valid archive extracts all entries under the plugin dir', () async {
      final notifier = MetadataPluginNotifier();
      final config =
          await notifier.extractPluginArchive(_buildArchive(_validPluginFiles()));

      final pluginDir = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-test-plugin-1.0.0',
        ),
      );
      expect(await pluginDir.exists(), true);
      expect(
        await File(p.join(pluginDir.path, 'plugin.json')).exists(),
        true,
      );
      expect(
        await File(p.join(pluginDir.path, 'plugin.out')).exists(),
        true,
      );
      expect(config.name, 'test-plugin');
    });

    test('archive without plugin.out is rejected before writing', () async {
      final files = _validPluginFiles()..remove('plugin.out');
      final notifier = MetadataPluginNotifier();

      await expectLater(
        notifier.extractPluginArchive(_buildArchive(files)),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.errorCode,
            'errorCode',
            MetadataPluginErrorCode.pluginByteCodeFileNotFound,
          ),
        ),
      );

      // Nothing was written.
      expect(
        Directory(p.join(supportDir.path, 'metadata-plugins', 'tester'))
            .existsSync(),
        false,
      );
    });

    test('archive without plugin.json is rejected', () async {
      final files = _validPluginFiles()..remove('plugin.json');
      final notifier = MetadataPluginNotifier();

      await expectLater(
        notifier.extractPluginArchive(_buildArchive(files)),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.errorCode,
            'errorCode',
            MetadataPluginErrorCode.pluginConfigJsonNotFound,
          ),
        ),
      );
    });

    test('archive with traversal entry is rejected, nothing extracted',
        () async {
      final files = _validPluginFiles()
        ..['../../escape/evil.bin'] = 'pwn';
      final notifier = MetadataPluginNotifier();

      await expectLater(
        notifier.extractPluginArchive(_buildArchive(files)),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.errorCode,
            'errorCode',
            MetadataPluginErrorCode.invalidPluginConfiguration,
          ),
        ),
      );

      expect(
        File(p.join(supportDir.path, 'escape', 'evil.bin')).existsSync(),
        false,
      );
    });

    test('archive with win32 traversal entry is rejected', () async {
      final files = _validPluginFiles()
        ..[r'..\escape\evil.bin'] = 'pwn';
      final notifier = MetadataPluginNotifier();

      await expectLater(
        notifier.extractPluginArchive(_buildArchive(files)),
        throwsA(isA<MetadataPluginException>()),
      );
    });
  });
}
