import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// HTTP status ngoài 2xx khi fetch config per-app (404 = bundle id chưa có
/// file config, 5xx = GitHub/server lỗi...). Typed để log/triage phân biệt
/// được "server trả HTTP lỗi" với "mạng chết" / "JSON sai schema".
class ConfigHttpException implements Exception {
  ConfigHttpException(this.statusCode, this.url);

  final int statusCode;
  final String url;

  @override
  String toString() => 'ConfigHttpException(HTTP $statusCode for $url)';
}

class ConfigLoader {
  /// Timeout 20s thay vì 10s — mạng yếu (3G, wifi yếu, GitHub cold cache)
  /// vẫn cần đủ thời gian. 10s thường gây "lỗi server" giả.
  static const Duration _httpTimeout = Duration(seconds: 20);

  static Future<Map<String, dynamic>> getConfig(String url) async {
    final Uri base = Uri.parse(url);
    final Uri requestUri = base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'r': Random().nextDouble().toString(),
      },
    );
    final Stopwatch sw = Stopwatch()..start();
    // print('[Boot] GET $requestUri (timeout=${_httpTimeout.inSeconds}s)');
    try {
      final http.Response response =
          await http.get(requestUri).timeout(_httpTimeout);
      // final int httpElapsed = sw.elapsedMilliseconds;
      // print(
      //   '[Boot] HTTP ${response.statusCode} '
      //   'in ${httpElapsed}ms '
      //   'body.length=${response.body.length} '
      //   'content-type=${response.headers['content-type']}',
      // );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ConfigHttpException(response.statusCode, url);
      }
      if (response.body.isEmpty) {
        throw FormatException('Empty config response for $url');
      }
      final String rawText = response.body;
      final String trimmedText = rawText.trim();
      // Plain JSON path.
      if (trimmedText.startsWith('{') && trimmedText.endsWith('}')) {
        try {
          final Map<String, dynamic> result =
              jsonDecode(trimmedText) as Map<String, dynamic>;
          sw.stop();
          // print(
          //   '[Boot] OK url=$url plain-JSON parsed in '
          //   '${sw.elapsedMilliseconds - httpElapsed}ms '
          //   '(total=${sw.elapsedMilliseconds}ms) keys=${result.keys.toList()}',
          // );
          return result;
        } catch (e) {
          throw FormatException(
            'Plain-JSON parse failed for $url: $e. '
            'Body preview: ${_preview(rawText)}',
          );
        }
      }
      // Base64 path — simple version (strip whitespace + decode).
      try {
        // Decode base64 — strip all whitespace first to handle GitHub line wrapping.
        final String cleanText = rawText.replaceAll(RegExp(r'\s+'), '');
        // print(
        //   '[Boot] base64 cleanText.length=${cleanText.length} '
        //   '(mod4=${cleanText.length % 4})',
        // );
        final List<int> bytes = base64Decode(cleanText);
        final String decodedText = utf8.decode(bytes);
        final Map<String, dynamic> result =
            _lenientJsonDecodeObject(decodedText, url);
        sw.stop();
        // print(
        //   '[Boot] OK url=$url base64-JSON parsed in '
        //   '${sw.elapsedMilliseconds - httpElapsed}ms '
        //   '(total=${sw.elapsedMilliseconds}ms) keys=${result.keys.toList()}',
        // );
        return result;
      } catch (e) {
        throw FormatException(
          'Base64-JSON parse failed for $url: $e. '
          'Body preview: ${_preview(rawText)}',
        );
      }
    } catch (e) {
      sw.stop();
      // print(
      //   '[Boot] FAILED url=$url after=${sw.elapsedMilliseconds}ms '
      //   'errorType=${e.runtimeType} error=$e',
      // );
      rethrow;
    }
  }

  /// Lấy 200 ký tự đầu của body để debug HTML 404 / error pages.
  static String _preview(String body) {
    final String trimmed = body.trim();
    if (trimmed.length <= 200) return trimmed;
    return '${trimmed.substring(0, 200)}…';
  }

  /// Parse JSON object có khả năng "tha thứ" 2 lỗi format phổ biến khi file
  /// được edit thủ công:
  /// 1. **Trailing comma trước `}` hoặc `]`** — vd: `{"a": 1,}` → strict JSON
  ///    fail, lenient pass.
  /// 2. **Extra characters sau JSON object đầu tiên** — vd: `{"a":1}\n}` →
  ///    truncate phần sau khi tìm được balanced closing `}`.
  ///
  /// Strategy: thử strict trước, nếu fail thì áp 2 fix rồi retry. Log warning
  /// nếu fix giúp được (để user biết file cần fix).
  static Map<String, dynamic> _lenientJsonDecodeObject(
    String text,
    String url,
  ) {
    // Attempt 1: strict
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (firstError) {
      // print(
      //   '[Boot] strict JSON parse FAILED for $url: $firstError\n'
      //   '  → trying lenient mode (trim trailing extra chars + remove trailing commas)',
      // );
    }

    // Attempt 2: trim mọi ký tự sau closing `}` đầu tiên (balanced).
    final String? trimmed = _extractFirstBalancedJsonObject(text);
    if (trimmed != null && trimmed.length < text.length) {
      try {
        final Map<String, dynamic> result =
            jsonDecode(trimmed) as Map<String, dynamic>;
        // print(
        //   '[Boot] LENIENT FIX (trimmed ${text.length - trimmed.length} '
        //   'extra chars after JSON close) for $url. '
        //   'Recommend fix file content!',
        // );
        return result;
      } catch (_) {
        // Fall through tiếp
      }
    }

    // Attempt 3: trim trailing commas trước `}` hoặc `]`.
    final String noTrailingComma = (trimmed ?? text).replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (Match m) => m.group(1)!,
    );
    if (noTrailingComma != (trimmed ?? text)) {
      try {
        final Map<String, dynamic> result =
            jsonDecode(noTrailingComma) as Map<String, dynamic>;
        // print(
        //   '[Boot] LENIENT FIX (removed trailing comma(s)) for $url. '
        //   'Recommend fix file content!',
        // );
        return result;
      } catch (_) {
        // Fall through, throw original error.
      }
    }

    // Tất cả attempt fail → throw error gốc (caller sẽ wrap với body preview).
    throw FormatException(
      'Lenient JSON parse failed for $url. File có lỗi syntax nghiêm trọng '
      '(không phải trailing comma cũng không phải extra trailing chars). '
      'Decode file và check syntax thủ công.',
    );
  }

  /// Tìm JSON object đầu tiên có cặp `{` và `}` cân bằng. Bỏ qua dấu trong
  /// string literals. Trả về substring từ `{` đầu tiên tới `}` đóng cân bằng,
  /// hoặc null nếu không tìm được.
  static String? _extractFirstBalancedJsonObject(String text) {
    int braceCount = 0;
    bool inString = false;
    bool escape = false;
    int? start;
    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') {
        start ??= i;
        braceCount++;
      } else if (ch == '}') {
        braceCount--;
        if (braceCount == 0 && start != null) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String base64EncodeFromJson(Object? json) {
    final String jsonString = jsonEncode(json);
    final List<int> utf8Bytes = utf8.encode(jsonString);
    return base64Encode(utf8Bytes);
  }
}
