// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'boot_command_response.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BootCommandResponse {

 int get status;
/// Create a copy of BootCommandResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BootCommandResponseCopyWith<BootCommandResponse> get copyWith => _$BootCommandResponseCopyWithImpl<BootCommandResponse>(this as BootCommandResponse, _$identity);

  /// Serializes this BootCommandResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BootCommandResponse&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status);

@override
String toString() {
  return 'BootCommandResponse(status: $status)';
}


}

/// @nodoc
abstract mixin class $BootCommandResponseCopyWith<$Res>  {
  factory $BootCommandResponseCopyWith(BootCommandResponse value, $Res Function(BootCommandResponse) _then) = _$BootCommandResponseCopyWithImpl;
@useResult
$Res call({
 int status
});




}
/// @nodoc
class _$BootCommandResponseCopyWithImpl<$Res>
    implements $BootCommandResponseCopyWith<$Res> {
  _$BootCommandResponseCopyWithImpl(this._self, this._then);

  final BootCommandResponse _self;
  final $Res Function(BootCommandResponse) _then;

/// Create a copy of BootCommandResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [BootCommandResponse].
extension BootCommandResponsePatterns on BootCommandResponse {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BootCommandResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BootCommandResponse() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BootCommandResponse value)  $default,){
final _that = this;
switch (_that) {
case _BootCommandResponse():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BootCommandResponse value)?  $default,){
final _that = this;
switch (_that) {
case _BootCommandResponse() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BootCommandResponse() when $default != null:
return $default(_that.status);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int status)  $default,) {final _that = this;
switch (_that) {
case _BootCommandResponse():
return $default(_that.status);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int status)?  $default,) {final _that = this;
switch (_that) {
case _BootCommandResponse() when $default != null:
return $default(_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BootCommandResponse implements BootCommandResponse {
  const _BootCommandResponse({required this.status});
  factory _BootCommandResponse.fromJson(Map<String, dynamic> json) => _$BootCommandResponseFromJson(json);

@override final  int status;

/// Create a copy of BootCommandResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BootCommandResponseCopyWith<_BootCommandResponse> get copyWith => __$BootCommandResponseCopyWithImpl<_BootCommandResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BootCommandResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BootCommandResponse&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status);

@override
String toString() {
  return 'BootCommandResponse(status: $status)';
}


}

/// @nodoc
abstract mixin class _$BootCommandResponseCopyWith<$Res> implements $BootCommandResponseCopyWith<$Res> {
  factory _$BootCommandResponseCopyWith(_BootCommandResponse value, $Res Function(_BootCommandResponse) _then) = __$BootCommandResponseCopyWithImpl;
@override @useResult
$Res call({
 int status
});




}
/// @nodoc
class __$BootCommandResponseCopyWithImpl<$Res>
    implements _$BootCommandResponseCopyWith<$Res> {
  __$BootCommandResponseCopyWithImpl(this._self, this._then);

  final _BootCommandResponse _self;
  final $Res Function(_BootCommandResponse) _then;

/// Create a copy of BootCommandResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(_BootCommandResponse(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
