import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/api_error.dart';

void main() {
  final req = RequestOptions(path: '/x');

  DioException withType(DioExceptionType type) =>
      DioException(requestOptions: req, type: type);

  DioException withResponse(int code, Object? data) => DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: req, statusCode: code, data: data),
      );

  group('apiErrorMessage 轉成使用者看得懂的中文', () {
    test('後端 error 欄位最優先', () {
      expect(apiErrorMessage(withResponse(409, {'error': '此行程已被接走'})), '此行程已被接走');
    });

    test('body 是 JSON 字串時也讀得到 error', () {
      expect(apiErrorMessage(withResponse(400, '{"error":"座標格式錯誤"}')), '座標格式錯誤');
    });

    test('後端連不上（connectionError）→ 中文提示，不吐 dio 英文訊息', () {
      // 實跑遇過：後端停掉時，司機端 banner 整段顯示
      // "The connection errored: Connection refused This indicates an error which
      //  most likely cannot be solved by the library."
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.connectionError,
        message: 'The connection errored: Connection refused This indicates an '
            'error which most likely cannot be solved by the library.',
      );
      final msg = apiErrorMessage(e);
      expect(msg, '無法連線到伺服器，請檢查網路');
      expect(msg, isNot(contains('library')), reason: '不可把 dio 原始英文訊息給使用者');
    });

    test('逾時 → 中文提示', () {
      expect(apiErrorMessage(withType(DioExceptionType.connectionTimeout)), '請求逾時，請稍後再試');
      expect(apiErrorMessage(withType(DioExceptionType.receiveTimeout)), '請求逾時，請稍後再試');
    });

    test('5xx 無 error 欄位 → 伺服器錯誤', () {
      expect(apiErrorMessage(withResponse(503, null)), '伺服器發生錯誤，請稍後再試');
    });

    test('4xx 無 error 欄位 → 帶狀態碼的泛用訊息', () {
      expect(apiErrorMessage(withResponse(418, null)), '請求失敗（418）');
    });

    test('unknown → 泛用中文', () {
      expect(apiErrorMessage(withType(DioExceptionType.unknown)), '網路錯誤，請稍後再試');
    });
  });
}
