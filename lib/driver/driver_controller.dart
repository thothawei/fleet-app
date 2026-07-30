import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/api_error.dart' show sessionExpiredMessage;
import '../core/api/fleet_api_client.dart';
import '../core/config/app_config.dart';
import '../core/location/driver_location_permissions.dart';
import '../core/location/driver_location_settings.dart';
import '../core/models/models.dart';
import '../core/push/fleet_push_service.dart';
import '../core/push/push_payload.dart';
import '../core/storage/token_storage.dart';
import '../core/ws/fleet_ws_client.dart';

/// 司機端狀態：登入、上線、WS 派單、行程操作。
class DriverController extends ChangeNotifier {
  DriverController({
    DriverAuthStore? storage,
    FleetApiClient? api,
    FleetWsClientFactory? wsFactory,
    FleetPushService? push,
  })  : _storage = storage ?? TokenStorage(),
        _api = api ?? FleetApiClient(),
        _wsFactory = wsFactory ?? FleetWsClient.new,
        _push = push ?? NoOpFleetPushService(),
        _ws = FleetWsClient(onEvent: (_) {}) {
    // token 過期／失效時把司機送回登入頁（見 _handleUnauthorized）。
    _api.onUnauthorized = _handleUnauthorized;
  }

  final DriverAuthStore _storage;
  final FleetApiClient _api;
  final FleetWsClientFactory _wsFactory;
  final FleetPushService _push;
  FleetWsClient _ws;

  AuthSession? _session;
  bool _loading = false;
  String? _error;
  bool _errorIsConnectivity = false;
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
  // session 失效清理中；並發的 401（位置回報＋還原行程同時打）不重入清理。
  bool _sessionExpiring = false;
  // 有一筆位置回報在路上（弱網下防止請求疊起來，見 _reportPosition）。
  bool _reportingPosition = false;
  // 最後一次**成功**回報位置的時刻；上線後還沒成功過時為 null（改看 _onlineSince）。
  DateTime? _lastLocationOkAt;
  DateTime? _onlineSince;

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

  /// 錯誤一律走這兩個入口設定，才能記住它「是不是連線類」。
  /// 這個分類只有一個用途：位置回報探針只能清掉連線類錯誤（見 `_reportPosition`）。
  void _setError(String? message) {
    _error = message;
    _errorIsConnectivity = false;
  }

  /// `statusCode == null` ＝ 沒收到 HTTP 回應（斷線／逾時），才算連線類；
  /// 4xx／5xx 是後端明確拒絕（如 409「此行程已完成」），屬業務錯誤。
  void _setApiError(ApiException e) {
    _error = e.message;
    _errorIsConnectivity = e.statusCode == null;
  }
  bool get online => _online;
  bool get wsConnected => _wsConnected;

  /// 位置已經久到後端不再把他當派單候選（＝**上線了卻收不到派單**）。
  ///
  /// 門檻取後端的 `DRIVER_OFFLINE_SEC`（預設 60 秒）：`NearbyDriverIDs` 只收
  /// `driver:<id>:loc` 的 `updated_at` 在這個窗內的司機，超過就直接跳過。
  /// 弱網最惡劣的地方就在這裡——連線沒斷、WS 看起來也還連著（凍結的後端不會送 FIN），
  /// 司機畫面上寫「等待派單中」，但他其實早就不在派單池裡了（實跑驗到）。
  ///
  /// 上線後還沒成功回報過就從上線時刻起算，否則剛按下上線的那幾秒會誤報。
  bool get locationStale {
    if (!_online) return false;
    final since = _lastLocationOkAt ?? _onlineSince;
    if (since == null) return false;
    return DateTime.now().difference(since) >
        const Duration(seconds: AppConfig.driverOfflineSec);
  }
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
    _setError(null);
    notifyListeners();
    try {
      await action(ride.rideId, stopId);
      // 重讀 active 讓停靠點狀態同步回畫面——標記的結果由後端決定，不在本地猜。
      await _restoreActiveRide();
      return true;
    } on ApiException catch (e) {
      _setApiError(e); // 重複標記／已跳過／已完成（409）的訊息已中文化
      // 逾時不代表後端沒標到（見 `_reconcileAfterTimeout`）；沒對帳的話下一站不會前移，
      // 司機再按一次會被 409 擋下。生效的判準是**那一站已經不是待處理**。
      if (e.statusCode == null) {
        // **必須 `return await`**：`return future;` 在 try/finally 裡會讓 finally
        // （也就是唯一的 notifyListeners）在對帳**完成之前**就跑掉，對帳後
        // `_setError(null)` 便沒有任何人通知畫面重畫——狀態早就乾淨了，
        // 螢幕上卻留著一張「請求逾時」的幽靈橫幅（2026-07-30 模擬器實跑抓到）。
        // 另外兩條路徑（pickUpPassenger／completeTrip）用的是 `await`，所以沒這個症狀。
        return await _reconcileAfterTimeout(
          ride.rideId,
          applied: (fresh) =>
              fresh.stops.any((s) => s.id == stopId && !s.pending),
        );
      }
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
  /// 以後端回的 has_vehicle 為準，不自行判斷「兩欄皆非空」——與 O2 同一條件。
  bool get hasVehicle => _vehicle?.hasVehicle ?? false;

  /// 車輛審核狀態（O5）；未載入時為 none。
  VehicleReviewStatus get vehicleReviewStatus =>
      _vehicle?.reviewStatus ?? VehicleReviewStatus.none;

  /// 能不能接單（O5 gate ＝已核准）。**以後端回的 can_accept 為準**，App 不自行推導。
  bool get canAcceptRides => _vehicle?.canAccept ?? false;

  /// 退回原因（O5）；rejected 時給司機看。
  String get vehicleReviewNote => _vehicle?.reviewNote ?? '';

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
      _setError(null);
    } on ApiException catch (e) {
      _setApiError(e);
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
    _setError(null);
    notifyListeners();
    try {
      _vehicle = await _api.updateVehicle(
        vehicleType: vehicleType,
        plateNumber: plateNumber,
      );
      return true;
    } on ApiException catch (e) {
      _setApiError(e); // 車牌重複（409）等訊息已由 api_error 中文化
      return false;
    } finally {
      _vehicleSaving = false;
      notifyListeners();
    }
  }

  /// 司機聯絡電話（O7）；'' ＝未填。隨 `GET /driver/vehicle` 一起載入。
  String get driverPhone => _vehicle?.phone ?? '';

  /// 設定聯絡電話（O7）。成功回 true。
  ///
  /// 走 `PUT /driver/profile` 而非車輛端點——**改電話不會重置車輛審核狀態**，
  /// 否則司機為了更新一個號碼就會被打回待審核、暫時接不了單。
  /// 以後端回傳值更新本地狀態（號碼已去分隔符）。
  Future<bool> savePhone(String phone) async {
    _vehicleSaving = true;
    _setError(null);
    notifyListeners();
    try {
      final saved = await _api.updateProfilePhone(phone);
      _vehicle = (_vehicle ?? DriverVehicle.empty).withPhone(saved);
      return true;
    } on ApiException catch (e) {
      _setApiError(e);
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

  /// 測試用：直接設定 WS 連線旗標（正式路徑由 WS client 回報）。
  @visibleForTesting
  void setWsConnectedForTest(bool value) {
    _wsConnected = value;
    notifyListeners();
  }

  /// 測試用：把「上線時刻／最後成功回報時刻」往前挪，驗位置過期的門檻。
  @visibleForTesting
  void markOnlineSinceForTest(DateTime since) {
    _onlineSince = since;
    _lastLocationOkAt = null;
    notifyListeners();
  }

  /// 測試用：模擬一次位置回報（正式路徑由 Geolocator stream 觸發，測試環境沒有 GPS）。
  @visibleForTesting
  Future<void> reportPositionForTest(Position pos) => _reportPosition(pos);

  /// App 重啟後從後端還原進行中行程（Accepted/PickedUp）。
  ///
  /// [silent] ＝ 不是司機按出來的（回前景對帳），失敗時不寫 error——
  /// 他只是把 App 切回來，不該因此看到一則錯誤。
  Future<void> _restoreActiveRide({bool silent = false}) async {
    try {
      _activeRide = await _api.activeRide();
      notifyListeners();
    } on ApiException catch (e) {
      if (silent) return;
      _setApiError(e);
      notifyListeners();
    }
  }

  /// App 從背景回到前景（由 `AppLifecycleReactor` 呼叫）。
  ///
  /// 司機端**沒有任何輪詢**：`ride.assigned`／`ride.cancelled`／`ride.completed`
  /// 全靠 WS。背景期間連線被系統關掉的話，漏掉的事件沒有第二條路補回來——
  /// 畫面會停在背景前的狀態，直到司機自己按下某個操作才被後端 409 打回。
  /// 所以回前景要做兩件事：**立刻重連 WS**（不等最長 30 秒的退避）
  /// ＋ **向後端重新對帳一次**進行中行程與協尋清單。
  ///
  /// **刻意不重查車輛審核狀態**：`refreshVehicle()` 失敗會打開 `vehicleLoadFailed`，
  /// 整個畫面換成錯誤頁——等於網路一不穩就把行程中的司機踢出首頁。
  /// 審核狀態變更本來就有後端 gate 擋著，不需要每次回前景都問一遍。
  Future<void> onAppResumed() async {
    if (_session == null) return;
    _ws.ensureConnected();
    await _restoreActiveRide(silent: true);
    await refreshLostItems();
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
      _setError(null);
      // 登入即更新「遺失物協尋」角標與工作清單，不用等進頁下拉（比照 init() 還原 session）。
      await refreshLostItems();
      // 登入後立刻查車輛：沒填的話 _DriverRoot 會直接導去設定頁（O3 gate 的 App 端引導）。
      await refreshVehicle();
    } on ApiException catch (e) {
      _setApiError(e);
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
    _pushSub = _push.rideEvents.listen(_handlePushEvent);
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _push.tokenRefresh.listen((_) => _syncDeviceToken());
  }

  /// 推播事件的入口。
  ///
  /// 派單邀請直接走 `_handleWsEvent`——它的 data 是完整的（後端沒有「目前 offer」端點，
  /// 喚醒後只能靠 payload 開接單卡）。**對話訊息不行**：推播 data 只有 `type` 與 `ride_id`，
  /// 餵進去 `RideMessage.fromJson` 會解析失敗被丟掉，未讀角標不會動。
  void _handlePushEvent(FleetWsEvent event) {
    if (isChatPush(event)) {
      _onChatPush();
      return;
    }
    if (isLostItemPush(event)) {
      // 同樣不能餵進 _handleWsEvent：推播 data 沒有協尋單本體，
      // LostItemRequest.fromJson 會解析失敗被丟掉，清單與角標都不會動。
      unawaited(refreshLostItems());
      return;
    }
    _handleWsEvent(event);
  }

  /// 收到「乘客傳來訊息」的推播：只把未讀角標點亮，內容等聊天室自己以 REST 補齊。
  ///
  /// 聊天室開著時忽略：那代表 App 在前景、WS 也連著，同一則訊息已經由 WS 送到並顯示，
  /// 這裡再加一次會把角標加在使用者正在看的訊息上。
  void _onChatPush() {
    if (_chatVisible) return;
    _unreadChat++;
    notifyListeners();
  }

  /// 登入後向後端註冊 FCM token；token 刷新時亦會重註冊。
  Future<void> _syncDeviceToken() async {
    if (!_push.isAvailable || _session == null) return;
    try {
      final token = await _push.getToken();
      if (token == null || token.isEmpty) return;
      await _api.registerDeviceToken(platform: 'fcm', token: token);
      _fcmToken = token;
    } on ApiException {
      // 靜默降級：這是登入時與 token 輪替時的背景動作，司機沒按任何東西。
      // 註冊失敗只代表「推播喚醒」這條退路暫時不可用，WS 派單仍照常運作——
      // 變成首頁上一條紅色橫幅只會讓司機以為自己不能接單，而他也無事可做。
      // 下一次輪替或重新登入會自動再試。
    }
  }

  Future<void> logout() async {
    if (_fcmToken != null) {
      try {
        await _api.unregisterDeviceToken(token: _fcmToken!);
      } catch (_) {}
    }
    await _clearSession();
    notifyListeners();
  }

  /// token 過期／失效（401）：**本地登出**並讓司機知道要重新登入。
  ///
  /// 沒有這條路，過期後的畫面會說謊：`isLoggedIn` 仍為 true，司機停在首頁、
  /// 上線開關看起來是開的，但每一次位置回報都被 401 擋下——他不在派單池裡，
  /// 卻只看到「等待派單中」。JWT 預設 72 小時（後端 `JWT_EXPIRY_HOURS`），
  /// 這不是邊角情境，是每個持續使用的司機三天後必然遇到的。
  ///
  /// **不打 `unregisterDeviceToken`**：token 已失效，那支 API 只會再回一次 401。
  void _handleUnauthorized() {
    if (_session == null || _sessionExpiring) return;
    _sessionExpiring = true;
    unawaited(() async {
      try {
        await _clearSession();
        _setError(sessionExpiredMessage);
      } finally {
        _sessionExpiring = false;
      }
      notifyListeners();
    }());
  }

  /// 清掉本機 session 與所有跟著它的狀態（登出與 session 失效共用）。
  ///
  /// **車輛狀態一定要一起清**：留著它，下一個登入的司機會在自己的資料載入前
  /// 先看到上一個人的審核狀態（甚至直接進首頁）。
  Future<void> _clearSession() async {
    await goOffline();
    await _ws.disconnect();
    await _storage.clear();
    _fcmToken = null;
    _session = null;
    _api.setToken(null);
    _pendingOffer = null;
    _activeRide = null;
    _unreadChat = 0;
    _chatVisible = false;
    _lostItems = [];
    _vehicle = null;
    _vehicleLoadFailed = false;
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
      _setError('需要定位權限才能上線');
      notifyListeners();
      return;
    }
    _online = true;
    _onlineSince = DateTime.now();
    _lastLocationOkAt = null;
    _setError(null);
    await _startLocationStream();
    notifyListeners();
  }

  Future<void> goOffline() async {
    _online = false;
    _onlineSince = null;
    _lastLocationOkAt = null;
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
    // 弱網保護：一次只放一筆位置在路上。
    // 定位每 8 秒一個 tick，但單筆請求最久可以拖 25 秒（連線 10＋接收 15），
    // 不擋的話請求會疊起來——實測後端凍結時同時連線數從 1 漲到 3，而且先送的舊座標
    // 可能後到，把司機在派單池裡的位置往回拉。丟掉這一筆沒有損失：下一個 tick
    // 送的是**更新**的座標，回報位置本來就只在乎最後一筆。
    if (_reportingPosition) return;
    _reportingPosition = true;
    try {
      _lastPosition = pos;
      await _api.reportLocation(lat: pos.latitude, lng: pos.longitude);
      _lastLocationOkAt = DateTime.now();
      // 位置回報是上線期間每幾秒一次的健康探針：它成功＝後端可達，
      // 此時還掛著上一輪的「無法連線到伺服器」只會誤導司機。
      // **但只能清連線類**：後端明確拒絕的業務錯誤（例如完成行程被 409 擋下）
      // 是司機唯一的失敗回饋，被 8 秒一次的探針抹掉就等於沒說過。
      if (_errorIsConnectivity) {
        _setError(null);
        notifyListeners();
      }
    } on ApiException catch (e) {
      _setApiError(e);
      notifyListeners();
    } catch (_) {
    } finally {
      _reportingPosition = false;
    }
  }

  Future<void> acceptOffer() async {
    final offer = _pendingOffer;
    if (offer == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final message = await _api.acceptRide(offer.rideId);
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
      _setError(null);
      // 以後端為權威補齊：**推播喚醒路徑**的 offer 來自 FCM data，data 值全是字串、
      // 不帶結構化的 stops 陣列（見 pitfall-fcm-data-all-strings），所以樂觀行程會缺全程。
      // 重讀 active 讓多停靠點清單／多點地圖一定齊全，不必讓推播 payload 塞 stops。
      // 同一次重讀也是**接單到底成不成立**的唯一可靠判準（見下）。
      await _refreshActiveAfterAccept(offer.rideId, message);
    } on ApiException catch (e) {
      _setApiError(e);
      // 弱網：逾時／連線失敗**不代表後端沒接到**（請求可能已經送達並處理完，
      // 只是回應沒回來）。這時直接報錯會讓司機再按一次，而後端會回
      // 「手慢了，這單已被其他司機接走」——他自己搶走了自己的單。
      // 所以先問後端：這張單現在是不是我的。
      if (e.statusCode == null) await _adoptRideIfAccepted(offer.rideId);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 接單後重讀 active：既補齊樂觀 offer 缺的欄位（尤其 stops），也判定接單是否真的成立。
  ///
  /// **後端接單失敗時回的是 HTTP 200**：搶輸別人回 `{"message":"手慢了，這單已被其他司機接走"}`、
  /// 非待命狀態回 `{"message":"您目前無法接單（非待命狀態）"}`——都不是錯誤碼（已對真後端實測）。
  /// 只看「有沒有丟例外」的話，沒搶到的司機會拿到一張**完整但假的行程卡**
  /// （前往上車點、導航、乘客已上車），開去接一個不存在的乘客，直到按下操作被 409 擋下。
  ///
  /// 判準用**後端的 active 行程**而不是 parse 那句文案（文案會改，狀態不會）：
  /// - 回傳同一張單 → 接單成立，以後端資料為準（缺的欄位用樂觀 offer 補，見 `filledFrom`）。
  /// - 回 null → **沒接到**：清掉樂觀行程與接單卡，把後端那句話顯示出來。
  ///   接單成功時後端在回應前就已寫入 ride（status/driver_id），這裡讀不到就是真的沒有。
  /// - 回別張單 → 也是沒接到，但司機手上另有一張進行中的單 → 顯示**那一張**（後端說了算）。
  /// - 重讀本身失敗（網路）→ **不知道，就不要亂改**：維持樂觀行程，之後回前景／
  ///   下一次操作會校正（見 `onAppResumed`）。
  Future<void> _refreshActiveAfterAccept(int rideId, String message) async {
    final optimistic = _activeRide;
    try {
      final fresh = await _api.activeRide();
      if (fresh != null && fresh.rideId == rideId) {
        _activeRide = optimistic == null ? fresh : fresh.filledFrom(optimistic);
        return;
      }
      _activeRide = fresh;
      _pendingOffer = null;
      _setError(message);
    } on ApiException {
      // 樂觀行程已足以繼續作業；重讀失敗不打斷接單流程。
    }
  }

  /// 接單請求逾時後，向後端確認這張單是不是已經接到手了。
  ///
  /// 接到了 → 收掉接單卡、顯示行程卡、清掉那句逾時錯誤（他其實成功了）。
  /// 沒接到 → 什麼都不動，逾時訊息留著讓他自己決定要不要再按一次。
  /// 查詢本身也失敗 → 同樣什麼都不動（不知道就不亂改）。
  Future<void> _adoptRideIfAccepted(int rideId) async {
    try {
      final fresh = await _api.activeRide();
      if (fresh == null || fresh.rideId != rideId) return;
      _activeRide = fresh;
      _pendingOffer = null;
      _setError(null);
    } on ApiException {
      // 弱網下這一問也可能逾時；維持原本的錯誤訊息。
    }
  }

  /// **行程中的寫入請求逾時後**，跟後端要一次進行中行程當作權威狀態。
  ///
  /// 逾時 ＝ 沒收到回應，**不等於後端沒收到請求**——上車／完成／停靠點標記都可能已經生效，
  /// 只是回應在半路不見了。畫面停在舊階段的話，司機再按一次會被後端 409 擋下，
  /// 等於他自己擋自己（第六輪已對接單與乘客建單做過同一件事，這裡補完剩下三條）。
  ///
  /// - **後端沒有進行中行程** → 這張單已經不在他手上（完成／被取消都算）：清掉行程卡與錯誤。
  /// - **回同一張單** → 以後端為準（缺的欄位用手上這張補，見 `filledFrom`）；
  ///   [applied] 說寫入生效了才清掉逾時訊息，否則留著讓他自己決定要不要再按一次。
  /// - **回別張單** → 也以後端為準；他要操作的那張已經不在了，訊息留著沒有意義。
  /// - **這一問也失敗**（弱網下很可能）→ **不知道就不亂改**：畫面與訊息都維持原狀，
  ///   之後回前景的 `onAppResumed` 還會再對帳一次。
  ///
  /// 回傳「寫入是否確定生效」。
  Future<bool> _reconcileAfterTimeout(
    int rideId, {
    bool Function(ActiveRide fresh)? applied,
  }) async {
    final before = _activeRide;
    try {
      final fresh = await _api.activeRide();
      if (fresh == null) {
        _activeRide = null;
        _setError(null);
        return true;
      }
      _activeRide = before == null ? fresh : fresh.filledFrom(before);
      if (fresh.rideId != rideId) {
        _setError(null);
        return false;
      }
      final ok = applied?.call(fresh) ?? false;
      if (ok) _setError(null);
      return ok;
    } on ApiException {
      return false;
    }
  }

  /// 略過這張派單。
  ///
  /// **要告訴後端**（`POST /rides/:id/decline`）：後端會把司機加進該單的「已拒接」名單，
  /// 重派時跳過他。只在本地關掉卡片的話，同一張單重新派單時還會再送到他面前。
  /// 失敗靜默——這是司機按「略過」的附帶動作，卡片該關就關，不能因為網路而卡住。
  void dismissOffer() {
    final offer = _pendingOffer;
    _pendingOffer = null;
    notifyListeners();
    if (offer == null) return;
    unawaited(() async {
      try {
        await _api.declineRide(offer.rideId);
      } on ApiException {
        // 後端沒收到拒單只會讓他可能再被派到同一張單，不值得打斷畫面。
      }
    }());
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
      _setError(null);
    } on ApiException catch (e) {
      _setApiError(e);
      // 逾時後後端可能已經是 picked_up 了；不對帳的話畫面停在「前往上車點」，
      // 他再按一次「乘客已上車」只會被後端擋下（生效的判準是階段已進到行程中）。
      if (e.statusCode == null) {
        await _reconcileAfterTimeout(
          ride.rideId,
          applied: (fresh) => fresh.phase == DriverRidePhase.onTrip,
        );
      }
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
      _setError(null);
    } on ApiException catch (e) {
      _setApiError(e);
      // 三條逾時對帳裡**這條最嚴重**：完成請求送到了、回應沒回來，行程卡會一直留著，
      // 司機以為這趟沒結束（後端那邊車資早就定格了），而他再按一次會被 409 擋下。
      // 「完成」生效的表現就是後端不再有進行中行程 → `_reconcileAfterTimeout` 的
      // fresh == null 分支會清掉行程卡與那句逾時訊息，不需要額外的 applied 判準。
      if (e.statusCode == null) await _reconcileAfterTimeout(ride.rideId);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 放棄已接的訂單。
  ///
  /// **後端拒絕時同樣回 200**（例如已進行到不能放棄的階段會回「此訂單目前無法放棄」），
  /// 所以跟接單一樣不能只看有沒有丟例外——否則畫面會把單收掉，司機以為放棄成功了，
  /// 實際上這張單還掛在他名下（乘客還在等）。判準一樣是後端的 active 行程。
  Future<void> abandonTrip() async {
    final ride = _activeRide;
    if (ride == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final message = await _api.cancelRide(ride.rideId);
      _activeRide = null;
      _setError(null);
      try {
        final fresh = await _api.activeRide();
        if (fresh != null && fresh.rideId == ride.rideId) {
          // 後端說這張單還是他的 → 沒放棄成功，把行程卡放回去並說明原因。
          _activeRide = fresh;
          _setError(message);
        }
      } on ApiException {
        // 查不到就維持樂觀（不知道就不亂改）；回前景時會再對帳一次。
      }
    } on ApiException catch (e) {
      _setApiError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 查當月收入（E1 司機收入頁用）。month 格式 YYYY-MM。
  Future<DriverEarnings> fetchEarnings(String month) =>
      _api.fetchEarnings(month: month);

  /// 查自己的服務評價彙總（B5 司機收入頁用）。
  Future<DriverRatingSummary> fetchMyRating() => _api.fetchMyRating();

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
  Future<LostItemRequest> markLostItemFound(int itemId, {required int rideId}) =>
      _writeLostItem(
        () => _api.markLostItemFound(itemId),
        rideId: rideId,
        // 「已經越過 open」＝這次標記生效了（乘客可能已接著付款）。
        // 不能只寫 `!= open`：被結案（closed）也符合那個條件，但那不是標尋獲。
        applied: (fresh) =>
            fresh.id == itemId &&
            (fresh.status == LostItemStatus.found ||
                fresh.status == LostItemStatus.paid ||
                fresh.status == LostItemStatus.returned),
      );

  /// 付訖後標記已歸還（paid → returned）。
  Future<LostItemRequest> markLostItemReturned(int itemId,
          {required int rideId}) =>
      _writeLostItem(
        () => _api.markLostItemReturned(itemId),
        rideId: rideId,
        applied: (fresh) =>
            fresh.id == itemId && fresh.status == LostItemStatus.returned,
      );

  /// 未尋獲結案（open/found → closed）。
  Future<LostItemRequest> closeLostItem(int itemId, {required int rideId}) =>
      _writeLostItem(
        () => _api.closeLostItem(itemId),
        rideId: rideId,
        applied: (fresh) =>
            fresh.id == itemId && fresh.status == LostItemStatus.closed,
      );

  /// 協尋單的寫入 ＋ 逾時對帳（司機端三條寫入路徑共用）。
  ///
  /// 與乘客端 `CustomerController._writeLostItem` 同一套判斷：連線類逾時或 409 時
  /// 問一次這趟的最新協尋單，[applied] 成立就當成成功、套用後端現況；
  /// 否則把**原本那個例外**丟回畫面。
  ///
  /// 為什麼判準不能用未結案清單：`returned` 與 `closed` 都不在清單裡，
  /// 分不出「已歸還」還是「被結案」——而這兩個動作要分得出來。
  Future<LostItemRequest> _writeLostItem(
    Future<LostItemRequest> Function() action, {
    required int rideId,
    required bool Function(LostItemRequest fresh) applied,
  }) async {
    try {
      final item = await action();
      _applyLostItem(item);
      notifyListeners();
      return item;
    } on ApiException catch (e) {
      if (e.statusCode != null && e.statusCode != 409) rethrow;
      final fresh = await _lostItemForReconcile(rideId);
      // 重擲的必須是原本那個動作的例外。對帳的 try/catch 收在
      // `_lostItemForReconcile` 裡（失敗回 null），所以這個 rethrow 擲的仍是 e。
      if (fresh == null || !applied(fresh)) rethrow;
      _applyLostItem(fresh);
      notifyListeners();
      return fresh;
    }
  }

  Future<LostItemRequest?> _lostItemForReconcile(int rideId) async {
    try {
      return await _api.fetchLostItemByRide(rideId);
    } on ApiException {
      return null;
    }
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
        // 這張單已經被接走了——**包含被自己的另一台裝置接走**。後端的 Hub 是依
        // (角色, id) 扇出，同一個帳號的每一條連線都收得到 ride.assigned 與
        // ride.accepted（已對真後端實測）。少了這一段，另一台裝置的全螢幕接單卡
        // 會一直蓋在畫面上，按下去只會拿到「非待命狀態」。
        if (event.rideId != null && _pendingOffer?.rideId == event.rideId) {
          _pendingOffer = null;
          notifyListeners();
          // 這台沒有行程資料（接單的是另一台），只收掉卡片會讓畫面顯示「等待派單中」——
          // 司機其實正在跑這一趟。跟後端要一次，兩台裝置就看到同一張行程卡。
          if (_activeRide == null) {
            unawaited(_restoreActiveRide(silent: true));
          }
        }
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
      case FleetEventTypes.rideStopUpdated:
        // 停靠點在**別處**被標記了（同一司機的另一台裝置、或 LINE 那條路徑）。
        // 乘客端早就會收這則事件並更新進度，司機端先前完全不處理——兩台裝置會停在
        // 不同的「下一站」，而「下一站」正是司機端唯一給操作按鈕的那一站，
        // 於是兩台會對不同的乘客顯示「已上車／已下車／跳過」。
        //
        // 事件 payload 帶整趟 stops，但這裡仍以**後端重讀**為準：司機端行程卡還要
        // 階段（phase）與車資等 payload 沒有的欄位，重讀一次最不容易對不齊。
        // 失敗靜默——這不是使用者按出來的動作，跳錯誤橫幅只會干擾他開車。
        if (event.rideId != null && _activeRide?.rideId == event.rideId) {
          unawaited(_restoreActiveRide(silent: true));
        }
      case FleetEventTypes.rideTaken:
        // 別的司機搶到了這單。同一張單會同時推給半徑內每一位待命司機，
        // 先前沒有任何事件收得掉沒搶到那些人的接單卡——他得自己按下去、
        // 拿到「手慢了，這單已被其他司機接走」才會消失（期間還蓋著整個畫面）。
        // **不寫錯誤訊息**：他什麼都沒做，卡片安靜地收掉就是正確的行為。
        if (event.rideId != null && _pendingOffer?.rideId == event.rideId) {
          _pendingOffer = null;
          notifyListeners();
        }
      case FleetEventTypes.rideCompleted:
      case FleetEventTypes.rideCancelled:
        if (event.rideId != null &&
            (_activeRide?.rideId == event.rideId ||
                _pendingOffer?.rideId == event.rideId)) {
          // 取消的行程卡**不能無聲消失**：司機正開往上車點，畫面突然少一張卡
          // 只會讓他以為 App 壞了。這則事件只有「別人取消」才會送到司機這邊
          // （他自己放棄走的是 ride.redispatched，且不推給司機），所以說得出原因。
          // 完成不必說——那是他自己按的。
          if (event.type == FleetEventTypes.rideCancelled &&
              _activeRide?.rideId == event.rideId) {
            _setError('這筆訂單已被取消，不用再前往上車點');
          }
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
