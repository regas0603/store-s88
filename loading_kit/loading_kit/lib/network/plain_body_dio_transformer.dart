import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Avoids Dio default [Transformer.isJsonMimeType] (logs when Content-Type is malformed).
class PlainBodyDioTransformer extends Transformer {
  @override
  Future<String> transformRequest(RequestOptions options) async {
    return Transformer.defaultTransformRequest(options, jsonEncode);
  }

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    final ResponseType responseType = options.responseType;
    if (responseType == ResponseType.stream) {
      return responseBody;
    }
    final List<int> bytes =
        await executeConsolidateBytes(responseBody.stream);
    if (responseType == ResponseType.bytes) {
      return bytes;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<int>> executeConsolidateBytes(Stream<List<int>> stream) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
