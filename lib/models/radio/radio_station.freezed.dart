// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'radio_station.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RadioStation _$RadioStationFromJson(Map<String, dynamic> json) {
  return _RadioStation.fromJson(json);
}

/// @nodoc
mixin _$RadioStation {
  /// Provider-scoped stable identifier. Namespaced together with [provider]
  /// so two directories can reuse the same raw id without collision.
  String get id => throw _privateConstructorUsedError;

  /// Which [RadioDirectoryProvider.id] produced this station.
  String get provider => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  /// The URL handed to the media backend to start playback. Providers must
  /// hand back an already-resolved `http`/`https` URL; scheme validation is
  /// enforced at the provider edge, not trusted from the model.
  String get streamUrl => throw _privateConstructorUsedError;
  List<String> get tags => throw _privateConstructorUsedError;
  String? get country => throw _privateConstructorUsedError;
  String? get faviconUrl => throw _privateConstructorUsedError;
  String? get homepageUrl => throw _privateConstructorUsedError;

  /// Stream codec as advertised by the directory (MP3 / AAC / Opus / ...).
  String? get codec => throw _privateConstructorUsedError;

  /// Nominal bitrate in kbps, when the directory reports one.
  int? get bitrate => throw _privateConstructorUsedError;

  /// Directory trust signal (Radio Browser's `vip`); informational only.
  bool get isVip => throw _privateConstructorUsedError;

  /// Serializes this RadioStation to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RadioStation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RadioStationCopyWith<RadioStation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RadioStationCopyWith<$Res> {
  factory $RadioStationCopyWith(
          RadioStation value, $Res Function(RadioStation) then) =
      _$RadioStationCopyWithImpl<$Res, RadioStation>;
  @useResult
  $Res call(
      {String id,
      String provider,
      String name,
      String streamUrl,
      List<String> tags,
      String? country,
      String? faviconUrl,
      String? homepageUrl,
      String? codec,
      int? bitrate,
      bool isVip});
}

/// @nodoc
class _$RadioStationCopyWithImpl<$Res, $Val extends RadioStation>
    implements $RadioStationCopyWith<$Res> {
  _$RadioStationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RadioStation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? provider = null,
    Object? name = null,
    Object? streamUrl = null,
    Object? tags = null,
    Object? country = freezed,
    Object? faviconUrl = freezed,
    Object? homepageUrl = freezed,
    Object? codec = freezed,
    Object? bitrate = freezed,
    Object? isVip = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      provider: null == provider
          ? _value.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      streamUrl: null == streamUrl
          ? _value.streamUrl
          : streamUrl // ignore: cast_nullable_to_non_nullable
              as String,
      tags: null == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      country: freezed == country
          ? _value.country
          : country // ignore: cast_nullable_to_non_nullable
              as String?,
      faviconUrl: freezed == faviconUrl
          ? _value.faviconUrl
          : faviconUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      homepageUrl: freezed == homepageUrl
          ? _value.homepageUrl
          : homepageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      codec: freezed == codec
          ? _value.codec
          : codec // ignore: cast_nullable_to_non_nullable
              as String?,
      bitrate: freezed == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as int?,
      isVip: null == isVip
          ? _value.isVip
          : isVip // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RadioStationImplCopyWith<$Res>
    implements $RadioStationCopyWith<$Res> {
  factory _$$RadioStationImplCopyWith(
          _$RadioStationImpl value, $Res Function(_$RadioStationImpl) then) =
      __$$RadioStationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String provider,
      String name,
      String streamUrl,
      List<String> tags,
      String? country,
      String? faviconUrl,
      String? homepageUrl,
      String? codec,
      int? bitrate,
      bool isVip});
}

/// @nodoc
class __$$RadioStationImplCopyWithImpl<$Res>
    extends _$RadioStationCopyWithImpl<$Res, _$RadioStationImpl>
    implements _$$RadioStationImplCopyWith<$Res> {
  __$$RadioStationImplCopyWithImpl(
      _$RadioStationImpl _value, $Res Function(_$RadioStationImpl) _then)
      : super(_value, _then);

  /// Create a copy of RadioStation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? provider = null,
    Object? name = null,
    Object? streamUrl = null,
    Object? tags = null,
    Object? country = freezed,
    Object? faviconUrl = freezed,
    Object? homepageUrl = freezed,
    Object? codec = freezed,
    Object? bitrate = freezed,
    Object? isVip = null,
  }) {
    return _then(_$RadioStationImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      provider: null == provider
          ? _value.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      streamUrl: null == streamUrl
          ? _value.streamUrl
          : streamUrl // ignore: cast_nullable_to_non_nullable
              as String,
      tags: null == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      country: freezed == country
          ? _value.country
          : country // ignore: cast_nullable_to_non_nullable
              as String?,
      faviconUrl: freezed == faviconUrl
          ? _value.faviconUrl
          : faviconUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      homepageUrl: freezed == homepageUrl
          ? _value.homepageUrl
          : homepageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      codec: freezed == codec
          ? _value.codec
          : codec // ignore: cast_nullable_to_non_nullable
              as String?,
      bitrate: freezed == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as int?,
      isVip: null == isVip
          ? _value.isVip
          : isVip // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RadioStationImpl extends _RadioStation {
  _$RadioStationImpl(
      {required this.id,
      required this.provider,
      required this.name,
      required this.streamUrl,
      final List<String> tags = const <String>[],
      this.country,
      this.faviconUrl,
      this.homepageUrl,
      this.codec,
      this.bitrate,
      this.isVip = false})
      : _tags = tags,
        super._();

  factory _$RadioStationImpl.fromJson(Map<String, dynamic> json) =>
      _$$RadioStationImplFromJson(json);

  /// Provider-scoped stable identifier. Namespaced together with [provider]
  /// so two directories can reuse the same raw id without collision.
  @override
  final String id;

  /// Which [RadioDirectoryProvider.id] produced this station.
  @override
  final String provider;
  @override
  final String name;

  /// The URL handed to the media backend to start playback. Providers must
  /// hand back an already-resolved `http`/`https` URL; scheme validation is
  /// enforced at the provider edge, not trusted from the model.
  @override
  final String streamUrl;
  final List<String> _tags;
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  @override
  final String? country;
  @override
  final String? faviconUrl;
  @override
  final String? homepageUrl;

  /// Stream codec as advertised by the directory (MP3 / AAC / Opus / ...).
  @override
  final String? codec;

  /// Nominal bitrate in kbps, when the directory reports one.
  @override
  final int? bitrate;

  /// Directory trust signal (Radio Browser's `vip`); informational only.
  @override
  @JsonKey()
  final bool isVip;

  @override
  String toString() {
    return 'RadioStation(id: $id, provider: $provider, name: $name, streamUrl: $streamUrl, tags: $tags, country: $country, faviconUrl: $faviconUrl, homepageUrl: $homepageUrl, codec: $codec, bitrate: $bitrate, isVip: $isVip)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RadioStationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.provider, provider) ||
                other.provider == provider) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.streamUrl, streamUrl) ||
                other.streamUrl == streamUrl) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            (identical(other.country, country) || other.country == country) &&
            (identical(other.faviconUrl, faviconUrl) ||
                other.faviconUrl == faviconUrl) &&
            (identical(other.homepageUrl, homepageUrl) ||
                other.homepageUrl == homepageUrl) &&
            (identical(other.codec, codec) || other.codec == codec) &&
            (identical(other.bitrate, bitrate) || other.bitrate == bitrate) &&
            (identical(other.isVip, isVip) || other.isVip == isVip));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      provider,
      name,
      streamUrl,
      const DeepCollectionEquality().hash(_tags),
      country,
      faviconUrl,
      homepageUrl,
      codec,
      bitrate,
      isVip);

  /// Create a copy of RadioStation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RadioStationImplCopyWith<_$RadioStationImpl> get copyWith =>
      __$$RadioStationImplCopyWithImpl<_$RadioStationImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RadioStationImplToJson(
      this,
    );
  }
}

abstract class _RadioStation extends RadioStation {
  factory _RadioStation(
      {required final String id,
      required final String provider,
      required final String name,
      required final String streamUrl,
      final List<String> tags,
      final String? country,
      final String? faviconUrl,
      final String? homepageUrl,
      final String? codec,
      final int? bitrate,
      final bool isVip}) = _$RadioStationImpl;
  _RadioStation._() : super._();

  factory _RadioStation.fromJson(Map<String, dynamic> json) =
      _$RadioStationImpl.fromJson;

  /// Provider-scoped stable identifier. Namespaced together with [provider]
  /// so two directories can reuse the same raw id without collision.
  @override
  String get id;

  /// Which [RadioDirectoryProvider.id] produced this station.
  @override
  String get provider;
  @override
  String get name;

  /// The URL handed to the media backend to start playback. Providers must
  /// hand back an already-resolved `http`/`https` URL; scheme validation is
  /// enforced at the provider edge, not trusted from the model.
  @override
  String get streamUrl;
  @override
  List<String> get tags;
  @override
  String? get country;
  @override
  String? get faviconUrl;
  @override
  String? get homepageUrl;

  /// Stream codec as advertised by the directory (MP3 / AAC / Opus / ...).
  @override
  String? get codec;

  /// Nominal bitrate in kbps, when the directory reports one.
  @override
  int? get bitrate;

  /// Directory trust signal (Radio Browser's `vip`); informational only.
  @override
  bool get isVip;

  /// Create a copy of RadioStation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RadioStationImplCopyWith<_$RadioStationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RadioTag _$RadioTagFromJson(Map<String, dynamic> json) {
  return _RadioTag.fromJson(json);
}

/// @nodoc
mixin _$RadioTag {
  String get name => throw _privateConstructorUsedError;
  int get stationCount => throw _privateConstructorUsedError;

  /// Serializes this RadioTag to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RadioTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RadioTagCopyWith<RadioTag> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RadioTagCopyWith<$Res> {
  factory $RadioTagCopyWith(RadioTag value, $Res Function(RadioTag) then) =
      _$RadioTagCopyWithImpl<$Res, RadioTag>;
  @useResult
  $Res call({String name, int stationCount});
}

/// @nodoc
class _$RadioTagCopyWithImpl<$Res, $Val extends RadioTag>
    implements $RadioTagCopyWith<$Res> {
  _$RadioTagCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RadioTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? stationCount = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      stationCount: null == stationCount
          ? _value.stationCount
          : stationCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RadioTagImplCopyWith<$Res>
    implements $RadioTagCopyWith<$Res> {
  factory _$$RadioTagImplCopyWith(
          _$RadioTagImpl value, $Res Function(_$RadioTagImpl) then) =
      __$$RadioTagImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, int stationCount});
}

/// @nodoc
class __$$RadioTagImplCopyWithImpl<$Res>
    extends _$RadioTagCopyWithImpl<$Res, _$RadioTagImpl>
    implements _$$RadioTagImplCopyWith<$Res> {
  __$$RadioTagImplCopyWithImpl(
      _$RadioTagImpl _value, $Res Function(_$RadioTagImpl) _then)
      : super(_value, _then);

  /// Create a copy of RadioTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? stationCount = null,
  }) {
    return _then(_$RadioTagImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      stationCount: null == stationCount
          ? _value.stationCount
          : stationCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RadioTagImpl implements _RadioTag {
  _$RadioTagImpl({required this.name, this.stationCount = 0});

  factory _$RadioTagImpl.fromJson(Map<String, dynamic> json) =>
      _$$RadioTagImplFromJson(json);

  @override
  final String name;
  @override
  @JsonKey()
  final int stationCount;

  @override
  String toString() {
    return 'RadioTag(name: $name, stationCount: $stationCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RadioTagImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.stationCount, stationCount) ||
                other.stationCount == stationCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name, stationCount);

  /// Create a copy of RadioTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RadioTagImplCopyWith<_$RadioTagImpl> get copyWith =>
      __$$RadioTagImplCopyWithImpl<_$RadioTagImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RadioTagImplToJson(
      this,
    );
  }
}

abstract class _RadioTag implements RadioTag {
  factory _RadioTag({required final String name, final int stationCount}) =
      _$RadioTagImpl;

  factory _RadioTag.fromJson(Map<String, dynamic> json) =
      _$RadioTagImpl.fromJson;

  @override
  String get name;
  @override
  int get stationCount;

  /// Create a copy of RadioTag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RadioTagImplCopyWith<_$RadioTagImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RadioCountry _$RadioCountryFromJson(Map<String, dynamic> json) {
  return _RadioCountry.fromJson(json);
}

/// @nodoc
mixin _$RadioCountry {
  String get code => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  int get stationCount => throw _privateConstructorUsedError;

  /// Serializes this RadioCountry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RadioCountry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RadioCountryCopyWith<RadioCountry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RadioCountryCopyWith<$Res> {
  factory $RadioCountryCopyWith(
          RadioCountry value, $Res Function(RadioCountry) then) =
      _$RadioCountryCopyWithImpl<$Res, RadioCountry>;
  @useResult
  $Res call({String code, String name, int stationCount});
}

/// @nodoc
class _$RadioCountryCopyWithImpl<$Res, $Val extends RadioCountry>
    implements $RadioCountryCopyWith<$Res> {
  _$RadioCountryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RadioCountry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
    Object? stationCount = null,
  }) {
    return _then(_value.copyWith(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      stationCount: null == stationCount
          ? _value.stationCount
          : stationCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RadioCountryImplCopyWith<$Res>
    implements $RadioCountryCopyWith<$Res> {
  factory _$$RadioCountryImplCopyWith(
          _$RadioCountryImpl value, $Res Function(_$RadioCountryImpl) then) =
      __$$RadioCountryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String name, int stationCount});
}

/// @nodoc
class __$$RadioCountryImplCopyWithImpl<$Res>
    extends _$RadioCountryCopyWithImpl<$Res, _$RadioCountryImpl>
    implements _$$RadioCountryImplCopyWith<$Res> {
  __$$RadioCountryImplCopyWithImpl(
      _$RadioCountryImpl _value, $Res Function(_$RadioCountryImpl) _then)
      : super(_value, _then);

  /// Create a copy of RadioCountry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
    Object? stationCount = null,
  }) {
    return _then(_$RadioCountryImpl(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      stationCount: null == stationCount
          ? _value.stationCount
          : stationCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RadioCountryImpl implements _RadioCountry {
  _$RadioCountryImpl(
      {required this.code, required this.name, this.stationCount = 0});

  factory _$RadioCountryImpl.fromJson(Map<String, dynamic> json) =>
      _$$RadioCountryImplFromJson(json);

  @override
  final String code;
  @override
  final String name;
  @override
  @JsonKey()
  final int stationCount;

  @override
  String toString() {
    return 'RadioCountry(code: $code, name: $name, stationCount: $stationCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RadioCountryImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.stationCount, stationCount) ||
                other.stationCount == stationCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, code, name, stationCount);

  /// Create a copy of RadioCountry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RadioCountryImplCopyWith<_$RadioCountryImpl> get copyWith =>
      __$$RadioCountryImplCopyWithImpl<_$RadioCountryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RadioCountryImplToJson(
      this,
    );
  }
}

abstract class _RadioCountry implements RadioCountry {
  factory _RadioCountry(
      {required final String code,
      required final String name,
      final int stationCount}) = _$RadioCountryImpl;

  factory _RadioCountry.fromJson(Map<String, dynamic> json) =
      _$RadioCountryImpl.fromJson;

  @override
  String get code;
  @override
  String get name;
  @override
  int get stationCount;

  /// Create a copy of RadioCountry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RadioCountryImplCopyWith<_$RadioCountryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
