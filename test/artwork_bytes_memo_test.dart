// The artwork-bytes memo shares one fetch per image URL across the download
// worker, the playback-cache finalizer and the palette hook, instead of each
// of them starting its own transfer for the same cover.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';

import 'support/common_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLogger.initialize(false);

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artwork_memo_');
    PathProviderPlatform.instance = FakePathProvider(root.path);
    ServiceUtils.debugClearArtworkMemo();
  });

  tearDown(() async {
    ServiceUtils.debugClearArtworkMemo();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('concurrent requests for one URL share a single fetch', () async {
    // No network in unit tests, so the shared fetch fails into null — the
    // point is structural: both callers must hold the same future, meaning
    // one transfer, not two.
    final first = ServiceUtils.artworkBytes('https://example.test/cover.jpg');
    final second = ServiceUtils.artworkBytes('https://example.test/cover.jpg');

    expect(identical(first, second), isTrue,
        reason: 'concurrent callers share one fetch per URL');

    expect(await first, isNull);
    expect(await second, isNull);
  });

  test('failed fetches are not retained, so outages stay retryable', () async {
    expect(
      await ServiceUtils.artworkBytes('https://example.test/missing.jpg'),
      isNull,
    );
    expect(
      ServiceUtils.debugArtworkMemoLength,
      0,
      reason: 'a null result evicts its own entry instead of caching failure',
    );
  });
}
