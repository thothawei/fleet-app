import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'api_error.dart';
import 'fleet_api_client.dart' show ApiException;

/// 乘客端 REST API 封裝，自動帶 JWT。端點對齊後端 cmd/server/main.go 的 customer 路由。
class CustomerApiClient {
  CustomerApiClient({Dio? dio, String? token, this.onUnauthorized})
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

  /// session 失效時的回呼（帶 token 的請求收到 401）；由 controller 注入。
  void Function()? onUnauthorized;

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
    String? requiredVehicleType,
    List<StopInput> stops = const [],
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
        // P2：未指定車種時**不帶這個鍵**，維持後端現行行為（不過濾車種）。
        if (requiredVehicleType != null && requiredVehicleType.isNotEmpty)
          'required_vehicle_type': requiredVehicleType,
        // N3：多乘客／多停靠點。空 ＝ **不帶這個鍵** ＝ 單點訂單（既有行為）。
        // 有帶時後端會由 stops 推導 pickup／dropoff 並忽略上面的座標欄位。
        if (stops.isNotEmpty) 'stops': [for (final s in stops) s.toJson()],
      });
      return CustomerRide.fromJson(res.data!);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 建單**前**預估車資（懸而未決 #1，對齊 POST /api/customer/rides/estimate）。
  ///
  /// 單點行程：pickup（GPS）＋ dropoff 座標必填（沒終點無法算路線）。
  /// 多停靠點行程：帶 stops，後端由它推導起訖，pickup/dropoff 會被忽略（照樣送 pickup 佔位）。
  /// 指定寵物車時預估會含清潔費。
  Future<FareEstimate> estimateFare({
    required double pickupLat,
    required double pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    List<StopInput> stops = const [],
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/customer/rides/estimate',
        data: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          if (dropoffLat != null && dropoffLng != null) ...{
            'dropoff_lat': dropoffLat,
            'dropoff_lng': dropoffLng,
          },
          if (requiredVehicleType != null && requiredVehicleType.isNotEmpty)
            'required_vehicle_type': requiredVehicleType,
          if (stops.isNotEmpty) 'stops': [for (final s in stops) s.toJson()],
        },
      );
      return FareEstimate.fromJson(res.data!);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查乘客可讀的費率（對齊 GET /api/customer/fees，P5）。
  ///
  /// 後端是**白名單輸出**，目前只回 pet_cleaning_fee_bps——不會有手續費／月會費。
  /// 供「選擇車種」UI 在選寵物用車時當場顯示加價，不必等行程完成才知道。
  Future<int> fetchPetCleaningFeeBps() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/customer/fees');
      return (res.data?['pet_cleaning_fee_bps'] as num?)?.toInt() ?? 0;
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

  /// 我的行程歷史（新到舊）。供「事後聯絡司機」的入口。
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/customer/rides',
        queryParameters: {'limit': limit},
      );
      final raw = res.data?['rides'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => CustomerRideSummary.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 查這趟我給過的評分星等；**尚未評分時回 null**（B5）。
  ///
  /// 讀的是 `GET /api/customer/rides/:id` 的 `ride.rating.score`——
  /// 後端這支單筆查詢本來就帶 rating（尚未評分時省略該鍵）。
  /// **用途是評分逾時後的對帳**：`rateRide` 逾時不代表後端沒記到，而「一趟一評」
  /// 有唯一索引，再送一次只會拿到 409，乘客沒有出路（見 `submitRating`）。
  Future<int?> fetchRideRatingScore(int rideId) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/customer/rides/$rideId');
      final ride = res.data?['ride'];
      if (ride is! Map) return null;
      final rating = ride['rating'];
      if (rating is! Map) return null;
      return (rating['score'] as num?)?.toInt();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 對已完成行程給司機評分（B5）。**一趟一評、不可重評**——
  /// 已評過的行程後端回 409，UI 不該再給入口（清單以 `ratingScore` 判斷）。
  Future<RideRating> rateRide(
    int rideId, {
    required int score,
    String comment = '',
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/customer/rides/$rideId/rating',
        data: {'score': score, 'comment': comment},
      );
      final raw = res.data?['rating'];
      if (raw is! Map) {
        // 後端回 200 但形狀不符時，仍以送出的分數為準——評分已經寫進去了，
        // 讓 UI 因為解析失敗而顯示「評分失敗」會誤導乘客再評一次（然後撞 409）。
        return RideRating(rideId: rideId, score: score, comment: comment);
      }
      return RideRating.fromJson(Map<String, dynamic>.from(raw));
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
      // **回可變空 list**：controller 把這份結果當成清單狀態，之後會 insert／removeAt
      // 進去（`_applyLostItem`）。回 `const []` 的話那一步會丟
      // `Cannot add to an unmodifiable list`。後端目前空清單回的是 `[]`
      // （2026-07-30 實測），所以這條分支只在回應格式異常時才走到——但形狀要是安全的。
      if (raw is! List) return <LostItemRequest>[];
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

  /// 註冊推播 token（對齊 `POST /api/customer/device-token`）。
  ///
  /// 這支端點後端**早就在路由上**（`RegisterByCustomer`），App 卻從沒呼叫過——
  /// 於是乘客 App 被系統殺掉後沒有任何管道叫得動他：WS 沒了、15 秒輪詢也停了，
  /// 「司機接單」「司機已抵達」全部收不到，只有他自己再打開 App 才由 REST 還原。
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {
    try {
      await _dio.post('/customer/device-token', data: {
        'platform': platform,
        'token': token,
      });
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 登出時註銷推播 token；不註銷的話，下一個在這台裝置登入的人
  /// 會收到上一位乘客的行程通知。
  Future<void> unregisterDeviceToken({required String token}) async {
    try {
      await _dio.delete(
        '/customer/device-token',
        data: {'platform': 'fcm', 'token': token},
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 401（登入／註冊以外）＝ session 失效：通知 controller 清掉它。
  /// 詳見 `FleetApiClient._wrap`——兩端同一條規則。
  ApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 && !isAuthPath(e.requestOptions.path)) {
      onUnauthorized?.call();
      return ApiException(sessionExpiredMessage, statusCode: code);
    }
    return ApiException(apiErrorMessage(e), statusCode: code);
  }
}
