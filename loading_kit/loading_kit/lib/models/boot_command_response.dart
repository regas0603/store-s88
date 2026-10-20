import 'package:freezed_annotation/freezed_annotation.dart';

part 'boot_command_response.freezed.dart';
part 'boot_command_response.g.dart';

/// Response của endpoint boot command (step 4).
///
/// CHỈ quan tâm `status`: `0` = boot (save flag → live), khác `0` = demo.
/// KHÔNG parse `data`/field khác — body chỉ cần `{"status":0}` là đủ. Field
/// `data` của server (ip/message) là để debug phía server, app không dùng.
@freezed
abstract class BootCommandResponse with _$BootCommandResponse {
  const factory BootCommandResponse({
    required int status,
  }) = _BootCommandResponse;

  factory BootCommandResponse.fromJson(Map<String, dynamic> json) =>
      _$BootCommandResponseFromJson(json);
}

