import 'dart:convert';

import 'package:dio/dio.dart';

/// 把 `DioException` 轉成可以直接顯示給司機／乘客看的中文訊息。
///
/// 優先序：後端回的 `error` 欄位 → 依錯誤類型分類 → 泛用退路。
///
/// **不可直接用 `e.message`**——那是 dio 的英文技術訊息，例如後端沒起時會得到
/// 「The connection errored: Connection refused This indicates an error which most
/// likely cannot be solved by the library.」，實跑時它整段出現在司機端錯誤 banner 上。
/// token 過期／失效（401）時給使用者看的訊息。
///
/// **不能沿用後端原文**「token 無效或已過期」——那是給開發者看的：使用者不知道
/// token 是什麼，更不知道自己該做什麼。這句話要能直接對應到唯一的出路（重新登入）。
const sessionExpiredMessage = '登入已過期，請重新登入';

/// 這兩條路徑的 401 是「帳號或密碼錯誤」，不是 session 失效——
/// 拿它去清 session 會把「打錯密碼」變成「被登出」。
bool isAuthPath(String path) =>
    path.endsWith('/login') || path.endsWith('/register');

String apiErrorMessage(DioException e) {
  final backend = _backendError(e.response?.data);
  if (backend != null && backend.isNotEmpty) return backend;

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return '請求逾時，請稍後再試';
    case DioExceptionType.connectionError:
      return '無法連線到伺服器，請檢查網路';
    case DioExceptionType.badCertificate:
      return '伺服器憑證有問題';
    case DioExceptionType.cancel:
      return '請求已取消';
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode ?? 0;
      return code >= 500 ? '伺服器發生錯誤，請稍後再試' : '請求失敗（$code）';
    case DioExceptionType.unknown:
      return '網路錯誤，請稍後再試';
  }
}

/// 後端統一以 `{"error": "..."}` 回錯誤；有些情況 body 會是未解析的字串。
String? _backendError(Object? data) {
  if (data is Map && data['error'] != null) return data['error'].toString();
  if (data is String) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return json['error']?.toString();
    } catch (_) {}
  }
  return null;
}
