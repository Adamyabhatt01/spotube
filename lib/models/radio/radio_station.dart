import 'package:freezed_annotation/freezed_annotation.dart';

part 'radio_station.freezed.dart';
part 'radio_station.g.dart';

/// A single internet-radio station as returned by a
/// [RadioDirectoryProvider](package:spotube/services/radio/radio_directory_provider.dart).
///
/// Deliberately *not* a `SpotubeTrackObject` variant: a live stream has no
/// duration, ISRC or album to fake, and keeping it out of the track union
/// means it can never be mistaken for a queueable track (`SpotubeMedia`'s
/// local-or-full assert, the loopback-proxy `uriFor`, the persisted music
/// queue). This is display + play metadata only.
@freezed
class RadioStation with _$RadioStation {
  const RadioStation._();

  factory RadioStation({
    /// Provider-scoped stable identifier. Namespaced together with [provider]
    /// so two directories can reuse the same raw id without collision.
    required String id,

    /// Which [RadioDirectoryProvider.id] produced this station.
    required String provider,

    required String name,

    /// The URL handed to the media backend to start playback. Providers must
    /// hand back an already-resolved `http`/`https` URL; scheme validation is
    /// enforced at the provider edge, not trusted from the model.
    required String streamUrl,

    @Default(<String>[]) List<String> tags,
    String? country,
    String? faviconUrl,
    String? homepageUrl,

    /// Stream codec as advertised by the directory (MP3 / AAC / Opus / ...).
    String? codec,

    /// Nominal bitrate in kbps, when the directory reports one.
    int? bitrate,

    /// Directory trust signal (Radio Browser's `vip`); informational only.
    @Default(false) bool isVip,
  }) = _RadioStation;

  factory RadioStation.fromJson(Map<String, dynamic> json) =>
      _$RadioStationFromJson(json);

  /// Persistence/dedupe key: unique per provider, so the same station listed
  /// in two directories is favorited independently.
  String get favoriteKey => '$provider:$id';

  /// One-line secondary text under the name: a few tags and the country.
  /// Null when there is nothing worth showing, so the tile can omit the row
  /// instead of rendering an empty second line.
  String? get subtitle {
    final parts = [
      if (tags.isNotEmpty) tags.take(3).join(' · '),
      if (country != null && country!.isNotEmpty) country!,
    ];
    return parts.isEmpty ? null : parts.join(' — ');
  }
}

/// A directory tag with its station count, for the browse-by-tag entry view.
@freezed
class RadioTag with _$RadioTag {
  factory RadioTag({
    required String name,
    @Default(0) int stationCount,
  }) = _RadioTag;

  factory RadioTag.fromJson(Map<String, dynamic> json) =>
      _$RadioTagFromJson(json);
}

/// A directory country with its station count, for the browse-by-country view.
@freezed
class RadioCountry with _$RadioCountry {
  factory RadioCountry({
    required String code,
    required String name,
    @Default(0) int stationCount,
  }) = _RadioCountry;

  factory RadioCountry.fromJson(Map<String, dynamic> json) =>
      _$RadioCountryFromJson(json);
}
