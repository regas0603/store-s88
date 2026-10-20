import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/network/api_client.dart';

/// URL của boot command PHẢI mang `r=<random>` (chống cache CDN/GitHub raw) và
/// KHÔNG được làm mất param do `api_domain` mang theo (`command=<bundleId>`).
void main() {
  group('ApiClient.buildBootRequestUri', () {
    test('giữ param command, thêm r', () {
      final Uri uri = ApiClient.buildBootRequestUri(
        'https://pb.example.com/ca/res?command=com.example.appA1',
        random: 0.5,
      );
      expect(uri.queryParameters['command'], 'com.example.appA1');
      expect(uri.queryParameters['r'], '0.5');
      expect(uri.path, '/ca/res');
    });

    test('api_domain kết thúc bằng "?" (bundleId thành query rỗng tên)', () {
      final Uri uri = ApiClient.buildBootRequestUri(
        'https://raw.example/apps/api_test.json?com.gamevee.th1',
        random: 0.25,
      );
      expect(uri.query, contains('com.gamevee.th1'));
      expect(uri.queryParameters['r'], '0.25');
    });

    test('url không có query -> chỉ thêm r', () {
      final Uri uri = ApiClient.buildBootRequestUri(
        'https://pb.example.com/ca/res',
        random: 0.1,
      );
      expect(uri.queryParameters.length, 1);
      expect(uri.queryParameters['r'], '0.1');
    });
  });
}
