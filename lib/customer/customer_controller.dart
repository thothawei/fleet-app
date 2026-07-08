import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/customer_api_client.dart';
import '../core/api/fleet_api_client.dart' show ApiException;
import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/storage/customer_token_storage.dart';
import '../core/ws/fleet_ws_client.dart';

/// 乘客端狀態：登入、定位、叫車（帶目的地）、WS 即時狀態、取消。
class CustomerController extends ChangeNotifier {
  CustomerController({
    CustomerTokenStorage? storage,
    CustomerApiClient? api,
  })  : _storage = storage ?? CustomerTokenStorage(),
        _api = api ?? CustomerApiClient(),
        _ws = FleetWsClient(onEvent: (_) {});

  final CustomerTokenStorage _storage;
  final CustomerApiClient _api;
  FleetWsClient _ws;

  // WS 即時到手後只做保底對帳，輪詢間隔放寬。
  static const _pollInterval = Duration(seconds: 15);

  CustomerSession? _session;
  bool _loading = false;
  String? _error;
  bool _busy = false;
  bool _wsConnected = false;
  Position? _lastPosition;
  CustomerRide? _activeRide;
  String? _driverName;
  int? _liveEtaSec;
  int? _liveDistM;
  Timer? _pollTimer;

  CustomerSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get busy => _busy;
  bool get wsConnected => _wsConnected;
  Position? get lastPosition => _lastPosition;
  CustomerRide? get activeRide => _activeRide;

  /// 司機姓名，來自 ride.accepted WS 事件（GET active 不含司機名，故為即時來源）。
  String? get driverName => _driverName;

  /// 司機接近上車點的即時 ETA/距離，來自 driver.location WS 事件（司機移動時更新）。
  int? get liveEtaSec => _liveEtaSec;
  int? get liveDistM => _liveDistM;

  Future<void> init() async {
    _ws = FleetWsClient(
      onEvent: _handleWsEvent,
      onConnectionChanged: (connected) {
        _wsConnected = connected;
        notifyListeners();
      },
    );
    final saved = await _storage.read();
    if (saved != null) {
      await _applySession(saved);
      await refreshActive();
    }
  }

  Future<void> login({
    required String lineUserId,
    required String password,
  }) async {
    await _authenticate(() => _api.login(
          lineUserId: lineUserId,
          password: password,
        ));
  }

  Future<void> register({
    required String lineUserId,
    required String name,
    required String password,
  }) async {
    await _authenticate(() => _api.register(
          lineUserId: lineUserId,
          name: name,
          password: password,
        ));
  }

  Future<void> _authenticate(
    Future<CustomerLoginResult> Function() action,
  ) async {
    _setLoading(true);
    try {
      final result = await action();
      final session = CustomerSession(
        customerId: result.customerId,
        token: result.token,
        name: result.name,
      );
      await _storage.save(session);
      await _applySession(session);
      _error = null;
      await refreshActive();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _applySession(CustomerSession session) async {
    _session = session;
    _api.setToken(session.token);
    await _ws.connect(session.token);
    notifyListeners();
  }

  Future<void> logout() async {
    _stopPolling();
    await _ws.disconnect();
    await _storage.clear();
    _session = null;
    _activeRide = null;
    _driverName = null;
    _liveEtaSec = null;
    _liveDistM = null;
    _api.setToken(null);
    notifyListeners();
  }

  /// WS 即時事件：訂單生命週期變化時立即以權威狀態對帳（GET active）。
  void _handleWsEvent(FleetWsEvent event) {
    final active = _activeRide;
    if (active == null || event.rideId != active.rideId) return;
    switch (event.type) {
      case FleetEventTypes.rideAccepted:
        _driverName = event.payload?['driver_name'] as String?;
        refreshActive();
      case FleetEventTypes.driverLocation:
        // 司機移動更新：只更新即時 ETA/距離，不打 GET active（頻率較高）
        _liveEtaSec = (event.payload?['eta_sec'] as num?)?.toInt();
        _liveDistM = (event.payload?['dist_m'] as num?)?.toInt();
        notifyListeners();
      case FleetEventTypes.driverArrived:
      case FleetEventTypes.ridePickedUp:
      case FleetEventTypes.rideCompleted:
      case FleetEventTypes.rideCancelled:
        refreshActive();
      default:
        break;
    }
  }

  /// 叫車：以目前 GPS 為上車點，帶乘客輸入的上車/目的地地址；
  /// 若目的地由地圖選點取得，另帶精確座標（dropoffLat/Lng）。
  Future<void> placeOrder({
    required String pickupAddress,
    required String dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
  }) async {
    if (_busy || _session == null) return;
    _setBusy(true);
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) {
        _error = '需要定位權限才能叫車';
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lastPosition = pos;
      final pickup = pickupAddress.trim().isNotEmpty
          ? pickupAddress.trim()
          : '目前位置 (${pos.latitude.toStringAsFixed(5)}, '
              '${pos.longitude.toStringAsFixed(5)})';
      final ride = await _api.createRide(
        pickupLat: pos.latitude,
        pickupLng: pos.longitude,
        pickupAddress: pickup,
        dropoffAddress: dropoffAddress.trim(),
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
      );
      _activeRide = ride;
      _driverName = null;
      _liveEtaSec = null;
      _liveDistM = null;
      _error = null;
      _startPolling();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshActive() async {
    if (_session == null) return;
    try {
      final ride = await _api.activeRide();
      _applyActiveRide(ride);
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  /// 套用 GET active 結果，清除終態/非接客階段的 stale 即時欄位。
  void _applyActiveRide(CustomerRide? ride) {
    if (ride == null || RideStatus.isTerminal(ride.status)) {
      _activeRide = null;
      _driverName = null;
      _liveEtaSec = null;
      _liveDistM = null;
      _stopPolling();
      return;
    }
    _activeRide = ride;
    if (ride.status < RideStatus.accepted) {
      _driverName = null;
    }
    if (ride.status != RideStatus.accepted) {
      _liveEtaSec = null;
      _liveDistM = null;
    }
    _startPolling();
  }

  Future<void> cancelOrder() async {
    final ride = _activeRide;
    if (ride == null || _busy) return;
    _setBusy(true);
    try {
      await _api.cancelRide(ride.rideId);
      await refreshActive();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refreshActive());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _ws.disconnect();
    super.dispose();
  }
}
