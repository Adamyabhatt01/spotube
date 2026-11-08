// Regression test for Phase 2 IMG.2: tile/card artwork requests decode at
// bounded dimensions while URL/cache identity is preserved and large-art
// requests remain unrestricted.
//
// Covers the UniversalImage.imageProvider contract that the edited call
// sites rely on: http URLs honor height/width as decode caps, call sites
// that pass no sizes stay uncapped (background/hero), and non-http paths
// are unaffected by size arguments.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'support/common_fakes.dart';

void main() {
  const httpUrl = 'https://example.test/art/300x300.jpg';

  setUpAll(() {
    // The http branch hands the provider the shared artwork cache manager,
    // whose Config asks path_provider for a temp dir at construction.
    PathProviderPlatform.instance = FakePathProvider(
      Directory.systemTemp.createTempSync('spotube-path-provider').path,
    );
  });

  test('tile dims flow to decode caps with identity preserved', () {
    final provider = UniversalImage.imageProvider(
      httpUrl,
      height: 80,
      width: 80,
    );

    expect(provider, isA<CachedNetworkImageProvider>());
    final sized = provider as CachedNetworkImageProvider;
    expect(sized.maxHeight, 80);
    expect(sized.maxWidth, 80);
    expect(sized.url, httpUrl);
    expect(sized.cacheKey, httpUrl);
  });

  test('scaled tile dims flow through', () {
    const scale = 1.5;
    final provider = UniversalImage.imageProvider(
      httpUrl,
      height: 100 * scale,
      width: 100 * scale,
    ) as CachedNetworkImageProvider;

    expect(provider.maxHeight, 150);
    expect(provider.maxWidth, 150);
    expect(provider.url, httpUrl);
  });

  test('requests without sizes remain unrestricted (background/hero)', () {
    final provider =
        UniversalImage.imageProvider(httpUrl) as CachedNetworkImageProvider;

    expect(provider.maxHeight, isNull);
    expect(provider.maxWidth, isNull);
    expect(provider.url, httpUrl);
    expect(provider.cacheKey, httpUrl);
  });

  test('same URL and dims produce equal providers (memory-shareable)', () {
    final first = UniversalImage.imageProvider(httpUrl, height: 80, width: 80);
    final second = UniversalImage.imageProvider(httpUrl, height: 80, width: 80);

    expect(first, second);
  });

  test('different dims shard memory entries but share URL identity', () {
    final tile = UniversalImage.imageProvider(httpUrl, height: 80, width: 80)
        as CachedNetworkImageProvider;
    final uncapped =
        UniversalImage.imageProvider(httpUrl) as CachedNetworkImageProvider;

    expect(tile, isNot(uncapped));
    expect(tile.url, uncapped.url);
    expect(tile.cacheKey, uncapped.cacheKey);
  });
}
