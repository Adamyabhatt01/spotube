// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RadioStationImpl _$$RadioStationImplFromJson(Map json) => _$RadioStationImpl(
      id: json['id'] as String,
      provider: json['provider'] as String,
      name: json['name'] as String,
      streamUrl: json['streamUrl'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const <String>[],
      country: json['country'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      homepageUrl: json['homepageUrl'] as String?,
      codec: json['codec'] as String?,
      bitrate: (json['bitrate'] as num?)?.toInt(),
      isVip: json['isVip'] as bool? ?? false,
    );

Map<String, dynamic> _$$RadioStationImplToJson(_$RadioStationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'provider': instance.provider,
      'name': instance.name,
      'streamUrl': instance.streamUrl,
      'tags': instance.tags,
      'country': instance.country,
      'faviconUrl': instance.faviconUrl,
      'homepageUrl': instance.homepageUrl,
      'codec': instance.codec,
      'bitrate': instance.bitrate,
      'isVip': instance.isVip,
    };

_$RadioTagImpl _$$RadioTagImplFromJson(Map json) => _$RadioTagImpl(
      name: json['name'] as String,
      stationCount: (json['stationCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$RadioTagImplToJson(_$RadioTagImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'stationCount': instance.stationCount,
    };

_$RadioCountryImpl _$$RadioCountryImplFromJson(Map json) => _$RadioCountryImpl(
      code: json['code'] as String,
      name: json['name'] as String,
      stationCount: (json['stationCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$RadioCountryImplToJson(_$RadioCountryImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'stationCount': instance.stationCount,
    };
