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
    FleetWsClientFactory? wsFactory,
  })  : _storage = storage ?? CustomerTokenStorage(),
        _api = api ?? CustomerApiClient(),
        _wsFactory = wsFactory ?? FleetWsClient.new,
        _ws = FleetWsClient(onEvent: (_) {});

  final CustomerTokenStorage _storage;
  final CustomerApiClient _api;
  final FleetWsClientFactory _wsFactory;
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
  // 最近一筆進行中訂單的鏡像：即使輪詢對帳先把 _activeRide 清成 null，仍能在稍後才到的
  // ride.completed 事件補出完成摘要（dropoff 等），避免完成卡因競態而不顯示。
  CustomerRide? _lastActiveRide;
  String? _driverName;
  // 司機車輛與聯絡方式（O4／O7），來自 ride.accepted payload。
  RideDriverInfo? _driverInfo;
  // 上一趟的取消原因（P4），來自 ride.cancelled payload 的機器可讀欄位。
  CancelReason? _cancelReason;
  String? _cancelledVehicleType;
  // 是否有待呈現的取消通知（P4）。reason 為 null 也要通知（乘客主動取消／司機放棄
  // 走泛用文案），故需獨立旗標，不能只看 _cancelReason。
  bool _rideCancelled = false;
  // 乘客指定的車種（P2）；null ＝不指定，維持現行行為。
  VehicleType? _requiredVehicleType;
  // 寵物車清潔費率（P5）；null ＝尚未查到（費率不常變，快取一次即可）。
  int? _petCleaningFeeBps;
  // 多乘客行程的編輯狀態（N3）；空 ＝ 單點訂單。
  final List<PassengerTrip> _passengers = [];
  int? _liveEtaSec;
  int? _liveDistM;
  double? _liveDriverLat;
  double? _liveDriverLng;
  bool _driverArrived = false;
  CompletedRideSummary? _completedSummary;
  Timer? _pollTimer;

  // 聊天：WS chat.message 即時串流 + 未讀計數（聊天室開啟時不累計）。
  final _chatStream = StreamController<RideMessage>.broadcast();
  int _unreadChat = 0;
  bool _chatVisible = false;

  // 遺失物：未結案協尋單（WS lost_item.* 即時更新）。
  List<LostItemRequest> _lostItems = [];

  // 歷史行程（我的行程列表；進畫面時才載入）。
  List<CustomerRideSummary> _rideHistory = [];
  bool _historyLoading = false;
  String? _historyError;

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

  /// 司機車輛與聯絡方式（O4／O7），來自 ride.accepted。未接單時為 null。
  /// 車種／車牌供路邊對車；電話為明碼，**僅該趟乘客可見**。
  RideDriverInfo? get driverInfo => _driverInfo;

  /// 上一趟的取消原因（P4）。**只有逾時取消會帶**，乘客主動取消／司機放棄為 null。
  CancelReason? get cancelReason => _cancelReason;

  /// 取消時乘客指定的車種 code（P4，搭配 cancelReason 產生訊息）。
  String? get cancelledVehicleType => _cancelledVehicleType;

  /// 待呈現的取消通知文案（P4）；null ＝ 沒有要顯示的取消。
  /// 文案由機器可讀的 cancel_reason 產生（cancelMessage），不 parse 後端字串。
  String? get cancelNotice =>
      _rideCancelled ? cancelMessage(_cancelReason, _cancelledVehicleType) : null;

  /// 是否該給「改用不指定車種重新叫車」快捷（P4：只有指定車種找不到才建議）。
  bool get suggestAnyVehicle =>
      _rideCancelled && shouldSuggestAnyVehicle(_cancelReason);

  /// 關閉取消通知（乘客按「知道了」或採用快捷操作後）。
  void dismissCancelNotice() {
    _rideCancelled = false;
    _cancelReason = null;
    _cancelledVehicleType = null;
    notifyListeners();
  }

  /// 乘客指定的車種（P2）；null ＝不指定（任何車種都可派）。
  VehicleType? get requiredVehicleType => _requiredVehicleType;

  /// 寵物車清潔費率（bps，P5）；尚未查到時為 null → UI 降級顯示「上限 30%」。
  int? get petCleaningFeeBps => _petCleaningFeeBps;

  /// 多乘客行程的編輯狀態（N3）；空 ＝ 單點訂單（維持現行行為）。
  List<PassengerTrip> get passengers => List.unmodifiable(_passengers);

  /// 是否已啟用多乘客模式。
  bool get multiStopEnabled => _passengers.isNotEmpty;

  /// 可否再加一位（後端 N2 拍板上限 5 位）。
  bool get canAddPassenger => _passengers.length < maxRidePassengers;

  /// 已填完上下車的乘客數——**只有這些人會被送出**（buildStops 略過未填完的）。
  int get completePassengerCount => _passengers.where((p) => p.complete).length;

  /// 啟用多乘客模式並加入第一位。
  ///
  /// **漸進展開**（App 端待拍板的建議方案）：預設 1 位、按「+ 新增乘客」再加——
  /// 一次逼使用者填滿 5 位太繁瑣，而多數行程只有 1-2 位。
  void enableMultiStop() {
    if (_passengers.isEmpty) addPassenger();
  }

  /// 關閉多乘客模式，回到單一目的地的既有流程。
  void disableMultiStop() {
    _passengers.clear();
    notifyListeners();
  }

  /// 新增一位乘客（標籤自動給 A/B/C…，與司機端看到的一致）。
  void addPassenger() {
    if (!canAddPassenger) return;
    _passengers.add(PassengerTrip(label: _labelFor(_passengers.length)));
    notifyListeners();
  }

  /// 移除某位乘客；移除後**重新編號**——出現「A、C」的跳號會讓司機困惑。
  void removePassenger(int index) {
    if (index < 0 || index >= _passengers.length) return;
    _passengers.removeAt(index);
    for (var i = 0; i < _passengers.length; i++) {
      final old = _passengers[i];
      _passengers[i] = PassengerTrip(
        label: _labelFor(i),
        pickup: old.pickup,
        dropoff: old.dropoff,
      );
    }
    notifyListeners();
  }

  /// 設定某位乘客的上車／下車點。
  void setPassengerPoint(int index, {StopPoint? pickup, StopPoint? dropoff}) {
    if (index < 0 || index >= _passengers.length) return;
    if (pickup != null) _passengers[index].pickup = pickup;
    if (dropoff != null) _passengers[index].dropoff = dropoff;
    notifyListeners();
  }

  static String _labelFor(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// 選擇車種（P2）。選寵物用車時順帶把費率查回來，讓 UI 當場顯示加價。
  Future<void> setRequiredVehicleType(VehicleType? type) async {
    _requiredVehicleType = type;
    notifyListeners();
    if (type == VehicleType.pet && _petCleaningFeeBps == null) {
      await refreshPetCleaningFee();
    }
  }

  /// 查乘客可讀的清潔費率（P5）。失敗**不設值也不擋叫車**——
  /// UI 會降級顯示「將加收清潔費（上限 30%）」，總比因為查費率失敗而不能叫車好。
  Future<void> refreshPetCleaningFee() async {
    try {
      _petCleaningFeeBps = await _api.fetchPetCleaningFeeBps();
      notifyListeners();
    } on ApiException {
      // 靜默降級：這不是乘客的錯，也不該打斷叫車流程。
    }
  }

  /// 司機接近上車點的即時 ETA/距離，來自 driver.location WS 事件（司機移動時更新）。
  int? get liveEtaSec => _liveEtaSec;
  int? get liveDistM => _liveDistM;

  /// 司機即時座標（WS driver.location），供地圖 marker 更新。
  double? get liveDriverLat => _liveDriverLat;
  double? get liveDriverLng => _liveDriverLng;

  /// 司機是否已進上車圍籬（WS `driver.arrived`；後端 status 仍為 Accepted）。
  bool get driverArrived => _driverArrived;

  /// 剛完成的行程摘要（B5 評分／付款佔位）；點「再叫一輛」後清除。
  CompletedRideSummary? get completedSummary => _completedSummary;

  /// 即時聊天訊息串流（WS chat.message，含自己其他裝置的回聲；聊天室以 id 去重）。
  Stream<RideMessage> get chatStream => _chatStream.stream;

  /// 對方傳來、尚未讀的訊息數（聊天室關閉時累計）。
  int get unreadChat => _unreadChat;

  /// 未結案遺失物協尋單。
  List<LostItemRequest> get lostItems => _lostItems;

  /// 歷史行程（我的行程列表）。
  List<CustomerRideSummary> get rideHistory => List.unmodifiable(_rideHistory);
  bool get historyLoading => _historyLoading;
  String? get historyError => _historyError;

  /// 載入歷史行程（進「我的行程」畫面時呼叫）。
  Future<void> loadRideHistory() async {
    if (_session == null) return;
    _historyLoading = true;
    _historyError = null;
    notifyListeners();
    try {
      _rideHistory = await _api.fetchRideHistory();
    } on ApiException catch (e) {
      _historyError = e.message;
    } finally {
      _historyLoading = false;
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
      await refreshActive();
      await refreshLostItems();
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
      // 登入即帶出「進行中協尋」banner，不用等下拉刷新（比照 init() 還原 session）。
      await refreshLostItems();
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
    _lastActiveRide = null;
    _driverName = null;
    _driverInfo = null;
    _cancelReason = null;
    _cancelledVehicleType = null;
    _rideCancelled = false;
    _requiredVehicleType = null;
    _passengers.clear();
    _liveEtaSec = null;
    _liveDistM = null;
    _liveDriverLat = null;
    _liveDriverLng = null;
    _driverArrived = false;
    _completedSummary = null;
    _unreadChat = 0;
    _chatVisible = false;
    _lostItems = [];
    _api.setToken(null);
    notifyListeners();
  }

  /// 關閉完成卡，回到叫車表單（評分／付款 API 就緒前的佔位流程）。
  void dismissCompleted() {
    _completedSummary = null;
    notifyListeners();
  }

  /// 測試用：模擬收到 WS 事件（等同正式連線後的 onEvent）。
  @visibleForTesting
  void handleWsEventForTest(FleetWsEvent event) => _handleWsEvent(event);

  /// 測試用：注入已登入 session（略過 storage/init）。
  @visibleForTesting
  void setSessionForTest(CustomerSession session) {
    _session = session;
    notifyListeners();
  }

  /// 測試用：注入進行中訂單與可選即時欄位。
  @visibleForTesting
  void setActiveRideForTest(
    CustomerRide ride, {
    String? driverName,
    int? liveEtaSec,
    int? liveDistM,
    bool driverArrived = false,
  }) {
    _activeRide = ride;
    _lastActiveRide = ride;
    _driverName = driverName;
    _liveEtaSec = liveEtaSec;
    _liveDistM = liveDistM;
    _driverArrived = driverArrived;
    _completedSummary = null;
    notifyListeners();
  }

  /// 測試用：模擬行程完成後進入 B5 佔位畫面。
  @visibleForTesting
  void markCompletedForTest({
    required int rideId,
    String? dropoffAddress,
    String? driverName,
    int? fareAmountCents,
    int? cleaningFeeCents,
  }) {
    _completedSummary = CompletedRideSummary(
      rideId: rideId,
      dropoffAddress: dropoffAddress,
      driverName: driverName,
      fareAmountCents: fareAmountCents,
      cleaningFeeCents: cleaningFeeCents,
    );
    notifyListeners();
  }

  /// WS 即時事件：訂單生命週期變化時立即以權威狀態對帳（GET active）。
  /// 聊天與遺失物事件不受「進行中訂單」限制——遺失物協尋發生在行程完成後。
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
    // ride.completed 特別處理：完成摘要不能依賴當下的 _activeRide——輪詢對帳（refreshActive
    // → _applyActiveRide）對終態行程會先把 _activeRide 清成 null，若這步早於 WS 完成事件抵達，
    // 原本的 active==null 早退就會讓 _completedSummary 永遠設不出來、完成卡不顯示（實跑重現的競態）。
    // 改用「當前或最近一筆」進行中訂單鏡像來取 rideId/dropoff，事件本身帶車資。
    if (event.type == FleetEventTypes.rideCompleted) {
      final ride = _activeRide ?? _lastActiveRide;
      if (ride == null || event.rideId != ride.rideId) return;
      // active API 不含終態；先留下摘要供 B5 佔位，再對帳清空進行中訂單
      _completedSummary = CompletedRideSummary(
        rideId: ride.rideId,
        dropoffAddress: ride.dropoffAddress,
        driverName: _driverName,
        fareAmountCents: (event.payload?['fare_amount_cents'] as num?)?.toInt(),
        // O6：只有乘客指定寵物車的行程才有；後端未加收時**不帶這個鍵** → null。
        cleaningFeeCents: (event.payload?['cleaning_fee_cents'] as num?)?.toInt(),
      );
      refreshActive();
      return;
    }
    final active = _activeRide;
    if (active == null || event.rideId != active.rideId) return;
    switch (event.type) {
      case FleetEventTypes.rideStopUpdated:
        // N8：payload 帶**整趟** stops，直接覆蓋——不在客戶端套用差異，
        // 漏收一則事件也不會讓進度永遠對不上（下一次 refreshActive 也會校正）。
        final stops = RideStop.listFrom(event.payload?['stops']);
        if (stops.isEmpty) return;
        _activeRide = active.withStops(stops);
        _lastActiveRide = _activeRide;
        notifyListeners();
      case FleetEventTypes.rideAccepted:
        _driverName = event.payload?['driver_name'] as String?;
        // O4／O7：車種車牌供路邊對車，電話供直接聯絡（明碼，僅該趟乘客收得到此事件）。
        _driverInfo = RideDriverInfo.fromPayload(event.payload ?? const {});
        _driverArrived = false;
        refreshActive();
      case FleetEventTypes.driverLocation:
        _liveEtaSec = (event.payload?['eta_sec'] as num?)?.toInt();
        _liveDistM = (event.payload?['dist_m'] as num?)?.toInt();
        _liveDriverLat = (event.payload?['lat'] as num?)?.toDouble();
        _liveDriverLng = (event.payload?['lng'] as num?)?.toDouble();
        notifyListeners();
      case FleetEventTypes.driverArrived:
        _driverArrived = true;
        _liveEtaSec = null;
        _liveDistM = null;
        _liveDriverLat = null;
        _liveDriverLng = null;
        notifyListeners();
      case FleetEventTypes.ridePickedUp:
        refreshActive();
      case FleetEventTypes.rideCancelled:
        // P4：以機器可讀的 cancel_reason 判斷，不 parse 後端文案（文案會改）。
        // 只有逾時取消會帶這兩個鍵；乘客主動取消／司機放棄不帶 → 解析為 null，
        // UI 走泛用訊息。
        _cancelReason = CancelReason.fromCode(event.payload?['cancel_reason'] as String?);
        _cancelledVehicleType = event.payload?['required_vehicle_type'] as String?;
        _rideCancelled = true;
        refreshActive();
      default:
        break;
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
    // 只有「對方傳來」且聊天室未開啟才累計未讀（自己其他裝置的回聲不算）。
    if (msg.senderRole != 'customer' && !_chatVisible) {
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

  /// 重新拉未結案協尋單（登入後、下拉更新時）。
  Future<void> refreshLostItems() async {
    if (_session == null) return;
    try {
      _lostItems = await _api.fetchLostItems();
      notifyListeners();
    } on ApiException catch (_) {
      // 保底輪詢性質，失敗不覆蓋主錯誤訊息
    }
  }

  /// 對已完成行程建立遺失物協尋單；回傳含處理費快照的協尋單。
  Future<LostItemRequest> reportLostItem(int rideId, String description) async {
    final item = await _api.createLostItem(rideId, description);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 支付處理費（司機尋獲後）。
  Future<LostItemRequest> payLostItem(int itemId) async {
    final item = await _api.payLostItem(itemId);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 取消協尋（open/found）。
  Future<LostItemRequest> closeLostItem(int itemId) async {
    final item = await _api.closeLostItem(itemId);
    _applyLostItem(item);
    notifyListeners();
    return item;
  }

  /// 查該行程最新協尋單（完成卡進入遺失物頁時用）。
  /// 抓到的最新單子順手合併回未結案清單（`_applyLostItem`）：協尋詳情頁 build 會以
  /// `lostItems` 為準來反映 WS 即時更新，若清單因漏收 WS 事件而過期，會蓋掉本頁剛抓到的
  /// 新狀態（實跑時「返回再進顯示舊狀態」的根因，該情境源於登入後 WS 未重連——已於別處修）。
  /// 這裡讓「新鮮抓取」同步成為清單的權威來源，即使 WS 偶爾漏事件也不會顯示過期狀態。
  Future<LostItemRequest?> fetchLostItemByRide(int rideId) async {
    final item = await _api.fetchLostItemByRide(rideId);
    if (item != null) {
      _applyLostItem(item);
      notifyListeners();
    }
    return item;
  }

  /// 聊天歷史／發送（聊天室畫面用）。
  Future<List<RideMessage>> fetchMessages(int rideId, {int afterId = 0}) =>
      _api.fetchMessages(rideId, afterId: afterId);

  Future<RideMessage> sendMessage(int rideId, String body) =>
      _api.sendMessage(rideId, body);

  /// 叫車：以目前 GPS 為上車點，帶乘客輸入的上車/目的地地址；
  /// 若目的地由地圖選點取得，另帶精確座標（dropoffLat/Lng）。
  Future<void> placeOrder({
    required String pickupAddress,
    required String dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
  }) async {
    if (_busy || _session == null) return;
    // N3：多乘客模式下，pickup／dropoff 由 stops 推導（後端也是這樣做），
    // 故不需要定位——但仍沿用同一條建單路徑。
    final stops = buildStops(_passengers);
    if (_passengers.isNotEmpty && stops.isEmpty) {
      _error = '請至少填完一位乘客的上車與下車點';
      notifyListeners();
      return;
    }
    _setBusy(true);
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) {
        _error = '需要定位權限才能叫車';
        return;
      }
      final pos = await _acquirePosition();
      if (pos == null) {
        _error = '目前無法取得定位，請確認 GPS 已開啟後再試';
        return;
      }
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
        // N3：有 stops 時後端會用它推導 pickup／dropoff 並覆蓋上面幾個欄位；
        // 空 list ＝ 不帶這個鍵 ＝ 單點訂單的既有行為。
        stops: stops,
        // P2：null ＝不指定，client 端不會帶這個鍵。
        requiredVehicleType: _requiredVehicleType?.code,
      );
      _activeRide = ride;
      _lastActiveRide = ride;
      // 這趟已送出，編輯狀態不該留到下一趟。
      _passengers.clear();
      _driverName = null;
      _driverInfo = null;
      // 新的一趟開始 → 上一趟的取消原因不該還掛著。
      _cancelReason = null;
      _cancelledVehicleType = null;
      _rideCancelled = false;
      _liveEtaSec = null;
      _liveDistM = null;
      _liveDriverLat = null;
      _liveDriverLng = null;
      _driverArrived = false;
      _completedSummary = null;
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
      _liveDriverLat = null;
      _liveDriverLng = null;
      _driverArrived = false;
      _stopPolling();
      return;
    }
    _activeRide = ride;
    _lastActiveRide = ride;
    if (ride.status < RideStatus.accepted) {
      _driverName = null;
      _driverArrived = false;
    }
    if (ride.status != RideStatus.accepted) {
      _liveEtaSec = null;
      _liveDistM = null;
      _liveDriverLat = null;
      _liveDriverLng = null;
      _driverArrived = false;
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

  /// 取得目前位置：高精度定位在模擬器／室內可能長時間拿不到 fix，
  /// 故設 8 秒逾時；逾時後退回最後已知位置，避免叫車一直卡在載入轉圈。
  Future<Position?> _acquirePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
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
    _chatStream.close();
    _ws.disconnect();
    super.dispose();
  }
}
