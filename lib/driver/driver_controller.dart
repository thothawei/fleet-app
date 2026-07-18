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

  // 車輛資訊（O2）。null ＝**尚未載入**，與「已載入但未填」是不同狀態——
  // 混為一談會在載入完成前誤判成「沒填」而閃跳轉到設定頁（見 vehicleChecked）。
  DriverVehicle? _vehicle;
  bool _vehicleSaving = false;
  // 車輛查詢是否失敗（例如 token 過期、後端不可達）。與「尚未查」是不同狀態——
  // 混為一談會讓 _DriverRoot 卡在無限 spinner，司機連登出都按不到。
  bool _vehicleLoadFailed = false;

  AuthSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;

  /// 操作進行中（接單／完成／標記停靠點…）；供按鈕禁用避免重複送出。
  bool get busy => _busy;
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

  /// 標記已到達某停靠點（N7）。成功回 true。
  Future<bool> markStopArrived(int stopId) => _markStop(stopId, _api.arriveStop);

  /// 標記跳過某停靠點（乘客未出現，N7）。成功回 true。
  /// **被跳過的站不計入車資**——後端 N5 的計費路線會排除它。
  Future<bool> markStopSkipped(int stopId) => _markStop(stopId, _api.skipStop);

  Future<bool> _markStop(int stopId, Future<void> Function(int, int) action) async {
    final ride = _activeRide;
    if (ride == null) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action(ride.rideId, stopId);
      // 重讀 active 讓停靠點狀態同步回畫面——標記的結果由後端決定，不在本地猜。
      await _restoreActiveRide();
      return true;
    } on ApiException catch (e) {
      _error = e.message; // 重複標記／已跳過／已完成（409）的訊息已中文化
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 自己的車輛資訊（O2）；尚未載入時為 null。
  DriverVehicle? get vehicle => _vehicle;

  /// 車輛資訊是否已向後端查過。**跳轉判斷必須先看它**——
  /// 未查完就看 hasVehicle 會把「還不知道」誤當成「沒填」而閃跳轉。
  bool get vehicleChecked => _vehicle != null;

  /// 是否已填妥車輛（未載入時為 false，但請搭配 vehicleChecked 判斷）。
  /// 以後端回的 has_vehicle 為準，不自行判斷「兩欄皆非空」——與 O3 gate 同一條件。
  bool get hasVehicle => _vehicle?.hasVehicle ?? false;

  /// 車輛設定儲存中（供設定頁禁用按鈕）。
  bool get vehicleSaving => _vehicleSaving;

  /// 車輛查詢是否失敗（token 過期／後端不可達…）。
  ///
  /// **與「尚未查」必須分開**：兩者都是 `vehicleChecked == false`，但 UI 後果天差地遠——
  /// 尚未查 → 轉圈等它；查失敗 → 要給錯誤與出路（重試／登出），否則司機卡在無限 spinner。
  bool get vehicleLoadFailed => _vehicleLoadFailed;

  /// 載入自己的車輛資訊（O2）。登入後與 init() 還原 session 後都會呼叫。
  ///
  /// 失敗時**不設 _vehicle**（不可把網路錯誤誤判成「沒填」而推去強制設定頁），
  /// 但會設 _vehicleLoadFailed 讓 UI 顯示錯誤與重試——「不誤判」不等於「什麼都不說」。
  Future<void> refreshVehicle() async {
    if (_session == null) return;
    try {
      _vehicle = await _api.fetchVehicle();
      _vehicleLoadFailed = false;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
      _vehicleLoadFailed = true;
    }
    notifyListeners();
  }

  /// 設定車種與車牌（O2）。成功回 true。
  /// 以後端回傳值更新狀態（車牌已正規化），不要用送出去的字串。
  Future<bool> saveVehicle({
    required String vehicleType,
    required String plateNumber,
  }) async {
    _vehicleSaving = true;
    _error = null;
    notifyListeners();
    try {
      _vehicle = await _api.updateVehicle(
        vehicleType: vehicleType,
        plateNumber: plateNumber,
      );
      return true;
    } on ApiException catch (e) {
      _error = e.message; // 車牌重複（409）等訊息已由 api_error 中文化
      return false;
    } finally {
      _vehicleSaving = false;
      notifyListeners();
    }
  }

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
      // O3 gate 的 App 端引導：一還原 session 就查車輛，_DriverRoot 才知道要不要跳設定頁。
      await refreshVehicle();
    }
    await _bindPushListener();
  }

  /// 測試用：模擬收到 WS 事件（等同正式連線後的 onEvent）。
  @visibleForTesting
  void handleWsEventForTest(FleetWsEvent event) => _handleWsEvent(event);

  /// 測試用：直接設定上線旗標。正式路徑 `goOnline()` 需要定位權限，widget 測試取不到。
  @visibleForTesting
  void setOnlineForTest(bool value) {
    _online = value;
    notifyListeners();
  }

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
      // 登入後立刻查車輛：沒填的話 _DriverRoot 會直接導去設定頁（O3 gate 的 App 端引導）。
      await refreshVehicle();
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
      // 位置回報是上線期間每幾秒一次的健康探針：它成功＝後端可達，
      // 此時還掛著上一輪的錯誤（例如「無法連線到伺服器」）只會誤導司機。
      _error = null;
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
      // 樂觀先以 offer 內容顯示：接單卡立刻消失、行程卡立刻出現，不等網路往返。
      _activeRide = ActiveRide(
        rideId: offer.rideId,
        address: offer.address,
        phase: DriverRidePhase.enRouteToPickup,
        pickupLat: offer.pickupLat,
        pickupLng: offer.pickupLng,
        dropoffAddress: offer.dropoffAddress,
        dropoffLat: offer.dropoffLat,
        dropoffLng: offer.dropoffLng,
        stops: offer.stops,
      );
      _pendingOffer = null;
      _error = null;
      // 以後端為權威補齊：**推播喚醒路徑**的 offer 來自 FCM data，data 值全是字串、
      // 不帶結構化的 stops 陣列（見 pitfall-fcm-data-all-strings），所以樂觀行程會缺全程。
      // 重讀 active 讓多停靠點清單／多點地圖一定齊全，不必讓推播 payload 塞 stops。
      await _refreshActiveAfterAccept(offer.rideId);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 接單後重讀 active，以後端回傳為權威補齊樂觀 offer 缺的欄位（尤其 stops）。
  ///
  /// **只在後端回傳非 null 且 rideId 相符時覆蓋**——active API 對剛接的單短暫回 null
  /// 或競態回別的行程時，寧可保留樂觀設定，也不要把剛接到的單清掉。
  /// 重讀失敗（網路）不算接單失敗：吞掉例外、不覆寫 error。
  Future<void> _refreshActiveAfterAccept(int rideId) async {
    try {
      final fresh = await _api.activeRide();
      if (fresh != null && fresh.rideId == rideId) {
        _activeRide = fresh;
      }
    } on ApiException {
      // 樂觀行程已足以繼續作業；重讀失敗不打斷接單流程。
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
