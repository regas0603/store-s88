import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart';
import 'package:loading_kit/models/boot_command_response.dart';
import 'package:loading_kit/network/config_loader.dart';

/// Lấy 1 `TypeError` thật (cast null → Map) để test nhánh phân loại `parse`.
Object captureTypeError() {
  try {
    final dynamic value = null;
    value as Map<String, dynamic>;
  } catch (e) {
    return e;
  }
  throw StateError('không tạo được TypeError');
}

/// test step 4 (checkBoot): 1 request DUY NHẤT, không retry, không hỏi user.
/// Model chỉ parse `status`; lỗi mạng/parse trả `hasError: true` (không throw)
/// để host mở app (AppScreen) thay vì kẹt splash.
void main() {
  group('executeCheckBoot (không retry)', () {
    test('status == 0 (body CHỈ có status) -> canBoot=true', () async {
      // Đúng ca thật đã gặp trên simulator: endpoint trả `{"status":0}`, không
      // có `data`. Model chỉ parse `status` nên không còn TypeError.
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      int calls = 0;
      String? requestedUrl;
      final ({bool canBoot, bool hasError}) result = await coordinator
          .executeCheckBoot(
        apiDomain: 'https://alpha-weather-check.workers.dev/?command=',
        appBundleId: 'com.example.appA1',
        request: (String url) async {
          calls++;
          requestedUrl = url;
          return BootCommandResponse.fromJson(<String, dynamic>{'status': 0});
        },
      );

      expect(calls, 1);
      expect(
        requestedUrl,
        'https://alpha-weather-check.workers.dev/?command=com.example.appA1',
      );
      expect(result.canBoot, isTrue);
      expect(result.hasError, isFalse);
    });

    test('status != 0 -> canBoot=false, hasError=false, gọi đúng 1 lần',
        () async {
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      int calls = 0;
      final ({bool canBoot, bool hasError}) result = await coordinator
          .executeCheckBoot(
        apiDomain: 'https://example-top123.site/?c=',
        appBundleId: 'com.example.appA1',
        request: (String url) async {
          calls++;
          return BootCommandResponse.fromJson(<String, dynamic>{'status': 1});
        },
      );

      expect(calls, 1);
      expect(result.canBoot, isFalse);
      expect(result.hasError, isFalse);
    });

    test('lỗi mạng -> hasError=true, canBoot=false, KHÔNG retry', () async {
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      int calls = 0;
      final ({bool canBoot, bool hasError}) result = await coordinator
          .executeCheckBoot(
        apiDomain: 'https://example-top123.site/?c=',
        appBundleId: 'com.example.appA1',
        request: (String url) async {
          calls++;
          throw Exception('DNS failure');
        },
      );

      // 1 lần duy nhất — không còn executeRetry(3 lần) + prompt dialog.
      expect(calls, 1);
      expect(result.canBoot, isFalse);
      expect(result.hasError, isTrue);
    });

    test('body thiếu status (sai schema) -> hasError=true, không throw',
        () async {
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      final ({bool canBoot, bool hasError}) result = await coordinator
          .executeCheckBoot(
        apiDomain: 'http://127.0.0.1:8787/ca/res?command=',
        appBundleId: 'com.example.appA1',
        request: (String url) async => BootCommandResponse.fromJson(
          <String, dynamic>{'data': <String, dynamic>{}},
        ),
      );

      expect(result.canBoot, isFalse);
      expect(result.hasError, isTrue);
    });
  });

  group('executeParseBootConfig (KHÔNG check scheme)', () {
    test('api_domain + rs_domain http:// nhận nguyên văn', () {
      final BootConfigResult result =
          BootFlowCoordinator().executeParseBootConfig(<String, dynamic>{
        'api_domain': 'http://127.0.0.1:8787/ca/res?command=',
        'rs_domain': 'http://pb2.local',
      }, bundleId: 'com.example.app');

      expect(result.apiDomain, 'http://127.0.0.1:8787/ca/res?command=');
      expect(result.rsDomain, 'http://pb2.local');
      expect(result.hasError, isFalse);
    });

    test('rs_domain fallback từ update.api_base_url vẫn đọc được', () {
      final BootConfigResult result =
          BootFlowCoordinator().executeParseBootConfig(<String, dynamic>{
        'api_domain': 'http://127.0.0.1:8787/ca/res?command=',
        'update': <String, dynamic>{'api_base_url': 'http://pb2.local'},
      }, bundleId: 'com.example.app');

      expect(result.apiDomain, 'http://127.0.0.1:8787/ca/res?command=');
      expect(result.rsDomain, 'http://pb2.local');
      expect(result.hasError, isFalse);
    });

    test('thiếu / rỗng / sai kiểu api_domain -> null (mở app demo)', () {
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      expect(
        coordinator.executeParseBootConfig(<String, dynamic>{}, bundleId: 'com.example.app').apiDomain,
        isNull,
      );
      expect(
        coordinator
            .executeParseBootConfig(<String, dynamic>{'api_domain': ''}, bundleId: 'com.example.app')
            .apiDomain,
        isNull,
      );
      expect(
        coordinator
            .executeParseBootConfig(<String, dynamic>{'api_domain': 123}, bundleId: 'com.example.app')
            .apiDomain,
        isNull,
      );
    });
  });

  group('executeDescribeErrorKind (chỉ để log)', () {
    final BootFlowCoordinator coordinator = BootFlowCoordinator();

    RequestOptions options() => RequestOptions(path: '/ca/res');

    test('timeout', () {
      expect(
        coordinator.executeDescribeErrorKind(TimeoutException('slow')),
        'timeout',
      );
      expect(
        coordinator.executeDescribeErrorKind(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        'timeout',
      );
      expect(
        coordinator.executeDescribeErrorKind(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.receiveTimeout,
          ),
        ),
        'timeout',
      );
    });

    test('http (404 config / 5xx)', () {
      expect(
        coordinator.executeDescribeErrorKind(
          ConfigHttpException(404, 'https://raw.example/x.json'),
        ),
        'http',
      );
      expect(
        coordinator.executeDescribeErrorKind(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.badResponse,
          ),
        ),
        'http',
      );
    });

    test('parse (body rỗng / không phải JSON / thiếu field)', () {
      expect(
        coordinator.executeDescribeErrorKind(const FormatException('rỗng')),
        'parse',
      );
      expect(
        coordinator.executeDescribeErrorKind(captureTypeError()),
        'parse',
      );
    });

    test('network + unknown', () {
      expect(
        coordinator.executeDescribeErrorKind(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.connectionError,
          ),
        ),
        'network',
      );
      expect(
        coordinator.executeDescribeErrorKind(Exception('?')),
        'unknown',
      );
    });
  });
}
