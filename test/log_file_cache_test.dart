import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spotube/services/logger/logger.dart';

/// Serves every path from [root] except the documents path, which throws
/// once to simulate a pre-binding call (startup phases log before the
/// Flutter binding exists, so path_provider throws there).
class _FailOncePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FailOncePathProvider(this.root);

  final String root;
  var documentsCalls = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    documentsCalls++;
    if (documentsCalls == 1) {
      throw PlatformException(code: 'pre-binding');
    }
    return root;
  }

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// `AppLogger.logFile` used to cache its first resolution unconditionally
/// (`_logFile ??= getLogsPath()`), so one pre-binding failure poisoned every
/// later caller — release startup lines and `reportError` file writes alike —
/// on the same dead future. The cache must forget failures.
void main() {
  test('a failed log-file resolution is retried, then cached', () async {
    final root =
        await Directory.systemTemp.createTemp('spotube_log_file_cache');
    PathProviderPlatform.instance = _FailOncePathProvider(root.path);

    // First call runs while "binding-less": must throw, not hang.
    await expectLater(AppLogger.logFile, throwsA(isA<PlatformException>()));

    // The failure must not be cached: the retry resolves to the log file.
    final file = await AppLogger.logFile;
    expect(file.path, endsWith('.spotube_logs'));

    // And the success IS cached: same instance, no third resolution.
    expect(identical(await AppLogger.logFile, file), isTrue);

    await root.delete(recursive: true);
  });
}
