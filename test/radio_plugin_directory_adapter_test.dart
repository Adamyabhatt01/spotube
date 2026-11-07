// PR-5: adapter <-> production-endpoint mapping over a REAL Hetu VM.
//
// `MetadataPluginRadioDirectoryProvider` is thin delegation, but the seam it
// guards (Hetu JSON crossing the boundary -> RadioStation/RadioTag/RadioCountry
// + the pagination envelope, with `provider` injected) is exactly the place a
// Hetu runtime or endpoint change can silently break. This boots the std-only
// Hetu interpreter from the pub-cache bytecode and evals an inline radio
// module — no HTTP, no plugin archive, no Flutter binding — then drives
// the production `MetadataPluginRadioEndpoint` through the adapter.
//
// The compiled Hetu plugins themselves are exercised live against their real
// upstreams by scripts/build-radio-plugin.sh + a throwaway probe (see
// .ai/AUDIT_STATE.md); this test pins the host side of the same wire contract.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_std/hetu_std.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/radio/plugin_directory_adapter.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

/// Locates the pinned `hetu_std` checkout through `.dart_tool/package_config.json`,
/// so the test runs on any machine (including CI) once `flutter pub get` has
/// run — no machine-specific absolute path.
String _stdPackagePath() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    throw StateError(
      '.dart_tool/package_config.json not found; run `fvm flutter pub get`.',
    );
  }
  final packages =
      (jsonDecode(config.readAsStringSync())['packages'] as List).cast<Map>();
  final hetu = packages.firstWhere((p) => p['name'] == 'hetu_std');
  return Uri.parse(hetu['rootUri'] as String).toFilePath();
}

/// A Hetu module exposing `metadataPlugin.radio` with the four directory
/// methods, returning plain JSON-shaped values (`{}/[].toJson()`) exactly as
/// the real plugins do, so the endpoint's `as Map`/`as List` casts are hit.
const _fakeRadioModule = '''
class FakeRadio {

  fun stations(query: Map) -> Map {
    var items = [
      {
        "id": "s1",
        "name": "One",
        "streamUrl": "https://example.com/one",
        "tags": ["jazz"],
        "country": "US",
        "codec": "MP3",
        "bitrate": 128,
        "isVip": false
      }.toJson(),
      {
        "id": "s2",
        "name": "Two",
        "streamUrl": "https://example.com/two",
        "tags": [],
        "country": "SE",
        "isVip": true
      }.toJson()
    ].toJson()

    return {
      "limit": query["limit"],
      "nextOffset": query["offset"] + query["limit"],
      "total": 2,
      "hasMore": true,
      "items": items
    }.toJson()
  }


  fun byId(id: string) -> Map {
    if (id == "missing") {
      return {}.toJson()
    }
    return {
      "id": id,
      "name": "Station " + id,
      "streamUrl": "https://example.com/" + id,
      "tags": [].toJson(),
      "country": "US"
    }.toJson()
  }


  fun tags(query: Map) -> List {
    return [
      {"name": "jazz", "stationCount": 12}.toJson(),
      {"name": "rock", "stationCount": 5}.toJson()
    ].toJson()
  }


  fun countries(query: Map) -> List {
    return [
      {"code": "US", "name": "United States", "stationCount": 900}.toJson()
    ].toJson()
  }
}

class FakePlugin {
  var radio: FakeRadio
  construct() {
    radio = FakeRadio()
  }
}

var metadataPlugin = FakePlugin()
''';

Future<MetadataPlugin> _bootFakePlugin() async {
  final stdBytecode = File('${_stdPackagePath()}/lib/assets/bytecode/std.out');
  if (!stdBytecode.existsSync()) {
    throw StateError(
      'hetu_std std bytecode not found at ${stdBytecode.path}; '
      'run `fvm flutter pub get` so the pinned git dependency is in pub-cache.',
    );
  }

  final hetu = Hetu()..init();
  HetuStdLoader.loadBindings(hetu);
  hetu.loadBytecode(bytes: stdBytecode.readAsBytesSync(), moduleName: 'std');
  hetu.eval(_fakeRadioModule);

  return MetadataPlugin.forTesting(hetu);
}

void main() {
  late MetadataPluginRadioDirectoryProvider provider;

  setUpAll(() async {
    final plugin = await _bootFakePlugin();
    provider = MetadataPluginRadioDirectoryProvider(
      id: 'Fake Plugin',
      plugin: () async => plugin,
    );
  });

  test('is a RadioDirectoryProvider', () {
    expect(provider, isA<RadioDirectoryProvider>());
    expect(provider.id, 'Fake Plugin');
  });

  test('stations parses the envelope and injects provider into each station',
      () async {
    final page = await provider.stations(search: 'x', offset: 20, limit: 2);

    expect(page.limit, 2);
    expect(page.nextOffset, 22);
    expect(page.total, 2);
    expect(page.hasMore, isTrue);
    expect(page.items.map((s) => s.id), ['s1', 's2']);
    // `provider` is a host concern the plugin never sets — injected per station.
    expect(page.items.every((s) => s.provider == 'Fake Plugin'), isTrue);
    expect(page.items.first.tags, ['jazz']);
    expect(page.items[1].isVip, isTrue);
  });

  test('byId returns a station and injects provider', () async {
    final station = await provider.byId('abc');

    expect(station, isNotNull);
    expect(station!.id, 'abc');
    expect(station.name, 'Station abc');
    expect(station.provider, 'Fake Plugin');
  });

  test('byId of a missing id (empty record) is null, not a throw', () async {
    expect(await provider.byId('missing'), isNull);
  });

  test('tags and countries map through their models', () async {
    final tags = await provider.tags(limit: 10);
    expect(tags.map((t) => t.name), ['jazz', 'rock']);
    expect(tags.first.stationCount, 12);

    final countries = await provider.countries(limit: 10);
    expect(countries.single, isA<RadioCountry>());
    expect(countries.first.code, 'US');
    expect(countries.first.stationCount, 900);
  });
}
