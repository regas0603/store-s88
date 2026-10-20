import 'dart:convert';
import 'dart:math';

import 'package:loading_kit/models/boot_command_response.dart';
import 'package:loading_kit/network/config_loader.dart';
import 'package:loading_kit/network/plain_body_dio_transformer.dart';
import 'package:dio/dio.dart';

class ApiClient {
  static Future<Map<String, dynamic>> getConfig(String url) =>
      ConfigLoader.getConfig(url);

  /// URL request thật cho boot command: giữ nguyên param sẵn có (ví dụ
  /// `command=<bundleId>` do `api_domain` mang theo) và thêm `r=<random>` để
  /// không dính cache của GitHub raw / CDN / proxy.
  ///
  /// [random] chỉ để test cho kết quả cố định.
  static Uri buildBootRequestUri(String url, {double? random}) {
    final Uri base = Uri.parse(url);
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'r': (random ?? Random().nextDouble()).toString(),
      },
    );
  }

  /// Uses Dio with a plain-body transformer so malformed `Content-Type` does not trigger MIME warnings.
  ///
  /// Response này quyết định user thật hay reviewer (`status`) → KHÔNG được
  /// dùng bản cache (xem [buildBootRequestUri]).
  static Future<BootCommandResponse> getBootCommandResponse({
    required String url,
  }) async {
    final Uri requestUri = buildBootRequestUri(url);
    final Stopwatch sw = Stopwatch()..start();
    // print('[Boot] bootCommand GET $requestUri');
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: const <String, String>{
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ),
    );
    dio.transformer = PlainBodyDioTransformer();
    try {
      final Response<String> response = await dio.get<String>(
        requestUri.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      // final int httpElapsed = sw.elapsedMilliseconds;
      // print(
      //   '[Boot] HTTP ${response.statusCode} '
      //   'in ${httpElapsed}ms body.length=${response.data?.length ?? 0}',
      // );
      final String rawJson = (response.data ?? '').trim();
      // print('[Boot] body=$rawJson');
      if (rawJson.isEmpty) {
        // FormatException = lỗi parse/schema (không phải lỗi mạng) → log
        // errorKind=parse để triage.
        throw FormatException('Empty response body. url=$requestUri');
      }
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
          'Response is not a JSON object. body=$rawJson',
        );
      }
      sw.stop();
      // print(
      //   '[Boot] OK total=${sw.elapsedMilliseconds}ms '
      //   'parsed-keys=${decoded.keys.toList()}',
      // );
      return BootCommandResponse.fromJson(decoded);
    } on DioException {
      sw.stop();
      // print(
      //   '[Boot] DioException after=${sw.elapsedMilliseconds}ms\n'
      //   '  type=${e.type}\n'
      //   '  message=${e.message}\n'
      //   '  statusCode=${e.response?.statusCode}\n'
      //   '  responseBody=${e.response?.data}',
      // );
      rethrow;
    } catch (e) {
      sw.stop();
      // print(
      //   '[Boot] FAILED after=${sw.elapsedMilliseconds}ms '
      //   'errorType=${e.runtimeType} error=$e',
      // );
      rethrow;
    }
  }
}
