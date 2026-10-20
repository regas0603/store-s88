import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_config.dart';

void main() {
  group('BootConfig (Phase 1: 1 link Git JSON)', () {
    test('bootConfigUrlFor ghép đúng URL per-app <bundleId>.json', () {
      expect(
        BootConfig.bootConfigUrlFor('com.example.appA1'),
        '${BootConfig.kConfigBaseUrl}/com.example.appA1.json',
      );
      expect(
        BootConfig.bootConfigUrlFor('com.other.appB'),
        '${BootConfig.kConfigBaseUrl}/com.other.appB.json',
      );
      // Repo configs để file trong thư mục `apps/` (bỏ tiền tố `config_` ở
      // Step 4.6 — bundle id đã encode trong tên file).
      expect(BootConfig.kConfigBaseUrl.endsWith('/apps'), isTrue);
    });

    group('readString', () {
      test('trả null khi thiếu field / rỗng / sai kiểu', () {
        expect(BootConfig.readString(<String, dynamic>{}, 'api_domain'),
            isNull);
        expect(
          BootConfig.readString(
            <String, dynamic>{'api_domain': ''},
            'api_domain',
          ),
          isNull,
        );
        expect(
          BootConfig.readString(
            <String, dynamic>{'api_domain': 123},
            'api_domain',
          ),
          isNull,
        );
      });

      test('trả giá trị khi là non-empty String', () {
        expect(
          BootConfig.readString(
            <String, dynamic>{'api_domain': 'https://x.dev'},
            'api_domain',
          ),
          'https://x.dev',
        );
      });
    });

    group('readOptionalInt', () {
      test('trả null khi thiếu / sai kiểu', () {
        expect(
          BootConfig.readOptionalInt(<String, dynamic>{}, 'min_version_code'),
          isNull,
        );
        expect(
          BootConfig.readOptionalInt(
            <String, dynamic>{'min_version_code': '5'},
            'min_version_code',
          ),
          isNull,
        );
      });

      test('chấp nhận int và num', () {
        expect(
          BootConfig.readOptionalInt(
            <String, dynamic>{'min_version_code': 5},
            'min_version_code',
          ),
          5,
        );
        expect(
          BootConfig.readOptionalInt(
            <String, dynamic>{'min_version_code': 5.0},
            'min_version_code',
          ),
          5,
        );
      });
    });

    group('readApiDomain / readRsDomain (schema api_domain)', () {
      test('api_domain + rs_domain ở root -> đọc đúng', () {
        expect(
          BootConfig.readApiDomain(<String, dynamic>{
            'api_domain': 'https://check.example.com/?command=',
          }),
          'https://check.example.com/?command=',
        );
        expect(
          BootConfig.readRsDomain(<String, dynamic>{
            'rs_domain': 'https://rs.example.com',
          }),
          'https://rs.example.com',
        );
      });

      test('api_domain thiếu/rỗng/sai kiểu -> null (fail-open)', () {
        expect(BootConfig.readApiDomain(<String, dynamic>{}), isNull);
        expect(
          BootConfig.readApiDomain(<String, dynamic>{'api_domain': ''}),
          isNull,
        );
        expect(
          BootConfig.readApiDomain(
              <String, dynamic>{'api_domain': '   '}),
          isNull,
        );
        expect(
          BootConfig.readApiDomain(<String, dynamic>{'api_domain': 123}),
          isNull,
        );
      });

      test('rs_domain fallback: update.api_base_url vẫn đọc được', () {
        expect(
          BootConfig.readRsDomain(<String, dynamic>{
            'update': <String, dynamic>{'api_base_url': 'http://pb2.local'},
          }),
          'http://pb2.local',
        );
      });

      test('rs_domain ưu tiên root hơn block update', () {
        expect(
          BootConfig.readRsDomain(<String, dynamic>{
            'rs_domain': 'https://new.example.com',
            'update': <String, dynamic>{'api_base_url': 'https://old.example.com'},
          }),
          'https://new.example.com',
        );
      });

      test('rs_domain được trim khoảng trắng thừa', () {
        expect(
          BootConfig.readRsDomain(<String, dynamic>{
            'rs_domain': '  https://pb.example.com/  ',
          }),
          'https://pb.example.com/',
        );
      });

      test('không có trường nào -> cả 2 null (fail-open)', () {
        expect(BootConfig.readApiDomain(<String, dynamic>{}), isNull);
        expect(BootConfig.readRsDomain(<String, dynamic>{}), isNull);
        expect(
          BootConfig.readRsDomain(
              <String, dynamic>{'update': 'not-a-map'}),
          isNull,
        );
      });
    });

    group('appReleaseDate date gate (Step 2)', () {
      test('appReleaseDate là ngày (00:00, không giờ phút)', () {
        final DateTime d = BootConfig.appReleaseDate;
        expect(d, DateTime(d.year, d.month, d.day));
      });
    });

  });
}
