// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SpotubeAudioSourceContainerPreset _$SpotubeAudioSourceContainerPresetFromJson(
    Map<String, dynamic> json) {
  switch (json['type']) {
    case 'lossy':
      return SpotubeAudioSourceContainerPresetLossy.fromJson(json);
    case 'lossless':
      return SpotubeAudioSourceContainerPresetLossless.fromJson(json);

    default:
      throw CheckedFromJsonException(
          json,
          'type',
          'SpotubeAudioSourceContainerPreset',
          'Invalid union type "${json['type']}"!');
  }
}

/// @nodoc
mixin _$SpotubeAudioSourceContainerPreset {
  SpotubeMediaCompressionType get type => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  List<Object> get qualities => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)
        lossy,
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)
        lossless,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeAudioSourceContainerPresetLossy value)
        lossy,
    required TResult Function(SpotubeAudioSourceContainerPresetLossless value)
        lossless,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult? Function(SpotubeAudioSourceContainerPresetLossless value)?
        lossless,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult Function(SpotubeAudioSourceContainerPresetLossless value)? lossless,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this SpotubeAudioSourceContainerPreset to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeAudioSourceContainerPresetCopyWith<SpotubeAudioSourceContainerPreset>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeAudioSourceContainerPresetCopyWith<$Res> {
  factory $SpotubeAudioSourceContainerPresetCopyWith(
          SpotubeAudioSourceContainerPreset value,
          $Res Function(SpotubeAudioSourceContainerPreset) then) =
      _$SpotubeAudioSourceContainerPresetCopyWithImpl<$Res,
          SpotubeAudioSourceContainerPreset>;
  @useResult
  $Res call({SpotubeMediaCompressionType type, String name});
}

/// @nodoc
class _$SpotubeAudioSourceContainerPresetCopyWithImpl<$Res,
        $Val extends SpotubeAudioSourceContainerPreset>
    implements $SpotubeAudioSourceContainerPresetCopyWith<$Res> {
  _$SpotubeAudioSourceContainerPresetCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? name = null,
  }) {
    return _then(_value.copyWith(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SpotubeMediaCompressionType,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeAudioSourceContainerPresetLossyImplCopyWith<$Res>
    implements $SpotubeAudioSourceContainerPresetCopyWith<$Res> {
  factory _$$SpotubeAudioSourceContainerPresetLossyImplCopyWith(
          _$SpotubeAudioSourceContainerPresetLossyImpl value,
          $Res Function(_$SpotubeAudioSourceContainerPresetLossyImpl) then) =
      __$$SpotubeAudioSourceContainerPresetLossyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {SpotubeMediaCompressionType type,
      String name,
      List<SpotubeAudioLossyContainerQuality> qualities});
}

/// @nodoc
class __$$SpotubeAudioSourceContainerPresetLossyImplCopyWithImpl<$Res>
    extends _$SpotubeAudioSourceContainerPresetCopyWithImpl<$Res,
        _$SpotubeAudioSourceContainerPresetLossyImpl>
    implements _$$SpotubeAudioSourceContainerPresetLossyImplCopyWith<$Res> {
  __$$SpotubeAudioSourceContainerPresetLossyImplCopyWithImpl(
      _$SpotubeAudioSourceContainerPresetLossyImpl _value,
      $Res Function(_$SpotubeAudioSourceContainerPresetLossyImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? name = null,
    Object? qualities = null,
  }) {
    return _then(_$SpotubeAudioSourceContainerPresetLossyImpl(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SpotubeMediaCompressionType,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      qualities: null == qualities
          ? _value._qualities
          : qualities // ignore: cast_nullable_to_non_nullable
              as List<SpotubeAudioLossyContainerQuality>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioSourceContainerPresetLossyImpl
    extends SpotubeAudioSourceContainerPresetLossy {
  _$SpotubeAudioSourceContainerPresetLossyImpl(
      {required this.type,
      required this.name,
      required final List<SpotubeAudioLossyContainerQuality> qualities})
      : _qualities = qualities,
        super._();

  factory _$SpotubeAudioSourceContainerPresetLossyImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioSourceContainerPresetLossyImplFromJson(json);

  @override
  final SpotubeMediaCompressionType type;
  @override
  final String name;
  final List<SpotubeAudioLossyContainerQuality> _qualities;
  @override
  List<SpotubeAudioLossyContainerQuality> get qualities {
    if (_qualities is EqualUnmodifiableListView) return _qualities;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_qualities);
  }

  @override
  String toString() {
    return 'SpotubeAudioSourceContainerPreset.lossy(type: $type, name: $name, qualities: $qualities)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioSourceContainerPresetLossyImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._qualities, _qualities));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, name, const DeepCollectionEquality().hash(_qualities));

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioSourceContainerPresetLossyImplCopyWith<
          _$SpotubeAudioSourceContainerPresetLossyImpl>
      get copyWith =>
          __$$SpotubeAudioSourceContainerPresetLossyImplCopyWithImpl<
              _$SpotubeAudioSourceContainerPresetLossyImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)
        lossy,
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)
        lossless,
  }) {
    return lossy(type, name, qualities);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
  }) {
    return lossy?.call(type, name, qualities);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
    required TResult orElse(),
  }) {
    if (lossy != null) {
      return lossy(type, name, qualities);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeAudioSourceContainerPresetLossy value)
        lossy,
    required TResult Function(SpotubeAudioSourceContainerPresetLossless value)
        lossless,
  }) {
    return lossy(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult? Function(SpotubeAudioSourceContainerPresetLossless value)?
        lossless,
  }) {
    return lossy?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult Function(SpotubeAudioSourceContainerPresetLossless value)? lossless,
    required TResult orElse(),
  }) {
    if (lossy != null) {
      return lossy(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioSourceContainerPresetLossyImplToJson(
      this,
    );
  }
}

abstract class SpotubeAudioSourceContainerPresetLossy
    extends SpotubeAudioSourceContainerPreset {
  factory SpotubeAudioSourceContainerPresetLossy(
          {required final SpotubeMediaCompressionType type,
          required final String name,
          required final List<SpotubeAudioLossyContainerQuality> qualities}) =
      _$SpotubeAudioSourceContainerPresetLossyImpl;
  SpotubeAudioSourceContainerPresetLossy._() : super._();

  factory SpotubeAudioSourceContainerPresetLossy.fromJson(
          Map<String, dynamic> json) =
      _$SpotubeAudioSourceContainerPresetLossyImpl.fromJson;

  @override
  SpotubeMediaCompressionType get type;
  @override
  String get name;
  @override
  List<SpotubeAudioLossyContainerQuality> get qualities;

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioSourceContainerPresetLossyImplCopyWith<
          _$SpotubeAudioSourceContainerPresetLossyImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SpotubeAudioSourceContainerPresetLosslessImplCopyWith<$Res>
    implements $SpotubeAudioSourceContainerPresetCopyWith<$Res> {
  factory _$$SpotubeAudioSourceContainerPresetLosslessImplCopyWith(
          _$SpotubeAudioSourceContainerPresetLosslessImpl value,
          $Res Function(_$SpotubeAudioSourceContainerPresetLosslessImpl) then) =
      __$$SpotubeAudioSourceContainerPresetLosslessImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {SpotubeMediaCompressionType type,
      String name,
      List<SpotubeAudioLosslessContainerQuality> qualities});
}

/// @nodoc
class __$$SpotubeAudioSourceContainerPresetLosslessImplCopyWithImpl<$Res>
    extends _$SpotubeAudioSourceContainerPresetCopyWithImpl<$Res,
        _$SpotubeAudioSourceContainerPresetLosslessImpl>
    implements _$$SpotubeAudioSourceContainerPresetLosslessImplCopyWith<$Res> {
  __$$SpotubeAudioSourceContainerPresetLosslessImplCopyWithImpl(
      _$SpotubeAudioSourceContainerPresetLosslessImpl _value,
      $Res Function(_$SpotubeAudioSourceContainerPresetLosslessImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? name = null,
    Object? qualities = null,
  }) {
    return _then(_$SpotubeAudioSourceContainerPresetLosslessImpl(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SpotubeMediaCompressionType,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      qualities: null == qualities
          ? _value._qualities
          : qualities // ignore: cast_nullable_to_non_nullable
              as List<SpotubeAudioLosslessContainerQuality>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioSourceContainerPresetLosslessImpl
    extends SpotubeAudioSourceContainerPresetLossless {
  _$SpotubeAudioSourceContainerPresetLosslessImpl(
      {required this.type,
      required this.name,
      required final List<SpotubeAudioLosslessContainerQuality> qualities})
      : _qualities = qualities,
        super._();

  factory _$SpotubeAudioSourceContainerPresetLosslessImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioSourceContainerPresetLosslessImplFromJson(json);

  @override
  final SpotubeMediaCompressionType type;
  @override
  final String name;
  final List<SpotubeAudioLosslessContainerQuality> _qualities;
  @override
  List<SpotubeAudioLosslessContainerQuality> get qualities {
    if (_qualities is EqualUnmodifiableListView) return _qualities;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_qualities);
  }

  @override
  String toString() {
    return 'SpotubeAudioSourceContainerPreset.lossless(type: $type, name: $name, qualities: $qualities)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioSourceContainerPresetLosslessImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._qualities, _qualities));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, name, const DeepCollectionEquality().hash(_qualities));

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioSourceContainerPresetLosslessImplCopyWith<
          _$SpotubeAudioSourceContainerPresetLosslessImpl>
      get copyWith =>
          __$$SpotubeAudioSourceContainerPresetLosslessImplCopyWithImpl<
                  _$SpotubeAudioSourceContainerPresetLosslessImpl>(
              this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)
        lossy,
    required TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)
        lossless,
  }) {
    return lossless(type, name, qualities);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult? Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
  }) {
    return lossless?.call(type, name, qualities);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLossyContainerQuality> qualities)?
        lossy,
    TResult Function(SpotubeMediaCompressionType type, String name,
            List<SpotubeAudioLosslessContainerQuality> qualities)?
        lossless,
    required TResult orElse(),
  }) {
    if (lossless != null) {
      return lossless(type, name, qualities);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeAudioSourceContainerPresetLossy value)
        lossy,
    required TResult Function(SpotubeAudioSourceContainerPresetLossless value)
        lossless,
  }) {
    return lossless(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult? Function(SpotubeAudioSourceContainerPresetLossless value)?
        lossless,
  }) {
    return lossless?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeAudioSourceContainerPresetLossy value)? lossy,
    TResult Function(SpotubeAudioSourceContainerPresetLossless value)? lossless,
    required TResult orElse(),
  }) {
    if (lossless != null) {
      return lossless(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioSourceContainerPresetLosslessImplToJson(
      this,
    );
  }
}

abstract class SpotubeAudioSourceContainerPresetLossless
    extends SpotubeAudioSourceContainerPreset {
  factory SpotubeAudioSourceContainerPresetLossless(
      {required final SpotubeMediaCompressionType type,
      required final String name,
      required final List<SpotubeAudioLosslessContainerQuality>
          qualities}) = _$SpotubeAudioSourceContainerPresetLosslessImpl;
  SpotubeAudioSourceContainerPresetLossless._() : super._();

  factory SpotubeAudioSourceContainerPresetLossless.fromJson(
          Map<String, dynamic> json) =
      _$SpotubeAudioSourceContainerPresetLosslessImpl.fromJson;

  @override
  SpotubeMediaCompressionType get type;
  @override
  String get name;
  @override
  List<SpotubeAudioLosslessContainerQuality> get qualities;

  /// Create a copy of SpotubeAudioSourceContainerPreset
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioSourceContainerPresetLosslessImplCopyWith<
          _$SpotubeAudioSourceContainerPresetLosslessImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeAudioLossyContainerQuality _$SpotubeAudioLossyContainerQualityFromJson(
    Map<String, dynamic> json) {
  return _SpotubeAudioLossyContainerQuality.fromJson(json);
}

/// @nodoc
mixin _$SpotubeAudioLossyContainerQuality {
  int get bitrate => throw _privateConstructorUsedError;

  /// Serializes this SpotubeAudioLossyContainerQuality to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeAudioLossyContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeAudioLossyContainerQualityCopyWith<SpotubeAudioLossyContainerQuality>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeAudioLossyContainerQualityCopyWith<$Res> {
  factory $SpotubeAudioLossyContainerQualityCopyWith(
          SpotubeAudioLossyContainerQuality value,
          $Res Function(SpotubeAudioLossyContainerQuality) then) =
      _$SpotubeAudioLossyContainerQualityCopyWithImpl<$Res,
          SpotubeAudioLossyContainerQuality>;
  @useResult
  $Res call({int bitrate});
}

/// @nodoc
class _$SpotubeAudioLossyContainerQualityCopyWithImpl<$Res,
        $Val extends SpotubeAudioLossyContainerQuality>
    implements $SpotubeAudioLossyContainerQualityCopyWith<$Res> {
  _$SpotubeAudioLossyContainerQualityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeAudioLossyContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bitrate = null,
  }) {
    return _then(_value.copyWith(
      bitrate: null == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeAudioLossyContainerQualityImplCopyWith<$Res>
    implements $SpotubeAudioLossyContainerQualityCopyWith<$Res> {
  factory _$$SpotubeAudioLossyContainerQualityImplCopyWith(
          _$SpotubeAudioLossyContainerQualityImpl value,
          $Res Function(_$SpotubeAudioLossyContainerQualityImpl) then) =
      __$$SpotubeAudioLossyContainerQualityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int bitrate});
}

/// @nodoc
class __$$SpotubeAudioLossyContainerQualityImplCopyWithImpl<$Res>
    extends _$SpotubeAudioLossyContainerQualityCopyWithImpl<$Res,
        _$SpotubeAudioLossyContainerQualityImpl>
    implements _$$SpotubeAudioLossyContainerQualityImplCopyWith<$Res> {
  __$$SpotubeAudioLossyContainerQualityImplCopyWithImpl(
      _$SpotubeAudioLossyContainerQualityImpl _value,
      $Res Function(_$SpotubeAudioLossyContainerQualityImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioLossyContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bitrate = null,
  }) {
    return _then(_$SpotubeAudioLossyContainerQualityImpl(
      bitrate: null == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioLossyContainerQualityImpl
    extends _SpotubeAudioLossyContainerQuality {
  _$SpotubeAudioLossyContainerQualityImpl({required this.bitrate}) : super._();

  factory _$SpotubeAudioLossyContainerQualityImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioLossyContainerQualityImplFromJson(json);

  @override
  final int bitrate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioLossyContainerQualityImpl &&
            (identical(other.bitrate, bitrate) || other.bitrate == bitrate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, bitrate);

  /// Create a copy of SpotubeAudioLossyContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioLossyContainerQualityImplCopyWith<
          _$SpotubeAudioLossyContainerQualityImpl>
      get copyWith => __$$SpotubeAudioLossyContainerQualityImplCopyWithImpl<
          _$SpotubeAudioLossyContainerQualityImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioLossyContainerQualityImplToJson(
      this,
    );
  }
}

abstract class _SpotubeAudioLossyContainerQuality
    extends SpotubeAudioLossyContainerQuality {
  factory _SpotubeAudioLossyContainerQuality({required final int bitrate}) =
      _$SpotubeAudioLossyContainerQualityImpl;
  _SpotubeAudioLossyContainerQuality._() : super._();

  factory _SpotubeAudioLossyContainerQuality.fromJson(
          Map<String, dynamic> json) =
      _$SpotubeAudioLossyContainerQualityImpl.fromJson;

  @override
  int get bitrate;

  /// Create a copy of SpotubeAudioLossyContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioLossyContainerQualityImplCopyWith<
          _$SpotubeAudioLossyContainerQualityImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeAudioLosslessContainerQuality
    _$SpotubeAudioLosslessContainerQualityFromJson(Map<String, dynamic> json) {
  return _SpotubeAudioLosslessContainerQuality.fromJson(json);
}

/// @nodoc
mixin _$SpotubeAudioLosslessContainerQuality {
  int get bitDepth => throw _privateConstructorUsedError; // bit
  int get sampleRate => throw _privateConstructorUsedError;

  /// Serializes this SpotubeAudioLosslessContainerQuality to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeAudioLosslessContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeAudioLosslessContainerQualityCopyWith<
          SpotubeAudioLosslessContainerQuality>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeAudioLosslessContainerQualityCopyWith<$Res> {
  factory $SpotubeAudioLosslessContainerQualityCopyWith(
          SpotubeAudioLosslessContainerQuality value,
          $Res Function(SpotubeAudioLosslessContainerQuality) then) =
      _$SpotubeAudioLosslessContainerQualityCopyWithImpl<$Res,
          SpotubeAudioLosslessContainerQuality>;
  @useResult
  $Res call({int bitDepth, int sampleRate});
}

/// @nodoc
class _$SpotubeAudioLosslessContainerQualityCopyWithImpl<$Res,
        $Val extends SpotubeAudioLosslessContainerQuality>
    implements $SpotubeAudioLosslessContainerQualityCopyWith<$Res> {
  _$SpotubeAudioLosslessContainerQualityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeAudioLosslessContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bitDepth = null,
    Object? sampleRate = null,
  }) {
    return _then(_value.copyWith(
      bitDepth: null == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as int,
      sampleRate: null == sampleRate
          ? _value.sampleRate
          : sampleRate // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeAudioLosslessContainerQualityImplCopyWith<$Res>
    implements $SpotubeAudioLosslessContainerQualityCopyWith<$Res> {
  factory _$$SpotubeAudioLosslessContainerQualityImplCopyWith(
          _$SpotubeAudioLosslessContainerQualityImpl value,
          $Res Function(_$SpotubeAudioLosslessContainerQualityImpl) then) =
      __$$SpotubeAudioLosslessContainerQualityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int bitDepth, int sampleRate});
}

/// @nodoc
class __$$SpotubeAudioLosslessContainerQualityImplCopyWithImpl<$Res>
    extends _$SpotubeAudioLosslessContainerQualityCopyWithImpl<$Res,
        _$SpotubeAudioLosslessContainerQualityImpl>
    implements _$$SpotubeAudioLosslessContainerQualityImplCopyWith<$Res> {
  __$$SpotubeAudioLosslessContainerQualityImplCopyWithImpl(
      _$SpotubeAudioLosslessContainerQualityImpl _value,
      $Res Function(_$SpotubeAudioLosslessContainerQualityImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioLosslessContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bitDepth = null,
    Object? sampleRate = null,
  }) {
    return _then(_$SpotubeAudioLosslessContainerQualityImpl(
      bitDepth: null == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as int,
      sampleRate: null == sampleRate
          ? _value.sampleRate
          : sampleRate // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioLosslessContainerQualityImpl
    extends _SpotubeAudioLosslessContainerQuality {
  _$SpotubeAudioLosslessContainerQualityImpl(
      {required this.bitDepth, required this.sampleRate})
      : super._();

  factory _$SpotubeAudioLosslessContainerQualityImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioLosslessContainerQualityImplFromJson(json);

  @override
  final int bitDepth;
// bit
  @override
  final int sampleRate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioLosslessContainerQualityImpl &&
            (identical(other.bitDepth, bitDepth) ||
                other.bitDepth == bitDepth) &&
            (identical(other.sampleRate, sampleRate) ||
                other.sampleRate == sampleRate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, bitDepth, sampleRate);

  /// Create a copy of SpotubeAudioLosslessContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioLosslessContainerQualityImplCopyWith<
          _$SpotubeAudioLosslessContainerQualityImpl>
      get copyWith => __$$SpotubeAudioLosslessContainerQualityImplCopyWithImpl<
          _$SpotubeAudioLosslessContainerQualityImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioLosslessContainerQualityImplToJson(
      this,
    );
  }
}

abstract class _SpotubeAudioLosslessContainerQuality
    extends SpotubeAudioLosslessContainerQuality {
  factory _SpotubeAudioLosslessContainerQuality(
          {required final int bitDepth, required final int sampleRate}) =
      _$SpotubeAudioLosslessContainerQualityImpl;
  _SpotubeAudioLosslessContainerQuality._() : super._();

  factory _SpotubeAudioLosslessContainerQuality.fromJson(
          Map<String, dynamic> json) =
      _$SpotubeAudioLosslessContainerQualityImpl.fromJson;

  @override
  int get bitDepth; // bit
  @override
  int get sampleRate;

  /// Create a copy of SpotubeAudioLosslessContainerQuality
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioLosslessContainerQualityImplCopyWith<
          _$SpotubeAudioLosslessContainerQualityImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeAudioSourceMatchObject _$SpotubeAudioSourceMatchObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeAudioSourceMatchObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeAudioSourceMatchObject {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  List<String> get artists => throw _privateConstructorUsedError;
  Duration get duration => throw _privateConstructorUsedError;
  String? get thumbnail => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;

  /// Serializes this SpotubeAudioSourceMatchObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeAudioSourceMatchObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeAudioSourceMatchObjectCopyWith<SpotubeAudioSourceMatchObject>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeAudioSourceMatchObjectCopyWith<$Res> {
  factory $SpotubeAudioSourceMatchObjectCopyWith(
          SpotubeAudioSourceMatchObject value,
          $Res Function(SpotubeAudioSourceMatchObject) then) =
      _$SpotubeAudioSourceMatchObjectCopyWithImpl<$Res,
          SpotubeAudioSourceMatchObject>;
  @useResult
  $Res call(
      {String id,
      String title,
      List<String> artists,
      Duration duration,
      String? thumbnail,
      String externalUri});
}

/// @nodoc
class _$SpotubeAudioSourceMatchObjectCopyWithImpl<$Res,
        $Val extends SpotubeAudioSourceMatchObject>
    implements $SpotubeAudioSourceMatchObjectCopyWith<$Res> {
  _$SpotubeAudioSourceMatchObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeAudioSourceMatchObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? artists = null,
    Object? duration = null,
    Object? thumbnail = freezed,
    Object? externalUri = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<String>,
      duration: null == duration
          ? _value.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as Duration,
      thumbnail: freezed == thumbnail
          ? _value.thumbnail
          : thumbnail // ignore: cast_nullable_to_non_nullable
              as String?,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeAudioSourceMatchObjectImplCopyWith<$Res>
    implements $SpotubeAudioSourceMatchObjectCopyWith<$Res> {
  factory _$$SpotubeAudioSourceMatchObjectImplCopyWith(
          _$SpotubeAudioSourceMatchObjectImpl value,
          $Res Function(_$SpotubeAudioSourceMatchObjectImpl) then) =
      __$$SpotubeAudioSourceMatchObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      List<String> artists,
      Duration duration,
      String? thumbnail,
      String externalUri});
}

/// @nodoc
class __$$SpotubeAudioSourceMatchObjectImplCopyWithImpl<$Res>
    extends _$SpotubeAudioSourceMatchObjectCopyWithImpl<$Res,
        _$SpotubeAudioSourceMatchObjectImpl>
    implements _$$SpotubeAudioSourceMatchObjectImplCopyWith<$Res> {
  __$$SpotubeAudioSourceMatchObjectImplCopyWithImpl(
      _$SpotubeAudioSourceMatchObjectImpl _value,
      $Res Function(_$SpotubeAudioSourceMatchObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioSourceMatchObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? artists = null,
    Object? duration = null,
    Object? thumbnail = freezed,
    Object? externalUri = null,
  }) {
    return _then(_$SpotubeAudioSourceMatchObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<String>,
      duration: null == duration
          ? _value.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as Duration,
      thumbnail: freezed == thumbnail
          ? _value.thumbnail
          : thumbnail // ignore: cast_nullable_to_non_nullable
              as String?,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioSourceMatchObjectImpl
    implements _SpotubeAudioSourceMatchObject {
  _$SpotubeAudioSourceMatchObjectImpl(
      {required this.id,
      required this.title,
      required final List<String> artists,
      required this.duration,
      this.thumbnail,
      required this.externalUri})
      : _artists = artists;

  factory _$SpotubeAudioSourceMatchObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioSourceMatchObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String title;
  final List<String> _artists;
  @override
  List<String> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  @override
  final Duration duration;
  @override
  final String? thumbnail;
  @override
  final String externalUri;

  @override
  String toString() {
    return 'SpotubeAudioSourceMatchObject(id: $id, title: $title, artists: $artists, duration: $duration, thumbnail: $thumbnail, externalUri: $externalUri)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioSourceMatchObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.thumbnail, thumbnail) ||
                other.thumbnail == thumbnail) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      const DeepCollectionEquality().hash(_artists),
      duration,
      thumbnail,
      externalUri);

  /// Create a copy of SpotubeAudioSourceMatchObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioSourceMatchObjectImplCopyWith<
          _$SpotubeAudioSourceMatchObjectImpl>
      get copyWith => __$$SpotubeAudioSourceMatchObjectImplCopyWithImpl<
          _$SpotubeAudioSourceMatchObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioSourceMatchObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeAudioSourceMatchObject
    implements SpotubeAudioSourceMatchObject {
  factory _SpotubeAudioSourceMatchObject(
      {required final String id,
      required final String title,
      required final List<String> artists,
      required final Duration duration,
      final String? thumbnail,
      required final String externalUri}) = _$SpotubeAudioSourceMatchObjectImpl;

  factory _SpotubeAudioSourceMatchObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeAudioSourceMatchObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  List<String> get artists;
  @override
  Duration get duration;
  @override
  String? get thumbnail;
  @override
  String get externalUri;

  /// Create a copy of SpotubeAudioSourceMatchObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioSourceMatchObjectImplCopyWith<
          _$SpotubeAudioSourceMatchObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeAudioSourceStreamObject _$SpotubeAudioSourceStreamObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeAudioSourceStreamObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeAudioSourceStreamObject {
  String get url => throw _privateConstructorUsedError;
  String get container => throw _privateConstructorUsedError;
  SpotubeMediaCompressionType get type => throw _privateConstructorUsedError;
  String? get codec => throw _privateConstructorUsedError;
  double? get bitrate => throw _privateConstructorUsedError;
  int? get bitDepth => throw _privateConstructorUsedError;
  double? get sampleRate => throw _privateConstructorUsedError;

  /// Serializes this SpotubeAudioSourceStreamObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeAudioSourceStreamObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeAudioSourceStreamObjectCopyWith<SpotubeAudioSourceStreamObject>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeAudioSourceStreamObjectCopyWith<$Res> {
  factory $SpotubeAudioSourceStreamObjectCopyWith(
          SpotubeAudioSourceStreamObject value,
          $Res Function(SpotubeAudioSourceStreamObject) then) =
      _$SpotubeAudioSourceStreamObjectCopyWithImpl<$Res,
          SpotubeAudioSourceStreamObject>;
  @useResult
  $Res call(
      {String url,
      String container,
      SpotubeMediaCompressionType type,
      String? codec,
      double? bitrate,
      int? bitDepth,
      double? sampleRate});
}

/// @nodoc
class _$SpotubeAudioSourceStreamObjectCopyWithImpl<$Res,
        $Val extends SpotubeAudioSourceStreamObject>
    implements $SpotubeAudioSourceStreamObjectCopyWith<$Res> {
  _$SpotubeAudioSourceStreamObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeAudioSourceStreamObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? container = null,
    Object? type = null,
    Object? codec = freezed,
    Object? bitrate = freezed,
    Object? bitDepth = freezed,
    Object? sampleRate = freezed,
  }) {
    return _then(_value.copyWith(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      container: null == container
          ? _value.container
          : container // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SpotubeMediaCompressionType,
      codec: freezed == codec
          ? _value.codec
          : codec // ignore: cast_nullable_to_non_nullable
              as String?,
      bitrate: freezed == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as double?,
      bitDepth: freezed == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as int?,
      sampleRate: freezed == sampleRate
          ? _value.sampleRate
          : sampleRate // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeAudioSourceStreamObjectImplCopyWith<$Res>
    implements $SpotubeAudioSourceStreamObjectCopyWith<$Res> {
  factory _$$SpotubeAudioSourceStreamObjectImplCopyWith(
          _$SpotubeAudioSourceStreamObjectImpl value,
          $Res Function(_$SpotubeAudioSourceStreamObjectImpl) then) =
      __$$SpotubeAudioSourceStreamObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String url,
      String container,
      SpotubeMediaCompressionType type,
      String? codec,
      double? bitrate,
      int? bitDepth,
      double? sampleRate});
}

/// @nodoc
class __$$SpotubeAudioSourceStreamObjectImplCopyWithImpl<$Res>
    extends _$SpotubeAudioSourceStreamObjectCopyWithImpl<$Res,
        _$SpotubeAudioSourceStreamObjectImpl>
    implements _$$SpotubeAudioSourceStreamObjectImplCopyWith<$Res> {
  __$$SpotubeAudioSourceStreamObjectImplCopyWithImpl(
      _$SpotubeAudioSourceStreamObjectImpl _value,
      $Res Function(_$SpotubeAudioSourceStreamObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeAudioSourceStreamObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? container = null,
    Object? type = null,
    Object? codec = freezed,
    Object? bitrate = freezed,
    Object? bitDepth = freezed,
    Object? sampleRate = freezed,
  }) {
    return _then(_$SpotubeAudioSourceStreamObjectImpl(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      container: null == container
          ? _value.container
          : container // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SpotubeMediaCompressionType,
      codec: freezed == codec
          ? _value.codec
          : codec // ignore: cast_nullable_to_non_nullable
              as String?,
      bitrate: freezed == bitrate
          ? _value.bitrate
          : bitrate // ignore: cast_nullable_to_non_nullable
              as double?,
      bitDepth: freezed == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as int?,
      sampleRate: freezed == sampleRate
          ? _value.sampleRate
          : sampleRate // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeAudioSourceStreamObjectImpl
    implements _SpotubeAudioSourceStreamObject {
  _$SpotubeAudioSourceStreamObjectImpl(
      {required this.url,
      required this.container,
      required this.type,
      this.codec,
      this.bitrate,
      this.bitDepth,
      this.sampleRate});

  factory _$SpotubeAudioSourceStreamObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeAudioSourceStreamObjectImplFromJson(json);

  @override
  final String url;
  @override
  final String container;
  @override
  final SpotubeMediaCompressionType type;
  @override
  final String? codec;
  @override
  final double? bitrate;
  @override
  final int? bitDepth;
  @override
  final double? sampleRate;

  @override
  String toString() {
    return 'SpotubeAudioSourceStreamObject(url: $url, container: $container, type: $type, codec: $codec, bitrate: $bitrate, bitDepth: $bitDepth, sampleRate: $sampleRate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeAudioSourceStreamObjectImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.container, container) ||
                other.container == container) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.codec, codec) || other.codec == codec) &&
            (identical(other.bitrate, bitrate) || other.bitrate == bitrate) &&
            (identical(other.bitDepth, bitDepth) ||
                other.bitDepth == bitDepth) &&
            (identical(other.sampleRate, sampleRate) ||
                other.sampleRate == sampleRate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, url, container, type, codec, bitrate, bitDepth, sampleRate);

  /// Create a copy of SpotubeAudioSourceStreamObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeAudioSourceStreamObjectImplCopyWith<
          _$SpotubeAudioSourceStreamObjectImpl>
      get copyWith => __$$SpotubeAudioSourceStreamObjectImplCopyWithImpl<
          _$SpotubeAudioSourceStreamObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeAudioSourceStreamObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeAudioSourceStreamObject
    implements SpotubeAudioSourceStreamObject {
  factory _SpotubeAudioSourceStreamObject(
      {required final String url,
      required final String container,
      required final SpotubeMediaCompressionType type,
      final String? codec,
      final double? bitrate,
      final int? bitDepth,
      final double? sampleRate}) = _$SpotubeAudioSourceStreamObjectImpl;

  factory _SpotubeAudioSourceStreamObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeAudioSourceStreamObjectImpl.fromJson;

  @override
  String get url;
  @override
  String get container;
  @override
  SpotubeMediaCompressionType get type;
  @override
  String? get codec;
  @override
  double? get bitrate;
  @override
  int? get bitDepth;
  @override
  double? get sampleRate;

  /// Create a copy of SpotubeAudioSourceStreamObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeAudioSourceStreamObjectImplCopyWith<
          _$SpotubeAudioSourceStreamObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeFullAlbumObject _$SpotubeFullAlbumObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeFullAlbumObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeFullAlbumObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  List<SpotubeSimpleArtistObject> get artists =>
      throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;
  String get releaseDate => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  int get totalTracks => throw _privateConstructorUsedError;
  SpotubeAlbumType get albumType => throw _privateConstructorUsedError;
  String? get recordLabel => throw _privateConstructorUsedError;
  List<String>? get genres => throw _privateConstructorUsedError;

  /// Serializes this SpotubeFullAlbumObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeFullAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeFullAlbumObjectCopyWith<SpotubeFullAlbumObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeFullAlbumObjectCopyWith<$Res> {
  factory $SpotubeFullAlbumObjectCopyWith(SpotubeFullAlbumObject value,
          $Res Function(SpotubeFullAlbumObject) then) =
      _$SpotubeFullAlbumObjectCopyWithImpl<$Res, SpotubeFullAlbumObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      List<SpotubeSimpleArtistObject> artists,
      List<SpotubeImageObject> images,
      String releaseDate,
      String externalUri,
      int totalTracks,
      SpotubeAlbumType albumType,
      String? recordLabel,
      List<String>? genres});
}

/// @nodoc
class _$SpotubeFullAlbumObjectCopyWithImpl<$Res,
        $Val extends SpotubeFullAlbumObject>
    implements $SpotubeFullAlbumObjectCopyWith<$Res> {
  _$SpotubeFullAlbumObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeFullAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? artists = null,
    Object? images = null,
    Object? releaseDate = null,
    Object? externalUri = null,
    Object? totalTracks = null,
    Object? albumType = null,
    Object? recordLabel = freezed,
    Object? genres = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      releaseDate: null == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      totalTracks: null == totalTracks
          ? _value.totalTracks
          : totalTracks // ignore: cast_nullable_to_non_nullable
              as int,
      albumType: null == albumType
          ? _value.albumType
          : albumType // ignore: cast_nullable_to_non_nullable
              as SpotubeAlbumType,
      recordLabel: freezed == recordLabel
          ? _value.recordLabel
          : recordLabel // ignore: cast_nullable_to_non_nullable
              as String?,
      genres: freezed == genres
          ? _value.genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeFullAlbumObjectImplCopyWith<$Res>
    implements $SpotubeFullAlbumObjectCopyWith<$Res> {
  factory _$$SpotubeFullAlbumObjectImplCopyWith(
          _$SpotubeFullAlbumObjectImpl value,
          $Res Function(_$SpotubeFullAlbumObjectImpl) then) =
      __$$SpotubeFullAlbumObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      List<SpotubeSimpleArtistObject> artists,
      List<SpotubeImageObject> images,
      String releaseDate,
      String externalUri,
      int totalTracks,
      SpotubeAlbumType albumType,
      String? recordLabel,
      List<String>? genres});
}

/// @nodoc
class __$$SpotubeFullAlbumObjectImplCopyWithImpl<$Res>
    extends _$SpotubeFullAlbumObjectCopyWithImpl<$Res,
        _$SpotubeFullAlbumObjectImpl>
    implements _$$SpotubeFullAlbumObjectImplCopyWith<$Res> {
  __$$SpotubeFullAlbumObjectImplCopyWithImpl(
      _$SpotubeFullAlbumObjectImpl _value,
      $Res Function(_$SpotubeFullAlbumObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeFullAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? artists = null,
    Object? images = null,
    Object? releaseDate = null,
    Object? externalUri = null,
    Object? totalTracks = null,
    Object? albumType = null,
    Object? recordLabel = freezed,
    Object? genres = freezed,
  }) {
    return _then(_$SpotubeFullAlbumObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      releaseDate: null == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      totalTracks: null == totalTracks
          ? _value.totalTracks
          : totalTracks // ignore: cast_nullable_to_non_nullable
              as int,
      albumType: null == albumType
          ? _value.albumType
          : albumType // ignore: cast_nullable_to_non_nullable
              as SpotubeAlbumType,
      recordLabel: freezed == recordLabel
          ? _value.recordLabel
          : recordLabel // ignore: cast_nullable_to_non_nullable
              as String?,
      genres: freezed == genres
          ? _value._genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeFullAlbumObjectImpl implements _SpotubeFullAlbumObject {
  _$SpotubeFullAlbumObjectImpl(
      {required this.id,
      required this.name,
      required final List<SpotubeSimpleArtistObject> artists,
      final List<SpotubeImageObject> images = const [],
      required this.releaseDate,
      required this.externalUri,
      required this.totalTracks,
      required this.albumType,
      this.recordLabel,
      final List<String>? genres})
      : _artists = artists,
        _images = images,
        _genres = genres;

  factory _$SpotubeFullAlbumObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeFullAlbumObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  final List<SpotubeSimpleArtistObject> _artists;
  @override
  List<SpotubeSimpleArtistObject> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  final String releaseDate;
  @override
  final String externalUri;
  @override
  final int totalTracks;
  @override
  final SpotubeAlbumType albumType;
  @override
  final String? recordLabel;
  final List<String>? _genres;
  @override
  List<String>? get genres {
    final value = _genres;
    if (value == null) return null;
    if (_genres is EqualUnmodifiableListView) return _genres;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'SpotubeFullAlbumObject(id: $id, name: $name, artists: $artists, images: $images, releaseDate: $releaseDate, externalUri: $externalUri, totalTracks: $totalTracks, albumType: $albumType, recordLabel: $recordLabel, genres: $genres)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeFullAlbumObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.releaseDate, releaseDate) ||
                other.releaseDate == releaseDate) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            (identical(other.totalTracks, totalTracks) ||
                other.totalTracks == totalTracks) &&
            (identical(other.albumType, albumType) ||
                other.albumType == albumType) &&
            (identical(other.recordLabel, recordLabel) ||
                other.recordLabel == recordLabel) &&
            const DeepCollectionEquality().equals(other._genres, _genres));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      const DeepCollectionEquality().hash(_artists),
      const DeepCollectionEquality().hash(_images),
      releaseDate,
      externalUri,
      totalTracks,
      albumType,
      recordLabel,
      const DeepCollectionEquality().hash(_genres));

  /// Create a copy of SpotubeFullAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeFullAlbumObjectImplCopyWith<_$SpotubeFullAlbumObjectImpl>
      get copyWith => __$$SpotubeFullAlbumObjectImplCopyWithImpl<
          _$SpotubeFullAlbumObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeFullAlbumObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeFullAlbumObject implements SpotubeFullAlbumObject {
  factory _SpotubeFullAlbumObject(
      {required final String id,
      required final String name,
      required final List<SpotubeSimpleArtistObject> artists,
      final List<SpotubeImageObject> images,
      required final String releaseDate,
      required final String externalUri,
      required final int totalTracks,
      required final SpotubeAlbumType albumType,
      final String? recordLabel,
      final List<String>? genres}) = _$SpotubeFullAlbumObjectImpl;

  factory _SpotubeFullAlbumObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeFullAlbumObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  List<SpotubeSimpleArtistObject> get artists;
  @override
  List<SpotubeImageObject> get images;
  @override
  String get releaseDate;
  @override
  String get externalUri;
  @override
  int get totalTracks;
  @override
  SpotubeAlbumType get albumType;
  @override
  String? get recordLabel;
  @override
  List<String>? get genres;

  /// Create a copy of SpotubeFullAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeFullAlbumObjectImplCopyWith<_$SpotubeFullAlbumObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeSimpleAlbumObject _$SpotubeSimpleAlbumObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeSimpleAlbumObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeSimpleAlbumObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  List<SpotubeSimpleArtistObject> get artists =>
      throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;
  SpotubeAlbumType get albumType => throw _privateConstructorUsedError;
  String? get releaseDate => throw _privateConstructorUsedError;

  /// Serializes this SpotubeSimpleAlbumObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeSimpleAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeSimpleAlbumObjectCopyWith<SpotubeSimpleAlbumObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeSimpleAlbumObjectCopyWith<$Res> {
  factory $SpotubeSimpleAlbumObjectCopyWith(SpotubeSimpleAlbumObject value,
          $Res Function(SpotubeSimpleAlbumObject) then) =
      _$SpotubeSimpleAlbumObjectCopyWithImpl<$Res, SpotubeSimpleAlbumObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeSimpleArtistObject> artists,
      List<SpotubeImageObject> images,
      SpotubeAlbumType albumType,
      String? releaseDate});
}

/// @nodoc
class _$SpotubeSimpleAlbumObjectCopyWithImpl<$Res,
        $Val extends SpotubeSimpleAlbumObject>
    implements $SpotubeSimpleAlbumObjectCopyWith<$Res> {
  _$SpotubeSimpleAlbumObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeSimpleAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? artists = null,
    Object? images = null,
    Object? albumType = null,
    Object? releaseDate = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      albumType: null == albumType
          ? _value.albumType
          : albumType // ignore: cast_nullable_to_non_nullable
              as SpotubeAlbumType,
      releaseDate: freezed == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeSimpleAlbumObjectImplCopyWith<$Res>
    implements $SpotubeSimpleAlbumObjectCopyWith<$Res> {
  factory _$$SpotubeSimpleAlbumObjectImplCopyWith(
          _$SpotubeSimpleAlbumObjectImpl value,
          $Res Function(_$SpotubeSimpleAlbumObjectImpl) then) =
      __$$SpotubeSimpleAlbumObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeSimpleArtistObject> artists,
      List<SpotubeImageObject> images,
      SpotubeAlbumType albumType,
      String? releaseDate});
}

/// @nodoc
class __$$SpotubeSimpleAlbumObjectImplCopyWithImpl<$Res>
    extends _$SpotubeSimpleAlbumObjectCopyWithImpl<$Res,
        _$SpotubeSimpleAlbumObjectImpl>
    implements _$$SpotubeSimpleAlbumObjectImplCopyWith<$Res> {
  __$$SpotubeSimpleAlbumObjectImplCopyWithImpl(
      _$SpotubeSimpleAlbumObjectImpl _value,
      $Res Function(_$SpotubeSimpleAlbumObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeSimpleAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? artists = null,
    Object? images = null,
    Object? albumType = null,
    Object? releaseDate = freezed,
  }) {
    return _then(_$SpotubeSimpleAlbumObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      albumType: null == albumType
          ? _value.albumType
          : albumType // ignore: cast_nullable_to_non_nullable
              as SpotubeAlbumType,
      releaseDate: freezed == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeSimpleAlbumObjectImpl implements _SpotubeSimpleAlbumObject {
  _$SpotubeSimpleAlbumObjectImpl(
      {required this.id,
      required this.name,
      required this.externalUri,
      required final List<SpotubeSimpleArtistObject> artists,
      final List<SpotubeImageObject> images = const [],
      required this.albumType,
      this.releaseDate})
      : _artists = artists,
        _images = images;

  factory _$SpotubeSimpleAlbumObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeSimpleAlbumObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String externalUri;
  final List<SpotubeSimpleArtistObject> _artists;
  @override
  List<SpotubeSimpleArtistObject> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  final SpotubeAlbumType albumType;
  @override
  final String? releaseDate;

  @override
  String toString() {
    return 'SpotubeSimpleAlbumObject(id: $id, name: $name, externalUri: $externalUri, artists: $artists, images: $images, albumType: $albumType, releaseDate: $releaseDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeSimpleAlbumObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.albumType, albumType) ||
                other.albumType == albumType) &&
            (identical(other.releaseDate, releaseDate) ||
                other.releaseDate == releaseDate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      externalUri,
      const DeepCollectionEquality().hash(_artists),
      const DeepCollectionEquality().hash(_images),
      albumType,
      releaseDate);

  /// Create a copy of SpotubeSimpleAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeSimpleAlbumObjectImplCopyWith<_$SpotubeSimpleAlbumObjectImpl>
      get copyWith => __$$SpotubeSimpleAlbumObjectImplCopyWithImpl<
          _$SpotubeSimpleAlbumObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeSimpleAlbumObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeSimpleAlbumObject implements SpotubeSimpleAlbumObject {
  factory _SpotubeSimpleAlbumObject(
      {required final String id,
      required final String name,
      required final String externalUri,
      required final List<SpotubeSimpleArtistObject> artists,
      final List<SpotubeImageObject> images,
      required final SpotubeAlbumType albumType,
      final String? releaseDate}) = _$SpotubeSimpleAlbumObjectImpl;

  factory _SpotubeSimpleAlbumObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeSimpleAlbumObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get externalUri;
  @override
  List<SpotubeSimpleArtistObject> get artists;
  @override
  List<SpotubeImageObject> get images;
  @override
  SpotubeAlbumType get albumType;
  @override
  String? get releaseDate;

  /// Create a copy of SpotubeSimpleAlbumObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeSimpleAlbumObjectImplCopyWith<_$SpotubeSimpleAlbumObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeFullArtistObject _$SpotubeFullArtistObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeFullArtistObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeFullArtistObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;
  List<String>? get genres => throw _privateConstructorUsedError;
  int? get followers => throw _privateConstructorUsedError;

  /// Serializes this SpotubeFullArtistObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeFullArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeFullArtistObjectCopyWith<SpotubeFullArtistObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeFullArtistObjectCopyWith<$Res> {
  factory $SpotubeFullArtistObjectCopyWith(SpotubeFullArtistObject value,
          $Res Function(SpotubeFullArtistObject) then) =
      _$SpotubeFullArtistObjectCopyWithImpl<$Res, SpotubeFullArtistObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeImageObject> images,
      List<String>? genres,
      int? followers});
}

/// @nodoc
class _$SpotubeFullArtistObjectCopyWithImpl<$Res,
        $Val extends SpotubeFullArtistObject>
    implements $SpotubeFullArtistObjectCopyWith<$Res> {
  _$SpotubeFullArtistObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeFullArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? images = null,
    Object? genres = freezed,
    Object? followers = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      genres: freezed == genres
          ? _value.genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      followers: freezed == followers
          ? _value.followers
          : followers // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeFullArtistObjectImplCopyWith<$Res>
    implements $SpotubeFullArtistObjectCopyWith<$Res> {
  factory _$$SpotubeFullArtistObjectImplCopyWith(
          _$SpotubeFullArtistObjectImpl value,
          $Res Function(_$SpotubeFullArtistObjectImpl) then) =
      __$$SpotubeFullArtistObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeImageObject> images,
      List<String>? genres,
      int? followers});
}

/// @nodoc
class __$$SpotubeFullArtistObjectImplCopyWithImpl<$Res>
    extends _$SpotubeFullArtistObjectCopyWithImpl<$Res,
        _$SpotubeFullArtistObjectImpl>
    implements _$$SpotubeFullArtistObjectImplCopyWith<$Res> {
  __$$SpotubeFullArtistObjectImplCopyWithImpl(
      _$SpotubeFullArtistObjectImpl _value,
      $Res Function(_$SpotubeFullArtistObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeFullArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? images = null,
    Object? genres = freezed,
    Object? followers = freezed,
  }) {
    return _then(_$SpotubeFullArtistObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      genres: freezed == genres
          ? _value._genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      followers: freezed == followers
          ? _value.followers
          : followers // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeFullArtistObjectImpl implements _SpotubeFullArtistObject {
  _$SpotubeFullArtistObjectImpl(
      {required this.id,
      required this.name,
      required this.externalUri,
      final List<SpotubeImageObject> images = const [],
      final List<String>? genres,
      this.followers})
      : _images = images,
        _genres = genres;

  factory _$SpotubeFullArtistObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeFullArtistObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String externalUri;
  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  final List<String>? _genres;
  @override
  List<String>? get genres {
    final value = _genres;
    if (value == null) return null;
    if (_genres is EqualUnmodifiableListView) return _genres;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final int? followers;

  @override
  String toString() {
    return 'SpotubeFullArtistObject(id: $id, name: $name, externalUri: $externalUri, images: $images, genres: $genres, followers: $followers)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeFullArtistObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            const DeepCollectionEquality().equals(other._genres, _genres) &&
            (identical(other.followers, followers) ||
                other.followers == followers));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      externalUri,
      const DeepCollectionEquality().hash(_images),
      const DeepCollectionEquality().hash(_genres),
      followers);

  /// Create a copy of SpotubeFullArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeFullArtistObjectImplCopyWith<_$SpotubeFullArtistObjectImpl>
      get copyWith => __$$SpotubeFullArtistObjectImplCopyWithImpl<
          _$SpotubeFullArtistObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeFullArtistObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeFullArtistObject implements SpotubeFullArtistObject {
  factory _SpotubeFullArtistObject(
      {required final String id,
      required final String name,
      required final String externalUri,
      final List<SpotubeImageObject> images,
      final List<String>? genres,
      final int? followers}) = _$SpotubeFullArtistObjectImpl;

  factory _SpotubeFullArtistObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeFullArtistObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get externalUri;
  @override
  List<SpotubeImageObject> get images;
  @override
  List<String>? get genres;
  @override
  int? get followers;

  /// Create a copy of SpotubeFullArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeFullArtistObjectImplCopyWith<_$SpotubeFullArtistObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeSimpleArtistObject _$SpotubeSimpleArtistObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeSimpleArtistObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeSimpleArtistObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  List<SpotubeImageObject>? get images => throw _privateConstructorUsedError;

  /// Serializes this SpotubeSimpleArtistObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeSimpleArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeSimpleArtistObjectCopyWith<SpotubeSimpleArtistObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeSimpleArtistObjectCopyWith<$Res> {
  factory $SpotubeSimpleArtistObjectCopyWith(SpotubeSimpleArtistObject value,
          $Res Function(SpotubeSimpleArtistObject) then) =
      _$SpotubeSimpleArtistObjectCopyWithImpl<$Res, SpotubeSimpleArtistObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeImageObject>? images});
}

/// @nodoc
class _$SpotubeSimpleArtistObjectCopyWithImpl<$Res,
        $Val extends SpotubeSimpleArtistObject>
    implements $SpotubeSimpleArtistObjectCopyWith<$Res> {
  _$SpotubeSimpleArtistObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeSimpleArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? images = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      images: freezed == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeSimpleArtistObjectImplCopyWith<$Res>
    implements $SpotubeSimpleArtistObjectCopyWith<$Res> {
  factory _$$SpotubeSimpleArtistObjectImplCopyWith(
          _$SpotubeSimpleArtistObjectImpl value,
          $Res Function(_$SpotubeSimpleArtistObjectImpl) then) =
      __$$SpotubeSimpleArtistObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeImageObject>? images});
}

/// @nodoc
class __$$SpotubeSimpleArtistObjectImplCopyWithImpl<$Res>
    extends _$SpotubeSimpleArtistObjectCopyWithImpl<$Res,
        _$SpotubeSimpleArtistObjectImpl>
    implements _$$SpotubeSimpleArtistObjectImplCopyWith<$Res> {
  __$$SpotubeSimpleArtistObjectImplCopyWithImpl(
      _$SpotubeSimpleArtistObjectImpl _value,
      $Res Function(_$SpotubeSimpleArtistObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeSimpleArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? images = freezed,
  }) {
    return _then(_$SpotubeSimpleArtistObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      images: freezed == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeSimpleArtistObjectImpl implements _SpotubeSimpleArtistObject {
  _$SpotubeSimpleArtistObjectImpl(
      {required this.id,
      required this.name,
      required this.externalUri,
      final List<SpotubeImageObject>? images})
      : _images = images;

  factory _$SpotubeSimpleArtistObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeSimpleArtistObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String externalUri;
  final List<SpotubeImageObject>? _images;
  @override
  List<SpotubeImageObject>? get images {
    final value = _images;
    if (value == null) return null;
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'SpotubeSimpleArtistObject(id: $id, name: $name, externalUri: $externalUri, images: $images)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeSimpleArtistObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            const DeepCollectionEquality().equals(other._images, _images));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, externalUri,
      const DeepCollectionEquality().hash(_images));

  /// Create a copy of SpotubeSimpleArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeSimpleArtistObjectImplCopyWith<_$SpotubeSimpleArtistObjectImpl>
      get copyWith => __$$SpotubeSimpleArtistObjectImplCopyWithImpl<
          _$SpotubeSimpleArtistObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeSimpleArtistObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeSimpleArtistObject implements SpotubeSimpleArtistObject {
  factory _SpotubeSimpleArtistObject(
          {required final String id,
          required final String name,
          required final String externalUri,
          final List<SpotubeImageObject>? images}) =
      _$SpotubeSimpleArtistObjectImpl;

  factory _SpotubeSimpleArtistObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeSimpleArtistObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get externalUri;
  @override
  List<SpotubeImageObject>? get images;

  /// Create a copy of SpotubeSimpleArtistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeSimpleArtistObjectImplCopyWith<_$SpotubeSimpleArtistObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeBrowseSectionObject<T> _$SpotubeBrowseSectionObjectFromJson<T>(
    Map<String, dynamic> json, T Function(Object?) fromJsonT) {
  return _SpotubeBrowseSectionObject<T>.fromJson(json, fromJsonT);
}

/// @nodoc
mixin _$SpotubeBrowseSectionObject<T> {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  bool get browseMore => throw _privateConstructorUsedError;
  List<T> get items => throw _privateConstructorUsedError;

  /// Serializes this SpotubeBrowseSectionObject to a JSON map.
  Map<String, dynamic> toJson(Object? Function(T) toJsonT) =>
      throw _privateConstructorUsedError;

  /// Create a copy of SpotubeBrowseSectionObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeBrowseSectionObjectCopyWith<T, SpotubeBrowseSectionObject<T>>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeBrowseSectionObjectCopyWith<T, $Res> {
  factory $SpotubeBrowseSectionObjectCopyWith(
          SpotubeBrowseSectionObject<T> value,
          $Res Function(SpotubeBrowseSectionObject<T>) then) =
      _$SpotubeBrowseSectionObjectCopyWithImpl<T, $Res,
          SpotubeBrowseSectionObject<T>>;
  @useResult
  $Res call(
      {String id,
      String title,
      String externalUri,
      bool browseMore,
      List<T> items});
}

/// @nodoc
class _$SpotubeBrowseSectionObjectCopyWithImpl<T, $Res,
        $Val extends SpotubeBrowseSectionObject<T>>
    implements $SpotubeBrowseSectionObjectCopyWith<T, $Res> {
  _$SpotubeBrowseSectionObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeBrowseSectionObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? externalUri = null,
    Object? browseMore = null,
    Object? items = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      browseMore: null == browseMore
          ? _value.browseMore
          : browseMore // ignore: cast_nullable_to_non_nullable
              as bool,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<T>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeBrowseSectionObjectImplCopyWith<T, $Res>
    implements $SpotubeBrowseSectionObjectCopyWith<T, $Res> {
  factory _$$SpotubeBrowseSectionObjectImplCopyWith(
          _$SpotubeBrowseSectionObjectImpl<T> value,
          $Res Function(_$SpotubeBrowseSectionObjectImpl<T>) then) =
      __$$SpotubeBrowseSectionObjectImplCopyWithImpl<T, $Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String externalUri,
      bool browseMore,
      List<T> items});
}

/// @nodoc
class __$$SpotubeBrowseSectionObjectImplCopyWithImpl<T, $Res>
    extends _$SpotubeBrowseSectionObjectCopyWithImpl<T, $Res,
        _$SpotubeBrowseSectionObjectImpl<T>>
    implements _$$SpotubeBrowseSectionObjectImplCopyWith<T, $Res> {
  __$$SpotubeBrowseSectionObjectImplCopyWithImpl(
      _$SpotubeBrowseSectionObjectImpl<T> _value,
      $Res Function(_$SpotubeBrowseSectionObjectImpl<T>) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeBrowseSectionObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? externalUri = null,
    Object? browseMore = null,
    Object? items = null,
  }) {
    return _then(_$SpotubeBrowseSectionObjectImpl<T>(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      browseMore: null == browseMore
          ? _value.browseMore
          : browseMore // ignore: cast_nullable_to_non_nullable
              as bool,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<T>,
    ));
  }
}

/// @nodoc
@JsonSerializable(genericArgumentFactories: true)
class _$SpotubeBrowseSectionObjectImpl<T>
    implements _SpotubeBrowseSectionObject<T> {
  _$SpotubeBrowseSectionObjectImpl(
      {required this.id,
      required this.title,
      required this.externalUri,
      required this.browseMore,
      required final List<T> items})
      : _items = items;

  factory _$SpotubeBrowseSectionObjectImpl.fromJson(
          Map<String, dynamic> json, T Function(Object?) fromJsonT) =>
      _$$SpotubeBrowseSectionObjectImplFromJson(json, fromJsonT);

  @override
  final String id;
  @override
  final String title;
  @override
  final String externalUri;
  @override
  final bool browseMore;
  final List<T> _items;
  @override
  List<T> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString() {
    return 'SpotubeBrowseSectionObject<$T>(id: $id, title: $title, externalUri: $externalUri, browseMore: $browseMore, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeBrowseSectionObjectImpl<T> &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            (identical(other.browseMore, browseMore) ||
                other.browseMore == browseMore) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, externalUri,
      browseMore, const DeepCollectionEquality().hash(_items));

  /// Create a copy of SpotubeBrowseSectionObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeBrowseSectionObjectImplCopyWith<T,
          _$SpotubeBrowseSectionObjectImpl<T>>
      get copyWith => __$$SpotubeBrowseSectionObjectImplCopyWithImpl<T,
          _$SpotubeBrowseSectionObjectImpl<T>>(this, _$identity);

  @override
  Map<String, dynamic> toJson(Object? Function(T) toJsonT) {
    return _$$SpotubeBrowseSectionObjectImplToJson<T>(this, toJsonT);
  }
}

abstract class _SpotubeBrowseSectionObject<T>
    implements SpotubeBrowseSectionObject<T> {
  factory _SpotubeBrowseSectionObject(
      {required final String id,
      required final String title,
      required final String externalUri,
      required final bool browseMore,
      required final List<T> items}) = _$SpotubeBrowseSectionObjectImpl<T>;

  factory _SpotubeBrowseSectionObject.fromJson(
          Map<String, dynamic> json, T Function(Object?) fromJsonT) =
      _$SpotubeBrowseSectionObjectImpl<T>.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  String get externalUri;
  @override
  bool get browseMore;
  @override
  List<T> get items;

  /// Create a copy of SpotubeBrowseSectionObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeBrowseSectionObjectImplCopyWith<T,
          _$SpotubeBrowseSectionObjectImpl<T>>
      get copyWith => throw _privateConstructorUsedError;
}

MetadataFormFieldObject _$MetadataFormFieldObjectFromJson(
    Map<String, dynamic> json) {
  switch (json['objectType']) {
    case 'input':
      return MetadataFormFieldInputObject.fromJson(json);
    case 'text':
      return MetadataFormFieldTextObject.fromJson(json);

    default:
      throw CheckedFromJsonException(
          json,
          'objectType',
          'MetadataFormFieldObject',
          'Invalid union type "${json['objectType']}"!');
  }
}

/// @nodoc
mixin _$MetadataFormFieldObject {
  String get objectType => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)
        input,
    required TResult Function(String objectType, String text) text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult? Function(String objectType, String text)? text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult Function(String objectType, String text)? text,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MetadataFormFieldInputObject value) input,
    required TResult Function(MetadataFormFieldTextObject value) text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MetadataFormFieldInputObject value)? input,
    TResult? Function(MetadataFormFieldTextObject value)? text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MetadataFormFieldInputObject value)? input,
    TResult Function(MetadataFormFieldTextObject value)? text,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this MetadataFormFieldObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MetadataFormFieldObjectCopyWith<MetadataFormFieldObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MetadataFormFieldObjectCopyWith<$Res> {
  factory $MetadataFormFieldObjectCopyWith(MetadataFormFieldObject value,
          $Res Function(MetadataFormFieldObject) then) =
      _$MetadataFormFieldObjectCopyWithImpl<$Res, MetadataFormFieldObject>;
  @useResult
  $Res call({String objectType});
}

/// @nodoc
class _$MetadataFormFieldObjectCopyWithImpl<$Res,
        $Val extends MetadataFormFieldObject>
    implements $MetadataFormFieldObjectCopyWith<$Res> {
  _$MetadataFormFieldObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? objectType = null,
  }) {
    return _then(_value.copyWith(
      objectType: null == objectType
          ? _value.objectType
          : objectType // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MetadataFormFieldInputObjectImplCopyWith<$Res>
    implements $MetadataFormFieldObjectCopyWith<$Res> {
  factory _$$MetadataFormFieldInputObjectImplCopyWith(
          _$MetadataFormFieldInputObjectImpl value,
          $Res Function(_$MetadataFormFieldInputObjectImpl) then) =
      __$$MetadataFormFieldInputObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String objectType,
      String id,
      FormFieldVariant variant,
      String? placeholder,
      String? defaultValue,
      bool? required,
      String? regex});
}

/// @nodoc
class __$$MetadataFormFieldInputObjectImplCopyWithImpl<$Res>
    extends _$MetadataFormFieldObjectCopyWithImpl<$Res,
        _$MetadataFormFieldInputObjectImpl>
    implements _$$MetadataFormFieldInputObjectImplCopyWith<$Res> {
  __$$MetadataFormFieldInputObjectImplCopyWithImpl(
      _$MetadataFormFieldInputObjectImpl _value,
      $Res Function(_$MetadataFormFieldInputObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? objectType = null,
    Object? id = null,
    Object? variant = null,
    Object? placeholder = freezed,
    Object? defaultValue = freezed,
    Object? required = freezed,
    Object? regex = freezed,
  }) {
    return _then(_$MetadataFormFieldInputObjectImpl(
      objectType: null == objectType
          ? _value.objectType
          : objectType // ignore: cast_nullable_to_non_nullable
              as String,
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      variant: null == variant
          ? _value.variant
          : variant // ignore: cast_nullable_to_non_nullable
              as FormFieldVariant,
      placeholder: freezed == placeholder
          ? _value.placeholder
          : placeholder // ignore: cast_nullable_to_non_nullable
              as String?,
      defaultValue: freezed == defaultValue
          ? _value.defaultValue
          : defaultValue // ignore: cast_nullable_to_non_nullable
              as String?,
      required: freezed == required
          ? _value.required
          : required // ignore: cast_nullable_to_non_nullable
              as bool?,
      regex: freezed == regex
          ? _value.regex
          : regex // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MetadataFormFieldInputObjectImpl
    implements MetadataFormFieldInputObject {
  _$MetadataFormFieldInputObjectImpl(
      {required this.objectType,
      required this.id,
      this.variant = FormFieldVariant.text,
      this.placeholder,
      this.defaultValue,
      this.required,
      this.regex});

  factory _$MetadataFormFieldInputObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$MetadataFormFieldInputObjectImplFromJson(json);

  @override
  final String objectType;
  @override
  final String id;
  @override
  @JsonKey()
  final FormFieldVariant variant;
  @override
  final String? placeholder;
  @override
  final String? defaultValue;
  @override
  final bool? required;
  @override
  final String? regex;

  @override
  String toString() {
    return 'MetadataFormFieldObject.input(objectType: $objectType, id: $id, variant: $variant, placeholder: $placeholder, defaultValue: $defaultValue, required: $required, regex: $regex)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MetadataFormFieldInputObjectImpl &&
            (identical(other.objectType, objectType) ||
                other.objectType == objectType) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.variant, variant) || other.variant == variant) &&
            (identical(other.placeholder, placeholder) ||
                other.placeholder == placeholder) &&
            (identical(other.defaultValue, defaultValue) ||
                other.defaultValue == defaultValue) &&
            (identical(other.required, required) ||
                other.required == required) &&
            (identical(other.regex, regex) || other.regex == regex));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, objectType, id, variant,
      placeholder, defaultValue, required, regex);

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MetadataFormFieldInputObjectImplCopyWith<
          _$MetadataFormFieldInputObjectImpl>
      get copyWith => __$$MetadataFormFieldInputObjectImplCopyWithImpl<
          _$MetadataFormFieldInputObjectImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)
        input,
    required TResult Function(String objectType, String text) text,
  }) {
    return input(
        objectType, id, variant, placeholder, defaultValue, required, regex);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult? Function(String objectType, String text)? text,
  }) {
    return input?.call(
        objectType, id, variant, placeholder, defaultValue, required, regex);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult Function(String objectType, String text)? text,
    required TResult orElse(),
  }) {
    if (input != null) {
      return input(
          objectType, id, variant, placeholder, defaultValue, required, regex);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MetadataFormFieldInputObject value) input,
    required TResult Function(MetadataFormFieldTextObject value) text,
  }) {
    return input(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MetadataFormFieldInputObject value)? input,
    TResult? Function(MetadataFormFieldTextObject value)? text,
  }) {
    return input?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MetadataFormFieldInputObject value)? input,
    TResult Function(MetadataFormFieldTextObject value)? text,
    required TResult orElse(),
  }) {
    if (input != null) {
      return input(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MetadataFormFieldInputObjectImplToJson(
      this,
    );
  }
}

abstract class MetadataFormFieldInputObject implements MetadataFormFieldObject {
  factory MetadataFormFieldInputObject(
      {required final String objectType,
      required final String id,
      final FormFieldVariant variant,
      final String? placeholder,
      final String? defaultValue,
      final bool? required,
      final String? regex}) = _$MetadataFormFieldInputObjectImpl;

  factory MetadataFormFieldInputObject.fromJson(Map<String, dynamic> json) =
      _$MetadataFormFieldInputObjectImpl.fromJson;

  @override
  String get objectType;
  String get id;
  FormFieldVariant get variant;
  String? get placeholder;
  String? get defaultValue;
  bool? get required;
  String? get regex;

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MetadataFormFieldInputObjectImplCopyWith<
          _$MetadataFormFieldInputObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MetadataFormFieldTextObjectImplCopyWith<$Res>
    implements $MetadataFormFieldObjectCopyWith<$Res> {
  factory _$$MetadataFormFieldTextObjectImplCopyWith(
          _$MetadataFormFieldTextObjectImpl value,
          $Res Function(_$MetadataFormFieldTextObjectImpl) then) =
      __$$MetadataFormFieldTextObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String objectType, String text});
}

/// @nodoc
class __$$MetadataFormFieldTextObjectImplCopyWithImpl<$Res>
    extends _$MetadataFormFieldObjectCopyWithImpl<$Res,
        _$MetadataFormFieldTextObjectImpl>
    implements _$$MetadataFormFieldTextObjectImplCopyWith<$Res> {
  __$$MetadataFormFieldTextObjectImplCopyWithImpl(
      _$MetadataFormFieldTextObjectImpl _value,
      $Res Function(_$MetadataFormFieldTextObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? objectType = null,
    Object? text = null,
  }) {
    return _then(_$MetadataFormFieldTextObjectImpl(
      objectType: null == objectType
          ? _value.objectType
          : objectType // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MetadataFormFieldTextObjectImpl implements MetadataFormFieldTextObject {
  _$MetadataFormFieldTextObjectImpl(
      {required this.objectType, required this.text});

  factory _$MetadataFormFieldTextObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$MetadataFormFieldTextObjectImplFromJson(json);

  @override
  final String objectType;
  @override
  final String text;

  @override
  String toString() {
    return 'MetadataFormFieldObject.text(objectType: $objectType, text: $text)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MetadataFormFieldTextObjectImpl &&
            (identical(other.objectType, objectType) ||
                other.objectType == objectType) &&
            (identical(other.text, text) || other.text == text));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, objectType, text);

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MetadataFormFieldTextObjectImplCopyWith<_$MetadataFormFieldTextObjectImpl>
      get copyWith => __$$MetadataFormFieldTextObjectImplCopyWithImpl<
          _$MetadataFormFieldTextObjectImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)
        input,
    required TResult Function(String objectType, String text) text,
  }) {
    return text(objectType, this.text);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult? Function(String objectType, String text)? text,
  }) {
    return text?.call(objectType, this.text);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String objectType,
            String id,
            FormFieldVariant variant,
            String? placeholder,
            String? defaultValue,
            bool? required,
            String? regex)?
        input,
    TResult Function(String objectType, String text)? text,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(objectType, this.text);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MetadataFormFieldInputObject value) input,
    required TResult Function(MetadataFormFieldTextObject value) text,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MetadataFormFieldInputObject value)? input,
    TResult? Function(MetadataFormFieldTextObject value)? text,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MetadataFormFieldInputObject value)? input,
    TResult Function(MetadataFormFieldTextObject value)? text,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MetadataFormFieldTextObjectImplToJson(
      this,
    );
  }
}

abstract class MetadataFormFieldTextObject implements MetadataFormFieldObject {
  factory MetadataFormFieldTextObject(
      {required final String objectType,
      required final String text}) = _$MetadataFormFieldTextObjectImpl;

  factory MetadataFormFieldTextObject.fromJson(Map<String, dynamic> json) =
      _$MetadataFormFieldTextObjectImpl.fromJson;

  @override
  String get objectType;
  String get text;

  /// Create a copy of MetadataFormFieldObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MetadataFormFieldTextObjectImplCopyWith<_$MetadataFormFieldTextObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeImageObject _$SpotubeImageObjectFromJson(Map<String, dynamic> json) {
  return _SpotubeImageObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeImageObject {
  String get url => throw _privateConstructorUsedError;
  int? get width => throw _privateConstructorUsedError;
  int? get height => throw _privateConstructorUsedError;

  /// Serializes this SpotubeImageObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeImageObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeImageObjectCopyWith<SpotubeImageObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeImageObjectCopyWith<$Res> {
  factory $SpotubeImageObjectCopyWith(
          SpotubeImageObject value, $Res Function(SpotubeImageObject) then) =
      _$SpotubeImageObjectCopyWithImpl<$Res, SpotubeImageObject>;
  @useResult
  $Res call({String url, int? width, int? height});
}

/// @nodoc
class _$SpotubeImageObjectCopyWithImpl<$Res, $Val extends SpotubeImageObject>
    implements $SpotubeImageObjectCopyWith<$Res> {
  _$SpotubeImageObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeImageObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? width = freezed,
    Object? height = freezed,
  }) {
    return _then(_value.copyWith(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      width: freezed == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int?,
      height: freezed == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeImageObjectImplCopyWith<$Res>
    implements $SpotubeImageObjectCopyWith<$Res> {
  factory _$$SpotubeImageObjectImplCopyWith(_$SpotubeImageObjectImpl value,
          $Res Function(_$SpotubeImageObjectImpl) then) =
      __$$SpotubeImageObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String url, int? width, int? height});
}

/// @nodoc
class __$$SpotubeImageObjectImplCopyWithImpl<$Res>
    extends _$SpotubeImageObjectCopyWithImpl<$Res, _$SpotubeImageObjectImpl>
    implements _$$SpotubeImageObjectImplCopyWith<$Res> {
  __$$SpotubeImageObjectImplCopyWithImpl(_$SpotubeImageObjectImpl _value,
      $Res Function(_$SpotubeImageObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeImageObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? width = freezed,
    Object? height = freezed,
  }) {
    return _then(_$SpotubeImageObjectImpl(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      width: freezed == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int?,
      height: freezed == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeImageObjectImpl implements _SpotubeImageObject {
  _$SpotubeImageObjectImpl({required this.url, this.width, this.height});

  factory _$SpotubeImageObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeImageObjectImplFromJson(json);

  @override
  final String url;
  @override
  final int? width;
  @override
  final int? height;

  @override
  String toString() {
    return 'SpotubeImageObject(url: $url, width: $width, height: $height)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeImageObjectImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, url, width, height);

  /// Create a copy of SpotubeImageObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeImageObjectImplCopyWith<_$SpotubeImageObjectImpl> get copyWith =>
      __$$SpotubeImageObjectImplCopyWithImpl<_$SpotubeImageObjectImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeImageObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeImageObject implements SpotubeImageObject {
  factory _SpotubeImageObject(
      {required final String url,
      final int? width,
      final int? height}) = _$SpotubeImageObjectImpl;

  factory _SpotubeImageObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeImageObjectImpl.fromJson;

  @override
  String get url;
  @override
  int? get width;
  @override
  int? get height;

  /// Create a copy of SpotubeImageObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeImageObjectImplCopyWith<_$SpotubeImageObjectImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SpotubePaginationResponseObject<T> _$SpotubePaginationResponseObjectFromJson<T>(
    Map<String, dynamic> json, T Function(Object?) fromJsonT) {
  return _SpotubePaginationResponseObject<T>.fromJson(json, fromJsonT);
}

/// @nodoc
mixin _$SpotubePaginationResponseObject<T> {
  int get limit => throw _privateConstructorUsedError;
  int? get nextOffset => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;
  bool get hasMore => throw _privateConstructorUsedError;
  List<T> get items => throw _privateConstructorUsedError;

  /// Serializes this SpotubePaginationResponseObject to a JSON map.
  Map<String, dynamic> toJson(Object? Function(T) toJsonT) =>
      throw _privateConstructorUsedError;

  /// Create a copy of SpotubePaginationResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubePaginationResponseObjectCopyWith<T,
          SpotubePaginationResponseObject<T>>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubePaginationResponseObjectCopyWith<T, $Res> {
  factory $SpotubePaginationResponseObjectCopyWith(
          SpotubePaginationResponseObject<T> value,
          $Res Function(SpotubePaginationResponseObject<T>) then) =
      _$SpotubePaginationResponseObjectCopyWithImpl<T, $Res,
          SpotubePaginationResponseObject<T>>;
  @useResult
  $Res call(
      {int limit, int? nextOffset, int total, bool hasMore, List<T> items});
}

/// @nodoc
class _$SpotubePaginationResponseObjectCopyWithImpl<T, $Res,
        $Val extends SpotubePaginationResponseObject<T>>
    implements $SpotubePaginationResponseObjectCopyWith<T, $Res> {
  _$SpotubePaginationResponseObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubePaginationResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? limit = null,
    Object? nextOffset = freezed,
    Object? total = null,
    Object? hasMore = null,
    Object? items = null,
  }) {
    return _then(_value.copyWith(
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      nextOffset: freezed == nextOffset
          ? _value.nextOffset
          : nextOffset // ignore: cast_nullable_to_non_nullable
              as int?,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      hasMore: null == hasMore
          ? _value.hasMore
          : hasMore // ignore: cast_nullable_to_non_nullable
              as bool,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<T>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubePaginationResponseObjectImplCopyWith<T, $Res>
    implements $SpotubePaginationResponseObjectCopyWith<T, $Res> {
  factory _$$SpotubePaginationResponseObjectImplCopyWith(
          _$SpotubePaginationResponseObjectImpl<T> value,
          $Res Function(_$SpotubePaginationResponseObjectImpl<T>) then) =
      __$$SpotubePaginationResponseObjectImplCopyWithImpl<T, $Res>;
  @override
  @useResult
  $Res call(
      {int limit, int? nextOffset, int total, bool hasMore, List<T> items});
}

/// @nodoc
class __$$SpotubePaginationResponseObjectImplCopyWithImpl<T, $Res>
    extends _$SpotubePaginationResponseObjectCopyWithImpl<T, $Res,
        _$SpotubePaginationResponseObjectImpl<T>>
    implements _$$SpotubePaginationResponseObjectImplCopyWith<T, $Res> {
  __$$SpotubePaginationResponseObjectImplCopyWithImpl(
      _$SpotubePaginationResponseObjectImpl<T> _value,
      $Res Function(_$SpotubePaginationResponseObjectImpl<T>) _then)
      : super(_value, _then);

  /// Create a copy of SpotubePaginationResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? limit = null,
    Object? nextOffset = freezed,
    Object? total = null,
    Object? hasMore = null,
    Object? items = null,
  }) {
    return _then(_$SpotubePaginationResponseObjectImpl<T>(
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      nextOffset: freezed == nextOffset
          ? _value.nextOffset
          : nextOffset // ignore: cast_nullable_to_non_nullable
              as int?,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      hasMore: null == hasMore
          ? _value.hasMore
          : hasMore // ignore: cast_nullable_to_non_nullable
              as bool,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<T>,
    ));
  }
}

/// @nodoc
@JsonSerializable(genericArgumentFactories: true)
class _$SpotubePaginationResponseObjectImpl<T>
    implements _SpotubePaginationResponseObject<T> {
  _$SpotubePaginationResponseObjectImpl(
      {required this.limit,
      required this.nextOffset,
      required this.total,
      required this.hasMore,
      required final List<T> items})
      : _items = items;

  factory _$SpotubePaginationResponseObjectImpl.fromJson(
          Map<String, dynamic> json, T Function(Object?) fromJsonT) =>
      _$$SpotubePaginationResponseObjectImplFromJson(json, fromJsonT);

  @override
  final int limit;
  @override
  final int? nextOffset;
  @override
  final int total;
  @override
  final bool hasMore;
  final List<T> _items;
  @override
  List<T> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString() {
    return 'SpotubePaginationResponseObject<$T>(limit: $limit, nextOffset: $nextOffset, total: $total, hasMore: $hasMore, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubePaginationResponseObjectImpl<T> &&
            (identical(other.limit, limit) || other.limit == limit) &&
            (identical(other.nextOffset, nextOffset) ||
                other.nextOffset == nextOffset) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.hasMore, hasMore) || other.hasMore == hasMore) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, limit, nextOffset, total,
      hasMore, const DeepCollectionEquality().hash(_items));

  /// Create a copy of SpotubePaginationResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubePaginationResponseObjectImplCopyWith<T,
          _$SpotubePaginationResponseObjectImpl<T>>
      get copyWith => __$$SpotubePaginationResponseObjectImplCopyWithImpl<T,
          _$SpotubePaginationResponseObjectImpl<T>>(this, _$identity);

  @override
  Map<String, dynamic> toJson(Object? Function(T) toJsonT) {
    return _$$SpotubePaginationResponseObjectImplToJson<T>(this, toJsonT);
  }
}

abstract class _SpotubePaginationResponseObject<T>
    implements SpotubePaginationResponseObject<T> {
  factory _SpotubePaginationResponseObject(
      {required final int limit,
      required final int? nextOffset,
      required final int total,
      required final bool hasMore,
      required final List<T> items}) = _$SpotubePaginationResponseObjectImpl<T>;

  factory _SpotubePaginationResponseObject.fromJson(
          Map<String, dynamic> json, T Function(Object?) fromJsonT) =
      _$SpotubePaginationResponseObjectImpl<T>.fromJson;

  @override
  int get limit;
  @override
  int? get nextOffset;
  @override
  int get total;
  @override
  bool get hasMore;
  @override
  List<T> get items;

  /// Create a copy of SpotubePaginationResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubePaginationResponseObjectImplCopyWith<T,
          _$SpotubePaginationResponseObjectImpl<T>>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeFullPlaylistObject _$SpotubeFullPlaylistObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeFullPlaylistObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeFullPlaylistObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  SpotubeUserObject get owner => throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;
  List<SpotubeUserObject> get collaborators =>
      throw _privateConstructorUsedError;
  bool get collaborative => throw _privateConstructorUsedError;
  bool get public => throw _privateConstructorUsedError;

  /// Serializes this SpotubeFullPlaylistObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeFullPlaylistObjectCopyWith<SpotubeFullPlaylistObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeFullPlaylistObjectCopyWith<$Res> {
  factory $SpotubeFullPlaylistObjectCopyWith(SpotubeFullPlaylistObject value,
          $Res Function(SpotubeFullPlaylistObject) then) =
      _$SpotubeFullPlaylistObjectCopyWithImpl<$Res, SpotubeFullPlaylistObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String externalUri,
      SpotubeUserObject owner,
      List<SpotubeImageObject> images,
      List<SpotubeUserObject> collaborators,
      bool collaborative,
      bool public});

  $SpotubeUserObjectCopyWith<$Res> get owner;
}

/// @nodoc
class _$SpotubeFullPlaylistObjectCopyWithImpl<$Res,
        $Val extends SpotubeFullPlaylistObject>
    implements $SpotubeFullPlaylistObjectCopyWith<$Res> {
  _$SpotubeFullPlaylistObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? externalUri = null,
    Object? owner = null,
    Object? images = null,
    Object? collaborators = null,
    Object? collaborative = null,
    Object? public = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as SpotubeUserObject,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      collaborators: null == collaborators
          ? _value.collaborators
          : collaborators // ignore: cast_nullable_to_non_nullable
              as List<SpotubeUserObject>,
      collaborative: null == collaborative
          ? _value.collaborative
          : collaborative // ignore: cast_nullable_to_non_nullable
              as bool,
      public: null == public
          ? _value.public
          : public // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SpotubeUserObjectCopyWith<$Res> get owner {
    return $SpotubeUserObjectCopyWith<$Res>(_value.owner, (value) {
      return _then(_value.copyWith(owner: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SpotubeFullPlaylistObjectImplCopyWith<$Res>
    implements $SpotubeFullPlaylistObjectCopyWith<$Res> {
  factory _$$SpotubeFullPlaylistObjectImplCopyWith(
          _$SpotubeFullPlaylistObjectImpl value,
          $Res Function(_$SpotubeFullPlaylistObjectImpl) then) =
      __$$SpotubeFullPlaylistObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String externalUri,
      SpotubeUserObject owner,
      List<SpotubeImageObject> images,
      List<SpotubeUserObject> collaborators,
      bool collaborative,
      bool public});

  @override
  $SpotubeUserObjectCopyWith<$Res> get owner;
}

/// @nodoc
class __$$SpotubeFullPlaylistObjectImplCopyWithImpl<$Res>
    extends _$SpotubeFullPlaylistObjectCopyWithImpl<$Res,
        _$SpotubeFullPlaylistObjectImpl>
    implements _$$SpotubeFullPlaylistObjectImplCopyWith<$Res> {
  __$$SpotubeFullPlaylistObjectImplCopyWithImpl(
      _$SpotubeFullPlaylistObjectImpl _value,
      $Res Function(_$SpotubeFullPlaylistObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? externalUri = null,
    Object? owner = null,
    Object? images = null,
    Object? collaborators = null,
    Object? collaborative = null,
    Object? public = null,
  }) {
    return _then(_$SpotubeFullPlaylistObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as SpotubeUserObject,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      collaborators: null == collaborators
          ? _value._collaborators
          : collaborators // ignore: cast_nullable_to_non_nullable
              as List<SpotubeUserObject>,
      collaborative: null == collaborative
          ? _value.collaborative
          : collaborative // ignore: cast_nullable_to_non_nullable
              as bool,
      public: null == public
          ? _value.public
          : public // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeFullPlaylistObjectImpl implements _SpotubeFullPlaylistObject {
  _$SpotubeFullPlaylistObjectImpl(
      {required this.id,
      required this.name,
      required this.description,
      required this.externalUri,
      required this.owner,
      final List<SpotubeImageObject> images = const [],
      final List<SpotubeUserObject> collaborators = const [],
      this.collaborative = false,
      this.public = false})
      : _images = images,
        _collaborators = collaborators;

  factory _$SpotubeFullPlaylistObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeFullPlaylistObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String description;
  @override
  final String externalUri;
  @override
  final SpotubeUserObject owner;
  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  final List<SpotubeUserObject> _collaborators;
  @override
  @JsonKey()
  List<SpotubeUserObject> get collaborators {
    if (_collaborators is EqualUnmodifiableListView) return _collaborators;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_collaborators);
  }

  @override
  @JsonKey()
  final bool collaborative;
  @override
  @JsonKey()
  final bool public;

  @override
  String toString() {
    return 'SpotubeFullPlaylistObject(id: $id, name: $name, description: $description, externalUri: $externalUri, owner: $owner, images: $images, collaborators: $collaborators, collaborative: $collaborative, public: $public)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeFullPlaylistObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            (identical(other.owner, owner) || other.owner == owner) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            const DeepCollectionEquality()
                .equals(other._collaborators, _collaborators) &&
            (identical(other.collaborative, collaborative) ||
                other.collaborative == collaborative) &&
            (identical(other.public, public) || other.public == public));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      externalUri,
      owner,
      const DeepCollectionEquality().hash(_images),
      const DeepCollectionEquality().hash(_collaborators),
      collaborative,
      public);

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeFullPlaylistObjectImplCopyWith<_$SpotubeFullPlaylistObjectImpl>
      get copyWith => __$$SpotubeFullPlaylistObjectImplCopyWithImpl<
          _$SpotubeFullPlaylistObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeFullPlaylistObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeFullPlaylistObject implements SpotubeFullPlaylistObject {
  factory _SpotubeFullPlaylistObject(
      {required final String id,
      required final String name,
      required final String description,
      required final String externalUri,
      required final SpotubeUserObject owner,
      final List<SpotubeImageObject> images,
      final List<SpotubeUserObject> collaborators,
      final bool collaborative,
      final bool public}) = _$SpotubeFullPlaylistObjectImpl;

  factory _SpotubeFullPlaylistObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeFullPlaylistObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override
  String get externalUri;
  @override
  SpotubeUserObject get owner;
  @override
  List<SpotubeImageObject> get images;
  @override
  List<SpotubeUserObject> get collaborators;
  @override
  bool get collaborative;
  @override
  bool get public;

  /// Create a copy of SpotubeFullPlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeFullPlaylistObjectImplCopyWith<_$SpotubeFullPlaylistObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeSimplePlaylistObject _$SpotubeSimplePlaylistObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeSimplePlaylistObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeSimplePlaylistObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  SpotubeUserObject get owner => throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;

  /// Serializes this SpotubeSimplePlaylistObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeSimplePlaylistObjectCopyWith<SpotubeSimplePlaylistObject>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeSimplePlaylistObjectCopyWith<$Res> {
  factory $SpotubeSimplePlaylistObjectCopyWith(
          SpotubeSimplePlaylistObject value,
          $Res Function(SpotubeSimplePlaylistObject) then) =
      _$SpotubeSimplePlaylistObjectCopyWithImpl<$Res,
          SpotubeSimplePlaylistObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String externalUri,
      SpotubeUserObject owner,
      List<SpotubeImageObject> images});

  $SpotubeUserObjectCopyWith<$Res> get owner;
}

/// @nodoc
class _$SpotubeSimplePlaylistObjectCopyWithImpl<$Res,
        $Val extends SpotubeSimplePlaylistObject>
    implements $SpotubeSimplePlaylistObjectCopyWith<$Res> {
  _$SpotubeSimplePlaylistObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? externalUri = null,
    Object? owner = null,
    Object? images = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as SpotubeUserObject,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
    ) as $Val);
  }

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SpotubeUserObjectCopyWith<$Res> get owner {
    return $SpotubeUserObjectCopyWith<$Res>(_value.owner, (value) {
      return _then(_value.copyWith(owner: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SpotubeSimplePlaylistObjectImplCopyWith<$Res>
    implements $SpotubeSimplePlaylistObjectCopyWith<$Res> {
  factory _$$SpotubeSimplePlaylistObjectImplCopyWith(
          _$SpotubeSimplePlaylistObjectImpl value,
          $Res Function(_$SpotubeSimplePlaylistObjectImpl) then) =
      __$$SpotubeSimplePlaylistObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String externalUri,
      SpotubeUserObject owner,
      List<SpotubeImageObject> images});

  @override
  $SpotubeUserObjectCopyWith<$Res> get owner;
}

/// @nodoc
class __$$SpotubeSimplePlaylistObjectImplCopyWithImpl<$Res>
    extends _$SpotubeSimplePlaylistObjectCopyWithImpl<$Res,
        _$SpotubeSimplePlaylistObjectImpl>
    implements _$$SpotubeSimplePlaylistObjectImplCopyWith<$Res> {
  __$$SpotubeSimplePlaylistObjectImplCopyWithImpl(
      _$SpotubeSimplePlaylistObjectImpl _value,
      $Res Function(_$SpotubeSimplePlaylistObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? externalUri = null,
    Object? owner = null,
    Object? images = null,
  }) {
    return _then(_$SpotubeSimplePlaylistObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as SpotubeUserObject,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeSimplePlaylistObjectImpl
    implements _SpotubeSimplePlaylistObject {
  _$SpotubeSimplePlaylistObjectImpl(
      {required this.id,
      required this.name,
      required this.description,
      required this.externalUri,
      required this.owner,
      final List<SpotubeImageObject> images = const []})
      : _images = images;

  factory _$SpotubeSimplePlaylistObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeSimplePlaylistObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String description;
  @override
  final String externalUri;
  @override
  final SpotubeUserObject owner;
  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  String toString() {
    return 'SpotubeSimplePlaylistObject(id: $id, name: $name, description: $description, externalUri: $externalUri, owner: $owner, images: $images)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeSimplePlaylistObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            (identical(other.owner, owner) || other.owner == owner) &&
            const DeepCollectionEquality().equals(other._images, _images));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, description,
      externalUri, owner, const DeepCollectionEquality().hash(_images));

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeSimplePlaylistObjectImplCopyWith<_$SpotubeSimplePlaylistObjectImpl>
      get copyWith => __$$SpotubeSimplePlaylistObjectImplCopyWithImpl<
          _$SpotubeSimplePlaylistObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeSimplePlaylistObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeSimplePlaylistObject
    implements SpotubeSimplePlaylistObject {
  factory _SpotubeSimplePlaylistObject(
          {required final String id,
          required final String name,
          required final String description,
          required final String externalUri,
          required final SpotubeUserObject owner,
          final List<SpotubeImageObject> images}) =
      _$SpotubeSimplePlaylistObjectImpl;

  factory _SpotubeSimplePlaylistObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeSimplePlaylistObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override
  String get externalUri;
  @override
  SpotubeUserObject get owner;
  @override
  List<SpotubeImageObject> get images;

  /// Create a copy of SpotubeSimplePlaylistObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeSimplePlaylistObjectImplCopyWith<_$SpotubeSimplePlaylistObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeSearchResponseObject _$SpotubeSearchResponseObjectFromJson(
    Map<String, dynamic> json) {
  return _SpotubeSearchResponseObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeSearchResponseObject {
  List<SpotubeSimpleAlbumObject> get albums =>
      throw _privateConstructorUsedError;
  List<SpotubeFullArtistObject> get artists =>
      throw _privateConstructorUsedError;
  List<SpotubeSimplePlaylistObject> get playlists =>
      throw _privateConstructorUsedError;
  List<SpotubeFullTrackObject> get tracks => throw _privateConstructorUsedError;

  /// Serializes this SpotubeSearchResponseObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeSearchResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeSearchResponseObjectCopyWith<SpotubeSearchResponseObject>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeSearchResponseObjectCopyWith<$Res> {
  factory $SpotubeSearchResponseObjectCopyWith(
          SpotubeSearchResponseObject value,
          $Res Function(SpotubeSearchResponseObject) then) =
      _$SpotubeSearchResponseObjectCopyWithImpl<$Res,
          SpotubeSearchResponseObject>;
  @useResult
  $Res call(
      {List<SpotubeSimpleAlbumObject> albums,
      List<SpotubeFullArtistObject> artists,
      List<SpotubeSimplePlaylistObject> playlists,
      List<SpotubeFullTrackObject> tracks});
}

/// @nodoc
class _$SpotubeSearchResponseObjectCopyWithImpl<$Res,
        $Val extends SpotubeSearchResponseObject>
    implements $SpotubeSearchResponseObjectCopyWith<$Res> {
  _$SpotubeSearchResponseObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeSearchResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? albums = null,
    Object? artists = null,
    Object? playlists = null,
    Object? tracks = null,
  }) {
    return _then(_value.copyWith(
      albums: null == albums
          ? _value.albums
          : albums // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleAlbumObject>,
      artists: null == artists
          ? _value.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeFullArtistObject>,
      playlists: null == playlists
          ? _value.playlists
          : playlists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimplePlaylistObject>,
      tracks: null == tracks
          ? _value.tracks
          : tracks // ignore: cast_nullable_to_non_nullable
              as List<SpotubeFullTrackObject>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeSearchResponseObjectImplCopyWith<$Res>
    implements $SpotubeSearchResponseObjectCopyWith<$Res> {
  factory _$$SpotubeSearchResponseObjectImplCopyWith(
          _$SpotubeSearchResponseObjectImpl value,
          $Res Function(_$SpotubeSearchResponseObjectImpl) then) =
      __$$SpotubeSearchResponseObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<SpotubeSimpleAlbumObject> albums,
      List<SpotubeFullArtistObject> artists,
      List<SpotubeSimplePlaylistObject> playlists,
      List<SpotubeFullTrackObject> tracks});
}

/// @nodoc
class __$$SpotubeSearchResponseObjectImplCopyWithImpl<$Res>
    extends _$SpotubeSearchResponseObjectCopyWithImpl<$Res,
        _$SpotubeSearchResponseObjectImpl>
    implements _$$SpotubeSearchResponseObjectImplCopyWith<$Res> {
  __$$SpotubeSearchResponseObjectImplCopyWithImpl(
      _$SpotubeSearchResponseObjectImpl _value,
      $Res Function(_$SpotubeSearchResponseObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeSearchResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? albums = null,
    Object? artists = null,
    Object? playlists = null,
    Object? tracks = null,
  }) {
    return _then(_$SpotubeSearchResponseObjectImpl(
      albums: null == albums
          ? _value._albums
          : albums // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleAlbumObject>,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeFullArtistObject>,
      playlists: null == playlists
          ? _value._playlists
          : playlists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimplePlaylistObject>,
      tracks: null == tracks
          ? _value._tracks
          : tracks // ignore: cast_nullable_to_non_nullable
              as List<SpotubeFullTrackObject>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeSearchResponseObjectImpl
    implements _SpotubeSearchResponseObject {
  _$SpotubeSearchResponseObjectImpl(
      {required final List<SpotubeSimpleAlbumObject> albums,
      required final List<SpotubeFullArtistObject> artists,
      required final List<SpotubeSimplePlaylistObject> playlists,
      required final List<SpotubeFullTrackObject> tracks})
      : _albums = albums,
        _artists = artists,
        _playlists = playlists,
        _tracks = tracks;

  factory _$SpotubeSearchResponseObjectImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$SpotubeSearchResponseObjectImplFromJson(json);

  final List<SpotubeSimpleAlbumObject> _albums;
  @override
  List<SpotubeSimpleAlbumObject> get albums {
    if (_albums is EqualUnmodifiableListView) return _albums;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_albums);
  }

  final List<SpotubeFullArtistObject> _artists;
  @override
  List<SpotubeFullArtistObject> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  final List<SpotubeSimplePlaylistObject> _playlists;
  @override
  List<SpotubeSimplePlaylistObject> get playlists {
    if (_playlists is EqualUnmodifiableListView) return _playlists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_playlists);
  }

  final List<SpotubeFullTrackObject> _tracks;
  @override
  List<SpotubeFullTrackObject> get tracks {
    if (_tracks is EqualUnmodifiableListView) return _tracks;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tracks);
  }

  @override
  String toString() {
    return 'SpotubeSearchResponseObject(albums: $albums, artists: $artists, playlists: $playlists, tracks: $tracks)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeSearchResponseObjectImpl &&
            const DeepCollectionEquality().equals(other._albums, _albums) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            const DeepCollectionEquality()
                .equals(other._playlists, _playlists) &&
            const DeepCollectionEquality().equals(other._tracks, _tracks));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_albums),
      const DeepCollectionEquality().hash(_artists),
      const DeepCollectionEquality().hash(_playlists),
      const DeepCollectionEquality().hash(_tracks));

  /// Create a copy of SpotubeSearchResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeSearchResponseObjectImplCopyWith<_$SpotubeSearchResponseObjectImpl>
      get copyWith => __$$SpotubeSearchResponseObjectImplCopyWithImpl<
          _$SpotubeSearchResponseObjectImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeSearchResponseObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeSearchResponseObject
    implements SpotubeSearchResponseObject {
  factory _SpotubeSearchResponseObject(
          {required final List<SpotubeSimpleAlbumObject> albums,
          required final List<SpotubeFullArtistObject> artists,
          required final List<SpotubeSimplePlaylistObject> playlists,
          required final List<SpotubeFullTrackObject> tracks}) =
      _$SpotubeSearchResponseObjectImpl;

  factory _SpotubeSearchResponseObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeSearchResponseObjectImpl.fromJson;

  @override
  List<SpotubeSimpleAlbumObject> get albums;
  @override
  List<SpotubeFullArtistObject> get artists;
  @override
  List<SpotubeSimplePlaylistObject> get playlists;
  @override
  List<SpotubeFullTrackObject> get tracks;

  /// Create a copy of SpotubeSearchResponseObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeSearchResponseObjectImplCopyWith<_$SpotubeSearchResponseObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeTrackObject _$SpotubeTrackObjectFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'local':
      return SpotubeLocalTrackObject.fromJson(json);
    case 'full':
      return SpotubeFullTrackObject.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'SpotubeTrackObject',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$SpotubeTrackObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;
  List<SpotubeSimpleArtistObject> get artists =>
      throw _privateConstructorUsedError;
  SpotubeSimpleAlbumObject get album => throw _privateConstructorUsedError;
  int get durationMs => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)
        local,
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)
        full,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeLocalTrackObject value) local,
    required TResult Function(SpotubeFullTrackObject value) full,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeLocalTrackObject value)? local,
    TResult? Function(SpotubeFullTrackObject value)? full,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeLocalTrackObject value)? local,
    TResult Function(SpotubeFullTrackObject value)? full,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this SpotubeTrackObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeTrackObjectCopyWith<SpotubeTrackObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeTrackObjectCopyWith<$Res> {
  factory $SpotubeTrackObjectCopyWith(
          SpotubeTrackObject value, $Res Function(SpotubeTrackObject) then) =
      _$SpotubeTrackObjectCopyWithImpl<$Res, SpotubeTrackObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeSimpleArtistObject> artists,
      SpotubeSimpleAlbumObject album,
      int durationMs});

  $SpotubeSimpleAlbumObjectCopyWith<$Res> get album;
}

/// @nodoc
class _$SpotubeTrackObjectCopyWithImpl<$Res, $Val extends SpotubeTrackObject>
    implements $SpotubeTrackObjectCopyWith<$Res> {
  _$SpotubeTrackObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? artists = null,
    Object? album = null,
    Object? durationMs = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      album: null == album
          ? _value.album
          : album // ignore: cast_nullable_to_non_nullable
              as SpotubeSimpleAlbumObject,
      durationMs: null == durationMs
          ? _value.durationMs
          : durationMs // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SpotubeSimpleAlbumObjectCopyWith<$Res> get album {
    return $SpotubeSimpleAlbumObjectCopyWith<$Res>(_value.album, (value) {
      return _then(_value.copyWith(album: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SpotubeLocalTrackObjectImplCopyWith<$Res>
    implements $SpotubeTrackObjectCopyWith<$Res> {
  factory _$$SpotubeLocalTrackObjectImplCopyWith(
          _$SpotubeLocalTrackObjectImpl value,
          $Res Function(_$SpotubeLocalTrackObjectImpl) then) =
      __$$SpotubeLocalTrackObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeSimpleArtistObject> artists,
      SpotubeSimpleAlbumObject album,
      int durationMs,
      String path});

  @override
  $SpotubeSimpleAlbumObjectCopyWith<$Res> get album;
}

/// @nodoc
class __$$SpotubeLocalTrackObjectImplCopyWithImpl<$Res>
    extends _$SpotubeTrackObjectCopyWithImpl<$Res,
        _$SpotubeLocalTrackObjectImpl>
    implements _$$SpotubeLocalTrackObjectImplCopyWith<$Res> {
  __$$SpotubeLocalTrackObjectImplCopyWithImpl(
      _$SpotubeLocalTrackObjectImpl _value,
      $Res Function(_$SpotubeLocalTrackObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? artists = null,
    Object? album = null,
    Object? durationMs = null,
    Object? path = null,
  }) {
    return _then(_$SpotubeLocalTrackObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      album: null == album
          ? _value.album
          : album // ignore: cast_nullable_to_non_nullable
              as SpotubeSimpleAlbumObject,
      durationMs: null == durationMs
          ? _value.durationMs
          : durationMs // ignore: cast_nullable_to_non_nullable
              as int,
      path: null == path
          ? _value.path
          : path // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeLocalTrackObjectImpl implements SpotubeLocalTrackObject {
  _$SpotubeLocalTrackObjectImpl(
      {required this.id,
      required this.name,
      required this.externalUri,
      final List<SpotubeSimpleArtistObject> artists = const [],
      required this.album,
      required this.durationMs,
      required this.path,
      final String? $type})
      : _artists = artists,
        $type = $type ?? 'local';

  factory _$SpotubeLocalTrackObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeLocalTrackObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String externalUri;
  final List<SpotubeSimpleArtistObject> _artists;
  @override
  @JsonKey()
  List<SpotubeSimpleArtistObject> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  @override
  final SpotubeSimpleAlbumObject album;
  @override
  final int durationMs;
  @override
  final String path;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'SpotubeTrackObject.local(id: $id, name: $name, externalUri: $externalUri, artists: $artists, album: $album, durationMs: $durationMs, path: $path)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeLocalTrackObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            (identical(other.album, album) || other.album == album) &&
            (identical(other.durationMs, durationMs) ||
                other.durationMs == durationMs) &&
            (identical(other.path, path) || other.path == path));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, externalUri,
      const DeepCollectionEquality().hash(_artists), album, durationMs, path);

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeLocalTrackObjectImplCopyWith<_$SpotubeLocalTrackObjectImpl>
      get copyWith => __$$SpotubeLocalTrackObjectImplCopyWithImpl<
          _$SpotubeLocalTrackObjectImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)
        local,
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)
        full,
  }) {
    return local(id, name, externalUri, artists, album, durationMs, path);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
  }) {
    return local?.call(id, name, externalUri, artists, album, durationMs, path);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
    required TResult orElse(),
  }) {
    if (local != null) {
      return local(id, name, externalUri, artists, album, durationMs, path);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeLocalTrackObject value) local,
    required TResult Function(SpotubeFullTrackObject value) full,
  }) {
    return local(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeLocalTrackObject value)? local,
    TResult? Function(SpotubeFullTrackObject value)? full,
  }) {
    return local?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeLocalTrackObject value)? local,
    TResult Function(SpotubeFullTrackObject value)? full,
    required TResult orElse(),
  }) {
    if (local != null) {
      return local(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeLocalTrackObjectImplToJson(
      this,
    );
  }
}

abstract class SpotubeLocalTrackObject implements SpotubeTrackObject {
  factory SpotubeLocalTrackObject(
      {required final String id,
      required final String name,
      required final String externalUri,
      final List<SpotubeSimpleArtistObject> artists,
      required final SpotubeSimpleAlbumObject album,
      required final int durationMs,
      required final String path}) = _$SpotubeLocalTrackObjectImpl;

  factory SpotubeLocalTrackObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeLocalTrackObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get externalUri;
  @override
  List<SpotubeSimpleArtistObject> get artists;
  @override
  SpotubeSimpleAlbumObject get album;
  @override
  int get durationMs;
  String get path;

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeLocalTrackObjectImplCopyWith<_$SpotubeLocalTrackObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SpotubeFullTrackObjectImplCopyWith<$Res>
    implements $SpotubeTrackObjectCopyWith<$Res> {
  factory _$$SpotubeFullTrackObjectImplCopyWith(
          _$SpotubeFullTrackObjectImpl value,
          $Res Function(_$SpotubeFullTrackObjectImpl) then) =
      __$$SpotubeFullTrackObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String externalUri,
      List<SpotubeSimpleArtistObject> artists,
      SpotubeSimpleAlbumObject album,
      int durationMs,
      String isrc,
      bool explicit});

  @override
  $SpotubeSimpleAlbumObjectCopyWith<$Res> get album;
}

/// @nodoc
class __$$SpotubeFullTrackObjectImplCopyWithImpl<$Res>
    extends _$SpotubeTrackObjectCopyWithImpl<$Res, _$SpotubeFullTrackObjectImpl>
    implements _$$SpotubeFullTrackObjectImplCopyWith<$Res> {
  __$$SpotubeFullTrackObjectImplCopyWithImpl(
      _$SpotubeFullTrackObjectImpl _value,
      $Res Function(_$SpotubeFullTrackObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? externalUri = null,
    Object? artists = null,
    Object? album = null,
    Object? durationMs = null,
    Object? isrc = null,
    Object? explicit = null,
  }) {
    return _then(_$SpotubeFullTrackObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
      artists: null == artists
          ? _value._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<SpotubeSimpleArtistObject>,
      album: null == album
          ? _value.album
          : album // ignore: cast_nullable_to_non_nullable
              as SpotubeSimpleAlbumObject,
      durationMs: null == durationMs
          ? _value.durationMs
          : durationMs // ignore: cast_nullable_to_non_nullable
              as int,
      isrc: null == isrc
          ? _value.isrc
          : isrc // ignore: cast_nullable_to_non_nullable
              as String,
      explicit: null == explicit
          ? _value.explicit
          : explicit // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeFullTrackObjectImpl implements SpotubeFullTrackObject {
  _$SpotubeFullTrackObjectImpl(
      {required this.id,
      required this.name,
      required this.externalUri,
      final List<SpotubeSimpleArtistObject> artists = const [],
      required this.album,
      required this.durationMs,
      required this.isrc,
      required this.explicit,
      final String? $type})
      : _artists = artists,
        $type = $type ?? 'full';

  factory _$SpotubeFullTrackObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeFullTrackObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String externalUri;
  final List<SpotubeSimpleArtistObject> _artists;
  @override
  @JsonKey()
  List<SpotubeSimpleArtistObject> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  @override
  final SpotubeSimpleAlbumObject album;
  @override
  final int durationMs;
  @override
  final String isrc;
  @override
  final bool explicit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'SpotubeTrackObject.full(id: $id, name: $name, externalUri: $externalUri, artists: $artists, album: $album, durationMs: $durationMs, isrc: $isrc, explicit: $explicit)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeFullTrackObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri) &&
            const DeepCollectionEquality().equals(other._artists, _artists) &&
            (identical(other.album, album) || other.album == album) &&
            (identical(other.durationMs, durationMs) ||
                other.durationMs == durationMs) &&
            (identical(other.isrc, isrc) || other.isrc == isrc) &&
            (identical(other.explicit, explicit) ||
                other.explicit == explicit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      externalUri,
      const DeepCollectionEquality().hash(_artists),
      album,
      durationMs,
      isrc,
      explicit);

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeFullTrackObjectImplCopyWith<_$SpotubeFullTrackObjectImpl>
      get copyWith => __$$SpotubeFullTrackObjectImplCopyWithImpl<
          _$SpotubeFullTrackObjectImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)
        local,
    required TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)
        full,
  }) {
    return full(
        id, name, externalUri, artists, album, durationMs, isrc, explicit);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult? Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
  }) {
    return full?.call(
        id, name, externalUri, artists, album, durationMs, isrc, explicit);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String path)?
        local,
    TResult Function(
            String id,
            String name,
            String externalUri,
            List<SpotubeSimpleArtistObject> artists,
            SpotubeSimpleAlbumObject album,
            int durationMs,
            String isrc,
            bool explicit)?
        full,
    required TResult orElse(),
  }) {
    if (full != null) {
      return full(
          id, name, externalUri, artists, album, durationMs, isrc, explicit);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SpotubeLocalTrackObject value) local,
    required TResult Function(SpotubeFullTrackObject value) full,
  }) {
    return full(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SpotubeLocalTrackObject value)? local,
    TResult? Function(SpotubeFullTrackObject value)? full,
  }) {
    return full?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SpotubeLocalTrackObject value)? local,
    TResult Function(SpotubeFullTrackObject value)? full,
    required TResult orElse(),
  }) {
    if (full != null) {
      return full(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeFullTrackObjectImplToJson(
      this,
    );
  }
}

abstract class SpotubeFullTrackObject implements SpotubeTrackObject {
  factory SpotubeFullTrackObject(
      {required final String id,
      required final String name,
      required final String externalUri,
      final List<SpotubeSimpleArtistObject> artists,
      required final SpotubeSimpleAlbumObject album,
      required final int durationMs,
      required final String isrc,
      required final bool explicit}) = _$SpotubeFullTrackObjectImpl;

  factory SpotubeFullTrackObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeFullTrackObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get externalUri;
  @override
  List<SpotubeSimpleArtistObject> get artists;
  @override
  SpotubeSimpleAlbumObject get album;
  @override
  int get durationMs;
  String get isrc;
  bool get explicit;

  /// Create a copy of SpotubeTrackObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeFullTrackObjectImplCopyWith<_$SpotubeFullTrackObjectImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SpotubeUserObject _$SpotubeUserObjectFromJson(Map<String, dynamic> json) {
  return _SpotubeUserObject.fromJson(json);
}

/// @nodoc
mixin _$SpotubeUserObject {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  List<SpotubeImageObject> get images => throw _privateConstructorUsedError;
  String get externalUri => throw _privateConstructorUsedError;

  /// Serializes this SpotubeUserObject to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SpotubeUserObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpotubeUserObjectCopyWith<SpotubeUserObject> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpotubeUserObjectCopyWith<$Res> {
  factory $SpotubeUserObjectCopyWith(
          SpotubeUserObject value, $Res Function(SpotubeUserObject) then) =
      _$SpotubeUserObjectCopyWithImpl<$Res, SpotubeUserObject>;
  @useResult
  $Res call(
      {String id,
      String name,
      List<SpotubeImageObject> images,
      String externalUri});
}

/// @nodoc
class _$SpotubeUserObjectCopyWithImpl<$Res, $Val extends SpotubeUserObject>
    implements $SpotubeUserObjectCopyWith<$Res> {
  _$SpotubeUserObjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpotubeUserObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? images = null,
    Object? externalUri = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SpotubeUserObjectImplCopyWith<$Res>
    implements $SpotubeUserObjectCopyWith<$Res> {
  factory _$$SpotubeUserObjectImplCopyWith(_$SpotubeUserObjectImpl value,
          $Res Function(_$SpotubeUserObjectImpl) then) =
      __$$SpotubeUserObjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      List<SpotubeImageObject> images,
      String externalUri});
}

/// @nodoc
class __$$SpotubeUserObjectImplCopyWithImpl<$Res>
    extends _$SpotubeUserObjectCopyWithImpl<$Res, _$SpotubeUserObjectImpl>
    implements _$$SpotubeUserObjectImplCopyWith<$Res> {
  __$$SpotubeUserObjectImplCopyWithImpl(_$SpotubeUserObjectImpl _value,
      $Res Function(_$SpotubeUserObjectImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpotubeUserObject
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? images = null,
    Object? externalUri = null,
  }) {
    return _then(_$SpotubeUserObjectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<SpotubeImageObject>,
      externalUri: null == externalUri
          ? _value.externalUri
          : externalUri // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SpotubeUserObjectImpl implements _SpotubeUserObject {
  _$SpotubeUserObjectImpl(
      {required this.id,
      required this.name,
      final List<SpotubeImageObject> images = const [],
      required this.externalUri})
      : _images = images;

  factory _$SpotubeUserObjectImpl.fromJson(Map<String, dynamic> json) =>
      _$$SpotubeUserObjectImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  final List<SpotubeImageObject> _images;
  @override
  @JsonKey()
  List<SpotubeImageObject> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  final String externalUri;

  @override
  String toString() {
    return 'SpotubeUserObject(id: $id, name: $name, images: $images, externalUri: $externalUri)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpotubeUserObjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.externalUri, externalUri) ||
                other.externalUri == externalUri));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name,
      const DeepCollectionEquality().hash(_images), externalUri);

  /// Create a copy of SpotubeUserObject
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpotubeUserObjectImplCopyWith<_$SpotubeUserObjectImpl> get copyWith =>
      __$$SpotubeUserObjectImplCopyWithImpl<_$SpotubeUserObjectImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SpotubeUserObjectImplToJson(
      this,
    );
  }
}

abstract class _SpotubeUserObject implements SpotubeUserObject {
  factory _SpotubeUserObject(
      {required final String id,
      required final String name,
      final List<SpotubeImageObject> images,
      required final String externalUri}) = _$SpotubeUserObjectImpl;

  factory _SpotubeUserObject.fromJson(Map<String, dynamic> json) =
      _$SpotubeUserObjectImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  List<SpotubeImageObject> get images;
  @override
  String get externalUri;

  /// Create a copy of SpotubeUserObject
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpotubeUserObjectImplCopyWith<_$SpotubeUserObjectImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PluginConfiguration _$PluginConfigurationFromJson(Map<String, dynamic> json) {
  return _PluginConfiguration.fromJson(json);
}

/// @nodoc
mixin _$PluginConfiguration {
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String get version => throw _privateConstructorUsedError;
  String get author => throw _privateConstructorUsedError;
  String get entryPoint => throw _privateConstructorUsedError;
  String get pluginApiVersion => throw _privateConstructorUsedError;
  List<PluginApis> get apis => throw _privateConstructorUsedError;
  List<PluginAbilities> get abilities => throw _privateConstructorUsedError;
  String? get repository => throw _privateConstructorUsedError;

  /// Serializes this PluginConfiguration to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PluginConfiguration
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PluginConfigurationCopyWith<PluginConfiguration> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PluginConfigurationCopyWith<$Res> {
  factory $PluginConfigurationCopyWith(
          PluginConfiguration value, $Res Function(PluginConfiguration) then) =
      _$PluginConfigurationCopyWithImpl<$Res, PluginConfiguration>;
  @useResult
  $Res call(
      {String name,
      String description,
      String version,
      String author,
      String entryPoint,
      String pluginApiVersion,
      List<PluginApis> apis,
      List<PluginAbilities> abilities,
      String? repository});
}

/// @nodoc
class _$PluginConfigurationCopyWithImpl<$Res, $Val extends PluginConfiguration>
    implements $PluginConfigurationCopyWith<$Res> {
  _$PluginConfigurationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PluginConfiguration
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? description = null,
    Object? version = null,
    Object? author = null,
    Object? entryPoint = null,
    Object? pluginApiVersion = null,
    Object? apis = null,
    Object? abilities = null,
    Object? repository = freezed,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      author: null == author
          ? _value.author
          : author // ignore: cast_nullable_to_non_nullable
              as String,
      entryPoint: null == entryPoint
          ? _value.entryPoint
          : entryPoint // ignore: cast_nullable_to_non_nullable
              as String,
      pluginApiVersion: null == pluginApiVersion
          ? _value.pluginApiVersion
          : pluginApiVersion // ignore: cast_nullable_to_non_nullable
              as String,
      apis: null == apis
          ? _value.apis
          : apis // ignore: cast_nullable_to_non_nullable
              as List<PluginApis>,
      abilities: null == abilities
          ? _value.abilities
          : abilities // ignore: cast_nullable_to_non_nullable
              as List<PluginAbilities>,
      repository: freezed == repository
          ? _value.repository
          : repository // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PluginConfigurationImplCopyWith<$Res>
    implements $PluginConfigurationCopyWith<$Res> {
  factory _$$PluginConfigurationImplCopyWith(_$PluginConfigurationImpl value,
          $Res Function(_$PluginConfigurationImpl) then) =
      __$$PluginConfigurationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      String description,
      String version,
      String author,
      String entryPoint,
      String pluginApiVersion,
      List<PluginApis> apis,
      List<PluginAbilities> abilities,
      String? repository});
}

/// @nodoc
class __$$PluginConfigurationImplCopyWithImpl<$Res>
    extends _$PluginConfigurationCopyWithImpl<$Res, _$PluginConfigurationImpl>
    implements _$$PluginConfigurationImplCopyWith<$Res> {
  __$$PluginConfigurationImplCopyWithImpl(_$PluginConfigurationImpl _value,
      $Res Function(_$PluginConfigurationImpl) _then)
      : super(_value, _then);

  /// Create a copy of PluginConfiguration
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? description = null,
    Object? version = null,
    Object? author = null,
    Object? entryPoint = null,
    Object? pluginApiVersion = null,
    Object? apis = null,
    Object? abilities = null,
    Object? repository = freezed,
  }) {
    return _then(_$PluginConfigurationImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      author: null == author
          ? _value.author
          : author // ignore: cast_nullable_to_non_nullable
              as String,
      entryPoint: null == entryPoint
          ? _value.entryPoint
          : entryPoint // ignore: cast_nullable_to_non_nullable
              as String,
      pluginApiVersion: null == pluginApiVersion
          ? _value.pluginApiVersion
          : pluginApiVersion // ignore: cast_nullable_to_non_nullable
              as String,
      apis: null == apis
          ? _value._apis
          : apis // ignore: cast_nullable_to_non_nullable
              as List<PluginApis>,
      abilities: null == abilities
          ? _value._abilities
          : abilities // ignore: cast_nullable_to_non_nullable
              as List<PluginAbilities>,
      repository: freezed == repository
          ? _value.repository
          : repository // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PluginConfigurationImpl extends _PluginConfiguration {
  _$PluginConfigurationImpl(
      {required this.name,
      required this.description,
      required this.version,
      required this.author,
      required this.entryPoint,
      required this.pluginApiVersion,
      final List<PluginApis> apis = const [],
      final List<PluginAbilities> abilities = const [],
      this.repository})
      : _apis = apis,
        _abilities = abilities,
        super._();

  factory _$PluginConfigurationImpl.fromJson(Map<String, dynamic> json) =>
      _$$PluginConfigurationImplFromJson(json);

  @override
  final String name;
  @override
  final String description;
  @override
  final String version;
  @override
  final String author;
  @override
  final String entryPoint;
  @override
  final String pluginApiVersion;
  final List<PluginApis> _apis;
  @override
  @JsonKey()
  List<PluginApis> get apis {
    if (_apis is EqualUnmodifiableListView) return _apis;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_apis);
  }

  final List<PluginAbilities> _abilities;
  @override
  @JsonKey()
  List<PluginAbilities> get abilities {
    if (_abilities is EqualUnmodifiableListView) return _abilities;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_abilities);
  }

  @override
  final String? repository;

  @override
  String toString() {
    return 'PluginConfiguration(name: $name, description: $description, version: $version, author: $author, entryPoint: $entryPoint, pluginApiVersion: $pluginApiVersion, apis: $apis, abilities: $abilities, repository: $repository)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PluginConfigurationImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.version, version) || other.version == version) &&
            (identical(other.author, author) || other.author == author) &&
            (identical(other.entryPoint, entryPoint) ||
                other.entryPoint == entryPoint) &&
            (identical(other.pluginApiVersion, pluginApiVersion) ||
                other.pluginApiVersion == pluginApiVersion) &&
            const DeepCollectionEquality().equals(other._apis, _apis) &&
            const DeepCollectionEquality()
                .equals(other._abilities, _abilities) &&
            (identical(other.repository, repository) ||
                other.repository == repository));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      name,
      description,
      version,
      author,
      entryPoint,
      pluginApiVersion,
      const DeepCollectionEquality().hash(_apis),
      const DeepCollectionEquality().hash(_abilities),
      repository);

  /// Create a copy of PluginConfiguration
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PluginConfigurationImplCopyWith<_$PluginConfigurationImpl> get copyWith =>
      __$$PluginConfigurationImplCopyWithImpl<_$PluginConfigurationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PluginConfigurationImplToJson(
      this,
    );
  }
}

abstract class _PluginConfiguration extends PluginConfiguration {
  factory _PluginConfiguration(
      {required final String name,
      required final String description,
      required final String version,
      required final String author,
      required final String entryPoint,
      required final String pluginApiVersion,
      final List<PluginApis> apis,
      final List<PluginAbilities> abilities,
      final String? repository}) = _$PluginConfigurationImpl;
  _PluginConfiguration._() : super._();

  factory _PluginConfiguration.fromJson(Map<String, dynamic> json) =
      _$PluginConfigurationImpl.fromJson;

  @override
  String get name;
  @override
  String get description;
  @override
  String get version;
  @override
  String get author;
  @override
  String get entryPoint;
  @override
  String get pluginApiVersion;
  @override
  List<PluginApis> get apis;
  @override
  List<PluginAbilities> get abilities;
  @override
  String? get repository;

  /// Create a copy of PluginConfiguration
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PluginConfigurationImplCopyWith<_$PluginConfigurationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PluginUpdateAvailable _$PluginUpdateAvailableFromJson(
    Map<String, dynamic> json) {
  return _PluginUpdateAvailable.fromJson(json);
}

/// @nodoc
mixin _$PluginUpdateAvailable {
  String get downloadUrl => throw _privateConstructorUsedError;
  String get version => throw _privateConstructorUsedError;
  String? get changelog => throw _privateConstructorUsedError;

  /// Serializes this PluginUpdateAvailable to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PluginUpdateAvailable
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PluginUpdateAvailableCopyWith<PluginUpdateAvailable> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PluginUpdateAvailableCopyWith<$Res> {
  factory $PluginUpdateAvailableCopyWith(PluginUpdateAvailable value,
          $Res Function(PluginUpdateAvailable) then) =
      _$PluginUpdateAvailableCopyWithImpl<$Res, PluginUpdateAvailable>;
  @useResult
  $Res call({String downloadUrl, String version, String? changelog});
}

/// @nodoc
class _$PluginUpdateAvailableCopyWithImpl<$Res,
        $Val extends PluginUpdateAvailable>
    implements $PluginUpdateAvailableCopyWith<$Res> {
  _$PluginUpdateAvailableCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PluginUpdateAvailable
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? downloadUrl = null,
    Object? version = null,
    Object? changelog = freezed,
  }) {
    return _then(_value.copyWith(
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      changelog: freezed == changelog
          ? _value.changelog
          : changelog // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PluginUpdateAvailableImplCopyWith<$Res>
    implements $PluginUpdateAvailableCopyWith<$Res> {
  factory _$$PluginUpdateAvailableImplCopyWith(
          _$PluginUpdateAvailableImpl value,
          $Res Function(_$PluginUpdateAvailableImpl) then) =
      __$$PluginUpdateAvailableImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String downloadUrl, String version, String? changelog});
}

/// @nodoc
class __$$PluginUpdateAvailableImplCopyWithImpl<$Res>
    extends _$PluginUpdateAvailableCopyWithImpl<$Res,
        _$PluginUpdateAvailableImpl>
    implements _$$PluginUpdateAvailableImplCopyWith<$Res> {
  __$$PluginUpdateAvailableImplCopyWithImpl(_$PluginUpdateAvailableImpl _value,
      $Res Function(_$PluginUpdateAvailableImpl) _then)
      : super(_value, _then);

  /// Create a copy of PluginUpdateAvailable
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? downloadUrl = null,
    Object? version = null,
    Object? changelog = freezed,
  }) {
    return _then(_$PluginUpdateAvailableImpl(
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      changelog: freezed == changelog
          ? _value.changelog
          : changelog // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PluginUpdateAvailableImpl implements _PluginUpdateAvailable {
  _$PluginUpdateAvailableImpl(
      {required this.downloadUrl, required this.version, this.changelog});

  factory _$PluginUpdateAvailableImpl.fromJson(Map<String, dynamic> json) =>
      _$$PluginUpdateAvailableImplFromJson(json);

  @override
  final String downloadUrl;
  @override
  final String version;
  @override
  final String? changelog;

  @override
  String toString() {
    return 'PluginUpdateAvailable(downloadUrl: $downloadUrl, version: $version, changelog: $changelog)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PluginUpdateAvailableImpl &&
            (identical(other.downloadUrl, downloadUrl) ||
                other.downloadUrl == downloadUrl) &&
            (identical(other.version, version) || other.version == version) &&
            (identical(other.changelog, changelog) ||
                other.changelog == changelog));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, downloadUrl, version, changelog);

  /// Create a copy of PluginUpdateAvailable
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PluginUpdateAvailableImplCopyWith<_$PluginUpdateAvailableImpl>
      get copyWith => __$$PluginUpdateAvailableImplCopyWithImpl<
          _$PluginUpdateAvailableImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PluginUpdateAvailableImplToJson(
      this,
    );
  }
}

abstract class _PluginUpdateAvailable implements PluginUpdateAvailable {
  factory _PluginUpdateAvailable(
      {required final String downloadUrl,
      required final String version,
      final String? changelog}) = _$PluginUpdateAvailableImpl;

  factory _PluginUpdateAvailable.fromJson(Map<String, dynamic> json) =
      _$PluginUpdateAvailableImpl.fromJson;

  @override
  String get downloadUrl;
  @override
  String get version;
  @override
  String? get changelog;

  /// Create a copy of PluginUpdateAvailable
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PluginUpdateAvailableImplCopyWith<_$PluginUpdateAvailableImpl>
      get copyWith => throw _privateConstructorUsedError;
}

MetadataPluginRepository _$MetadataPluginRepositoryFromJson(
    Map<String, dynamic> json) {
  return _MetadataPluginRepository.fromJson(json);
}

/// @nodoc
mixin _$MetadataPluginRepository {
  String get name => throw _privateConstructorUsedError;
  String get owner => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String get repoUrl => throw _privateConstructorUsedError;
  List<String> get topics => throw _privateConstructorUsedError;

  /// Serializes this MetadataPluginRepository to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MetadataPluginRepository
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MetadataPluginRepositoryCopyWith<MetadataPluginRepository> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MetadataPluginRepositoryCopyWith<$Res> {
  factory $MetadataPluginRepositoryCopyWith(MetadataPluginRepository value,
          $Res Function(MetadataPluginRepository) then) =
      _$MetadataPluginRepositoryCopyWithImpl<$Res, MetadataPluginRepository>;
  @useResult
  $Res call(
      {String name,
      String owner,
      String description,
      String repoUrl,
      List<String> topics});
}

/// @nodoc
class _$MetadataPluginRepositoryCopyWithImpl<$Res,
        $Val extends MetadataPluginRepository>
    implements $MetadataPluginRepositoryCopyWith<$Res> {
  _$MetadataPluginRepositoryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MetadataPluginRepository
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? owner = null,
    Object? description = null,
    Object? repoUrl = null,
    Object? topics = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      repoUrl: null == repoUrl
          ? _value.repoUrl
          : repoUrl // ignore: cast_nullable_to_non_nullable
              as String,
      topics: null == topics
          ? _value.topics
          : topics // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MetadataPluginRepositoryImplCopyWith<$Res>
    implements $MetadataPluginRepositoryCopyWith<$Res> {
  factory _$$MetadataPluginRepositoryImplCopyWith(
          _$MetadataPluginRepositoryImpl value,
          $Res Function(_$MetadataPluginRepositoryImpl) then) =
      __$$MetadataPluginRepositoryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      String owner,
      String description,
      String repoUrl,
      List<String> topics});
}

/// @nodoc
class __$$MetadataPluginRepositoryImplCopyWithImpl<$Res>
    extends _$MetadataPluginRepositoryCopyWithImpl<$Res,
        _$MetadataPluginRepositoryImpl>
    implements _$$MetadataPluginRepositoryImplCopyWith<$Res> {
  __$$MetadataPluginRepositoryImplCopyWithImpl(
      _$MetadataPluginRepositoryImpl _value,
      $Res Function(_$MetadataPluginRepositoryImpl) _then)
      : super(_value, _then);

  /// Create a copy of MetadataPluginRepository
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? owner = null,
    Object? description = null,
    Object? repoUrl = null,
    Object? topics = null,
  }) {
    return _then(_$MetadataPluginRepositoryImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      owner: null == owner
          ? _value.owner
          : owner // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      repoUrl: null == repoUrl
          ? _value.repoUrl
          : repoUrl // ignore: cast_nullable_to_non_nullable
              as String,
      topics: null == topics
          ? _value._topics
          : topics // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MetadataPluginRepositoryImpl implements _MetadataPluginRepository {
  _$MetadataPluginRepositoryImpl(
      {required this.name,
      required this.owner,
      required this.description,
      required this.repoUrl,
      required final List<String> topics})
      : _topics = topics;

  factory _$MetadataPluginRepositoryImpl.fromJson(Map<String, dynamic> json) =>
      _$$MetadataPluginRepositoryImplFromJson(json);

  @override
  final String name;
  @override
  final String owner;
  @override
  final String description;
  @override
  final String repoUrl;
  final List<String> _topics;
  @override
  List<String> get topics {
    if (_topics is EqualUnmodifiableListView) return _topics;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_topics);
  }

  @override
  String toString() {
    return 'MetadataPluginRepository(name: $name, owner: $owner, description: $description, repoUrl: $repoUrl, topics: $topics)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MetadataPluginRepositoryImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.owner, owner) || other.owner == owner) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.repoUrl, repoUrl) || other.repoUrl == repoUrl) &&
            const DeepCollectionEquality().equals(other._topics, _topics));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name, owner, description,
      repoUrl, const DeepCollectionEquality().hash(_topics));

  /// Create a copy of MetadataPluginRepository
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MetadataPluginRepositoryImplCopyWith<_$MetadataPluginRepositoryImpl>
      get copyWith => __$$MetadataPluginRepositoryImplCopyWithImpl<
          _$MetadataPluginRepositoryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MetadataPluginRepositoryImplToJson(
      this,
    );
  }
}

abstract class _MetadataPluginRepository implements MetadataPluginRepository {
  factory _MetadataPluginRepository(
      {required final String name,
      required final String owner,
      required final String description,
      required final String repoUrl,
      required final List<String> topics}) = _$MetadataPluginRepositoryImpl;

  factory _MetadataPluginRepository.fromJson(Map<String, dynamic> json) =
      _$MetadataPluginRepositoryImpl.fromJson;

  @override
  String get name;
  @override
  String get owner;
  @override
  String get description;
  @override
  String get repoUrl;
  @override
  List<String> get topics;

  /// Create a copy of MetadataPluginRepository
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MetadataPluginRepositoryImplCopyWith<_$MetadataPluginRepositoryImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ThemeDefinition _$ThemeDefinitionFromJson(Map<String, dynamic> json) {
  return _ThemeDefinition.fromJson(json);
}

/// @nodoc
mixin _$ThemeDefinition {
  /// The payload version this theme was written against.
  ///
  /// 2 is the contract the app read until the v3 blocks arrived; 3 adds
  /// the extra colour roles, the tokens, the component styles, the shell's
  /// composition, branding and the UI tree.
  ///
  /// The version describes the *payload*, not what the app can do: a host
  /// reads the fields it knows and ignores the rest, so a v3 theme still
  /// works on a v2 host (it draws as its two colour schemes there).
  int get specVersion => throw _privateConstructorUsedError;
  ThemeColors get light => throw _privateConstructorUsedError;
  ThemeColors get dark => throw _privateConstructorUsedError;
  ThemeSurfaces get surfaces => throw _privateConstructorUsedError;
  ThemeBackground get background => throw _privateConstructorUsedError;
  ThemeRadius get radius => throw _privateConstructorUsedError;
  double get density => throw _privateConstructorUsedError;
  ThemeTokens get tokens => throw _privateConstructorUsedError;
  ThemeLayout get layout => throw _privateConstructorUsedError;
  @JsonKey(name: 'dynamic')
  DynamicTheme? get dynamicTheme => throw _privateConstructorUsedError;

  /// The v3 presentation blocks. They stay as contract-owned maps at this
  /// layer, like UI nodes: the renderer reads the keys it knows and clamps
  /// every number it uses, so a newer theme can add a key without a host
  /// model change, and a malformed key cannot take the palette down.
  Map<String, dynamic> get typography => throw _privateConstructorUsedError;
  Map<String, dynamic> get spacing => throw _privateConstructorUsedError;
  Map<String, dynamic> get motion => throw _privateConstructorUsedError;
  Map<String, dynamic> get scale => throw _privateConstructorUsedError;
  Map<String, dynamic> get icons => throw _privateConstructorUsedError;
  Map<String, dynamic> get components => throw _privateConstructorUsedError;
  Map<String, dynamic> get branding => throw _privateConstructorUsedError;
  Map<String, dynamic> get assets => throw _privateConstructorUsedError;

  /// The declarative UI tree a theme may carry inline in `getTheme()`.
  ///
  /// A theme that answers from its optional `getUi()` method leaves this
  /// null; `themeUiProvider` asks the plugin and caches the result. A
  /// malformed tree is dropped here rather than taking the palette with
  /// it, so a broken screen cannot leave the user on the built-in theme.
  @JsonKey(fromJson: _themeUiFromJson)
  ThemeUiDocument? get ui => throw _privateConstructorUsedError;

  /// Serializes this ThemeDefinition to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeDefinitionCopyWith<ThemeDefinition> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeDefinitionCopyWith<$Res> {
  factory $ThemeDefinitionCopyWith(
          ThemeDefinition value, $Res Function(ThemeDefinition) then) =
      _$ThemeDefinitionCopyWithImpl<$Res, ThemeDefinition>;
  @useResult
  $Res call(
      {int specVersion,
      ThemeColors light,
      ThemeColors dark,
      ThemeSurfaces surfaces,
      ThemeBackground background,
      ThemeRadius radius,
      double density,
      ThemeTokens tokens,
      ThemeLayout layout,
      @JsonKey(name: 'dynamic') DynamicTheme? dynamicTheme,
      Map<String, dynamic> typography,
      Map<String, dynamic> spacing,
      Map<String, dynamic> motion,
      Map<String, dynamic> scale,
      Map<String, dynamic> icons,
      Map<String, dynamic> components,
      Map<String, dynamic> branding,
      Map<String, dynamic> assets,
      @JsonKey(fromJson: _themeUiFromJson) ThemeUiDocument? ui});

  $ThemeColorsCopyWith<$Res> get light;
  $ThemeColorsCopyWith<$Res> get dark;
  $ThemeSurfacesCopyWith<$Res> get surfaces;
  $ThemeBackgroundCopyWith<$Res> get background;
  $ThemeRadiusCopyWith<$Res> get radius;
  $ThemeTokensCopyWith<$Res> get tokens;
  $ThemeLayoutCopyWith<$Res> get layout;
  $DynamicThemeCopyWith<$Res>? get dynamicTheme;
  $ThemeUiDocumentCopyWith<$Res>? get ui;
}

/// @nodoc
class _$ThemeDefinitionCopyWithImpl<$Res, $Val extends ThemeDefinition>
    implements $ThemeDefinitionCopyWith<$Res> {
  _$ThemeDefinitionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? specVersion = null,
    Object? light = null,
    Object? dark = null,
    Object? surfaces = null,
    Object? background = null,
    Object? radius = null,
    Object? density = null,
    Object? tokens = null,
    Object? layout = null,
    Object? dynamicTheme = freezed,
    Object? typography = null,
    Object? spacing = null,
    Object? motion = null,
    Object? scale = null,
    Object? icons = null,
    Object? components = null,
    Object? branding = null,
    Object? assets = null,
    Object? ui = freezed,
  }) {
    return _then(_value.copyWith(
      specVersion: null == specVersion
          ? _value.specVersion
          : specVersion // ignore: cast_nullable_to_non_nullable
              as int,
      light: null == light
          ? _value.light
          : light // ignore: cast_nullable_to_non_nullable
              as ThemeColors,
      dark: null == dark
          ? _value.dark
          : dark // ignore: cast_nullable_to_non_nullable
              as ThemeColors,
      surfaces: null == surfaces
          ? _value.surfaces
          : surfaces // ignore: cast_nullable_to_non_nullable
              as ThemeSurfaces,
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as ThemeBackground,
      radius: null == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as ThemeRadius,
      density: null == density
          ? _value.density
          : density // ignore: cast_nullable_to_non_nullable
              as double,
      tokens: null == tokens
          ? _value.tokens
          : tokens // ignore: cast_nullable_to_non_nullable
              as ThemeTokens,
      layout: null == layout
          ? _value.layout
          : layout // ignore: cast_nullable_to_non_nullable
              as ThemeLayout,
      dynamicTheme: freezed == dynamicTheme
          ? _value.dynamicTheme
          : dynamicTheme // ignore: cast_nullable_to_non_nullable
              as DynamicTheme?,
      typography: null == typography
          ? _value.typography
          : typography // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      spacing: null == spacing
          ? _value.spacing
          : spacing // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      motion: null == motion
          ? _value.motion
          : motion // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      scale: null == scale
          ? _value.scale
          : scale // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      icons: null == icons
          ? _value.icons
          : icons // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      components: null == components
          ? _value.components
          : components // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      branding: null == branding
          ? _value.branding
          : branding // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      assets: null == assets
          ? _value.assets
          : assets // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      ui: freezed == ui
          ? _value.ui
          : ui // ignore: cast_nullable_to_non_nullable
              as ThemeUiDocument?,
    ) as $Val);
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeColorsCopyWith<$Res> get light {
    return $ThemeColorsCopyWith<$Res>(_value.light, (value) {
      return _then(_value.copyWith(light: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeColorsCopyWith<$Res> get dark {
    return $ThemeColorsCopyWith<$Res>(_value.dark, (value) {
      return _then(_value.copyWith(dark: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeSurfacesCopyWith<$Res> get surfaces {
    return $ThemeSurfacesCopyWith<$Res>(_value.surfaces, (value) {
      return _then(_value.copyWith(surfaces: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeBackgroundCopyWith<$Res> get background {
    return $ThemeBackgroundCopyWith<$Res>(_value.background, (value) {
      return _then(_value.copyWith(background: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeRadiusCopyWith<$Res> get radius {
    return $ThemeRadiusCopyWith<$Res>(_value.radius, (value) {
      return _then(_value.copyWith(radius: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeTokensCopyWith<$Res> get tokens {
    return $ThemeTokensCopyWith<$Res>(_value.tokens, (value) {
      return _then(_value.copyWith(tokens: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeLayoutCopyWith<$Res> get layout {
    return $ThemeLayoutCopyWith<$Res>(_value.layout, (value) {
      return _then(_value.copyWith(layout: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $DynamicThemeCopyWith<$Res>? get dynamicTheme {
    if (_value.dynamicTheme == null) {
      return null;
    }

    return $DynamicThemeCopyWith<$Res>(_value.dynamicTheme!, (value) {
      return _then(_value.copyWith(dynamicTheme: value) as $Val);
    });
  }

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemeUiDocumentCopyWith<$Res>? get ui {
    if (_value.ui == null) {
      return null;
    }

    return $ThemeUiDocumentCopyWith<$Res>(_value.ui!, (value) {
      return _then(_value.copyWith(ui: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ThemeDefinitionImplCopyWith<$Res>
    implements $ThemeDefinitionCopyWith<$Res> {
  factory _$$ThemeDefinitionImplCopyWith(_$ThemeDefinitionImpl value,
          $Res Function(_$ThemeDefinitionImpl) then) =
      __$$ThemeDefinitionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int specVersion,
      ThemeColors light,
      ThemeColors dark,
      ThemeSurfaces surfaces,
      ThemeBackground background,
      ThemeRadius radius,
      double density,
      ThemeTokens tokens,
      ThemeLayout layout,
      @JsonKey(name: 'dynamic') DynamicTheme? dynamicTheme,
      Map<String, dynamic> typography,
      Map<String, dynamic> spacing,
      Map<String, dynamic> motion,
      Map<String, dynamic> scale,
      Map<String, dynamic> icons,
      Map<String, dynamic> components,
      Map<String, dynamic> branding,
      Map<String, dynamic> assets,
      @JsonKey(fromJson: _themeUiFromJson) ThemeUiDocument? ui});

  @override
  $ThemeColorsCopyWith<$Res> get light;
  @override
  $ThemeColorsCopyWith<$Res> get dark;
  @override
  $ThemeSurfacesCopyWith<$Res> get surfaces;
  @override
  $ThemeBackgroundCopyWith<$Res> get background;
  @override
  $ThemeRadiusCopyWith<$Res> get radius;
  @override
  $ThemeTokensCopyWith<$Res> get tokens;
  @override
  $ThemeLayoutCopyWith<$Res> get layout;
  @override
  $DynamicThemeCopyWith<$Res>? get dynamicTheme;
  @override
  $ThemeUiDocumentCopyWith<$Res>? get ui;
}

/// @nodoc
class __$$ThemeDefinitionImplCopyWithImpl<$Res>
    extends _$ThemeDefinitionCopyWithImpl<$Res, _$ThemeDefinitionImpl>
    implements _$$ThemeDefinitionImplCopyWith<$Res> {
  __$$ThemeDefinitionImplCopyWithImpl(
      _$ThemeDefinitionImpl _value, $Res Function(_$ThemeDefinitionImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? specVersion = null,
    Object? light = null,
    Object? dark = null,
    Object? surfaces = null,
    Object? background = null,
    Object? radius = null,
    Object? density = null,
    Object? tokens = null,
    Object? layout = null,
    Object? dynamicTheme = freezed,
    Object? typography = null,
    Object? spacing = null,
    Object? motion = null,
    Object? scale = null,
    Object? icons = null,
    Object? components = null,
    Object? branding = null,
    Object? assets = null,
    Object? ui = freezed,
  }) {
    return _then(_$ThemeDefinitionImpl(
      specVersion: null == specVersion
          ? _value.specVersion
          : specVersion // ignore: cast_nullable_to_non_nullable
              as int,
      light: null == light
          ? _value.light
          : light // ignore: cast_nullable_to_non_nullable
              as ThemeColors,
      dark: null == dark
          ? _value.dark
          : dark // ignore: cast_nullable_to_non_nullable
              as ThemeColors,
      surfaces: null == surfaces
          ? _value.surfaces
          : surfaces // ignore: cast_nullable_to_non_nullable
              as ThemeSurfaces,
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as ThemeBackground,
      radius: null == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as ThemeRadius,
      density: null == density
          ? _value.density
          : density // ignore: cast_nullable_to_non_nullable
              as double,
      tokens: null == tokens
          ? _value.tokens
          : tokens // ignore: cast_nullable_to_non_nullable
              as ThemeTokens,
      layout: null == layout
          ? _value.layout
          : layout // ignore: cast_nullable_to_non_nullable
              as ThemeLayout,
      dynamicTheme: freezed == dynamicTheme
          ? _value.dynamicTheme
          : dynamicTheme // ignore: cast_nullable_to_non_nullable
              as DynamicTheme?,
      typography: null == typography
          ? _value._typography
          : typography // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      spacing: null == spacing
          ? _value._spacing
          : spacing // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      motion: null == motion
          ? _value._motion
          : motion // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      scale: null == scale
          ? _value._scale
          : scale // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      icons: null == icons
          ? _value._icons
          : icons // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      components: null == components
          ? _value._components
          : components // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      branding: null == branding
          ? _value._branding
          : branding // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      assets: null == assets
          ? _value._assets
          : assets // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      ui: freezed == ui
          ? _value.ui
          : ui // ignore: cast_nullable_to_non_nullable
              as ThemeUiDocument?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeDefinitionImpl implements _ThemeDefinition {
  const _$ThemeDefinitionImpl(
      {this.specVersion = 2,
      required this.light,
      required this.dark,
      this.surfaces = const ThemeSurfaces(),
      this.background = const ThemeBackground(),
      this.radius = const ThemeRadius(),
      this.density = 1.0,
      this.tokens = const ThemeTokens(),
      this.layout = const ThemeLayout(),
      @JsonKey(name: 'dynamic') this.dynamicTheme,
      final Map<String, dynamic> typography = const {},
      final Map<String, dynamic> spacing = const {},
      final Map<String, dynamic> motion = const {},
      final Map<String, dynamic> scale = const {},
      final Map<String, dynamic> icons = const {},
      final Map<String, dynamic> components = const {},
      final Map<String, dynamic> branding = const {},
      final Map<String, dynamic> assets = const {},
      @JsonKey(fromJson: _themeUiFromJson) this.ui})
      : _typography = typography,
        _spacing = spacing,
        _motion = motion,
        _scale = scale,
        _icons = icons,
        _components = components,
        _branding = branding,
        _assets = assets;

  factory _$ThemeDefinitionImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeDefinitionImplFromJson(json);

  /// The payload version this theme was written against.
  ///
  /// 2 is the contract the app read until the v3 blocks arrived; 3 adds
  /// the extra colour roles, the tokens, the component styles, the shell's
  /// composition, branding and the UI tree.
  ///
  /// The version describes the *payload*, not what the app can do: a host
  /// reads the fields it knows and ignores the rest, so a v3 theme still
  /// works on a v2 host (it draws as its two colour schemes there).
  @override
  @JsonKey()
  final int specVersion;
  @override
  final ThemeColors light;
  @override
  final ThemeColors dark;
  @override
  @JsonKey()
  final ThemeSurfaces surfaces;
  @override
  @JsonKey()
  final ThemeBackground background;
  @override
  @JsonKey()
  final ThemeRadius radius;
  @override
  @JsonKey()
  final double density;
  @override
  @JsonKey()
  final ThemeTokens tokens;
  @override
  @JsonKey()
  final ThemeLayout layout;
  @override
  @JsonKey(name: 'dynamic')
  final DynamicTheme? dynamicTheme;

  /// The v3 presentation blocks. They stay as contract-owned maps at this
  /// layer, like UI nodes: the renderer reads the keys it knows and clamps
  /// every number it uses, so a newer theme can add a key without a host
  /// model change, and a malformed key cannot take the palette down.
  final Map<String, dynamic> _typography;

  /// The v3 presentation blocks. They stay as contract-owned maps at this
  /// layer, like UI nodes: the renderer reads the keys it knows and clamps
  /// every number it uses, so a newer theme can add a key without a host
  /// model change, and a malformed key cannot take the palette down.
  @override
  @JsonKey()
  Map<String, dynamic> get typography {
    if (_typography is EqualUnmodifiableMapView) return _typography;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_typography);
  }

  final Map<String, dynamic> _spacing;
  @override
  @JsonKey()
  Map<String, dynamic> get spacing {
    if (_spacing is EqualUnmodifiableMapView) return _spacing;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_spacing);
  }

  final Map<String, dynamic> _motion;
  @override
  @JsonKey()
  Map<String, dynamic> get motion {
    if (_motion is EqualUnmodifiableMapView) return _motion;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_motion);
  }

  final Map<String, dynamic> _scale;
  @override
  @JsonKey()
  Map<String, dynamic> get scale {
    if (_scale is EqualUnmodifiableMapView) return _scale;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_scale);
  }

  final Map<String, dynamic> _icons;
  @override
  @JsonKey()
  Map<String, dynamic> get icons {
    if (_icons is EqualUnmodifiableMapView) return _icons;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_icons);
  }

  final Map<String, dynamic> _components;
  @override
  @JsonKey()
  Map<String, dynamic> get components {
    if (_components is EqualUnmodifiableMapView) return _components;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_components);
  }

  final Map<String, dynamic> _branding;
  @override
  @JsonKey()
  Map<String, dynamic> get branding {
    if (_branding is EqualUnmodifiableMapView) return _branding;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_branding);
  }

  final Map<String, dynamic> _assets;
  @override
  @JsonKey()
  Map<String, dynamic> get assets {
    if (_assets is EqualUnmodifiableMapView) return _assets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_assets);
  }

  /// The declarative UI tree a theme may carry inline in `getTheme()`.
  ///
  /// A theme that answers from its optional `getUi()` method leaves this
  /// null; `themeUiProvider` asks the plugin and caches the result. A
  /// malformed tree is dropped here rather than taking the palette with
  /// it, so a broken screen cannot leave the user on the built-in theme.
  @override
  @JsonKey(fromJson: _themeUiFromJson)
  final ThemeUiDocument? ui;

  @override
  String toString() {
    return 'ThemeDefinition(specVersion: $specVersion, light: $light, dark: $dark, surfaces: $surfaces, background: $background, radius: $radius, density: $density, tokens: $tokens, layout: $layout, dynamicTheme: $dynamicTheme, typography: $typography, spacing: $spacing, motion: $motion, scale: $scale, icons: $icons, components: $components, branding: $branding, assets: $assets, ui: $ui)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeDefinitionImpl &&
            (identical(other.specVersion, specVersion) ||
                other.specVersion == specVersion) &&
            (identical(other.light, light) || other.light == light) &&
            (identical(other.dark, dark) || other.dark == dark) &&
            (identical(other.surfaces, surfaces) ||
                other.surfaces == surfaces) &&
            (identical(other.background, background) ||
                other.background == background) &&
            (identical(other.radius, radius) || other.radius == radius) &&
            (identical(other.density, density) || other.density == density) &&
            (identical(other.tokens, tokens) || other.tokens == tokens) &&
            (identical(other.layout, layout) || other.layout == layout) &&
            (identical(other.dynamicTheme, dynamicTheme) ||
                other.dynamicTheme == dynamicTheme) &&
            const DeepCollectionEquality()
                .equals(other._typography, _typography) &&
            const DeepCollectionEquality().equals(other._spacing, _spacing) &&
            const DeepCollectionEquality().equals(other._motion, _motion) &&
            const DeepCollectionEquality().equals(other._scale, _scale) &&
            const DeepCollectionEquality().equals(other._icons, _icons) &&
            const DeepCollectionEquality()
                .equals(other._components, _components) &&
            const DeepCollectionEquality().equals(other._branding, _branding) &&
            const DeepCollectionEquality().equals(other._assets, _assets) &&
            (identical(other.ui, ui) || other.ui == ui));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        specVersion,
        light,
        dark,
        surfaces,
        background,
        radius,
        density,
        tokens,
        layout,
        dynamicTheme,
        const DeepCollectionEquality().hash(_typography),
        const DeepCollectionEquality().hash(_spacing),
        const DeepCollectionEquality().hash(_motion),
        const DeepCollectionEquality().hash(_scale),
        const DeepCollectionEquality().hash(_icons),
        const DeepCollectionEquality().hash(_components),
        const DeepCollectionEquality().hash(_branding),
        const DeepCollectionEquality().hash(_assets),
        ui
      ]);

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeDefinitionImplCopyWith<_$ThemeDefinitionImpl> get copyWith =>
      __$$ThemeDefinitionImplCopyWithImpl<_$ThemeDefinitionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeDefinitionImplToJson(
      this,
    );
  }
}

abstract class _ThemeDefinition implements ThemeDefinition {
  const factory _ThemeDefinition(
          {final int specVersion,
          required final ThemeColors light,
          required final ThemeColors dark,
          final ThemeSurfaces surfaces,
          final ThemeBackground background,
          final ThemeRadius radius,
          final double density,
          final ThemeTokens tokens,
          final ThemeLayout layout,
          @JsonKey(name: 'dynamic') final DynamicTheme? dynamicTheme,
          final Map<String, dynamic> typography,
          final Map<String, dynamic> spacing,
          final Map<String, dynamic> motion,
          final Map<String, dynamic> scale,
          final Map<String, dynamic> icons,
          final Map<String, dynamic> components,
          final Map<String, dynamic> branding,
          final Map<String, dynamic> assets,
          @JsonKey(fromJson: _themeUiFromJson) final ThemeUiDocument? ui}) =
      _$ThemeDefinitionImpl;

  factory _ThemeDefinition.fromJson(Map<String, dynamic> json) =
      _$ThemeDefinitionImpl.fromJson;

  /// The payload version this theme was written against.
  ///
  /// 2 is the contract the app read until the v3 blocks arrived; 3 adds
  /// the extra colour roles, the tokens, the component styles, the shell's
  /// composition, branding and the UI tree.
  ///
  /// The version describes the *payload*, not what the app can do: a host
  /// reads the fields it knows and ignores the rest, so a v3 theme still
  /// works on a v2 host (it draws as its two colour schemes there).
  @override
  int get specVersion;
  @override
  ThemeColors get light;
  @override
  ThemeColors get dark;
  @override
  ThemeSurfaces get surfaces;
  @override
  ThemeBackground get background;
  @override
  ThemeRadius get radius;
  @override
  double get density;
  @override
  ThemeTokens get tokens;
  @override
  ThemeLayout get layout;
  @override
  @JsonKey(name: 'dynamic')
  DynamicTheme? get dynamicTheme;

  /// The v3 presentation blocks. They stay as contract-owned maps at this
  /// layer, like UI nodes: the renderer reads the keys it knows and clamps
  /// every number it uses, so a newer theme can add a key without a host
  /// model change, and a malformed key cannot take the palette down.
  @override
  Map<String, dynamic> get typography;
  @override
  Map<String, dynamic> get spacing;
  @override
  Map<String, dynamic> get motion;
  @override
  Map<String, dynamic> get scale;
  @override
  Map<String, dynamic> get icons;
  @override
  Map<String, dynamic> get components;
  @override
  Map<String, dynamic> get branding;
  @override
  Map<String, dynamic> get assets;

  /// The declarative UI tree a theme may carry inline in `getTheme()`.
  ///
  /// A theme that answers from its optional `getUi()` method leaves this
  /// null; `themeUiProvider` asks the plugin and caches the result. A
  /// malformed tree is dropped here rather than taking the palette with
  /// it, so a broken screen cannot leave the user on the built-in theme.
  @override
  @JsonKey(fromJson: _themeUiFromJson)
  ThemeUiDocument? get ui;

  /// Create a copy of ThemeDefinition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeDefinitionImplCopyWith<_$ThemeDefinitionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeLayout _$ThemeLayoutFromJson(Map<String, dynamic> json) {
  return _ThemeLayout.fromJson(json);
}

/// @nodoc
mixin _$ThemeLayout {
  /// `inset` floats the page content in a rounded panel over a darkened
  /// backdrop, leaving the player bar full width on the backdrop.
  @JsonKey(unknownEnumValue: ThemeChrome.flat)
  ThemeChrome get chrome => throw _privateConstructorUsedError;

  /// `rail` keeps the navigation icon-only at every width instead of
  /// trading width for labels.
  @JsonKey(unknownEnumValue: ThemeNav.labels)
  ThemeNav get nav => throw _privateConstructorUsedError;

  /// `below` spans the seek bar across the full player width instead of
  /// docking it above the transport controls.
  @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
  ThemeProgress get progress => throw _privateConstructorUsedError;

  /// The player's own shape. `stage` makes the player the centre of the
  /// app (the theme fills `stage.center`/`stage.below`); the other values
  /// keep the host's footer player.
  ThemePlayerLayout get player => throw _privateConstructorUsedError;

  /// Layout fields the theme takes over even when the user chose otherwise.
  /// The host only acts on fields it understands.
  List<String> get enforce => throw _privateConstructorUsedError;

  /// The navigation entries and library entries the theme wants the host
  /// to show, in order. Kept raw so a theme can add a future entry without
  /// a model release; the host filters to the ids it implements.
  List<String> get navItems => throw _privateConstructorUsedError;
  List<String> get libraryItems => throw _privateConstructorUsedError;

  /// Home/settings section order and composition, as contract-owned maps.
  Map<String, dynamic> get home => throw _privateConstructorUsedError;
  Map<String, dynamic> get settings => throw _privateConstructorUsedError;

  /// Window title-bar geometry and back-control preference.
  Map<String, dynamic> get titlebar => throw _privateConstructorUsedError;

  /// Launch splash logo/text, resolved through the theme's own assets.
  Map<String, dynamic> get splash => throw _privateConstructorUsedError;

  /// Breakpoint-specific overrides (`compact`, `medium`, ...).
  Map<String, dynamic> get responsive => throw _privateConstructorUsedError;

  /// Serializes this ThemeLayout to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeLayoutCopyWith<ThemeLayout> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeLayoutCopyWith<$Res> {
  factory $ThemeLayoutCopyWith(
          ThemeLayout value, $Res Function(ThemeLayout) then) =
      _$ThemeLayoutCopyWithImpl<$Res, ThemeLayout>;
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemeChrome.flat) ThemeChrome chrome,
      @JsonKey(unknownEnumValue: ThemeNav.labels) ThemeNav nav,
      @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
      ThemeProgress progress,
      ThemePlayerLayout player,
      List<String> enforce,
      List<String> navItems,
      List<String> libraryItems,
      Map<String, dynamic> home,
      Map<String, dynamic> settings,
      Map<String, dynamic> titlebar,
      Map<String, dynamic> splash,
      Map<String, dynamic> responsive});

  $ThemePlayerLayoutCopyWith<$Res> get player;
}

/// @nodoc
class _$ThemeLayoutCopyWithImpl<$Res, $Val extends ThemeLayout>
    implements $ThemeLayoutCopyWith<$Res> {
  _$ThemeLayoutCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? chrome = null,
    Object? nav = null,
    Object? progress = null,
    Object? player = null,
    Object? enforce = null,
    Object? navItems = null,
    Object? libraryItems = null,
    Object? home = null,
    Object? settings = null,
    Object? titlebar = null,
    Object? splash = null,
    Object? responsive = null,
  }) {
    return _then(_value.copyWith(
      chrome: null == chrome
          ? _value.chrome
          : chrome // ignore: cast_nullable_to_non_nullable
              as ThemeChrome,
      nav: null == nav
          ? _value.nav
          : nav // ignore: cast_nullable_to_non_nullable
              as ThemeNav,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as ThemeProgress,
      player: null == player
          ? _value.player
          : player // ignore: cast_nullable_to_non_nullable
              as ThemePlayerLayout,
      enforce: null == enforce
          ? _value.enforce
          : enforce // ignore: cast_nullable_to_non_nullable
              as List<String>,
      navItems: null == navItems
          ? _value.navItems
          : navItems // ignore: cast_nullable_to_non_nullable
              as List<String>,
      libraryItems: null == libraryItems
          ? _value.libraryItems
          : libraryItems // ignore: cast_nullable_to_non_nullable
              as List<String>,
      home: null == home
          ? _value.home
          : home // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      settings: null == settings
          ? _value.settings
          : settings // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      titlebar: null == titlebar
          ? _value.titlebar
          : titlebar // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      splash: null == splash
          ? _value.splash
          : splash // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      responsive: null == responsive
          ? _value.responsive
          : responsive // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ) as $Val);
  }

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThemePlayerLayoutCopyWith<$Res> get player {
    return $ThemePlayerLayoutCopyWith<$Res>(_value.player, (value) {
      return _then(_value.copyWith(player: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ThemeLayoutImplCopyWith<$Res>
    implements $ThemeLayoutCopyWith<$Res> {
  factory _$$ThemeLayoutImplCopyWith(
          _$ThemeLayoutImpl value, $Res Function(_$ThemeLayoutImpl) then) =
      __$$ThemeLayoutImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemeChrome.flat) ThemeChrome chrome,
      @JsonKey(unknownEnumValue: ThemeNav.labels) ThemeNav nav,
      @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
      ThemeProgress progress,
      ThemePlayerLayout player,
      List<String> enforce,
      List<String> navItems,
      List<String> libraryItems,
      Map<String, dynamic> home,
      Map<String, dynamic> settings,
      Map<String, dynamic> titlebar,
      Map<String, dynamic> splash,
      Map<String, dynamic> responsive});

  @override
  $ThemePlayerLayoutCopyWith<$Res> get player;
}

/// @nodoc
class __$$ThemeLayoutImplCopyWithImpl<$Res>
    extends _$ThemeLayoutCopyWithImpl<$Res, _$ThemeLayoutImpl>
    implements _$$ThemeLayoutImplCopyWith<$Res> {
  __$$ThemeLayoutImplCopyWithImpl(
      _$ThemeLayoutImpl _value, $Res Function(_$ThemeLayoutImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? chrome = null,
    Object? nav = null,
    Object? progress = null,
    Object? player = null,
    Object? enforce = null,
    Object? navItems = null,
    Object? libraryItems = null,
    Object? home = null,
    Object? settings = null,
    Object? titlebar = null,
    Object? splash = null,
    Object? responsive = null,
  }) {
    return _then(_$ThemeLayoutImpl(
      chrome: null == chrome
          ? _value.chrome
          : chrome // ignore: cast_nullable_to_non_nullable
              as ThemeChrome,
      nav: null == nav
          ? _value.nav
          : nav // ignore: cast_nullable_to_non_nullable
              as ThemeNav,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as ThemeProgress,
      player: null == player
          ? _value.player
          : player // ignore: cast_nullable_to_non_nullable
              as ThemePlayerLayout,
      enforce: null == enforce
          ? _value._enforce
          : enforce // ignore: cast_nullable_to_non_nullable
              as List<String>,
      navItems: null == navItems
          ? _value._navItems
          : navItems // ignore: cast_nullable_to_non_nullable
              as List<String>,
      libraryItems: null == libraryItems
          ? _value._libraryItems
          : libraryItems // ignore: cast_nullable_to_non_nullable
              as List<String>,
      home: null == home
          ? _value._home
          : home // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      settings: null == settings
          ? _value._settings
          : settings // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      titlebar: null == titlebar
          ? _value._titlebar
          : titlebar // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      splash: null == splash
          ? _value._splash
          : splash // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      responsive: null == responsive
          ? _value._responsive
          : responsive // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeLayoutImpl implements _ThemeLayout {
  const _$ThemeLayoutImpl(
      {@JsonKey(unknownEnumValue: ThemeChrome.flat)
      this.chrome = ThemeChrome.flat,
      @JsonKey(unknownEnumValue: ThemeNav.labels) this.nav = ThemeNav.labels,
      @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
      this.progress = ThemeProgress.inlinePlacement,
      this.player = const ThemePlayerLayout(),
      final List<String> enforce = const [],
      final List<String> navItems = const [],
      final List<String> libraryItems = const [],
      final Map<String, dynamic> home = const {},
      final Map<String, dynamic> settings = const {},
      final Map<String, dynamic> titlebar = const {},
      final Map<String, dynamic> splash = const {},
      final Map<String, dynamic> responsive = const {}})
      : _enforce = enforce,
        _navItems = navItems,
        _libraryItems = libraryItems,
        _home = home,
        _settings = settings,
        _titlebar = titlebar,
        _splash = splash,
        _responsive = responsive;

  factory _$ThemeLayoutImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeLayoutImplFromJson(json);

  /// `inset` floats the page content in a rounded panel over a darkened
  /// backdrop, leaving the player bar full width on the backdrop.
  @override
  @JsonKey(unknownEnumValue: ThemeChrome.flat)
  final ThemeChrome chrome;

  /// `rail` keeps the navigation icon-only at every width instead of
  /// trading width for labels.
  @override
  @JsonKey(unknownEnumValue: ThemeNav.labels)
  final ThemeNav nav;

  /// `below` spans the seek bar across the full player width instead of
  /// docking it above the transport controls.
  @override
  @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
  final ThemeProgress progress;

  /// The player's own shape. `stage` makes the player the centre of the
  /// app (the theme fills `stage.center`/`stage.below`); the other values
  /// keep the host's footer player.
  @override
  @JsonKey()
  final ThemePlayerLayout player;

  /// Layout fields the theme takes over even when the user chose otherwise.
  /// The host only acts on fields it understands.
  final List<String> _enforce;

  /// Layout fields the theme takes over even when the user chose otherwise.
  /// The host only acts on fields it understands.
  @override
  @JsonKey()
  List<String> get enforce {
    if (_enforce is EqualUnmodifiableListView) return _enforce;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_enforce);
  }

  /// The navigation entries and library entries the theme wants the host
  /// to show, in order. Kept raw so a theme can add a future entry without
  /// a model release; the host filters to the ids it implements.
  final List<String> _navItems;

  /// The navigation entries and library entries the theme wants the host
  /// to show, in order. Kept raw so a theme can add a future entry without
  /// a model release; the host filters to the ids it implements.
  @override
  @JsonKey()
  List<String> get navItems {
    if (_navItems is EqualUnmodifiableListView) return _navItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_navItems);
  }

  final List<String> _libraryItems;
  @override
  @JsonKey()
  List<String> get libraryItems {
    if (_libraryItems is EqualUnmodifiableListView) return _libraryItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_libraryItems);
  }

  /// Home/settings section order and composition, as contract-owned maps.
  final Map<String, dynamic> _home;

  /// Home/settings section order and composition, as contract-owned maps.
  @override
  @JsonKey()
  Map<String, dynamic> get home {
    if (_home is EqualUnmodifiableMapView) return _home;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_home);
  }

  final Map<String, dynamic> _settings;
  @override
  @JsonKey()
  Map<String, dynamic> get settings {
    if (_settings is EqualUnmodifiableMapView) return _settings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_settings);
  }

  /// Window title-bar geometry and back-control preference.
  final Map<String, dynamic> _titlebar;

  /// Window title-bar geometry and back-control preference.
  @override
  @JsonKey()
  Map<String, dynamic> get titlebar {
    if (_titlebar is EqualUnmodifiableMapView) return _titlebar;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_titlebar);
  }

  /// Launch splash logo/text, resolved through the theme's own assets.
  final Map<String, dynamic> _splash;

  /// Launch splash logo/text, resolved through the theme's own assets.
  @override
  @JsonKey()
  Map<String, dynamic> get splash {
    if (_splash is EqualUnmodifiableMapView) return _splash;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_splash);
  }

  /// Breakpoint-specific overrides (`compact`, `medium`, ...).
  final Map<String, dynamic> _responsive;

  /// Breakpoint-specific overrides (`compact`, `medium`, ...).
  @override
  @JsonKey()
  Map<String, dynamic> get responsive {
    if (_responsive is EqualUnmodifiableMapView) return _responsive;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_responsive);
  }

  @override
  String toString() {
    return 'ThemeLayout(chrome: $chrome, nav: $nav, progress: $progress, player: $player, enforce: $enforce, navItems: $navItems, libraryItems: $libraryItems, home: $home, settings: $settings, titlebar: $titlebar, splash: $splash, responsive: $responsive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeLayoutImpl &&
            (identical(other.chrome, chrome) || other.chrome == chrome) &&
            (identical(other.nav, nav) || other.nav == nav) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.player, player) || other.player == player) &&
            const DeepCollectionEquality().equals(other._enforce, _enforce) &&
            const DeepCollectionEquality().equals(other._navItems, _navItems) &&
            const DeepCollectionEquality()
                .equals(other._libraryItems, _libraryItems) &&
            const DeepCollectionEquality().equals(other._home, _home) &&
            const DeepCollectionEquality().equals(other._settings, _settings) &&
            const DeepCollectionEquality().equals(other._titlebar, _titlebar) &&
            const DeepCollectionEquality().equals(other._splash, _splash) &&
            const DeepCollectionEquality()
                .equals(other._responsive, _responsive));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      chrome,
      nav,
      progress,
      player,
      const DeepCollectionEquality().hash(_enforce),
      const DeepCollectionEquality().hash(_navItems),
      const DeepCollectionEquality().hash(_libraryItems),
      const DeepCollectionEquality().hash(_home),
      const DeepCollectionEquality().hash(_settings),
      const DeepCollectionEquality().hash(_titlebar),
      const DeepCollectionEquality().hash(_splash),
      const DeepCollectionEquality().hash(_responsive));

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeLayoutImplCopyWith<_$ThemeLayoutImpl> get copyWith =>
      __$$ThemeLayoutImplCopyWithImpl<_$ThemeLayoutImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeLayoutImplToJson(
      this,
    );
  }
}

abstract class _ThemeLayout implements ThemeLayout {
  const factory _ThemeLayout(
      {@JsonKey(unknownEnumValue: ThemeChrome.flat) final ThemeChrome chrome,
      @JsonKey(unknownEnumValue: ThemeNav.labels) final ThemeNav nav,
      @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
      final ThemeProgress progress,
      final ThemePlayerLayout player,
      final List<String> enforce,
      final List<String> navItems,
      final List<String> libraryItems,
      final Map<String, dynamic> home,
      final Map<String, dynamic> settings,
      final Map<String, dynamic> titlebar,
      final Map<String, dynamic> splash,
      final Map<String, dynamic> responsive}) = _$ThemeLayoutImpl;

  factory _ThemeLayout.fromJson(Map<String, dynamic> json) =
      _$ThemeLayoutImpl.fromJson;

  /// `inset` floats the page content in a rounded panel over a darkened
  /// backdrop, leaving the player bar full width on the backdrop.
  @override
  @JsonKey(unknownEnumValue: ThemeChrome.flat)
  ThemeChrome get chrome;

  /// `rail` keeps the navigation icon-only at every width instead of
  /// trading width for labels.
  @override
  @JsonKey(unknownEnumValue: ThemeNav.labels)
  ThemeNav get nav;

  /// `below` spans the seek bar across the full player width instead of
  /// docking it above the transport controls.
  @override
  @JsonKey(unknownEnumValue: ThemeProgress.inlinePlacement)
  ThemeProgress get progress;

  /// The player's own shape. `stage` makes the player the centre of the
  /// app (the theme fills `stage.center`/`stage.below`); the other values
  /// keep the host's footer player.
  @override
  ThemePlayerLayout get player;

  /// Layout fields the theme takes over even when the user chose otherwise.
  /// The host only acts on fields it understands.
  @override
  List<String> get enforce;

  /// The navigation entries and library entries the theme wants the host
  /// to show, in order. Kept raw so a theme can add a future entry without
  /// a model release; the host filters to the ids it implements.
  @override
  List<String> get navItems;
  @override
  List<String> get libraryItems;

  /// Home/settings section order and composition, as contract-owned maps.
  @override
  Map<String, dynamic> get home;
  @override
  Map<String, dynamic> get settings;

  /// Window title-bar geometry and back-control preference.
  @override
  Map<String, dynamic> get titlebar;

  /// Launch splash logo/text, resolved through the theme's own assets.
  @override
  Map<String, dynamic> get splash;

  /// Breakpoint-specific overrides (`compact`, `medium`, ...).
  @override
  Map<String, dynamic> get responsive;

  /// Create a copy of ThemeLayout
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeLayoutImplCopyWith<_$ThemeLayoutImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemePlayerLayout _$ThemePlayerLayoutFromJson(Map<String, dynamic> json) {
  return _ThemePlayerLayout.fromJson(json);
}

/// @nodoc
mixin _$ThemePlayerLayout {
  @JsonKey(unknownEnumValue: ThemePlayerDock.full)
  ThemePlayerDock get dock => throw _privateConstructorUsedError;
  bool get showTrackDetails => throw _privateConstructorUsedError;
  bool get showActions => throw _privateConstructorUsedError;
  bool get showVolume => throw _privateConstructorUsedError;
  bool get showLyrics => throw _privateConstructorUsedError;
  bool get showProgress => throw _privateConstructorUsedError;

  /// Serializes this ThemePlayerLayout to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemePlayerLayout
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemePlayerLayoutCopyWith<ThemePlayerLayout> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemePlayerLayoutCopyWith<$Res> {
  factory $ThemePlayerLayoutCopyWith(
          ThemePlayerLayout value, $Res Function(ThemePlayerLayout) then) =
      _$ThemePlayerLayoutCopyWithImpl<$Res, ThemePlayerLayout>;
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemePlayerDock.full) ThemePlayerDock dock,
      bool showTrackDetails,
      bool showActions,
      bool showVolume,
      bool showLyrics,
      bool showProgress});
}

/// @nodoc
class _$ThemePlayerLayoutCopyWithImpl<$Res, $Val extends ThemePlayerLayout>
    implements $ThemePlayerLayoutCopyWith<$Res> {
  _$ThemePlayerLayoutCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemePlayerLayout
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dock = null,
    Object? showTrackDetails = null,
    Object? showActions = null,
    Object? showVolume = null,
    Object? showLyrics = null,
    Object? showProgress = null,
  }) {
    return _then(_value.copyWith(
      dock: null == dock
          ? _value.dock
          : dock // ignore: cast_nullable_to_non_nullable
              as ThemePlayerDock,
      showTrackDetails: null == showTrackDetails
          ? _value.showTrackDetails
          : showTrackDetails // ignore: cast_nullable_to_non_nullable
              as bool,
      showActions: null == showActions
          ? _value.showActions
          : showActions // ignore: cast_nullable_to_non_nullable
              as bool,
      showVolume: null == showVolume
          ? _value.showVolume
          : showVolume // ignore: cast_nullable_to_non_nullable
              as bool,
      showLyrics: null == showLyrics
          ? _value.showLyrics
          : showLyrics // ignore: cast_nullable_to_non_nullable
              as bool,
      showProgress: null == showProgress
          ? _value.showProgress
          : showProgress // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemePlayerLayoutImplCopyWith<$Res>
    implements $ThemePlayerLayoutCopyWith<$Res> {
  factory _$$ThemePlayerLayoutImplCopyWith(_$ThemePlayerLayoutImpl value,
          $Res Function(_$ThemePlayerLayoutImpl) then) =
      __$$ThemePlayerLayoutImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemePlayerDock.full) ThemePlayerDock dock,
      bool showTrackDetails,
      bool showActions,
      bool showVolume,
      bool showLyrics,
      bool showProgress});
}

/// @nodoc
class __$$ThemePlayerLayoutImplCopyWithImpl<$Res>
    extends _$ThemePlayerLayoutCopyWithImpl<$Res, _$ThemePlayerLayoutImpl>
    implements _$$ThemePlayerLayoutImplCopyWith<$Res> {
  __$$ThemePlayerLayoutImplCopyWithImpl(_$ThemePlayerLayoutImpl _value,
      $Res Function(_$ThemePlayerLayoutImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemePlayerLayout
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dock = null,
    Object? showTrackDetails = null,
    Object? showActions = null,
    Object? showVolume = null,
    Object? showLyrics = null,
    Object? showProgress = null,
  }) {
    return _then(_$ThemePlayerLayoutImpl(
      dock: null == dock
          ? _value.dock
          : dock // ignore: cast_nullable_to_non_nullable
              as ThemePlayerDock,
      showTrackDetails: null == showTrackDetails
          ? _value.showTrackDetails
          : showTrackDetails // ignore: cast_nullable_to_non_nullable
              as bool,
      showActions: null == showActions
          ? _value.showActions
          : showActions // ignore: cast_nullable_to_non_nullable
              as bool,
      showVolume: null == showVolume
          ? _value.showVolume
          : showVolume // ignore: cast_nullable_to_non_nullable
              as bool,
      showLyrics: null == showLyrics
          ? _value.showLyrics
          : showLyrics // ignore: cast_nullable_to_non_nullable
              as bool,
      showProgress: null == showProgress
          ? _value.showProgress
          : showProgress // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemePlayerLayoutImpl implements _ThemePlayerLayout {
  const _$ThemePlayerLayoutImpl(
      {@JsonKey(unknownEnumValue: ThemePlayerDock.full)
      this.dock = ThemePlayerDock.full,
      this.showTrackDetails = true,
      this.showActions = true,
      this.showVolume = true,
      this.showLyrics = true,
      this.showProgress = true});

  factory _$ThemePlayerLayoutImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemePlayerLayoutImplFromJson(json);

  @override
  @JsonKey(unknownEnumValue: ThemePlayerDock.full)
  final ThemePlayerDock dock;
  @override
  @JsonKey()
  final bool showTrackDetails;
  @override
  @JsonKey()
  final bool showActions;
  @override
  @JsonKey()
  final bool showVolume;
  @override
  @JsonKey()
  final bool showLyrics;
  @override
  @JsonKey()
  final bool showProgress;

  @override
  String toString() {
    return 'ThemePlayerLayout(dock: $dock, showTrackDetails: $showTrackDetails, showActions: $showActions, showVolume: $showVolume, showLyrics: $showLyrics, showProgress: $showProgress)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemePlayerLayoutImpl &&
            (identical(other.dock, dock) || other.dock == dock) &&
            (identical(other.showTrackDetails, showTrackDetails) ||
                other.showTrackDetails == showTrackDetails) &&
            (identical(other.showActions, showActions) ||
                other.showActions == showActions) &&
            (identical(other.showVolume, showVolume) ||
                other.showVolume == showVolume) &&
            (identical(other.showLyrics, showLyrics) ||
                other.showLyrics == showLyrics) &&
            (identical(other.showProgress, showProgress) ||
                other.showProgress == showProgress));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, dock, showTrackDetails,
      showActions, showVolume, showLyrics, showProgress);

  /// Create a copy of ThemePlayerLayout
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemePlayerLayoutImplCopyWith<_$ThemePlayerLayoutImpl> get copyWith =>
      __$$ThemePlayerLayoutImplCopyWithImpl<_$ThemePlayerLayoutImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemePlayerLayoutImplToJson(
      this,
    );
  }
}

abstract class _ThemePlayerLayout implements ThemePlayerLayout {
  const factory _ThemePlayerLayout(
      {@JsonKey(unknownEnumValue: ThemePlayerDock.full)
      final ThemePlayerDock dock,
      final bool showTrackDetails,
      final bool showActions,
      final bool showVolume,
      final bool showLyrics,
      final bool showProgress}) = _$ThemePlayerLayoutImpl;

  factory _ThemePlayerLayout.fromJson(Map<String, dynamic> json) =
      _$ThemePlayerLayoutImpl.fromJson;

  @override
  @JsonKey(unknownEnumValue: ThemePlayerDock.full)
  ThemePlayerDock get dock;
  @override
  bool get showTrackDetails;
  @override
  bool get showActions;
  @override
  bool get showVolume;
  @override
  bool get showLyrics;
  @override
  bool get showProgress;

  /// Create a copy of ThemePlayerLayout
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemePlayerLayoutImplCopyWith<_$ThemePlayerLayoutImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeTokens _$ThemeTokensFromJson(Map<String, dynamic> json) {
  return _ThemeTokens.fromJson(json);
}

/// @nodoc
mixin _$ThemeTokens {
  /// Width of an album/playlist card, and edge of its square cover.
  double get cardWidth => throw _privateConstructorUsedError;

  /// Height of an album/playlist card row or grid cell.
  double get cardHeight => throw _privateConstructorUsedError;

  /// Width of an artist card. Always at least as wide as its avatar.
  double get artistCardWidth => throw _privateConstructorUsedError;

  /// Height of an artist card row or grid cell.
  double get artistCardHeight => throw _privateConstructorUsedError;

  /// Space between cards, and between a card row's blocks.
  double get gutter => throw _privateConstructorUsedError;

  /// Font family to render text with. Resolved against the platform's
  /// font fallbacks, never loaded from the plugin.
  String? get fontFamily => throw _privateConstructorUsedError;

  /// Serializes this ThemeTokens to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeTokens
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeTokensCopyWith<ThemeTokens> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeTokensCopyWith<$Res> {
  factory $ThemeTokensCopyWith(
          ThemeTokens value, $Res Function(ThemeTokens) then) =
      _$ThemeTokensCopyWithImpl<$Res, ThemeTokens>;
  @useResult
  $Res call(
      {double cardWidth,
      double cardHeight,
      double artistCardWidth,
      double artistCardHeight,
      double gutter,
      String? fontFamily});
}

/// @nodoc
class _$ThemeTokensCopyWithImpl<$Res, $Val extends ThemeTokens>
    implements $ThemeTokensCopyWith<$Res> {
  _$ThemeTokensCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeTokens
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? cardWidth = null,
    Object? cardHeight = null,
    Object? artistCardWidth = null,
    Object? artistCardHeight = null,
    Object? gutter = null,
    Object? fontFamily = freezed,
  }) {
    return _then(_value.copyWith(
      cardWidth: null == cardWidth
          ? _value.cardWidth
          : cardWidth // ignore: cast_nullable_to_non_nullable
              as double,
      cardHeight: null == cardHeight
          ? _value.cardHeight
          : cardHeight // ignore: cast_nullable_to_non_nullable
              as double,
      artistCardWidth: null == artistCardWidth
          ? _value.artistCardWidth
          : artistCardWidth // ignore: cast_nullable_to_non_nullable
              as double,
      artistCardHeight: null == artistCardHeight
          ? _value.artistCardHeight
          : artistCardHeight // ignore: cast_nullable_to_non_nullable
              as double,
      gutter: null == gutter
          ? _value.gutter
          : gutter // ignore: cast_nullable_to_non_nullable
              as double,
      fontFamily: freezed == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeTokensImplCopyWith<$Res>
    implements $ThemeTokensCopyWith<$Res> {
  factory _$$ThemeTokensImplCopyWith(
          _$ThemeTokensImpl value, $Res Function(_$ThemeTokensImpl) then) =
      __$$ThemeTokensImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double cardWidth,
      double cardHeight,
      double artistCardWidth,
      double artistCardHeight,
      double gutter,
      String? fontFamily});
}

/// @nodoc
class __$$ThemeTokensImplCopyWithImpl<$Res>
    extends _$ThemeTokensCopyWithImpl<$Res, _$ThemeTokensImpl>
    implements _$$ThemeTokensImplCopyWith<$Res> {
  __$$ThemeTokensImplCopyWithImpl(
      _$ThemeTokensImpl _value, $Res Function(_$ThemeTokensImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeTokens
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? cardWidth = null,
    Object? cardHeight = null,
    Object? artistCardWidth = null,
    Object? artistCardHeight = null,
    Object? gutter = null,
    Object? fontFamily = freezed,
  }) {
    return _then(_$ThemeTokensImpl(
      cardWidth: null == cardWidth
          ? _value.cardWidth
          : cardWidth // ignore: cast_nullable_to_non_nullable
              as double,
      cardHeight: null == cardHeight
          ? _value.cardHeight
          : cardHeight // ignore: cast_nullable_to_non_nullable
              as double,
      artistCardWidth: null == artistCardWidth
          ? _value.artistCardWidth
          : artistCardWidth // ignore: cast_nullable_to_non_nullable
              as double,
      artistCardHeight: null == artistCardHeight
          ? _value.artistCardHeight
          : artistCardHeight // ignore: cast_nullable_to_non_nullable
              as double,
      gutter: null == gutter
          ? _value.gutter
          : gutter // ignore: cast_nullable_to_non_nullable
              as double,
      fontFamily: freezed == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeTokensImpl implements _ThemeTokens {
  const _$ThemeTokensImpl(
      {this.cardWidth = 150.0,
      this.cardHeight = 225.0,
      this.artistCardWidth = 180.0,
      this.artistCardHeight = 250.0,
      this.gutter = 12.0,
      this.fontFamily});

  factory _$ThemeTokensImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeTokensImplFromJson(json);

  /// Width of an album/playlist card, and edge of its square cover.
  @override
  @JsonKey()
  final double cardWidth;

  /// Height of an album/playlist card row or grid cell.
  @override
  @JsonKey()
  final double cardHeight;

  /// Width of an artist card. Always at least as wide as its avatar.
  @override
  @JsonKey()
  final double artistCardWidth;

  /// Height of an artist card row or grid cell.
  @override
  @JsonKey()
  final double artistCardHeight;

  /// Space between cards, and between a card row's blocks.
  @override
  @JsonKey()
  final double gutter;

  /// Font family to render text with. Resolved against the platform's
  /// font fallbacks, never loaded from the plugin.
  @override
  final String? fontFamily;

  @override
  String toString() {
    return 'ThemeTokens(cardWidth: $cardWidth, cardHeight: $cardHeight, artistCardWidth: $artistCardWidth, artistCardHeight: $artistCardHeight, gutter: $gutter, fontFamily: $fontFamily)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeTokensImpl &&
            (identical(other.cardWidth, cardWidth) ||
                other.cardWidth == cardWidth) &&
            (identical(other.cardHeight, cardHeight) ||
                other.cardHeight == cardHeight) &&
            (identical(other.artistCardWidth, artistCardWidth) ||
                other.artistCardWidth == artistCardWidth) &&
            (identical(other.artistCardHeight, artistCardHeight) ||
                other.artistCardHeight == artistCardHeight) &&
            (identical(other.gutter, gutter) || other.gutter == gutter) &&
            (identical(other.fontFamily, fontFamily) ||
                other.fontFamily == fontFamily));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, cardWidth, cardHeight,
      artistCardWidth, artistCardHeight, gutter, fontFamily);

  /// Create a copy of ThemeTokens
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeTokensImplCopyWith<_$ThemeTokensImpl> get copyWith =>
      __$$ThemeTokensImplCopyWithImpl<_$ThemeTokensImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeTokensImplToJson(
      this,
    );
  }
}

abstract class _ThemeTokens implements ThemeTokens {
  const factory _ThemeTokens(
      {final double cardWidth,
      final double cardHeight,
      final double artistCardWidth,
      final double artistCardHeight,
      final double gutter,
      final String? fontFamily}) = _$ThemeTokensImpl;

  factory _ThemeTokens.fromJson(Map<String, dynamic> json) =
      _$ThemeTokensImpl.fromJson;

  /// Width of an album/playlist card, and edge of its square cover.
  @override
  double get cardWidth;

  /// Height of an album/playlist card row or grid cell.
  @override
  double get cardHeight;

  /// Width of an artist card. Always at least as wide as its avatar.
  @override
  double get artistCardWidth;

  /// Height of an artist card row or grid cell.
  @override
  double get artistCardHeight;

  /// Space between cards, and between a card row's blocks.
  @override
  double get gutter;

  /// Font family to render text with. Resolved against the platform's
  /// font fallbacks, never loaded from the plugin.
  @override
  String? get fontFamily;

  /// Create a copy of ThemeTokens
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeTokensImplCopyWith<_$ThemeTokensImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeColors _$ThemeColorsFromJson(Map<String, dynamic> json) {
  return _ThemeColors.fromJson(json);
}

/// @nodoc
mixin _$ThemeColors {
  String get background => throw _privateConstructorUsedError;
  String get foreground => throw _privateConstructorUsedError;
  String get card => throw _privateConstructorUsedError;
  String get cardForeground => throw _privateConstructorUsedError;
  String get primary => throw _privateConstructorUsedError;
  String get primaryForeground => throw _privateConstructorUsedError;
  String get secondary => throw _privateConstructorUsedError;
  String get secondaryForeground => throw _privateConstructorUsedError;
  String get muted => throw _privateConstructorUsedError;
  String get mutedForeground => throw _privateConstructorUsedError;
  String get accent => throw _privateConstructorUsedError;
  String get accentForeground => throw _privateConstructorUsedError;
  String get destructive => throw _privateConstructorUsedError;
  String get destructiveForeground => throw _privateConstructorUsedError;
  String get border => throw _privateConstructorUsedError;
  String get input => throw _privateConstructorUsedError;
  String get ring =>
      throw _privateConstructorUsedError; // The roles a v2 payload does not have. Each is optional, and each falls
// back to the role it aliases, so a theme may set only the ones it cares
// about and the host keeps its own for the rest.
  /// The floating surface: menus, popovers, dropdowns.
  String? get popover => throw _privateConstructorUsedError;

  /// Text on [popover].
  String? get popoverForeground => throw _privateConstructorUsedError;

  /// The sidebar's own surface.
  String? get sidebar => throw _privateConstructorUsedError;

  /// Text on [sidebar].
  String? get sidebarForeground => throw _privateConstructorUsedError;

  /// The sidebar's active accent.
  String? get sidebarPrimary => throw _privateConstructorUsedError;

  /// Text on [sidebarPrimary].
  String? get sidebarPrimaryForeground => throw _privateConstructorUsedError;

  /// The sidebar's secondary accent.
  String? get sidebarAccent => throw _privateConstructorUsedError;

  /// Text on [sidebarAccent].
  String? get sidebarAccentForeground => throw _privateConstructorUsedError;

  /// The sidebar's outlines.
  String? get sidebarBorder => throw _privateConstructorUsedError;

  /// The sidebar's focus ring.
  String? get sidebarRing => throw _privateConstructorUsedError;

  /// The categorical palette, used by charts and summaries.
  String? get chart1 => throw _privateConstructorUsedError;
  String? get chart2 => throw _privateConstructorUsedError;
  String? get chart3 => throw _privateConstructorUsedError;
  String? get chart4 => throw _privateConstructorUsedError;
  String? get chart5 => throw _privateConstructorUsedError;
  String? get chart6 => throw _privateConstructorUsedError;

  /// The status colours: success, warning and information.
  String? get success => throw _privateConstructorUsedError;
  String? get successForeground => throw _privateConstructorUsedError;
  String? get warning => throw _privateConstructorUsedError;
  String? get warningForeground => throw _privateConstructorUsedError;
  String? get info => throw _privateConstructorUsedError;
  String? get infoForeground => throw _privateConstructorUsedError;

  /// Serializes this ThemeColors to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeColors
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeColorsCopyWith<ThemeColors> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeColorsCopyWith<$Res> {
  factory $ThemeColorsCopyWith(
          ThemeColors value, $Res Function(ThemeColors) then) =
      _$ThemeColorsCopyWithImpl<$Res, ThemeColors>;
  @useResult
  $Res call(
      {String background,
      String foreground,
      String card,
      String cardForeground,
      String primary,
      String primaryForeground,
      String secondary,
      String secondaryForeground,
      String muted,
      String mutedForeground,
      String accent,
      String accentForeground,
      String destructive,
      String destructiveForeground,
      String border,
      String input,
      String ring,
      String? popover,
      String? popoverForeground,
      String? sidebar,
      String? sidebarForeground,
      String? sidebarPrimary,
      String? sidebarPrimaryForeground,
      String? sidebarAccent,
      String? sidebarAccentForeground,
      String? sidebarBorder,
      String? sidebarRing,
      String? chart1,
      String? chart2,
      String? chart3,
      String? chart4,
      String? chart5,
      String? chart6,
      String? success,
      String? successForeground,
      String? warning,
      String? warningForeground,
      String? info,
      String? infoForeground});
}

/// @nodoc
class _$ThemeColorsCopyWithImpl<$Res, $Val extends ThemeColors>
    implements $ThemeColorsCopyWith<$Res> {
  _$ThemeColorsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeColors
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? background = null,
    Object? foreground = null,
    Object? card = null,
    Object? cardForeground = null,
    Object? primary = null,
    Object? primaryForeground = null,
    Object? secondary = null,
    Object? secondaryForeground = null,
    Object? muted = null,
    Object? mutedForeground = null,
    Object? accent = null,
    Object? accentForeground = null,
    Object? destructive = null,
    Object? destructiveForeground = null,
    Object? border = null,
    Object? input = null,
    Object? ring = null,
    Object? popover = freezed,
    Object? popoverForeground = freezed,
    Object? sidebar = freezed,
    Object? sidebarForeground = freezed,
    Object? sidebarPrimary = freezed,
    Object? sidebarPrimaryForeground = freezed,
    Object? sidebarAccent = freezed,
    Object? sidebarAccentForeground = freezed,
    Object? sidebarBorder = freezed,
    Object? sidebarRing = freezed,
    Object? chart1 = freezed,
    Object? chart2 = freezed,
    Object? chart3 = freezed,
    Object? chart4 = freezed,
    Object? chart5 = freezed,
    Object? chart6 = freezed,
    Object? success = freezed,
    Object? successForeground = freezed,
    Object? warning = freezed,
    Object? warningForeground = freezed,
    Object? info = freezed,
    Object? infoForeground = freezed,
  }) {
    return _then(_value.copyWith(
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as String,
      foreground: null == foreground
          ? _value.foreground
          : foreground // ignore: cast_nullable_to_non_nullable
              as String,
      card: null == card
          ? _value.card
          : card // ignore: cast_nullable_to_non_nullable
              as String,
      cardForeground: null == cardForeground
          ? _value.cardForeground
          : cardForeground // ignore: cast_nullable_to_non_nullable
              as String,
      primary: null == primary
          ? _value.primary
          : primary // ignore: cast_nullable_to_non_nullable
              as String,
      primaryForeground: null == primaryForeground
          ? _value.primaryForeground
          : primaryForeground // ignore: cast_nullable_to_non_nullable
              as String,
      secondary: null == secondary
          ? _value.secondary
          : secondary // ignore: cast_nullable_to_non_nullable
              as String,
      secondaryForeground: null == secondaryForeground
          ? _value.secondaryForeground
          : secondaryForeground // ignore: cast_nullable_to_non_nullable
              as String,
      muted: null == muted
          ? _value.muted
          : muted // ignore: cast_nullable_to_non_nullable
              as String,
      mutedForeground: null == mutedForeground
          ? _value.mutedForeground
          : mutedForeground // ignore: cast_nullable_to_non_nullable
              as String,
      accent: null == accent
          ? _value.accent
          : accent // ignore: cast_nullable_to_non_nullable
              as String,
      accentForeground: null == accentForeground
          ? _value.accentForeground
          : accentForeground // ignore: cast_nullable_to_non_nullable
              as String,
      destructive: null == destructive
          ? _value.destructive
          : destructive // ignore: cast_nullable_to_non_nullable
              as String,
      destructiveForeground: null == destructiveForeground
          ? _value.destructiveForeground
          : destructiveForeground // ignore: cast_nullable_to_non_nullable
              as String,
      border: null == border
          ? _value.border
          : border // ignore: cast_nullable_to_non_nullable
              as String,
      input: null == input
          ? _value.input
          : input // ignore: cast_nullable_to_non_nullable
              as String,
      ring: null == ring
          ? _value.ring
          : ring // ignore: cast_nullable_to_non_nullable
              as String,
      popover: freezed == popover
          ? _value.popover
          : popover // ignore: cast_nullable_to_non_nullable
              as String?,
      popoverForeground: freezed == popoverForeground
          ? _value.popoverForeground
          : popoverForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebar: freezed == sidebar
          ? _value.sidebar
          : sidebar // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarForeground: freezed == sidebarForeground
          ? _value.sidebarForeground
          : sidebarForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarPrimary: freezed == sidebarPrimary
          ? _value.sidebarPrimary
          : sidebarPrimary // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarPrimaryForeground: freezed == sidebarPrimaryForeground
          ? _value.sidebarPrimaryForeground
          : sidebarPrimaryForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarAccent: freezed == sidebarAccent
          ? _value.sidebarAccent
          : sidebarAccent // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarAccentForeground: freezed == sidebarAccentForeground
          ? _value.sidebarAccentForeground
          : sidebarAccentForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarBorder: freezed == sidebarBorder
          ? _value.sidebarBorder
          : sidebarBorder // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarRing: freezed == sidebarRing
          ? _value.sidebarRing
          : sidebarRing // ignore: cast_nullable_to_non_nullable
              as String?,
      chart1: freezed == chart1
          ? _value.chart1
          : chart1 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart2: freezed == chart2
          ? _value.chart2
          : chart2 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart3: freezed == chart3
          ? _value.chart3
          : chart3 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart4: freezed == chart4
          ? _value.chart4
          : chart4 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart5: freezed == chart5
          ? _value.chart5
          : chart5 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart6: freezed == chart6
          ? _value.chart6
          : chart6 // ignore: cast_nullable_to_non_nullable
              as String?,
      success: freezed == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as String?,
      successForeground: freezed == successForeground
          ? _value.successForeground
          : successForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      warning: freezed == warning
          ? _value.warning
          : warning // ignore: cast_nullable_to_non_nullable
              as String?,
      warningForeground: freezed == warningForeground
          ? _value.warningForeground
          : warningForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      info: freezed == info
          ? _value.info
          : info // ignore: cast_nullable_to_non_nullable
              as String?,
      infoForeground: freezed == infoForeground
          ? _value.infoForeground
          : infoForeground // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeColorsImplCopyWith<$Res>
    implements $ThemeColorsCopyWith<$Res> {
  factory _$$ThemeColorsImplCopyWith(
          _$ThemeColorsImpl value, $Res Function(_$ThemeColorsImpl) then) =
      __$$ThemeColorsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String background,
      String foreground,
      String card,
      String cardForeground,
      String primary,
      String primaryForeground,
      String secondary,
      String secondaryForeground,
      String muted,
      String mutedForeground,
      String accent,
      String accentForeground,
      String destructive,
      String destructiveForeground,
      String border,
      String input,
      String ring,
      String? popover,
      String? popoverForeground,
      String? sidebar,
      String? sidebarForeground,
      String? sidebarPrimary,
      String? sidebarPrimaryForeground,
      String? sidebarAccent,
      String? sidebarAccentForeground,
      String? sidebarBorder,
      String? sidebarRing,
      String? chart1,
      String? chart2,
      String? chart3,
      String? chart4,
      String? chart5,
      String? chart6,
      String? success,
      String? successForeground,
      String? warning,
      String? warningForeground,
      String? info,
      String? infoForeground});
}

/// @nodoc
class __$$ThemeColorsImplCopyWithImpl<$Res>
    extends _$ThemeColorsCopyWithImpl<$Res, _$ThemeColorsImpl>
    implements _$$ThemeColorsImplCopyWith<$Res> {
  __$$ThemeColorsImplCopyWithImpl(
      _$ThemeColorsImpl _value, $Res Function(_$ThemeColorsImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeColors
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? background = null,
    Object? foreground = null,
    Object? card = null,
    Object? cardForeground = null,
    Object? primary = null,
    Object? primaryForeground = null,
    Object? secondary = null,
    Object? secondaryForeground = null,
    Object? muted = null,
    Object? mutedForeground = null,
    Object? accent = null,
    Object? accentForeground = null,
    Object? destructive = null,
    Object? destructiveForeground = null,
    Object? border = null,
    Object? input = null,
    Object? ring = null,
    Object? popover = freezed,
    Object? popoverForeground = freezed,
    Object? sidebar = freezed,
    Object? sidebarForeground = freezed,
    Object? sidebarPrimary = freezed,
    Object? sidebarPrimaryForeground = freezed,
    Object? sidebarAccent = freezed,
    Object? sidebarAccentForeground = freezed,
    Object? sidebarBorder = freezed,
    Object? sidebarRing = freezed,
    Object? chart1 = freezed,
    Object? chart2 = freezed,
    Object? chart3 = freezed,
    Object? chart4 = freezed,
    Object? chart5 = freezed,
    Object? chart6 = freezed,
    Object? success = freezed,
    Object? successForeground = freezed,
    Object? warning = freezed,
    Object? warningForeground = freezed,
    Object? info = freezed,
    Object? infoForeground = freezed,
  }) {
    return _then(_$ThemeColorsImpl(
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as String,
      foreground: null == foreground
          ? _value.foreground
          : foreground // ignore: cast_nullable_to_non_nullable
              as String,
      card: null == card
          ? _value.card
          : card // ignore: cast_nullable_to_non_nullable
              as String,
      cardForeground: null == cardForeground
          ? _value.cardForeground
          : cardForeground // ignore: cast_nullable_to_non_nullable
              as String,
      primary: null == primary
          ? _value.primary
          : primary // ignore: cast_nullable_to_non_nullable
              as String,
      primaryForeground: null == primaryForeground
          ? _value.primaryForeground
          : primaryForeground // ignore: cast_nullable_to_non_nullable
              as String,
      secondary: null == secondary
          ? _value.secondary
          : secondary // ignore: cast_nullable_to_non_nullable
              as String,
      secondaryForeground: null == secondaryForeground
          ? _value.secondaryForeground
          : secondaryForeground // ignore: cast_nullable_to_non_nullable
              as String,
      muted: null == muted
          ? _value.muted
          : muted // ignore: cast_nullable_to_non_nullable
              as String,
      mutedForeground: null == mutedForeground
          ? _value.mutedForeground
          : mutedForeground // ignore: cast_nullable_to_non_nullable
              as String,
      accent: null == accent
          ? _value.accent
          : accent // ignore: cast_nullable_to_non_nullable
              as String,
      accentForeground: null == accentForeground
          ? _value.accentForeground
          : accentForeground // ignore: cast_nullable_to_non_nullable
              as String,
      destructive: null == destructive
          ? _value.destructive
          : destructive // ignore: cast_nullable_to_non_nullable
              as String,
      destructiveForeground: null == destructiveForeground
          ? _value.destructiveForeground
          : destructiveForeground // ignore: cast_nullable_to_non_nullable
              as String,
      border: null == border
          ? _value.border
          : border // ignore: cast_nullable_to_non_nullable
              as String,
      input: null == input
          ? _value.input
          : input // ignore: cast_nullable_to_non_nullable
              as String,
      ring: null == ring
          ? _value.ring
          : ring // ignore: cast_nullable_to_non_nullable
              as String,
      popover: freezed == popover
          ? _value.popover
          : popover // ignore: cast_nullable_to_non_nullable
              as String?,
      popoverForeground: freezed == popoverForeground
          ? _value.popoverForeground
          : popoverForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebar: freezed == sidebar
          ? _value.sidebar
          : sidebar // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarForeground: freezed == sidebarForeground
          ? _value.sidebarForeground
          : sidebarForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarPrimary: freezed == sidebarPrimary
          ? _value.sidebarPrimary
          : sidebarPrimary // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarPrimaryForeground: freezed == sidebarPrimaryForeground
          ? _value.sidebarPrimaryForeground
          : sidebarPrimaryForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarAccent: freezed == sidebarAccent
          ? _value.sidebarAccent
          : sidebarAccent // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarAccentForeground: freezed == sidebarAccentForeground
          ? _value.sidebarAccentForeground
          : sidebarAccentForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarBorder: freezed == sidebarBorder
          ? _value.sidebarBorder
          : sidebarBorder // ignore: cast_nullable_to_non_nullable
              as String?,
      sidebarRing: freezed == sidebarRing
          ? _value.sidebarRing
          : sidebarRing // ignore: cast_nullable_to_non_nullable
              as String?,
      chart1: freezed == chart1
          ? _value.chart1
          : chart1 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart2: freezed == chart2
          ? _value.chart2
          : chart2 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart3: freezed == chart3
          ? _value.chart3
          : chart3 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart4: freezed == chart4
          ? _value.chart4
          : chart4 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart5: freezed == chart5
          ? _value.chart5
          : chart5 // ignore: cast_nullable_to_non_nullable
              as String?,
      chart6: freezed == chart6
          ? _value.chart6
          : chart6 // ignore: cast_nullable_to_non_nullable
              as String?,
      success: freezed == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as String?,
      successForeground: freezed == successForeground
          ? _value.successForeground
          : successForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      warning: freezed == warning
          ? _value.warning
          : warning // ignore: cast_nullable_to_non_nullable
              as String?,
      warningForeground: freezed == warningForeground
          ? _value.warningForeground
          : warningForeground // ignore: cast_nullable_to_non_nullable
              as String?,
      info: freezed == info
          ? _value.info
          : info // ignore: cast_nullable_to_non_nullable
              as String?,
      infoForeground: freezed == infoForeground
          ? _value.infoForeground
          : infoForeground // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeColorsImpl implements _ThemeColors {
  const _$ThemeColorsImpl(
      {required this.background,
      required this.foreground,
      required this.card,
      required this.cardForeground,
      required this.primary,
      required this.primaryForeground,
      required this.secondary,
      required this.secondaryForeground,
      required this.muted,
      required this.mutedForeground,
      required this.accent,
      required this.accentForeground,
      required this.destructive,
      required this.destructiveForeground,
      required this.border,
      required this.input,
      required this.ring,
      this.popover,
      this.popoverForeground,
      this.sidebar,
      this.sidebarForeground,
      this.sidebarPrimary,
      this.sidebarPrimaryForeground,
      this.sidebarAccent,
      this.sidebarAccentForeground,
      this.sidebarBorder,
      this.sidebarRing,
      this.chart1,
      this.chart2,
      this.chart3,
      this.chart4,
      this.chart5,
      this.chart6,
      this.success,
      this.successForeground,
      this.warning,
      this.warningForeground,
      this.info,
      this.infoForeground});

  factory _$ThemeColorsImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeColorsImplFromJson(json);

  @override
  final String background;
  @override
  final String foreground;
  @override
  final String card;
  @override
  final String cardForeground;
  @override
  final String primary;
  @override
  final String primaryForeground;
  @override
  final String secondary;
  @override
  final String secondaryForeground;
  @override
  final String muted;
  @override
  final String mutedForeground;
  @override
  final String accent;
  @override
  final String accentForeground;
  @override
  final String destructive;
  @override
  final String destructiveForeground;
  @override
  final String border;
  @override
  final String input;
  @override
  final String ring;
// The roles a v2 payload does not have. Each is optional, and each falls
// back to the role it aliases, so a theme may set only the ones it cares
// about and the host keeps its own for the rest.
  /// The floating surface: menus, popovers, dropdowns.
  @override
  final String? popover;

  /// Text on [popover].
  @override
  final String? popoverForeground;

  /// The sidebar's own surface.
  @override
  final String? sidebar;

  /// Text on [sidebar].
  @override
  final String? sidebarForeground;

  /// The sidebar's active accent.
  @override
  final String? sidebarPrimary;

  /// Text on [sidebarPrimary].
  @override
  final String? sidebarPrimaryForeground;

  /// The sidebar's secondary accent.
  @override
  final String? sidebarAccent;

  /// Text on [sidebarAccent].
  @override
  final String? sidebarAccentForeground;

  /// The sidebar's outlines.
  @override
  final String? sidebarBorder;

  /// The sidebar's focus ring.
  @override
  final String? sidebarRing;

  /// The categorical palette, used by charts and summaries.
  @override
  final String? chart1;
  @override
  final String? chart2;
  @override
  final String? chart3;
  @override
  final String? chart4;
  @override
  final String? chart5;
  @override
  final String? chart6;

  /// The status colours: success, warning and information.
  @override
  final String? success;
  @override
  final String? successForeground;
  @override
  final String? warning;
  @override
  final String? warningForeground;
  @override
  final String? info;
  @override
  final String? infoForeground;

  @override
  String toString() {
    return 'ThemeColors(background: $background, foreground: $foreground, card: $card, cardForeground: $cardForeground, primary: $primary, primaryForeground: $primaryForeground, secondary: $secondary, secondaryForeground: $secondaryForeground, muted: $muted, mutedForeground: $mutedForeground, accent: $accent, accentForeground: $accentForeground, destructive: $destructive, destructiveForeground: $destructiveForeground, border: $border, input: $input, ring: $ring, popover: $popover, popoverForeground: $popoverForeground, sidebar: $sidebar, sidebarForeground: $sidebarForeground, sidebarPrimary: $sidebarPrimary, sidebarPrimaryForeground: $sidebarPrimaryForeground, sidebarAccent: $sidebarAccent, sidebarAccentForeground: $sidebarAccentForeground, sidebarBorder: $sidebarBorder, sidebarRing: $sidebarRing, chart1: $chart1, chart2: $chart2, chart3: $chart3, chart4: $chart4, chart5: $chart5, chart6: $chart6, success: $success, successForeground: $successForeground, warning: $warning, warningForeground: $warningForeground, info: $info, infoForeground: $infoForeground)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeColorsImpl &&
            (identical(other.background, background) ||
                other.background == background) &&
            (identical(other.foreground, foreground) ||
                other.foreground == foreground) &&
            (identical(other.card, card) || other.card == card) &&
            (identical(other.cardForeground, cardForeground) ||
                other.cardForeground == cardForeground) &&
            (identical(other.primary, primary) || other.primary == primary) &&
            (identical(other.primaryForeground, primaryForeground) ||
                other.primaryForeground == primaryForeground) &&
            (identical(other.secondary, secondary) ||
                other.secondary == secondary) &&
            (identical(other.secondaryForeground, secondaryForeground) ||
                other.secondaryForeground == secondaryForeground) &&
            (identical(other.muted, muted) || other.muted == muted) &&
            (identical(other.mutedForeground, mutedForeground) ||
                other.mutedForeground == mutedForeground) &&
            (identical(other.accent, accent) || other.accent == accent) &&
            (identical(other.accentForeground, accentForeground) ||
                other.accentForeground == accentForeground) &&
            (identical(other.destructive, destructive) ||
                other.destructive == destructive) &&
            (identical(other.destructiveForeground, destructiveForeground) ||
                other.destructiveForeground == destructiveForeground) &&
            (identical(other.border, border) || other.border == border) &&
            (identical(other.input, input) || other.input == input) &&
            (identical(other.ring, ring) || other.ring == ring) &&
            (identical(other.popover, popover) || other.popover == popover) &&
            (identical(other.popoverForeground, popoverForeground) ||
                other.popoverForeground == popoverForeground) &&
            (identical(other.sidebar, sidebar) || other.sidebar == sidebar) &&
            (identical(other.sidebarForeground, sidebarForeground) ||
                other.sidebarForeground == sidebarForeground) &&
            (identical(other.sidebarPrimary, sidebarPrimary) ||
                other.sidebarPrimary == sidebarPrimary) &&
            (identical(
                    other.sidebarPrimaryForeground, sidebarPrimaryForeground) ||
                other.sidebarPrimaryForeground == sidebarPrimaryForeground) &&
            (identical(other.sidebarAccent, sidebarAccent) ||
                other.sidebarAccent == sidebarAccent) &&
            (identical(
                    other.sidebarAccentForeground, sidebarAccentForeground) ||
                other.sidebarAccentForeground == sidebarAccentForeground) &&
            (identical(other.sidebarBorder, sidebarBorder) ||
                other.sidebarBorder == sidebarBorder) &&
            (identical(other.sidebarRing, sidebarRing) ||
                other.sidebarRing == sidebarRing) &&
            (identical(other.chart1, chart1) || other.chart1 == chart1) &&
            (identical(other.chart2, chart2) || other.chart2 == chart2) &&
            (identical(other.chart3, chart3) || other.chart3 == chart3) &&
            (identical(other.chart4, chart4) || other.chart4 == chart4) &&
            (identical(other.chart5, chart5) || other.chart5 == chart5) &&
            (identical(other.chart6, chart6) || other.chart6 == chart6) &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.successForeground, successForeground) ||
                other.successForeground == successForeground) &&
            (identical(other.warning, warning) || other.warning == warning) &&
            (identical(other.warningForeground, warningForeground) ||
                other.warningForeground == warningForeground) &&
            (identical(other.info, info) || other.info == info) &&
            (identical(other.infoForeground, infoForeground) ||
                other.infoForeground == infoForeground));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        background,
        foreground,
        card,
        cardForeground,
        primary,
        primaryForeground,
        secondary,
        secondaryForeground,
        muted,
        mutedForeground,
        accent,
        accentForeground,
        destructive,
        destructiveForeground,
        border,
        input,
        ring,
        popover,
        popoverForeground,
        sidebar,
        sidebarForeground,
        sidebarPrimary,
        sidebarPrimaryForeground,
        sidebarAccent,
        sidebarAccentForeground,
        sidebarBorder,
        sidebarRing,
        chart1,
        chart2,
        chart3,
        chart4,
        chart5,
        chart6,
        success,
        successForeground,
        warning,
        warningForeground,
        info,
        infoForeground
      ]);

  /// Create a copy of ThemeColors
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeColorsImplCopyWith<_$ThemeColorsImpl> get copyWith =>
      __$$ThemeColorsImplCopyWithImpl<_$ThemeColorsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeColorsImplToJson(
      this,
    );
  }
}

abstract class _ThemeColors implements ThemeColors {
  const factory _ThemeColors(
      {required final String background,
      required final String foreground,
      required final String card,
      required final String cardForeground,
      required final String primary,
      required final String primaryForeground,
      required final String secondary,
      required final String secondaryForeground,
      required final String muted,
      required final String mutedForeground,
      required final String accent,
      required final String accentForeground,
      required final String destructive,
      required final String destructiveForeground,
      required final String border,
      required final String input,
      required final String ring,
      final String? popover,
      final String? popoverForeground,
      final String? sidebar,
      final String? sidebarForeground,
      final String? sidebarPrimary,
      final String? sidebarPrimaryForeground,
      final String? sidebarAccent,
      final String? sidebarAccentForeground,
      final String? sidebarBorder,
      final String? sidebarRing,
      final String? chart1,
      final String? chart2,
      final String? chart3,
      final String? chart4,
      final String? chart5,
      final String? chart6,
      final String? success,
      final String? successForeground,
      final String? warning,
      final String? warningForeground,
      final String? info,
      final String? infoForeground}) = _$ThemeColorsImpl;

  factory _ThemeColors.fromJson(Map<String, dynamic> json) =
      _$ThemeColorsImpl.fromJson;

  @override
  String get background;
  @override
  String get foreground;
  @override
  String get card;
  @override
  String get cardForeground;
  @override
  String get primary;
  @override
  String get primaryForeground;
  @override
  String get secondary;
  @override
  String get secondaryForeground;
  @override
  String get muted;
  @override
  String get mutedForeground;
  @override
  String get accent;
  @override
  String get accentForeground;
  @override
  String get destructive;
  @override
  String get destructiveForeground;
  @override
  String get border;
  @override
  String get input;
  @override
  String
      get ring; // The roles a v2 payload does not have. Each is optional, and each falls
// back to the role it aliases, so a theme may set only the ones it cares
// about and the host keeps its own for the rest.
  /// The floating surface: menus, popovers, dropdowns.
  @override
  String? get popover;

  /// Text on [popover].
  @override
  String? get popoverForeground;

  /// The sidebar's own surface.
  @override
  String? get sidebar;

  /// Text on [sidebar].
  @override
  String? get sidebarForeground;

  /// The sidebar's active accent.
  @override
  String? get sidebarPrimary;

  /// Text on [sidebarPrimary].
  @override
  String? get sidebarPrimaryForeground;

  /// The sidebar's secondary accent.
  @override
  String? get sidebarAccent;

  /// Text on [sidebarAccent].
  @override
  String? get sidebarAccentForeground;

  /// The sidebar's outlines.
  @override
  String? get sidebarBorder;

  /// The sidebar's focus ring.
  @override
  String? get sidebarRing;

  /// The categorical palette, used by charts and summaries.
  @override
  String? get chart1;
  @override
  String? get chart2;
  @override
  String? get chart3;
  @override
  String? get chart4;
  @override
  String? get chart5;
  @override
  String? get chart6;

  /// The status colours: success, warning and information.
  @override
  String? get success;
  @override
  String? get successForeground;
  @override
  String? get warning;
  @override
  String? get warningForeground;
  @override
  String? get info;
  @override
  String? get infoForeground;

  /// Create a copy of ThemeColors
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeColorsImplCopyWith<_$ThemeColorsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeSemanticColors _$ThemeSemanticColorsFromJson(Map<String, dynamic> json) {
  return _ThemeSemanticColors.fromJson(json);
}

/// @nodoc
mixin _$ThemeSemanticColors {
  String get success => throw _privateConstructorUsedError;
  String get successForeground => throw _privateConstructorUsedError;
  String get warning => throw _privateConstructorUsedError;
  String get warningForeground => throw _privateConstructorUsedError;
  String get info => throw _privateConstructorUsedError;
  String get infoForeground => throw _privateConstructorUsedError;
  String get chart6 => throw _privateConstructorUsedError;

  /// Serializes this ThemeSemanticColors to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeSemanticColors
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeSemanticColorsCopyWith<ThemeSemanticColors> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeSemanticColorsCopyWith<$Res> {
  factory $ThemeSemanticColorsCopyWith(
          ThemeSemanticColors value, $Res Function(ThemeSemanticColors) then) =
      _$ThemeSemanticColorsCopyWithImpl<$Res, ThemeSemanticColors>;
  @useResult
  $Res call(
      {String success,
      String successForeground,
      String warning,
      String warningForeground,
      String info,
      String infoForeground,
      String chart6});
}

/// @nodoc
class _$ThemeSemanticColorsCopyWithImpl<$Res, $Val extends ThemeSemanticColors>
    implements $ThemeSemanticColorsCopyWith<$Res> {
  _$ThemeSemanticColorsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeSemanticColors
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? successForeground = null,
    Object? warning = null,
    Object? warningForeground = null,
    Object? info = null,
    Object? infoForeground = null,
    Object? chart6 = null,
  }) {
    return _then(_value.copyWith(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as String,
      successForeground: null == successForeground
          ? _value.successForeground
          : successForeground // ignore: cast_nullable_to_non_nullable
              as String,
      warning: null == warning
          ? _value.warning
          : warning // ignore: cast_nullable_to_non_nullable
              as String,
      warningForeground: null == warningForeground
          ? _value.warningForeground
          : warningForeground // ignore: cast_nullable_to_non_nullable
              as String,
      info: null == info
          ? _value.info
          : info // ignore: cast_nullable_to_non_nullable
              as String,
      infoForeground: null == infoForeground
          ? _value.infoForeground
          : infoForeground // ignore: cast_nullable_to_non_nullable
              as String,
      chart6: null == chart6
          ? _value.chart6
          : chart6 // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeSemanticColorsImplCopyWith<$Res>
    implements $ThemeSemanticColorsCopyWith<$Res> {
  factory _$$ThemeSemanticColorsImplCopyWith(_$ThemeSemanticColorsImpl value,
          $Res Function(_$ThemeSemanticColorsImpl) then) =
      __$$ThemeSemanticColorsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String success,
      String successForeground,
      String warning,
      String warningForeground,
      String info,
      String infoForeground,
      String chart6});
}

/// @nodoc
class __$$ThemeSemanticColorsImplCopyWithImpl<$Res>
    extends _$ThemeSemanticColorsCopyWithImpl<$Res, _$ThemeSemanticColorsImpl>
    implements _$$ThemeSemanticColorsImplCopyWith<$Res> {
  __$$ThemeSemanticColorsImplCopyWithImpl(_$ThemeSemanticColorsImpl _value,
      $Res Function(_$ThemeSemanticColorsImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeSemanticColors
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? successForeground = null,
    Object? warning = null,
    Object? warningForeground = null,
    Object? info = null,
    Object? infoForeground = null,
    Object? chart6 = null,
  }) {
    return _then(_$ThemeSemanticColorsImpl(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as String,
      successForeground: null == successForeground
          ? _value.successForeground
          : successForeground // ignore: cast_nullable_to_non_nullable
              as String,
      warning: null == warning
          ? _value.warning
          : warning // ignore: cast_nullable_to_non_nullable
              as String,
      warningForeground: null == warningForeground
          ? _value.warningForeground
          : warningForeground // ignore: cast_nullable_to_non_nullable
              as String,
      info: null == info
          ? _value.info
          : info // ignore: cast_nullable_to_non_nullable
              as String,
      infoForeground: null == infoForeground
          ? _value.infoForeground
          : infoForeground // ignore: cast_nullable_to_non_nullable
              as String,
      chart6: null == chart6
          ? _value.chart6
          : chart6 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeSemanticColorsImpl implements _ThemeSemanticColors {
  const _$ThemeSemanticColorsImpl(
      {this.success = '#16a34a',
      this.successForeground = '#ffffff',
      this.warning = '#b45309',
      this.warningForeground = '#ffffff',
      this.info = '#2563eb',
      this.infoForeground = '#ffffff',
      this.chart6 = '#8b5cf6'});

  factory _$ThemeSemanticColorsImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeSemanticColorsImplFromJson(json);

  @override
  @JsonKey()
  final String success;
  @override
  @JsonKey()
  final String successForeground;
  @override
  @JsonKey()
  final String warning;
  @override
  @JsonKey()
  final String warningForeground;
  @override
  @JsonKey()
  final String info;
  @override
  @JsonKey()
  final String infoForeground;
  @override
  @JsonKey()
  final String chart6;

  @override
  String toString() {
    return 'ThemeSemanticColors(success: $success, successForeground: $successForeground, warning: $warning, warningForeground: $warningForeground, info: $info, infoForeground: $infoForeground, chart6: $chart6)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeSemanticColorsImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.successForeground, successForeground) ||
                other.successForeground == successForeground) &&
            (identical(other.warning, warning) || other.warning == warning) &&
            (identical(other.warningForeground, warningForeground) ||
                other.warningForeground == warningForeground) &&
            (identical(other.info, info) || other.info == info) &&
            (identical(other.infoForeground, infoForeground) ||
                other.infoForeground == infoForeground) &&
            (identical(other.chart6, chart6) || other.chart6 == chart6));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, success, successForeground,
      warning, warningForeground, info, infoForeground, chart6);

  /// Create a copy of ThemeSemanticColors
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeSemanticColorsImplCopyWith<_$ThemeSemanticColorsImpl> get copyWith =>
      __$$ThemeSemanticColorsImplCopyWithImpl<_$ThemeSemanticColorsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeSemanticColorsImplToJson(
      this,
    );
  }
}

abstract class _ThemeSemanticColors implements ThemeSemanticColors {
  const factory _ThemeSemanticColors(
      {final String success,
      final String successForeground,
      final String warning,
      final String warningForeground,
      final String info,
      final String infoForeground,
      final String chart6}) = _$ThemeSemanticColorsImpl;

  factory _ThemeSemanticColors.fromJson(Map<String, dynamic> json) =
      _$ThemeSemanticColorsImpl.fromJson;

  @override
  String get success;
  @override
  String get successForeground;
  @override
  String get warning;
  @override
  String get warningForeground;
  @override
  String get info;
  @override
  String get infoForeground;
  @override
  String get chart6;

  /// Create a copy of ThemeSemanticColors
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeSemanticColorsImplCopyWith<_$ThemeSemanticColorsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeSurfaces _$ThemeSurfacesFromJson(Map<String, dynamic> json) {
  return _ThemeSurfaces.fromJson(json);
}

/// @nodoc
mixin _$ThemeSurfaces {
  double get opacity => throw _privateConstructorUsedError;
  double get blur => throw _privateConstructorUsedError;

  /// Optional surface tint as `#RRGGBB` or Flutter-native `#AARRGGBB`.
  String? get tint => throw _privateConstructorUsedError;

  /// Serializes this ThemeSurfaces to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeSurfaces
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeSurfacesCopyWith<ThemeSurfaces> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeSurfacesCopyWith<$Res> {
  factory $ThemeSurfacesCopyWith(
          ThemeSurfaces value, $Res Function(ThemeSurfaces) then) =
      _$ThemeSurfacesCopyWithImpl<$Res, ThemeSurfaces>;
  @useResult
  $Res call({double opacity, double blur, String? tint});
}

/// @nodoc
class _$ThemeSurfacesCopyWithImpl<$Res, $Val extends ThemeSurfaces>
    implements $ThemeSurfacesCopyWith<$Res> {
  _$ThemeSurfacesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeSurfaces
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? opacity = null,
    Object? blur = null,
    Object? tint = freezed,
  }) {
    return _then(_value.copyWith(
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      blur: null == blur
          ? _value.blur
          : blur // ignore: cast_nullable_to_non_nullable
              as double,
      tint: freezed == tint
          ? _value.tint
          : tint // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeSurfacesImplCopyWith<$Res>
    implements $ThemeSurfacesCopyWith<$Res> {
  factory _$$ThemeSurfacesImplCopyWith(
          _$ThemeSurfacesImpl value, $Res Function(_$ThemeSurfacesImpl) then) =
      __$$ThemeSurfacesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double opacity, double blur, String? tint});
}

/// @nodoc
class __$$ThemeSurfacesImplCopyWithImpl<$Res>
    extends _$ThemeSurfacesCopyWithImpl<$Res, _$ThemeSurfacesImpl>
    implements _$$ThemeSurfacesImplCopyWith<$Res> {
  __$$ThemeSurfacesImplCopyWithImpl(
      _$ThemeSurfacesImpl _value, $Res Function(_$ThemeSurfacesImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeSurfaces
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? opacity = null,
    Object? blur = null,
    Object? tint = freezed,
  }) {
    return _then(_$ThemeSurfacesImpl(
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      blur: null == blur
          ? _value.blur
          : blur // ignore: cast_nullable_to_non_nullable
              as double,
      tint: freezed == tint
          ? _value.tint
          : tint // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeSurfacesImpl implements _ThemeSurfaces {
  const _$ThemeSurfacesImpl({this.opacity = 0.8, this.blur = 10.0, this.tint});

  factory _$ThemeSurfacesImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeSurfacesImplFromJson(json);

  @override
  @JsonKey()
  final double opacity;
  @override
  @JsonKey()
  final double blur;

  /// Optional surface tint as `#RRGGBB` or Flutter-native `#AARRGGBB`.
  @override
  final String? tint;

  @override
  String toString() {
    return 'ThemeSurfaces(opacity: $opacity, blur: $blur, tint: $tint)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeSurfacesImpl &&
            (identical(other.opacity, opacity) || other.opacity == opacity) &&
            (identical(other.blur, blur) || other.blur == blur) &&
            (identical(other.tint, tint) || other.tint == tint));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, opacity, blur, tint);

  /// Create a copy of ThemeSurfaces
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeSurfacesImplCopyWith<_$ThemeSurfacesImpl> get copyWith =>
      __$$ThemeSurfacesImplCopyWithImpl<_$ThemeSurfacesImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeSurfacesImplToJson(
      this,
    );
  }
}

abstract class _ThemeSurfaces implements ThemeSurfaces {
  const factory _ThemeSurfaces(
      {final double opacity,
      final double blur,
      final String? tint}) = _$ThemeSurfacesImpl;

  factory _ThemeSurfaces.fromJson(Map<String, dynamic> json) =
      _$ThemeSurfacesImpl.fromJson;

  @override
  double get opacity;
  @override
  double get blur;

  /// Optional surface tint as `#RRGGBB` or Flutter-native `#AARRGGBB`.
  @override
  String? get tint;

  /// Create a copy of ThemeSurfaces
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeSurfacesImplCopyWith<_$ThemeSurfacesImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeBackground _$ThemeBackgroundFromJson(Map<String, dynamic> json) {
  return _ThemeBackground.fromJson(json);
}

/// @nodoc
mixin _$ThemeBackground {
  @JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
  ThemeBackgroundSource get source => throw _privateConstructorUsedError;
  double get opacity => throw _privateConstructorUsedError;
  double get blur => throw _privateConstructorUsedError;

  /// A v3 background shipped with the theme (`asset://…`).
  String? get asset => throw _privateConstructorUsedError;

  /// Repeat [asset] instead of stretching it.
  bool get tile => throw _privateConstructorUsedError;

  /// Whole-number magnification for a tiled [asset], 1..8.
  int get scale => throw _privateConstructorUsedError;

  /// Optional veil over the background image as `#RRGGBB` or
  /// Flutter-native `#AARRGGBB` (alpha honored, e.g. `#80000000`
  /// is 50% black). Brightness-adapted by the host layer.
  String? get overlay => throw _privateConstructorUsedError;

  /// Real window transparency opt-in, tri-state by design:
  /// - `true`: theme wants the compositor to show through (still needs
  ///   the host master setting);
  /// - `false`: explicit veto, always opaque even with the setting on;
  /// - absent (`null`): no opinion, the host setting decides alone (this
  ///   is what old themes decode to).
  /// Decoded leniently: anything that is not a JSON bool reads as absent,
  /// so one malformed flag can never nuke the whole theme.
  @JsonKey(fromJson: _transparentFromJson)
  bool? get transparent => throw _privateConstructorUsedError;

  /// Serializes this ThemeBackground to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeBackground
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeBackgroundCopyWith<ThemeBackground> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeBackgroundCopyWith<$Res> {
  factory $ThemeBackgroundCopyWith(
          ThemeBackground value, $Res Function(ThemeBackground) then) =
      _$ThemeBackgroundCopyWithImpl<$Res, ThemeBackground>;
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
      ThemeBackgroundSource source,
      double opacity,
      double blur,
      String? asset,
      bool tile,
      int scale,
      String? overlay,
      @JsonKey(fromJson: _transparentFromJson) bool? transparent});
}

/// @nodoc
class _$ThemeBackgroundCopyWithImpl<$Res, $Val extends ThemeBackground>
    implements $ThemeBackgroundCopyWith<$Res> {
  _$ThemeBackgroundCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeBackground
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? opacity = null,
    Object? blur = null,
    Object? asset = freezed,
    Object? tile = null,
    Object? scale = null,
    Object? overlay = freezed,
    Object? transparent = freezed,
  }) {
    return _then(_value.copyWith(
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as ThemeBackgroundSource,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      blur: null == blur
          ? _value.blur
          : blur // ignore: cast_nullable_to_non_nullable
              as double,
      asset: freezed == asset
          ? _value.asset
          : asset // ignore: cast_nullable_to_non_nullable
              as String?,
      tile: null == tile
          ? _value.tile
          : tile // ignore: cast_nullable_to_non_nullable
              as bool,
      scale: null == scale
          ? _value.scale
          : scale // ignore: cast_nullable_to_non_nullable
              as int,
      overlay: freezed == overlay
          ? _value.overlay
          : overlay // ignore: cast_nullable_to_non_nullable
              as String?,
      transparent: freezed == transparent
          ? _value.transparent
          : transparent // ignore: cast_nullable_to_non_nullable
              as bool?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeBackgroundImplCopyWith<$Res>
    implements $ThemeBackgroundCopyWith<$Res> {
  factory _$$ThemeBackgroundImplCopyWith(_$ThemeBackgroundImpl value,
          $Res Function(_$ThemeBackgroundImpl) then) =
      __$$ThemeBackgroundImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
      ThemeBackgroundSource source,
      double opacity,
      double blur,
      String? asset,
      bool tile,
      int scale,
      String? overlay,
      @JsonKey(fromJson: _transparentFromJson) bool? transparent});
}

/// @nodoc
class __$$ThemeBackgroundImplCopyWithImpl<$Res>
    extends _$ThemeBackgroundCopyWithImpl<$Res, _$ThemeBackgroundImpl>
    implements _$$ThemeBackgroundImplCopyWith<$Res> {
  __$$ThemeBackgroundImplCopyWithImpl(
      _$ThemeBackgroundImpl _value, $Res Function(_$ThemeBackgroundImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeBackground
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? opacity = null,
    Object? blur = null,
    Object? asset = freezed,
    Object? tile = null,
    Object? scale = null,
    Object? overlay = freezed,
    Object? transparent = freezed,
  }) {
    return _then(_$ThemeBackgroundImpl(
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as ThemeBackgroundSource,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      blur: null == blur
          ? _value.blur
          : blur // ignore: cast_nullable_to_non_nullable
              as double,
      asset: freezed == asset
          ? _value.asset
          : asset // ignore: cast_nullable_to_non_nullable
              as String?,
      tile: null == tile
          ? _value.tile
          : tile // ignore: cast_nullable_to_non_nullable
              as bool,
      scale: null == scale
          ? _value.scale
          : scale // ignore: cast_nullable_to_non_nullable
              as int,
      overlay: freezed == overlay
          ? _value.overlay
          : overlay // ignore: cast_nullable_to_non_nullable
              as String?,
      transparent: freezed == transparent
          ? _value.transparent
          : transparent // ignore: cast_nullable_to_non_nullable
              as bool?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeBackgroundImpl implements _ThemeBackground {
  const _$ThemeBackgroundImpl(
      {@JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
      this.source = ThemeBackgroundSource.none,
      this.opacity = 0.0,
      this.blur = 0.0,
      this.asset,
      this.tile = false,
      this.scale = 1,
      this.overlay,
      @JsonKey(fromJson: _transparentFromJson) this.transparent});

  factory _$ThemeBackgroundImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeBackgroundImplFromJson(json);

  @override
  @JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
  final ThemeBackgroundSource source;
  @override
  @JsonKey()
  final double opacity;
  @override
  @JsonKey()
  final double blur;

  /// A v3 background shipped with the theme (`asset://…`).
  @override
  final String? asset;

  /// Repeat [asset] instead of stretching it.
  @override
  @JsonKey()
  final bool tile;

  /// Whole-number magnification for a tiled [asset], 1..8.
  @override
  @JsonKey()
  final int scale;

  /// Optional veil over the background image as `#RRGGBB` or
  /// Flutter-native `#AARRGGBB` (alpha honored, e.g. `#80000000`
  /// is 50% black). Brightness-adapted by the host layer.
  @override
  final String? overlay;

  /// Real window transparency opt-in, tri-state by design:
  /// - `true`: theme wants the compositor to show through (still needs
  ///   the host master setting);
  /// - `false`: explicit veto, always opaque even with the setting on;
  /// - absent (`null`): no opinion, the host setting decides alone (this
  ///   is what old themes decode to).
  /// Decoded leniently: anything that is not a JSON bool reads as absent,
  /// so one malformed flag can never nuke the whole theme.
  @override
  @JsonKey(fromJson: _transparentFromJson)
  final bool? transparent;

  @override
  String toString() {
    return 'ThemeBackground(source: $source, opacity: $opacity, blur: $blur, asset: $asset, tile: $tile, scale: $scale, overlay: $overlay, transparent: $transparent)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeBackgroundImpl &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.opacity, opacity) || other.opacity == opacity) &&
            (identical(other.blur, blur) || other.blur == blur) &&
            (identical(other.asset, asset) || other.asset == asset) &&
            (identical(other.tile, tile) || other.tile == tile) &&
            (identical(other.scale, scale) || other.scale == scale) &&
            (identical(other.overlay, overlay) || other.overlay == overlay) &&
            (identical(other.transparent, transparent) ||
                other.transparent == transparent));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, source, opacity, blur, asset,
      tile, scale, overlay, transparent);

  /// Create a copy of ThemeBackground
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeBackgroundImplCopyWith<_$ThemeBackgroundImpl> get copyWith =>
      __$$ThemeBackgroundImplCopyWithImpl<_$ThemeBackgroundImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeBackgroundImplToJson(
      this,
    );
  }
}

abstract class _ThemeBackground implements ThemeBackground {
  const factory _ThemeBackground(
          {@JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
          final ThemeBackgroundSource source,
          final double opacity,
          final double blur,
          final String? asset,
          final bool tile,
          final int scale,
          final String? overlay,
          @JsonKey(fromJson: _transparentFromJson) final bool? transparent}) =
      _$ThemeBackgroundImpl;

  factory _ThemeBackground.fromJson(Map<String, dynamic> json) =
      _$ThemeBackgroundImpl.fromJson;

  @override
  @JsonKey(unknownEnumValue: ThemeBackgroundSource.none)
  ThemeBackgroundSource get source;
  @override
  double get opacity;
  @override
  double get blur;

  /// A v3 background shipped with the theme (`asset://…`).
  @override
  String? get asset;

  /// Repeat [asset] instead of stretching it.
  @override
  bool get tile;

  /// Whole-number magnification for a tiled [asset], 1..8.
  @override
  int get scale;

  /// Optional veil over the background image as `#RRGGBB` or
  /// Flutter-native `#AARRGGBB` (alpha honored, e.g. `#80000000`
  /// is 50% black). Brightness-adapted by the host layer.
  @override
  String? get overlay;

  /// Real window transparency opt-in, tri-state by design:
  /// - `true`: theme wants the compositor to show through (still needs
  ///   the host master setting);
  /// - `false`: explicit veto, always opaque even with the setting on;
  /// - absent (`null`): no opinion, the host setting decides alone (this
  ///   is what old themes decode to).
  /// Decoded leniently: anything that is not a JSON bool reads as absent,
  /// so one malformed flag can never nuke the whole theme.
  @override
  @JsonKey(fromJson: _transparentFromJson)
  bool? get transparent;

  /// Create a copy of ThemeBackground
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeBackgroundImplCopyWith<_$ThemeBackgroundImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeRadius _$ThemeRadiusFromJson(Map<String, dynamic> json) {
  return _ThemeRadius.fromJson(json);
}

/// @nodoc
mixin _$ThemeRadius {
  double get small => throw _privateConstructorUsedError;
  double get medium => throw _privateConstructorUsedError;
  double get large => throw _privateConstructorUsedError;
  double get pill => throw _privateConstructorUsedError;

  /// Serializes this ThemeRadius to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeRadius
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeRadiusCopyWith<ThemeRadius> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeRadiusCopyWith<$Res> {
  factory $ThemeRadiusCopyWith(
          ThemeRadius value, $Res Function(ThemeRadius) then) =
      _$ThemeRadiusCopyWithImpl<$Res, ThemeRadius>;
  @useResult
  $Res call({double small, double medium, double large, double pill});
}

/// @nodoc
class _$ThemeRadiusCopyWithImpl<$Res, $Val extends ThemeRadius>
    implements $ThemeRadiusCopyWith<$Res> {
  _$ThemeRadiusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeRadius
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? small = null,
    Object? medium = null,
    Object? large = null,
    Object? pill = null,
  }) {
    return _then(_value.copyWith(
      small: null == small
          ? _value.small
          : small // ignore: cast_nullable_to_non_nullable
              as double,
      medium: null == medium
          ? _value.medium
          : medium // ignore: cast_nullable_to_non_nullable
              as double,
      large: null == large
          ? _value.large
          : large // ignore: cast_nullable_to_non_nullable
              as double,
      pill: null == pill
          ? _value.pill
          : pill // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeRadiusImplCopyWith<$Res>
    implements $ThemeRadiusCopyWith<$Res> {
  factory _$$ThemeRadiusImplCopyWith(
          _$ThemeRadiusImpl value, $Res Function(_$ThemeRadiusImpl) then) =
      __$$ThemeRadiusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double small, double medium, double large, double pill});
}

/// @nodoc
class __$$ThemeRadiusImplCopyWithImpl<$Res>
    extends _$ThemeRadiusCopyWithImpl<$Res, _$ThemeRadiusImpl>
    implements _$$ThemeRadiusImplCopyWith<$Res> {
  __$$ThemeRadiusImplCopyWithImpl(
      _$ThemeRadiusImpl _value, $Res Function(_$ThemeRadiusImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeRadius
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? small = null,
    Object? medium = null,
    Object? large = null,
    Object? pill = null,
  }) {
    return _then(_$ThemeRadiusImpl(
      small: null == small
          ? _value.small
          : small // ignore: cast_nullable_to_non_nullable
              as double,
      medium: null == medium
          ? _value.medium
          : medium // ignore: cast_nullable_to_non_nullable
              as double,
      large: null == large
          ? _value.large
          : large // ignore: cast_nullable_to_non_nullable
              as double,
      pill: null == pill
          ? _value.pill
          : pill // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeRadiusImpl implements _ThemeRadius {
  const _$ThemeRadiusImpl(
      {this.small = 6.0,
      this.medium = 10.0,
      this.large = 16.0,
      this.pill = 999.0});

  factory _$ThemeRadiusImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeRadiusImplFromJson(json);

  @override
  @JsonKey()
  final double small;
  @override
  @JsonKey()
  final double medium;
  @override
  @JsonKey()
  final double large;
  @override
  @JsonKey()
  final double pill;

  @override
  String toString() {
    return 'ThemeRadius(small: $small, medium: $medium, large: $large, pill: $pill)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeRadiusImpl &&
            (identical(other.small, small) || other.small == small) &&
            (identical(other.medium, medium) || other.medium == medium) &&
            (identical(other.large, large) || other.large == large) &&
            (identical(other.pill, pill) || other.pill == pill));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, small, medium, large, pill);

  /// Create a copy of ThemeRadius
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeRadiusImplCopyWith<_$ThemeRadiusImpl> get copyWith =>
      __$$ThemeRadiusImplCopyWithImpl<_$ThemeRadiusImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeRadiusImplToJson(
      this,
    );
  }
}

abstract class _ThemeRadius implements ThemeRadius {
  const factory _ThemeRadius(
      {final double small,
      final double medium,
      final double large,
      final double pill}) = _$ThemeRadiusImpl;

  factory _ThemeRadius.fromJson(Map<String, dynamic> json) =
      _$ThemeRadiusImpl.fromJson;

  @override
  double get small;
  @override
  double get medium;
  @override
  double get large;
  @override
  double get pill;

  /// Create a copy of ThemeRadius
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeRadiusImplCopyWith<_$ThemeRadiusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DynamicTheme _$DynamicThemeFromJson(Map<String, dynamic> json) {
  return _DynamicTheme.fromJson(json);
}

/// @nodoc
mixin _$DynamicTheme {
  DynamicThemeSource get source => throw _privateConstructorUsedError;
  DynamicThemeAlgorithm get algorithm => throw _privateConstructorUsedError;

  /// Serializes this DynamicTheme to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DynamicTheme
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DynamicThemeCopyWith<DynamicTheme> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DynamicThemeCopyWith<$Res> {
  factory $DynamicThemeCopyWith(
          DynamicTheme value, $Res Function(DynamicTheme) then) =
      _$DynamicThemeCopyWithImpl<$Res, DynamicTheme>;
  @useResult
  $Res call({DynamicThemeSource source, DynamicThemeAlgorithm algorithm});
}

/// @nodoc
class _$DynamicThemeCopyWithImpl<$Res, $Val extends DynamicTheme>
    implements $DynamicThemeCopyWith<$Res> {
  _$DynamicThemeCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DynamicTheme
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? algorithm = null,
  }) {
    return _then(_value.copyWith(
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as DynamicThemeSource,
      algorithm: null == algorithm
          ? _value.algorithm
          : algorithm // ignore: cast_nullable_to_non_nullable
              as DynamicThemeAlgorithm,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DynamicThemeImplCopyWith<$Res>
    implements $DynamicThemeCopyWith<$Res> {
  factory _$$DynamicThemeImplCopyWith(
          _$DynamicThemeImpl value, $Res Function(_$DynamicThemeImpl) then) =
      __$$DynamicThemeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({DynamicThemeSource source, DynamicThemeAlgorithm algorithm});
}

/// @nodoc
class __$$DynamicThemeImplCopyWithImpl<$Res>
    extends _$DynamicThemeCopyWithImpl<$Res, _$DynamicThemeImpl>
    implements _$$DynamicThemeImplCopyWith<$Res> {
  __$$DynamicThemeImplCopyWithImpl(
      _$DynamicThemeImpl _value, $Res Function(_$DynamicThemeImpl) _then)
      : super(_value, _then);

  /// Create a copy of DynamicTheme
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? algorithm = null,
  }) {
    return _then(_$DynamicThemeImpl(
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as DynamicThemeSource,
      algorithm: null == algorithm
          ? _value.algorithm
          : algorithm // ignore: cast_nullable_to_non_nullable
              as DynamicThemeAlgorithm,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DynamicThemeImpl implements _DynamicTheme {
  const _$DynamicThemeImpl(
      {required this.source, this.algorithm = DynamicThemeAlgorithm.material});

  factory _$DynamicThemeImpl.fromJson(Map<String, dynamic> json) =>
      _$$DynamicThemeImplFromJson(json);

  @override
  final DynamicThemeSource source;
  @override
  @JsonKey()
  final DynamicThemeAlgorithm algorithm;

  @override
  String toString() {
    return 'DynamicTheme(source: $source, algorithm: $algorithm)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DynamicThemeImpl &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.algorithm, algorithm) ||
                other.algorithm == algorithm));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, source, algorithm);

  /// Create a copy of DynamicTheme
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DynamicThemeImplCopyWith<_$DynamicThemeImpl> get copyWith =>
      __$$DynamicThemeImplCopyWithImpl<_$DynamicThemeImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DynamicThemeImplToJson(
      this,
    );
  }
}

abstract class _DynamicTheme implements DynamicTheme {
  const factory _DynamicTheme(
      {required final DynamicThemeSource source,
      final DynamicThemeAlgorithm algorithm}) = _$DynamicThemeImpl;

  factory _DynamicTheme.fromJson(Map<String, dynamic> json) =
      _$DynamicThemeImpl.fromJson;

  @override
  DynamicThemeSource get source;
  @override
  DynamicThemeAlgorithm get algorithm;

  /// Create a copy of DynamicTheme
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DynamicThemeImplCopyWith<_$DynamicThemeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeUiDocument _$ThemeUiDocumentFromJson(Map<String, dynamic> json) {
  return _ThemeUiDocument.fromJson(json);
}

/// @nodoc
mixin _$ThemeUiDocument {
  int get specVersion => throw _privateConstructorUsedError;
  Map<String, ThemeUiSlot> get slots => throw _privateConstructorUsedError;
  Map<String, ThemeUiScreen> get screens => throw _privateConstructorUsedError;
  Map<String, ThemeUiTemplate> get templates =>
      throw _privateConstructorUsedError;

  /// Serializes this ThemeUiDocument to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeUiDocument
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeUiDocumentCopyWith<ThemeUiDocument> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeUiDocumentCopyWith<$Res> {
  factory $ThemeUiDocumentCopyWith(
          ThemeUiDocument value, $Res Function(ThemeUiDocument) then) =
      _$ThemeUiDocumentCopyWithImpl<$Res, ThemeUiDocument>;
  @useResult
  $Res call(
      {int specVersion,
      Map<String, ThemeUiSlot> slots,
      Map<String, ThemeUiScreen> screens,
      Map<String, ThemeUiTemplate> templates});
}

/// @nodoc
class _$ThemeUiDocumentCopyWithImpl<$Res, $Val extends ThemeUiDocument>
    implements $ThemeUiDocumentCopyWith<$Res> {
  _$ThemeUiDocumentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeUiDocument
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? specVersion = null,
    Object? slots = null,
    Object? screens = null,
    Object? templates = null,
  }) {
    return _then(_value.copyWith(
      specVersion: null == specVersion
          ? _value.specVersion
          : specVersion // ignore: cast_nullable_to_non_nullable
              as int,
      slots: null == slots
          ? _value.slots
          : slots // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiSlot>,
      screens: null == screens
          ? _value.screens
          : screens // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiScreen>,
      templates: null == templates
          ? _value.templates
          : templates // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiTemplate>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeUiDocumentImplCopyWith<$Res>
    implements $ThemeUiDocumentCopyWith<$Res> {
  factory _$$ThemeUiDocumentImplCopyWith(_$ThemeUiDocumentImpl value,
          $Res Function(_$ThemeUiDocumentImpl) then) =
      __$$ThemeUiDocumentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int specVersion,
      Map<String, ThemeUiSlot> slots,
      Map<String, ThemeUiScreen> screens,
      Map<String, ThemeUiTemplate> templates});
}

/// @nodoc
class __$$ThemeUiDocumentImplCopyWithImpl<$Res>
    extends _$ThemeUiDocumentCopyWithImpl<$Res, _$ThemeUiDocumentImpl>
    implements _$$ThemeUiDocumentImplCopyWith<$Res> {
  __$$ThemeUiDocumentImplCopyWithImpl(
      _$ThemeUiDocumentImpl _value, $Res Function(_$ThemeUiDocumentImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeUiDocument
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? specVersion = null,
    Object? slots = null,
    Object? screens = null,
    Object? templates = null,
  }) {
    return _then(_$ThemeUiDocumentImpl(
      specVersion: null == specVersion
          ? _value.specVersion
          : specVersion // ignore: cast_nullable_to_non_nullable
              as int,
      slots: null == slots
          ? _value._slots
          : slots // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiSlot>,
      screens: null == screens
          ? _value._screens
          : screens // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiScreen>,
      templates: null == templates
          ? _value._templates
          : templates // ignore: cast_nullable_to_non_nullable
              as Map<String, ThemeUiTemplate>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeUiDocumentImpl implements _ThemeUiDocument {
  const _$ThemeUiDocumentImpl(
      {this.specVersion = 1,
      final Map<String, ThemeUiSlot> slots = const {},
      final Map<String, ThemeUiScreen> screens = const {},
      final Map<String, ThemeUiTemplate> templates =
          const <String, ThemeUiTemplate>{}})
      : _slots = slots,
        _screens = screens,
        _templates = templates;

  factory _$ThemeUiDocumentImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeUiDocumentImplFromJson(json);

  @override
  @JsonKey()
  final int specVersion;
  final Map<String, ThemeUiSlot> _slots;
  @override
  @JsonKey()
  Map<String, ThemeUiSlot> get slots {
    if (_slots is EqualUnmodifiableMapView) return _slots;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_slots);
  }

  final Map<String, ThemeUiScreen> _screens;
  @override
  @JsonKey()
  Map<String, ThemeUiScreen> get screens {
    if (_screens is EqualUnmodifiableMapView) return _screens;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_screens);
  }

  final Map<String, ThemeUiTemplate> _templates;
  @override
  @JsonKey()
  Map<String, ThemeUiTemplate> get templates {
    if (_templates is EqualUnmodifiableMapView) return _templates;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_templates);
  }

  @override
  String toString() {
    return 'ThemeUiDocument(specVersion: $specVersion, slots: $slots, screens: $screens, templates: $templates)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeUiDocumentImpl &&
            (identical(other.specVersion, specVersion) ||
                other.specVersion == specVersion) &&
            const DeepCollectionEquality().equals(other._slots, _slots) &&
            const DeepCollectionEquality().equals(other._screens, _screens) &&
            const DeepCollectionEquality()
                .equals(other._templates, _templates));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      specVersion,
      const DeepCollectionEquality().hash(_slots),
      const DeepCollectionEquality().hash(_screens),
      const DeepCollectionEquality().hash(_templates));

  /// Create a copy of ThemeUiDocument
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeUiDocumentImplCopyWith<_$ThemeUiDocumentImpl> get copyWith =>
      __$$ThemeUiDocumentImplCopyWithImpl<_$ThemeUiDocumentImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeUiDocumentImplToJson(
      this,
    );
  }
}

abstract class _ThemeUiDocument implements ThemeUiDocument {
  const factory _ThemeUiDocument(
      {final int specVersion,
      final Map<String, ThemeUiSlot> slots,
      final Map<String, ThemeUiScreen> screens,
      final Map<String, ThemeUiTemplate> templates}) = _$ThemeUiDocumentImpl;

  factory _ThemeUiDocument.fromJson(Map<String, dynamic> json) =
      _$ThemeUiDocumentImpl.fromJson;

  @override
  int get specVersion;
  @override
  Map<String, ThemeUiSlot> get slots;
  @override
  Map<String, ThemeUiScreen> get screens;
  @override
  Map<String, ThemeUiTemplate> get templates;

  /// Create a copy of ThemeUiDocument
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeUiDocumentImplCopyWith<_$ThemeUiDocumentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeUiSlot _$ThemeUiSlotFromJson(Map<String, dynamic> json) {
  return _ThemeUiSlot.fromJson(json);
}

/// @nodoc
mixin _$ThemeUiSlot {
  List<Map<String, dynamic>> get children => throw _privateConstructorUsedError;

  /// How often the host may refresh data-bound children in this slot.
  /// Zero means "on state changes only".
  double? get refreshSeconds => throw _privateConstructorUsedError;

  /// Serializes this ThemeUiSlot to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeUiSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeUiSlotCopyWith<ThemeUiSlot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeUiSlotCopyWith<$Res> {
  factory $ThemeUiSlotCopyWith(
          ThemeUiSlot value, $Res Function(ThemeUiSlot) then) =
      _$ThemeUiSlotCopyWithImpl<$Res, ThemeUiSlot>;
  @useResult
  $Res call({List<Map<String, dynamic>> children, double? refreshSeconds});
}

/// @nodoc
class _$ThemeUiSlotCopyWithImpl<$Res, $Val extends ThemeUiSlot>
    implements $ThemeUiSlotCopyWith<$Res> {
  _$ThemeUiSlotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeUiSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? children = null,
    Object? refreshSeconds = freezed,
  }) {
    return _then(_value.copyWith(
      children: null == children
          ? _value.children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      refreshSeconds: freezed == refreshSeconds
          ? _value.refreshSeconds
          : refreshSeconds // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeUiSlotImplCopyWith<$Res>
    implements $ThemeUiSlotCopyWith<$Res> {
  factory _$$ThemeUiSlotImplCopyWith(
          _$ThemeUiSlotImpl value, $Res Function(_$ThemeUiSlotImpl) then) =
      __$$ThemeUiSlotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Map<String, dynamic>> children, double? refreshSeconds});
}

/// @nodoc
class __$$ThemeUiSlotImplCopyWithImpl<$Res>
    extends _$ThemeUiSlotCopyWithImpl<$Res, _$ThemeUiSlotImpl>
    implements _$$ThemeUiSlotImplCopyWith<$Res> {
  __$$ThemeUiSlotImplCopyWithImpl(
      _$ThemeUiSlotImpl _value, $Res Function(_$ThemeUiSlotImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeUiSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? children = null,
    Object? refreshSeconds = freezed,
  }) {
    return _then(_$ThemeUiSlotImpl(
      children: null == children
          ? _value._children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      refreshSeconds: freezed == refreshSeconds
          ? _value.refreshSeconds
          : refreshSeconds // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeUiSlotImpl implements _ThemeUiSlot {
  const _$ThemeUiSlotImpl(
      {final List<Map<String, dynamic>> children = const [],
      this.refreshSeconds})
      : _children = children;

  factory _$ThemeUiSlotImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeUiSlotImplFromJson(json);

  final List<Map<String, dynamic>> _children;
  @override
  @JsonKey()
  List<Map<String, dynamic>> get children {
    if (_children is EqualUnmodifiableListView) return _children;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_children);
  }

  /// How often the host may refresh data-bound children in this slot.
  /// Zero means "on state changes only".
  @override
  final double? refreshSeconds;

  @override
  String toString() {
    return 'ThemeUiSlot(children: $children, refreshSeconds: $refreshSeconds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeUiSlotImpl &&
            const DeepCollectionEquality().equals(other._children, _children) &&
            (identical(other.refreshSeconds, refreshSeconds) ||
                other.refreshSeconds == refreshSeconds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(_children), refreshSeconds);

  /// Create a copy of ThemeUiSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeUiSlotImplCopyWith<_$ThemeUiSlotImpl> get copyWith =>
      __$$ThemeUiSlotImplCopyWithImpl<_$ThemeUiSlotImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeUiSlotImplToJson(
      this,
    );
  }
}

abstract class _ThemeUiSlot implements ThemeUiSlot {
  const factory _ThemeUiSlot(
      {final List<Map<String, dynamic>> children,
      final double? refreshSeconds}) = _$ThemeUiSlotImpl;

  factory _ThemeUiSlot.fromJson(Map<String, dynamic> json) =
      _$ThemeUiSlotImpl.fromJson;

  @override
  List<Map<String, dynamic>> get children;

  /// How often the host may refresh data-bound children in this slot.
  /// Zero means "on state changes only".
  @override
  double? get refreshSeconds;

  /// Create a copy of ThemeUiSlot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeUiSlotImplCopyWith<_$ThemeUiSlotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeUiScreen _$ThemeUiScreenFromJson(Map<String, dynamic> json) {
  return _ThemeUiScreen.fromJson(json);
}

/// @nodoc
mixin _$ThemeUiScreen {
  String? get title => throw _privateConstructorUsedError;
  bool get showBack => throw _privateConstructorUsedError;
  List<Map<String, dynamic>> get children => throw _privateConstructorUsedError;

  /// Serializes this ThemeUiScreen to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeUiScreen
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeUiScreenCopyWith<ThemeUiScreen> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeUiScreenCopyWith<$Res> {
  factory $ThemeUiScreenCopyWith(
          ThemeUiScreen value, $Res Function(ThemeUiScreen) then) =
      _$ThemeUiScreenCopyWithImpl<$Res, ThemeUiScreen>;
  @useResult
  $Res call(
      {String? title, bool showBack, List<Map<String, dynamic>> children});
}

/// @nodoc
class _$ThemeUiScreenCopyWithImpl<$Res, $Val extends ThemeUiScreen>
    implements $ThemeUiScreenCopyWith<$Res> {
  _$ThemeUiScreenCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeUiScreen
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? showBack = null,
    Object? children = null,
  }) {
    return _then(_value.copyWith(
      title: freezed == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      showBack: null == showBack
          ? _value.showBack
          : showBack // ignore: cast_nullable_to_non_nullable
              as bool,
      children: null == children
          ? _value.children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeUiScreenImplCopyWith<$Res>
    implements $ThemeUiScreenCopyWith<$Res> {
  factory _$$ThemeUiScreenImplCopyWith(
          _$ThemeUiScreenImpl value, $Res Function(_$ThemeUiScreenImpl) then) =
      __$$ThemeUiScreenImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? title, bool showBack, List<Map<String, dynamic>> children});
}

/// @nodoc
class __$$ThemeUiScreenImplCopyWithImpl<$Res>
    extends _$ThemeUiScreenCopyWithImpl<$Res, _$ThemeUiScreenImpl>
    implements _$$ThemeUiScreenImplCopyWith<$Res> {
  __$$ThemeUiScreenImplCopyWithImpl(
      _$ThemeUiScreenImpl _value, $Res Function(_$ThemeUiScreenImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeUiScreen
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? showBack = null,
    Object? children = null,
  }) {
    return _then(_$ThemeUiScreenImpl(
      title: freezed == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      showBack: null == showBack
          ? _value.showBack
          : showBack // ignore: cast_nullable_to_non_nullable
              as bool,
      children: null == children
          ? _value._children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeUiScreenImpl implements _ThemeUiScreen {
  const _$ThemeUiScreenImpl(
      {this.title,
      this.showBack = false,
      final List<Map<String, dynamic>> children = const []})
      : _children = children;

  factory _$ThemeUiScreenImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeUiScreenImplFromJson(json);

  @override
  final String? title;
  @override
  @JsonKey()
  final bool showBack;
  final List<Map<String, dynamic>> _children;
  @override
  @JsonKey()
  List<Map<String, dynamic>> get children {
    if (_children is EqualUnmodifiableListView) return _children;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_children);
  }

  @override
  String toString() {
    return 'ThemeUiScreen(title: $title, showBack: $showBack, children: $children)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeUiScreenImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.showBack, showBack) ||
                other.showBack == showBack) &&
            const DeepCollectionEquality().equals(other._children, _children));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, title, showBack,
      const DeepCollectionEquality().hash(_children));

  /// Create a copy of ThemeUiScreen
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeUiScreenImplCopyWith<_$ThemeUiScreenImpl> get copyWith =>
      __$$ThemeUiScreenImplCopyWithImpl<_$ThemeUiScreenImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeUiScreenImplToJson(
      this,
    );
  }
}

abstract class _ThemeUiScreen implements ThemeUiScreen {
  const factory _ThemeUiScreen(
      {final String? title,
      final bool showBack,
      final List<Map<String, dynamic>> children}) = _$ThemeUiScreenImpl;

  factory _ThemeUiScreen.fromJson(Map<String, dynamic> json) =
      _$ThemeUiScreenImpl.fromJson;

  @override
  String? get title;
  @override
  bool get showBack;
  @override
  List<Map<String, dynamic>> get children;

  /// Create a copy of ThemeUiScreen
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeUiScreenImplCopyWith<_$ThemeUiScreenImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ThemeUiTemplate _$ThemeUiTemplateFromJson(Map<String, dynamic> json) {
  return _ThemeUiTemplate.fromJson(json);
}

/// @nodoc
mixin _$ThemeUiTemplate {
  List<String> get params => throw _privateConstructorUsedError;
  List<Map<String, dynamic>> get children => throw _privateConstructorUsedError;

  /// Serializes this ThemeUiTemplate to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ThemeUiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThemeUiTemplateCopyWith<ThemeUiTemplate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThemeUiTemplateCopyWith<$Res> {
  factory $ThemeUiTemplateCopyWith(
          ThemeUiTemplate value, $Res Function(ThemeUiTemplate) then) =
      _$ThemeUiTemplateCopyWithImpl<$Res, ThemeUiTemplate>;
  @useResult
  $Res call({List<String> params, List<Map<String, dynamic>> children});
}

/// @nodoc
class _$ThemeUiTemplateCopyWithImpl<$Res, $Val extends ThemeUiTemplate>
    implements $ThemeUiTemplateCopyWith<$Res> {
  _$ThemeUiTemplateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThemeUiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? params = null,
    Object? children = null,
  }) {
    return _then(_value.copyWith(
      params: null == params
          ? _value.params
          : params // ignore: cast_nullable_to_non_nullable
              as List<String>,
      children: null == children
          ? _value.children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ThemeUiTemplateImplCopyWith<$Res>
    implements $ThemeUiTemplateCopyWith<$Res> {
  factory _$$ThemeUiTemplateImplCopyWith(_$ThemeUiTemplateImpl value,
          $Res Function(_$ThemeUiTemplateImpl) then) =
      __$$ThemeUiTemplateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<String> params, List<Map<String, dynamic>> children});
}

/// @nodoc
class __$$ThemeUiTemplateImplCopyWithImpl<$Res>
    extends _$ThemeUiTemplateCopyWithImpl<$Res, _$ThemeUiTemplateImpl>
    implements _$$ThemeUiTemplateImplCopyWith<$Res> {
  __$$ThemeUiTemplateImplCopyWithImpl(
      _$ThemeUiTemplateImpl _value, $Res Function(_$ThemeUiTemplateImpl) _then)
      : super(_value, _then);

  /// Create a copy of ThemeUiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? params = null,
    Object? children = null,
  }) {
    return _then(_$ThemeUiTemplateImpl(
      params: null == params
          ? _value._params
          : params // ignore: cast_nullable_to_non_nullable
              as List<String>,
      children: null == children
          ? _value._children
          : children // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ThemeUiTemplateImpl implements _ThemeUiTemplate {
  const _$ThemeUiTemplateImpl(
      {final List<String> params = const [],
      final List<Map<String, dynamic>> children = const []})
      : _params = params,
        _children = children;

  factory _$ThemeUiTemplateImpl.fromJson(Map<String, dynamic> json) =>
      _$$ThemeUiTemplateImplFromJson(json);

  final List<String> _params;
  @override
  @JsonKey()
  List<String> get params {
    if (_params is EqualUnmodifiableListView) return _params;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_params);
  }

  final List<Map<String, dynamic>> _children;
  @override
  @JsonKey()
  List<Map<String, dynamic>> get children {
    if (_children is EqualUnmodifiableListView) return _children;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_children);
  }

  @override
  String toString() {
    return 'ThemeUiTemplate(params: $params, children: $children)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThemeUiTemplateImpl &&
            const DeepCollectionEquality().equals(other._params, _params) &&
            const DeepCollectionEquality().equals(other._children, _children));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_params),
      const DeepCollectionEquality().hash(_children));

  /// Create a copy of ThemeUiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThemeUiTemplateImplCopyWith<_$ThemeUiTemplateImpl> get copyWith =>
      __$$ThemeUiTemplateImplCopyWithImpl<_$ThemeUiTemplateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ThemeUiTemplateImplToJson(
      this,
    );
  }
}

abstract class _ThemeUiTemplate implements ThemeUiTemplate {
  const factory _ThemeUiTemplate(
      {final List<String> params,
      final List<Map<String, dynamic>> children}) = _$ThemeUiTemplateImpl;

  factory _ThemeUiTemplate.fromJson(Map<String, dynamic> json) =
      _$ThemeUiTemplateImpl.fromJson;

  @override
  List<String> get params;
  @override
  List<Map<String, dynamic>> get children;

  /// Create a copy of ThemeUiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThemeUiTemplateImplCopyWith<_$ThemeUiTemplateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
