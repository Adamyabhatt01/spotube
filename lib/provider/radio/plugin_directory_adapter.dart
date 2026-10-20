import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Adapts a running Hetu plugin's `radio` endpoint to [RadioDirectoryProvider],
/// so an installed radio plugin drops into the existing browse/search/favorites
/// fan-out unchanged — the UI, playback, ICY and persistence never learn the
/// difference. The [id] is the plugin's display name, which is the same value
/// [MetadataPluginRadioEndpoint] stamps onto every station's `provider`, so
/// favorites key on it consistently.
///
/// The VM is resolved lazily through [plugin]: the registry lists every
/// installed radio directory, but the fan-out stops at the first provider that
/// answers, so only a directory the query actually reaches pays to boot a Hetu
/// VM (which the runtime never releases).
class MetadataPluginRadioDirectoryProvider implements RadioDirectoryProvider {
  MetadataPluginRadioDirectoryProvider({
    required this.id,
    required Future<MetadataPlugin> Function() plugin,
  }) : _plugin = plugin;

  @override
  final String id;

  final Future<MetadataPlugin> Function() _plugin;

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    final plugin = await _plugin();
    return plugin.radio.stations(
      provider: id,
      tag: tag,
      country: country,
      search: search,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<RadioStation?> byId(String id) async {
    final plugin = await _plugin();
    return plugin.radio.byId(provider: this.id, id: id);
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async {
    final plugin = await _plugin();
    return plugin.radio.tags(limit: limit);
  }

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async {
    final plugin = await _plugin();
    return plugin.radio.countries(limit: limit);
  }
}
