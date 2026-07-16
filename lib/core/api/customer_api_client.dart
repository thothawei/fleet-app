import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'api_error.dart';
import 'fleet_api_client.dart' show ApiException;

/// 乘客端 REST API 封裝，自動帶 JWT。端點對齊後端 cmd/server/main.go 的 customer 路由。
class CustomerApiClient {
  CustomerApiClient({Dio? dio, String? token})
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

  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async {
    return _postAuth('/customer/login', {
      'line_user_id': lineUserId,
      'password': password,
    });
  }

  Future<CustomerLoginResult> register({
    required String lineUserId,
    required String name,
    required String password,
  }) async {
    return _postAuth('/customer/register', {
      'line_user_id': lineUserId,
      'name': name,
      'password': password,
    });
  }

  Future<CustomerLoginResult> _postAuth(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return CustomerLoginResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 下單叫車。dropoff 座標為選填（未由地圖選點時留空 → 後端存 NULL point，
  /// 司機端仍可用 dropoff_address 導航）。
  Future<CustomerRide> createRide({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/rides', data: {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'pickup_address': pickupAddress,
        if (dropoffAddress != null && dropoffAddress.isNotEmpty)
          'dropoff_address': dropoffAddress,
        if (dropoffLat != null && dropoffLng != null) ...{
          'dropoff_lat': dropoffLat,
          'dropoff_lng': dropoffLng,
        },
      });
      return CustomerRide.fromJson(res.data!);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查目前進行中的訂單；無進行中訂單時回 null。
  Future<CustomerRide?> activeRide() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/customer/rides/active');
      final ride = res.data?['ride'];
      if (ride is Map) {
        return CustomerRide.fromJson(Map<String, dynamic>.from(ride));
      }
      return null;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<void> cancelRide(int rideId) async {
    try {
      await _dio.post('/rides/$rideId/cancel-by-customer');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 行程內對話歷史（afterId > 0 時做增量補讀，WS 斷線重連後補漏）。
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

  /// 對已完成行程建立遺失物協尋單；回應含依當下處理費%快照的 fee_cents。
  Future<LostItemRequest> createLostItem(int rideId, String description) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/rides/$rideId/lost-items',
        data: {'description': description},
      );
      return LostItemRequest.fromJson(
        Map<String, dynamic>.from(res.data!['lost_item'] as Map),
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查該行程最新協尋單；從未建立過時回 null。
  Future<LostItemRequest?> fetchLostItemByRide(int rideId) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/rides/$rideId/lost-items');
      final raw = res.data?['lost_item'];
      if (raw is! Map) return null;
      return LostItemRequest.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 我的未結案協尋單。
  Future<List<LostItemRequest>> fetchLostItems() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/customer/lost-items');
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

  /// 支付處理費（記帳式確認；司機尋獲後才可付）。
  Future<LostItemRequest> payLostItem(int itemId) async {
    return _postLostItemAction('/lost-items/$itemId/pay');
  }

  /// 取消協尋（open/found 可取消；已付款後不可）。
  Future<LostItemRequest> closeLostItem(int itemId) async {
    return _postLostItemAction('/lost-items/$itemId/close');
  }

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

  ApiException _wrap(DioException e) =>
      ApiException(apiErrorMessage(e), statusCode: e.response?.statusCode);
}
