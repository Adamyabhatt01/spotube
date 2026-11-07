// Regression tests for plugin archive extraction safety.
//
// Covered:
//  - entry paths cannot escape the extraction directory (posix '..',
//    win32 '..\\', absolute paths, normalize-then-escape variants).
//  - the extraction *directory* name cannot escape either: `version` came
//    from the archive's own plugin.json and was interpolated unsanitized.
//  - archives missing the bytecode entry (plugin.out) are rejected
//    before anything is written, so no partial install lingers.
//  - a valid archive extracts all entries under the plugin directory.
//  - downloaded bytes are verified against the publisher's checksum
//    before extraction: a mismatch throws and nothing is written, while
//    an absent checksum installs as before (third-party trust).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/plugin_storage.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

import 'support/common_fakes.dart';

List<int> _buildArchive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, utf8.encode(entry.value)),
    );
  }
  return ZipEncoder().encode(archive);
}

Map<String, String> _validPluginFiles({
  String name = 'test-plugin',
  String version = '1.0.0',
  String bytecode = 'fake-bytecode',
}) =>
    {
      'plugin.json': jsonEncode({
        'name': name,
        'description': 'test',
        'version': version,
        'author': 'tester',
        'entryPoint': 'plugin.out',
        'pluginApiVersion': '2.0.0',
      }),
      'plugin.out': bytecode,
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
      expect(PluginStorage.isSafePluginEntryPath('plugin.json'), true);
      expect(
        PluginStorage.isSafePluginEntryPath('assets/img/logo.png'),
        true,
      );
      expect(PluginStorage.isSafePluginEntryPath('./logo.png'), true);
    });

    test('rejects posix traversal variants', () {
      expect(
        PluginStorage.isSafePluginEntryPath('../evil.bin'),
        false,
      );
      expect(
        PluginStorage.isSafePluginEntryPath('a/../../evil.bin'),
        false,
      );
      expect(
        PluginStorage.isSafePluginEntryPath('..'),
        false,
      );
    });

    test('rejects win32 traversal and absolute paths', () {
      expect(
        PluginStorage.isSafePluginEntryPath(r'..\evil.bin'),
        false,
      );
      expect(
        PluginStorage.isSafePluginEntryPath(r'a\..\..\evil.bin'),
        false,
      );
      expect(
        PluginStorage.isSafePluginEntryPath('/etc/passwd'),
        false,
      );
      expect(
        PluginStorage.isSafePluginEntryPath(r'C:\evil.bin'),
        false,
      );
    });
  });

  group('extractPluginArchive', () {
    test('valid archive extracts all entries under the plugin dir', () async {
      final storage = PluginStorage();
      final config =
          await storage.extractArchive(_buildArchive(_validPluginFiles()));

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

    test('a failed re-extraction leaves the existing install intact', () async {
      const name = 'atomic-failure-plugin';
      final storage = PluginStorage();
      final target = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-$name-1.0.0',
        ),
      );

      await storage.extractArchive(
        _buildArchive(
          _validPluginFiles(name: name, bytecode: 'old-bytecode'),
        ),
      );
      final oldJson =
          await File(p.join(target.path, 'plugin.json')).readAsBytes();
      final oldOut =
          await File(p.join(target.path, 'plugin.out')).readAsBytes();

      // The second entry set contains a file whose child path cannot be
      // created (`blocker/child` under a regular file), so extraction fails
      // after it has already written part of the archive.
      final broken = _validPluginFiles(name: name, bytecode: 'new-bytecode')
        ..['blocker'] = 'not a directory'
        ..['blocker/child'] = 'boom';

      await expectLater(
        storage.extractArchive(_buildArchive(broken)),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.exists(), isTrue,
          reason: 'the previous working version must survive');
      expect(
        await File(p.join(target.path, 'plugin.json')).readAsBytes(),
        oldJson,
      );
      expect(
        await File(p.join(target.path, 'plugin.out')).readAsBytes(),
        oldOut,
        reason: 'a partial new bytecode must never replace the old one',
      );
      expect(
        await Directory('${target.path}.backup').exists(),
        isFalse,
      );

      final root = Directory(p.join(supportDir.path, 'metadata-plugins'));
      final staging = await root
          .list()
          .where((e) => p.basename(e.path).startsWith('.staging-'))
          .toList();
      expect(staging, isEmpty, reason: 'failed staging dirs are cleaned up');
    });

    test('a successful re-extraction swaps the directory contents', () async {
      const name = 'atomic-swap-plugin';
      final storage = PluginStorage();
      final target = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-$name-1.0.0',
        ),
      );

      final first = _validPluginFiles(name: name, bytecode: 'old-bytecode')
        ..['legacy.txt'] = 'stale';
      await storage.extractArchive(_buildArchive(first));
      expect(await File(p.join(target.path, 'legacy.txt')).exists(), isTrue);

      await storage.extractArchive(
        _buildArchive(
          _validPluginFiles(name: name, bytecode: 'new-bytecode'),
        ),
      );

      expect(
        await File(p.join(target.path, 'plugin.out')).readAsString(),
        'new-bytecode',
      );
      expect(
        await File(p.join(target.path, 'legacy.txt')).exists(),
        isFalse,
        reason: 'the target is replaced, not patched in place',
      );
      expect(await Directory('${target.path}.backup').exists(), isFalse);
    });

    test('a backup left by an interrupted swap is recovered', () async {
      const name = 'atomic-recovery-plugin';
      final storage = PluginStorage();
      final target = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-$name-1.0.0',
        ),
      );

      await storage.extractArchive(
        _buildArchive(
          _validPluginFiles(name: name, bytecode: 'old-bytecode'),
        ),
      );

      // Simulate a crash after the old target was moved aside but before the
      // staged directory was promoted.
      final backup = Directory('${target.path}.backup');
      await target.rename(backup.path);

      await storage.extractArchive(
        _buildArchive(
          _validPluginFiles(name: name, bytecode: 'recovered-bytecode'),
        ),
      );

      expect(await target.exists(), isTrue);
      expect(
        await File(p.join(target.path, 'plugin.out')).readAsString(),
        'recovered-bytecode',
      );
      expect(await backup.exists(), isFalse);
    });

    test('archive without plugin.out is rejected before writing', () async {
      final files = _validPluginFiles()..remove('plugin.out');
      final storage = PluginStorage();

      await expectLater(
        storage.extractArchive(_buildArchive(files)),
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
      final storage = PluginStorage();

      await expectLater(
        storage.extractArchive(_buildArchive(files)),
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
      final files = _validPluginFiles()..['../../escape/evil.bin'] = 'pwn';
      final storage = PluginStorage();

      await expectLater(
        storage.extractArchive(_buildArchive(files)),
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
      final files = _validPluginFiles()..[r'..\escape\evil.bin'] = 'pwn';
      final storage = PluginStorage();

      await expectLater(
        storage.extractArchive(_buildArchive(files)),
        throwsA(isA<MetadataPluginException>()),
      );
    });

    // `version` was the one component of the extraction directory name that
    // was not sanitized, so a crafted plugin.json decided where every entry
    // landed — before the user was asked to consent to the install, because
    // the repository flow extracts in `downloadAndCachePlugin` first.
    for (final version in <String>[
      'x/../../../../escape',
      '..',
      r'x\..\..\escape',
      '/absolute/escape',
    ]) {
      test('a traversing version "$version" is rejected, nothing written',
          () async {
        final files = _validPluginFiles();
        final manifest =
            jsonDecode(files['plugin.json']!) as Map<String, dynamic>;
        manifest['version'] = version;
        files['plugin.json'] = jsonEncode(manifest);

        final storage = PluginStorage();
        await expectLater(
          storage.extractArchive(_buildArchive(files)),
          throwsA(
            isA<MetadataPluginException>().having(
              (e) => e.errorCode,
              'errorCode',
              MetadataPluginErrorCode.invalidPluginConfiguration,
            ),
          ),
        );

        expect(
          Directory(p.join(supportDir.path, 'metadata-plugins', 'tester'))
              .existsSync(),
          false,
        );
        expect(File(p.join(supportDir.path, 'escape')).existsSync(), false);
      });
    }

    test('a version with a harmless subpath segment stays inside the root',
        () async {
      // `isSafePluginEntryPath` normalizes first, so a `..` that lands back
      // inside the base is not an escape. Guard against over-rejecting.
      expect(
        PluginStorage.isSafePluginEntryPath('1.0.0/../1.0.0'),
        true,
      );
    });
  });

  // `plugin.json` decides the extraction directory name and the fields every
  // later read depends on, so it is validated before the first byte is
  // written — not after extraction, where a bad install leaves an orphan
  // directory that no row points at.
  group('manifest validation', () {
    Map<String, dynamic> manifest({String name = 'manifest-plugin'}) =>
        jsonDecode(_validPluginFiles(name: name)['plugin.json']!)
            as Map<String, dynamic>;

    Future<void> expectRejected(
      Map<String, dynamic> manifest,
      String reason,
    ) async {
      final name = manifest['name'] as String;
      final files = _validPluginFiles(name: name)
        ..['plugin.json'] = jsonEncode(manifest);

      await expectLater(
        PluginStorage().extractArchive(_buildArchive(files)),
        throwsA(
          isA<MetadataPluginException>()
              .having((e) => e.message, 'message', contains(reason)),
        ),
      );

      expect(
        Directory(
          p.join(
            supportDir.path,
            'metadata-plugins',
            'tester-$name-1.0.0',
          ),
        ).existsSync(),
        isFalse,
        reason: 'a rejected manifest must not leave an extraction directory',
      );
    }

    test('a required field cannot be empty', () async {
      await expectRejected(
        manifest(name: 'empty-name')..['name'] = ' ',
        'plugin.json: "name" must be a non-empty string',
      );
    });

    test('a value with no path-safe characters is refused', () async {
      final config = manifest(name: 'punctuation-name');
      config['author'] = '...';
      await expectRejected(
        config,
        'plugin.json: "author" has no characters a path can use',
      );
    });

    test('a required field is capped at 128 characters', () async {
      await expectRejected(
        manifest(name: 'long-entry-point')..['entryPoint'] = 'x' * 129,
        'plugin.json: "entryPoint" is longer than 128 characters',
      );
    });

    test('a version that names a path is refused before extraction', () async {
      await expectRejected(
        manifest(name: 'path-version')..['version'] = '../escape',
        'plugin.json: "version" must not contain a path',
      );
    });

    test('an unparseable pluginApiVersion is refused before extraction',
        () async {
      await expectRejected(
        manifest(name: 'bad-api-version')..['pluginApiVersion'] = 'v2',
        'plugin.json: "pluginApiVersion" is not a version',
      );
    });

    test('a valid manifest passes', () {
      final archive = ZipDecoder().decodeBytes(
        _buildArchive(_validPluginFiles(name: 'valid-manifest')),
      );
      expect(
        PluginStorage.manifestRejection(
          PluginStorage.readArchiveConfig(archive),
        ),
        isNull,
      );
    });
  });

  // The extractor writes every entry it is given, so an archive can only be
  // stopped by what it declares: entry names, entry count, unpacked size, and
  // whether an entry is a link at all.
  group('archiveRejection', () {
    Archive archiveOf(List<ArchiveFile> files) {
      final archive = Archive()
        ..addFile(ArchiveFile.string('plugin.json', '{}'))
        ..addFile(ArchiveFile.string('plugin.out', 'bytecode'));
      for (final file in files) {
        archive.addFile(file);
      }
      return archive;
    }

    test('a symlink entry is refused', () {
      // A symlink still reports `isFile`, so the write loop below would take
      // it for a regular file — the only way to stop a link is to refuse it.
      final rejection = PluginStorage.archiveRejection(
        archiveOf([ArchiveFile.symlink('assets/logo.png', '/etc/passwd')]),
      );
      expect(rejection, contains('symbolic link'));
      expect(rejection, contains('assets/logo.png'));
    });

    test('an entry that would land outside the directory is refused', () {
      final rejection = PluginStorage.archiveRejection(
        archiveOf([ArchiveFile.string('../../evil', 'pwn')]),
      );
      expect(rejection, contains('outside the plugin directory'));
    });

    test('the entry count cap is enforced', () {
      // `archiveOf` already holds the manifest and the bytecode.
      final archive = archiveOf([
        for (var i = 0; i < PluginStorage.maxArchiveEntries - 2; i++)
          ArchiveFile.noData('asset-$i'),
      ]);
      expect(archive.length, PluginStorage.maxArchiveEntries);
      expect(PluginStorage.archiveRejection(archive), isNull);
      archive.addFile(ArchiveFile.noData('one-too-many'));
      expect(
        PluginStorage.archiveRejection(archive),
        contains('entries, over the ${PluginStorage.maxArchiveEntries}'),
      );
    });

    test('the unpacked size cap is enforced', () {
      // `size` is what the archive declares, which is what the extraction
      // spends — so this is a claimed 51 MB, not a real one.
      final archive = archiveOf([
        ArchiveFile('big.bin', PluginStorage.maxArchiveBytes + 1, [1, 2, 3]),
      ]);
      expect(
        PluginStorage.archiveRejection(archive),
        contains('bytes unpacked, over the ${PluginStorage.maxArchiveBytes}'),
      );
    });

    test('extractArchiveFrom refuses an unsafe archive before writing it',
        () async {
      const name = 'rejected-archive-plugin';
      final files = _validPluginFiles(name: name);
      final archive = ZipDecoder().decodeBytes(_buildArchive(files))
        ..addFile(ArchiveFile.symlink('escape', '../../../../etc/passwd'));

      await expectLater(
        PluginStorage().extractArchiveFrom(archive),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.message,
            'message',
            contains('symbolic link'),
          ),
        ),
      );
      expect(
        Directory(
          p.join(
            supportDir.path,
            'metadata-plugins',
            'tester-$name-1.0.0',
          ),
        ).existsSync(),
        false,
      );
    });
  });

  // Startup used to inflate and rewrite every bundled plugin on every launch,
  // on the path that blocks the plugin list (and with it the first frame). The
  // skip has to keep repairing anything incomplete.
  group('isBundledPluginUpToDate', () {
    Map<String, String> bundledFiles({String version = '1.0.0'}) => {
          'plugin.json': jsonEncode({
            'name': 'bundled-plugin',
            'description': 'test',
            'version': version,
            'author': 'tester',
            'entryPoint': 'plugin.out',
            'pluginApiVersion': '2.0.0',
          }),
          'plugin.out': 'fake-bytecode',
        };

    MetadataPluginState installedWith(PluginConfiguration? config) =>
        MetadataPluginState(plugins: config == null ? const [] : [config]);

    int byteCodeSize(Archive archive) => archive
        .firstWhere((file) => file.isFile && file.name == 'plugin.out')
        .size;

    test('only a registered, complete copy of the same version is skipped',
        () async {
      final notifier = MetadataPluginNotifier();
      final storage = PluginStorage();
      final archive = ZipDecoder().decodeBytes(_buildArchive(bundledFiles()));
      final config = PluginStorage.readArchiveConfig(archive);
      final size = byteCodeSize(archive);
      final dir = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-bundled-plugin-1.0.0',
        ),
      );

      expect(
        await notifier.isBundledPluginUpToDate(
          config,
          size,
          installedWith(config),
        ),
        isFalse,
        reason: 'registered but no files on disk',
      );

      await storage.extractArchiveFrom(archive);
      expect(await dir.exists(), isTrue);
      expect(
        await notifier.isBundledPluginUpToDate(
          config,
          size,
          installedWith(config),
        ),
        isTrue,
        reason: 'this is the launch case that used to rewrite every entry',
      );

      // An extraction interrupted by a crash leaves a short plugin.out behind.
      final binary = File(p.join(dir.path, 'plugin.out'));
      final intact = await binary.readAsBytes();
      await binary.writeAsBytes(const [1, 2, 3]);
      expect(
        await notifier.isBundledPluginUpToDate(
          config,
          size,
          installedWith(config),
        ),
        isFalse,
        reason: 'a truncated bytecode must be re-extracted',
      );
      await binary.writeAsBytes(intact);

      final newer = ZipDecoder()
          .decodeBytes(_buildArchive(bundledFiles(version: '1.0.1')));
      expect(
        await notifier.isBundledPluginUpToDate(
          PluginStorage.readArchiveConfig(newer),
          byteCodeSize(newer),
          installedWith(config),
        ),
        isFalse,
        reason: 'the bundled copy is newer than the registered one',
      );

      expect(
        await notifier.isBundledPluginUpToDate(
          config,
          size,
          installedWith(null),
        ),
        isFalse,
        reason: 'first run',
      );
      expect(
        await notifier.isBundledPluginUpToDate(
          config,
          null,
          installedWith(config),
        ),
        isFalse,
        reason: 'an archive without a bytecode entry is never reusable',
      );
    });
  });

  // The download path verifies bytes against the publisher's declared
  // checksum before extraction. A mismatch must stop the install with
  // nothing written; an absent checksum installs as before — that stays
  // the user's explicit trust in the source (third-party plugins).
  String digestOf(List<int> bytes) => sha256.convert(bytes).toString();

  Future<List<int>> archiveBytes({String version = '1.0.0'}) async =>
      _buildArchive(_validPluginFiles(name: 'checksum-plugin', version: version));

  Future<ProviderContainer> downloadContainer(List<int> bytes) async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      appDioProvider.overrideWithValue(
        Dio()
          ..httpClientAdapter = _BytesAdapter(bytes),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('plugin checksum verification', () {
    test('verifyPluginBytesIntegrity accepts a matching checksum', () async {
      final bytes = await archiveBytes();
      final expected = digestOf(bytes);
      expect(() => verifyPluginBytesIntegrity(bytes, expected), returnsNormally);
      expect(
        () => verifyPluginBytesIntegrity(bytes, ' ${expected.toUpperCase()} '),
        returnsNormally,
        reason: 'case and surrounding whitespace are cosmetic',
      );
    });

    test('verifyPluginBytesIntegrity rejects a mismatch', () async {
      final bytes = await archiveBytes();
      final expected = digestOf(utf8.encode('different bytes'));
      expect(
        () => verifyPluginBytesIntegrity(bytes, expected),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.errorCode,
            'errorCode',
            MetadataPluginErrorCode.pluginChecksumMismatch,
          ),
        ),
      );
    });

    test('no declared checksum installs as before', () async {
      final bytes = await archiveBytes();
      expect(() => verifyPluginBytesIntegrity(bytes, null), returnsNormally);
    });

    test('a download with the publisher checksum installs normally', () async {
      // Distinct version per integration test: both hit the same
      // extraction root, and the mismatch case asserts its own dir
      // was not written.
      final bytes = await archiveBytes(version: '1.2.3');
      final container = await downloadContainer(bytes);
      final config = await container
          .read(metadataPluginsProvider.notifier)
          .downloadAndCachePlugin(
            'https://example.test/plugins/checksum-plugin.smplug',
            expectedSha256: digestOf(bytes),
          );
      expect(config.name, 'checksum-plugin');
      final dir = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-checksum-plugin-1.2.3',
        ),
      );
      expect(await File(p.join(dir.path, 'plugin.out')).exists(), isTrue);
    });

    test('a tampered download throws and extracts nothing', () async {
      final bytes = await archiveBytes(version: '2.0.0');
      final container = await downloadContainer(bytes);
      const declared = '0000000000000000000000000000000000000000000000000000000000000000';
      await expectLater(
        container
            .read(metadataPluginsProvider.notifier)
            .downloadAndCachePlugin(
              'https://example.test/plugins/checksum-plugin.smplug',
              expectedSha256: declared,
            ),
        throwsA(
          isA<MetadataPluginException>().having(
            (e) => e.errorCode,
            'errorCode',
            MetadataPluginErrorCode.pluginChecksumMismatch,
          ),
        ),
      );

      final dir = Directory(
        p.join(
          supportDir.path,
          'metadata-plugins',
          'tester-checksum-plugin-2.0.0',
        ),
      );
      expect(
        await dir.exists(),
        isFalse,
        reason: 'a checksum mismatch must never reach extraction',
      );
    });

    test('updates carrying a hash verify the same way', () async {
      final parsed = PluginUpdateAvailable.fromJson(const {
        'downloadUrl': 'https://example.test/plugins/checksum-plugin.smplug',
        'version': '2.0.0',
        'sha256': '0000000000000000000000000000000000000000000000000000000000000000',
      });
      expect(parsed.expectedSha256, '0' * 64);
      final without = PluginUpdateAvailable.fromJson(const {
        'downloadUrl': 'https://example.test/plugins/checksum-plugin.smplug',
        'version': '2.0.0',
      });
      expect(without.expectedSha256, isNull);
    });
  });
}

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);

  final List<int> bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}
