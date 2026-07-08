import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/customer_api_client.dart';
import '../core/api/fleet_api_client.dart' show ApiException;
import '../core/models/models.dart';
import '../core/storage/customer_token_storage.dart';

/// 乘客端狀態：登入、定位、叫車（帶目的地）、訂單狀態輪詢、取消。
class CustomerController extends ChangeNotifier {
  CustomerController({
    CustomerTokenStorage? storage,
    CustomerApiClient? api,
  })  : _storage = storage ?? CustomerTokenStorage(),
        _api = api ?? CustomerApiClient();

  final CustomerTokenStorage _storage;
  final CustomerApiClient _api;

  static const _pollInterval = Duration(seconds: 5);

  CustomerSession? _session;
  bool _loading = false;
  String? _error;
  bool _busy = false;
  Position? _lastPosition;
  CustomerRide? _activeRide;
  Timer? _pollTimer;

  CustomerSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get busy => _busy;
  Position? get lastPosition => _lastPosition;
  CustomerRide? get activeRide => _activeRide;

  Future<void> init() async {
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
    notifyListeners();
  }

  Future<void> logout() async {
    _stopPolling();
    await _storage.clear();
    _session = null;
    _activeRide = null;
    _api.setToken(null);
    notifyListeners();
  }

  /// 叫車：以目前 GPS 為上車點，帶乘客輸入的上車/目的地地址。
  Future<void> placeOrder({
    required String pickupAddress,
    required String dropoffAddress,
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
      );
      _activeRide = ride;
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
      _activeRide = ride;
      if (ride == null) {
        _stopPolling();
      } else {
        _startPolling();
      }
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
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
    super.dispose();
  }
}
