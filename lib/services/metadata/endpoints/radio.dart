import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/values.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';

/// Host-side endpoint for a plugin that advertises the `radio` ability.
///
/// A plugin exposes a `radio` member on its `metadataPlugin` instance with
/// `stations`/`byId`/`tags`/`countries` methods that speak the same JSON shapes
/// as [RadioStation]/[RadioTag]/[RadioCountry] (plus the pagination envelope).
/// Mirrors [MetadataPluginAudioSourceEndpoint]: everything crosses the Hetu
/// boundary as plain JSON-ish maps/lists and is parsed here.
///
/// `provider` (the plugin's display name) is a host concern, not something a
/// plugin knows about itself, so it is injected into every station on the way
/// out — the same namespace the favorites store keys on.
class MetadataPluginRadioEndpoint {
  final Hetu hetu;
  MetadataPluginRadioEndpoint(this.hetu);

  HTInstance get hetuMetadataRadio =>
      (hetu.fetch("metadataPlugin") as HTInstance).memberGet("radio")
          as HTInstance;

  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    required String provider,
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    final raw = await hetuMetadataRadio.invoke(
      "stations",
      positionalArgs: [
        {
          "tag": tag,
          "country": country,
          "search": search,
          "offset": offset,
          "limit": limit,
        },
      ],
    ) as Map;

    return SpotubePaginationResponseObject<RadioStation>.fromJson(
      Map<String, dynamic>.from(raw),
      (itemJson) => RadioStation.fromJson({...itemJson, "provider": provider}),
    );
  }

  Future<RadioStation?> byId({
    required String provider,
    required String id,
  }) async {
    final raw =
        await hetuMetadataRadio.invoke("byId", positionalArgs: [id]);
    if (raw == null) return null;

    final station = Map<String, dynamic>.from(raw as Map);
    // A miss is an empty record; `id` is required on a real station.
    if (station.isEmpty || station["id"] == null) return null;

    return RadioStation.fromJson({...station, "provider": provider});
  }

  Future<List<RadioTag>> tags({int limit = 50}) async {
    final raw = await hetuMetadataRadio
        .invoke("tags", positionalArgs: [
          {"limit": limit}
        ]) as List;

    return raw
        .map((e) => RadioTag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<RadioCountry>> countries({int limit = 100}) async {
    final raw = await hetuMetadataRadio
        .invoke("countries", positionalArgs: [
          {"limit": limit}
        ]) as List;

    return raw
        .map((e) => RadioCountry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
