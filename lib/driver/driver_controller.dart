import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/fleet_api_client.dart';
import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/storage/token_storage.dart';
import '../core/ws/fleet_ws_client.dart';

/// 司機端狀態：登入、上線、WS 派單、行程操作。
class DriverController extends ChangeNotifier {
  DriverController({
    TokenStorage? storage,
    FleetApiClient? api,
  })  : _storage = storage ?? TokenStorage(),
        _api = api ?? FleetApiClient(),
        _ws = FleetWsClient(onEvent: (_) {});

  final TokenStorage _storage;
  final FleetApiClient _api;
  FleetWsClient _ws;

  AuthSession? _session;
  bool _loading = false;
  String? _error;
  bool _online = false;
  bool _wsConnected = false;
  RideOffer? _pendingOffer;
  ActiveRide? _activeRide;
  Position? _lastPosition;
  Timer? _locationTimer;
  bool _busy = false;

  AuthSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get online => _online;
  bool get wsConnected => _wsConnected;
  RideOffer? get pendingOffer => _pendingOffer;
  ActiveRide? get activeRide => _activeRide;
  Position? get lastPosition => _lastPosition;

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

  Future<void> _authenticate(Future<LoginResult> Function() action) async {
    _setLoading(true);
    try {
      final result = await action();
      final session = AuthSession(
        driverId: result.driverId,
        token: result.token,
        name: result.name,
      );
      await _storage.save(session);
      await _applySession(session);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _applySession(AuthSession session) async {
    _session = session;
    _api.setToken(session.token);
    await _ws.connect(session.token);
    notifyListeners();
  }

  Future<void> logout() async {
    await goOffline();
    await _ws.disconnect();
    await _storage.clear();
    _session = null;
    _api.setToken(null);
    _pendingOffer = null;
    _activeRide = null;
    notifyListeners();
  }

  Future<void> toggleOnline() async {
    if (_online) {
      await goOffline();
    } else {
      await goOnline();
    }
  }

  Future<void> goOnline() async {
    if (_session == null) return;
    final ok = await _ensureLocationPermission();
    if (!ok) {
      _error = '需要定位權限才能上線';
      notifyListeners();
      return;
    }
    _online = true;
    _error = null;
    await _reportLocationOnce();
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      const Duration(seconds: AppConfig.locationIntervalSec),
      (_) => _reportLocationOnce(),
    );
    notifyListeners();
  }

  Future<void> goOffline() async {
    _online = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    notifyListeners();
  }

  Future<bool> _ensureLocationPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<void> _reportLocationOnce() async {
    if (!_online || _session == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lastPosition = pos;
      await _api.reportLocation(lat: pos.latitude, lng: pos.longitude);
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> acceptOffer() async {
    final offer = _pendingOffer;
    if (offer == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _api.acceptRide(offer.rideId);
      _activeRide = ActiveRide(
        rideId: offer.rideId,
        address: offer.address,
        phase: DriverRidePhase.enRouteToPickup,
      );
      _pendingOffer = null;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissOffer() {
    _pendingOffer = null;
    notifyListeners();
  }

  Future<void> pickUpPassenger() async {
    final ride = _activeRide;
    if (ride == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final dropoffAddress = await _api.pickUp(ride.rideId);
      _activeRide = ride.copyWith(
        phase: DriverRidePhase.onTrip,
        dropoffAddress: dropoffAddress,
      );
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> completeTrip() async {
    final ride = _activeRide;
    if (ride == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _api.completeRide(ride.rideId);
      _activeRide = null;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> abandonTrip() async {
    final ride = _activeRide;
    if (ride == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _api.cancelRide(ride.rideId);
      _activeRide = null;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _handleWsEvent(FleetWsEvent event) {
    switch (event.type) {
      case FleetEventTypes.rideAssigned:
        if (event.rideId != null && _activeRide == null) {
          _pendingOffer = RideOffer.fromEvent(event.rideId!, event.payload);
          notifyListeners();
        }
      case FleetEventTypes.rideAccepted:
        if (event.rideId != null && _activeRide?.rideId == event.rideId) {
          // 司機端 ride.accepted 事件帶目的地，先預載供 onTrip 導航（pickup 回應為保底來源）
          final dropoff = event.payload?['dropoff_address'] as String?;
          _activeRide = _activeRide!.copyWith(
            phase: DriverRidePhase.enRouteToPickup,
            dropoffAddress:
                (dropoff != null && dropoff.isNotEmpty) ? dropoff : null,
          );
          notifyListeners();
        }
      case FleetEventTypes.ridePickedUp:
        if (event.rideId != null && _activeRide?.rideId == event.rideId) {
          _activeRide = _activeRide!.copyWith(phase: DriverRidePhase.onTrip);
          notifyListeners();
        }
      case FleetEventTypes.rideCompleted:
      case FleetEventTypes.rideCancelled:
        if (event.rideId != null &&
            (_activeRide?.rideId == event.rideId ||
                _pendingOffer?.rideId == event.rideId)) {
          if (_activeRide?.rideId == event.rideId) _activeRide = null;
          if (_pendingOffer?.rideId == event.rideId) _pendingOffer = null;
          notifyListeners();
        }
      case FleetEventTypes.driverArrived:
        break;
      default:
        break;
    }
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _ws.disconnect();
    super.dispose();
  }
}
