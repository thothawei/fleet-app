import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';

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

  Future<void> pickUp(int rideId) async {
    try {
      await _dio.post('/rides/$rideId/pickup');
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
