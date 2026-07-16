import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'api_error.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// REST API 封裝，自動帶 JWT。
class FleetApiClient {
  FleetApiClient({Dio? dio, String? token})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${AppConfig.apiBase}/api',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Content-Type': 'application/json'},
            )) {
    if (token != null) setToken(token);
  }

  final Dio _dio;

  void setToken(String? token) {
    if (token == null) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<LoginResult> login({
    required String lineUserId,
    required String password,
  }) async {
    return _postAuth('/driver/login', {
      'line_user_id': lineUserId,
      'password': password,
    });
  }

  Future<LoginResult> register({
    required String lineUserId,
    required String name,
    required String password,
  }) async {
    return _postAuth('/driver/register', {
      'line_user_id': lineUserId,
      'name': name,
      'password': password,
    });
  }

  Future<LoginResult> _postAuth(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return LoginResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<void> reportLocation({required double lat, required double lng}) async {
    try {
      await _dio.post('/driver/location', data: {'lat': lat, 'lng': lng});
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<String> acceptRide(int rideId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/rides/$rideId/accept');
      return res.data?['message'] as String? ?? '接單成功';
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 確認乘客上車，回傳後端帶回的目的地地址與座標（未指定目的地時欄位皆為 null）。
  Future<DropoffInfo> pickUp(int rideId) async {
    try {
      final res =
          await _dio.post<Map<String, dynamic>>('/rides/$rideId/pickup');
      return DropoffInfo.fromJson(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<void> completeRide(int rideId) async {
    try {
      await _dio.post('/rides/$rideId/complete');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<void> cancelRide(int rideId) async {
    try {
      await _dio.post('/rides/$rideId/cancel');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查司機目前進行中訂單；無進行中訂單時回 null（App 重啟恢復行程用）。
  Future<ActiveRide?> activeRide() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/driver/rides/active');
      final ride = res.data?['ride'];
      if (ride is Map) {
        return ActiveRide.fromBackendJson(Map<String, dynamic>.from(ride));
      }
      return null;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查司機當月收入（對齊 GET /api/driver/earnings?month=YYYY-MM，F7）。
  /// month 為 null 時後端預設當月。
  Future<DriverEarnings> fetchEarnings({String? month}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/driver/earnings',
        queryParameters: month != null ? {'month': month} : null,
      );
      return DriverEarnings.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 行程內對話歷史（afterId > 0 時做增量補讀）。
  Future<List<RideMessage>> fetchMessages(int rideId, {int afterId = 0}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/rides/$rideId/messages',
        queryParameters: afterId > 0 ? {'after': afterId} : null,
      );
      final raw = res.data?['messages'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => RideMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 發送訊息；即時遞送由後端透過 WS chat.message 推給雙方。
  Future<RideMessage> sendMessage(int rideId, String body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/rides/$rideId/messages',
        data: {'body': body},
      );
      return RideMessage.fromJson(
        Map<String, dynamic>.from(res.data!['message'] as Map),
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 司機的未結案協尋單（遺失物工作清單）。
  Future<List<LostItemRequest>> fetchLostItems() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/driver/lost-items');
      final raw = res.data?['lost_items'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => LostItemRequest.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 標記已尋獲（open → found），之後等待乘客支付處理費。
  Future<LostItemRequest> markLostItemFound(int itemId) =>
      _postLostItemAction('/lost-items/$itemId/found');

  /// 付訖後標記已歸還（paid → returned），結案。
  Future<LostItemRequest> markLostItemReturned(int itemId) =>
      _postLostItemAction('/lost-items/$itemId/return');

  /// 未尋獲結案（open/found → closed）。
  Future<LostItemRequest> closeLostItem(int itemId) =>
      _postLostItemAction('/lost-items/$itemId/close');

  Future<LostItemRequest> _postLostItemAction(String path) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path);
      return LostItemRequest.fromJson(
        Map<String, dynamic>.from(res.data!['lost_item'] as Map),
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 註冊 FCM/APNs 推播 token（對齊 POST /api/driver/device-token）。
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {
    try {
      await _dio.post('/driver/device-token', data: {
        'platform': platform,
        'token': token,
      });
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 登出時註銷推播 token。
  Future<void> unregisterDeviceToken({required String token}) async {
    try {
      await _dio.delete(
        '/driver/device-token',
        data: {'platform': 'fcm', 'token': token},
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  ApiException _wrap(DioException e) =>
      ApiException(apiErrorMessage(e), statusCode: e.response?.statusCode);
}
