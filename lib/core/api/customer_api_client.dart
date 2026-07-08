import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';
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

  ApiException _wrap(DioException e) {
    final data = e.response?.data;
    String message = e.message ?? '網路錯誤';
    if (data is Map && data['error'] != null) {
      message = data['error'].toString();
    } else if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        message = json['error']?.toString() ?? message;
      } catch (_) {}
    }
    return ApiException(message, statusCode: e.response?.statusCode);
  }
}
