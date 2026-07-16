import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/fleet_api_client.dart';
import '../core/config/app_config.dart';
import '../core/location/driver_location_permissions.dart';
import '../core/location/driver_location_settings.dart';
import '../core/models/models.dart';
import '../core/push/driver_push_service.dart';
import '../core/storage/token_storage.dart';
import '../core/ws/fleet_ws_client.dart';

/// 司機端狀態：登入、上線、WS 派單、行程操作。
class DriverController extends ChangeNotifier {
  DriverController({
    DriverAuthStore? storage,
    FleetApiClient? api,
    FleetWsClientFactory? wsFactory,
    DriverPushService? push,
  })  : _storage = storage ?? TokenStorage(),
        _api = api ?? FleetApiClient(),
        _wsFactory = wsFactory ?? FleetWsClient.new,
        _push = push ?? NoOpDriverPushService(),
        _ws = FleetWsClient(onEvent: (_) {});

  final DriverAuthStore _storage;
  final FleetApiClient _api;
  final FleetWsClientFactory _wsFactory;
  final DriverPushService _push;
  FleetWsClient _ws;

  AuthSession? _session;
  bool _loading = false;
  String? _error;
  bool _online = false;
  bool _wsConnected = false;
  RideOffer? _pendingOffer;
  ActiveRide? _activeRide;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<FleetWsEvent>? _pushSub;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _fcmToken;
  bool _busy = false;

  // 聊天：WS chat.message 即時串流 + 未讀計數（聊天室開啟時不累計）。
  final _chatStream = StreamController<RideMessage>.broadcast();
  int _unreadChat = 0;
  bool _chatVisible = false;

  // 遺失物：未結案協尋工作清單（WS lost_item.* 即時更新）。
  List<LostItemRequest> _lostItems = [];

  AuthSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get online => _online;
  bool get wsConnected => _wsConnected;
  RideOffer? get pendingOffer => _pendingOffer;
  ActiveRide? get activeRide => _activeRide;
  Position? get lastPosition => _lastPosition;
  bool get fcmAvailable => _push.isAvailable;

  /// 即時聊天訊息串流（WS chat.message；聊天室以 id 去重）。
  Stream<RideMessage> get chatStream => _chatStream.stream;

  /// 乘客傳來、尚未讀的訊息數。
  int get unreadChat => _unreadChat;

  /// 未結案遺失物協尋工作清單。
  List<LostItemRequest> get lostItems => _lostItems;

  /// 聊天室開啟/關閉；開啟時清未讀並停止累計。
  void setChatVisible(bool visible) {
    _chatVisible = visible;
    if (visible && _unreadChat != 0) {
      _unreadChat = 0;
    }
    notifyListeners();
  }
  String? get fcmTokenPrefix {
    final t = _fcmToken;
    if (t == null || t.length <= 8) return t;
    return '${t.substring(0, 8)}…';
  }

  Future<void> init() async {
    _ws = _wsFactory(
      onEvent: _handleWsEvent,
      onConnectionChanged: (connected) {
        _wsConnected = connected;
        notifyListeners();
      },
    );
    final saved = await _storage.read();
    if (saved != null) {
      await _applySession(saved);
      await _restoreActiveRide();
      await refreshLostItems();
    }
    await _bindPushListener();
  }

  /// 測試用：模擬收到 WS 事件（等同正式連線後的 onEvent）。
  @visibleForTesting
  void handleWsEventForTest(FleetWsEvent event) => _handleWsEvent(event);

  /// App 重啟後從後端還原進行中行程（Accepted/PickedUp）。
  Future<void> _restoreActiveRide() async {
    try {
      _activeRide = await _api.activeRide();
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
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
      // 登入即更新「遺失物協尋」角標與工作清單，不用等進頁下拉（比照 init() 還原 session）。
      await refreshLostItems();
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
    await _syncDeviceToken();
    notifyListeners();
  }

  Future<void> _bindPushListener() async {
    await _pushSub?.cancel();
    _pushSub = _push.rideEvents.listen(_handleWsEvent);
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _push.tokenRefresh.listen((_) => _syncDeviceToken());
  }

  /// 登入後向後端註冊 FCM token；token 刷新時亦會重註冊。
  Future<void> _syncDeviceToken() async {
    if (!_push.isAvailable || _session == null) return;
    try {
      final token = await _push.getToken();
      if (token == null || token.isEmpty) return;
      await _api.registerDeviceToken(platform: 'fcm', token: token);
      _fcmToken = token;
    } on ApiException catch (e) {
      _error = e.message;
    }
  }

  Future<void> logout() async {
    await goOffline();
    if (_fcmToken != null) {
      try {
        await _api.unregisterDeviceToken(token: _fcmToken!);
      } catch (_) {}
      _fcmToken = null;
    }
    await _ws.disconnect();
    await _storage.clear();
    _session = null;
    _api.setToken(null);
    _pendingOffer = null;
    _activeRide = null;
    _unreadChat = 0;
    _chatVisible = false;
    _lostItems = [];
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
    final ok = await ensureDriverLocationPermissions();
    if (!ok) {
      _error = '需要定位權限才能上線';
      notifyListeners();
      return;
    }
    _online = true;
    _error = null;
    await _startLocationStream();
    notifyListeners();
  }

  Future<void> goOffline() async {
    _online = false;
    await _stopLocationStream();
    notifyListeners();
  }

  /// 以 getPositionStream + Android 前景服務持續回報，取代 Timer 前景輪詢。
  Future<void> _startLocationStream() async {
    await _stopLocationStream();
    if (!_online || _session == null) return;

    final settings = driverLocationSettings();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) => _reportPosition(pos),
      onError: (_) {},
    );

    // 立即回報一筆，不必等第一個 stream tick；不 await 以免上線鈕卡在等 GPS fix。
    unawaited(_reportImmediatePosition());
  }

  /// 上線後立即回報一筆位置。高精度定位在模擬器／室內可能長時間無 fix，
  /// 故設 8 秒逾時；逾時就放棄這筆，後續由 stream 補上精確位置。
  Future<void> _reportImmediatePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _reportPosition(pos);
    } catch (_) {}
  }

  Future<void> _stopLocationStream() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _reportPosition(Position pos) async {
    if (!_online || _session == null) return;
    try {
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
        pickupLat: offer.pickupLat,
        pickupLng: offer.pickupLng,
        dropoffAddress: offer.dropoffAddress,
        dropoffLat: offer.dropoffLat,
        dropoffLng: offer.dropoffLng,
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
      final dropoff = await _api.pickUp(ride.rideId);
      _activeRide = ride.copyWith(
        phase: DriverRidePhase.onTrip,
        dropoffAddress: dropoff.address,
        dropoffLat: dropoff.lat,
        dropoffLng: dropoff.lng,
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

  /// 查當月收入（E1 司機收入頁用）。month 格式 YYYY-MM。
  Future<DriverEarnings> fetchEarnings(String month) =>
      _api.fetchEarnings(month: month);

  /// 聊天歷史／發送（聊天室畫面用）。
  Future<List<RideMessage>> fetchMessages(int rideId, {int afterId = 0}) =>
      _api.fetchMessages(rideId, afterId: afterId);

  Future<RideMessage> sendMessage(int rideId, String body) =>
      _api.sendMessage(rideId, body);

  /// 重新拉未結案協尋工作清單（登入後、遺失物頁下拉）。
  Future<void> refreshLostItems() async {
    if (_session == null) return;
    try {
      _lostItems = await _api.fetchLostItems();
      notifyListeners();
    } on ApiException catch (_) {
      // 背景保底，失敗不覆蓋主錯誤訊息
    }
  }

  /// 標記已尋獲（open → found）。
  Future<LostItemRequest> markLostItemFound(int itemId) async {
    final item = await _api.markLostItemFound(itemId);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 付訖後標記已歸還（paid → returned）。
  Future<LostItemRequest> markLostItemReturned(int itemId) async {
    final item = await _api.markLostItemReturned(itemId);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 未尋獲結案（open/found → closed）。
  Future<LostItemRequest> closeLostItem(int itemId) async {
    final item = await _api.closeLostItem(itemId);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 以單筆最新狀態合併進未結案清單：結案移除、未結案更新或插入（新的在前）。
  void _applyLostItem(LostItemRequest item) {
    final idx = _lostItems.indexWhere((e) => e.id == item.id);
    if (!item.isActive) {
      if (idx >= 0) _lostItems.removeAt(idx);
      return;
    }
    if (idx >= 0) {
      _lostItems[idx] = item;
    } else {
      _lostItems.insert(0, item);
    }
  }

  void _onChatMessage(FleetWsEvent event) {
    final payload = event.payload;
    if (payload == null) return;
    final RideMessage msg;
    try {
      msg = RideMessage.fromJson(payload);
    } catch (_) {
      return;
    }
    _chatStream.add(msg);
    // 只有「乘客傳來」且聊天室未開啟才累計未讀（自己其他裝置的回聲不算）。
    if (msg.senderRole != 'driver' && !_chatVisible) {
      _unreadChat++;
      notifyListeners();
    }
  }

  void _onLostItemEvent(FleetWsEvent event) {
    final payload = event.payload;
    if (payload == null) return;
    final LostItemRequest item;
    try {
      item = LostItemRequest.fromJson(payload);
    } catch (_) {
      return;
    }
    _applyLostItem(item);
    notifyListeners();
  }

  void _handleWsEvent(FleetWsEvent event) {
    switch (event.type) {
      case FleetEventTypes.chatMessage:
        _onChatMessage(event);
        return;
      case FleetEventTypes.lostItemCreated:
      case FleetEventTypes.lostItemUpdated:
        _onLostItemEvent(event);
        return;
    }
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
            dropoffLat: (event.payload?['dropoff_lat'] as num?)?.toDouble(),
            dropoffLng: (event.payload?['dropoff_lng'] as num?)?.toDouble(),
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
    _positionSub?.cancel();
    _pushSub?.cancel();
    _tokenRefreshSub?.cancel();
    _chatStream.close();
    _ws.disconnect();
    _push.dispose();
    super.dispose();
  }
}
