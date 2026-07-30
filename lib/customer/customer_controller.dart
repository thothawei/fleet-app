import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/api_error.dart' show sessionExpiredMessage;
import '../core/api/customer_api_client.dart';
import '../core/api/fleet_api_client.dart' show ApiException;
import '../core/config/app_config.dart';
import '../core/location/customer_locator.dart';
import '../core/models/models.dart';
import '../core/push/fleet_push_service.dart';
import '../core/push/push_payload.dart';
import '../core/storage/customer_token_storage.dart';
import '../core/ws/fleet_ws_client.dart';

/// 乘客端狀態：登入、定位、叫車（帶目的地）、WS 即時狀態、取消。
class CustomerController extends ChangeNotifier {
  CustomerController({
    CustomerTokenStorage? storage,
    CustomerApiClient? api,
    FleetWsClientFactory? wsFactory,
    FleetPushService? push,
    CustomerLocator? locator,
  })  : _storage = storage ?? CustomerTokenStorage(),
        _api = api ?? CustomerApiClient(),
        _wsFactory = wsFactory ?? FleetWsClient.new,
        _push = push ?? NoOpFleetPushService(),
        _locator = locator ?? const GeolocatorCustomerLocator(),
        _ws = FleetWsClient(onEvent: (_) {}) {
    // token 過期／失效時把乘客送回登入頁（見 _handleUnauthorized）。
    _api.onUnauthorized = _handleUnauthorized;
  }

  final CustomerTokenStorage _storage;
  final CustomerApiClient _api;
  final FleetWsClientFactory _wsFactory;
  final FleetPushService _push;
  final CustomerLocator _locator;
  FleetWsClient _ws;

  /// 已向後端註冊的推播 token；登出時要拿它去註銷。
  String? _fcmToken;
  StreamSubscription<FleetWsEvent>? _pushSub;
  StreamSubscription<String>? _tokenRefreshSub;

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
  // 司機放棄後「正在重新派車」的說明；與取消通知分開——**行程還在**，
  // 混用取消通知會讓乘客以為要重新叫車。
  String? _redispatchNotice;
  // 乘客指定的車種（P2）；null ＝不指定，維持現行行為。
  VehicleType? _requiredVehicleType;
  // 寵物車清潔費率（P5）；null ＝尚未查到（費率不常變，快取一次即可）。
  int? _petCleaningFeeBps;
  // 多乘客行程的編輯狀態（N3）；空 ＝ 單點訂單。
  final List<PassengerTrip> _passengers = [];
  // 建單前的車資預估（懸而未決 #1）；null ＝尚無預估（未選目的地／預估失敗）。
  FareEstimate? _estimate;
  bool _estimating = false;
  // 單點模式下地圖選點得到的目的地座標——存在 controller 才能在車種變更時重算預估
  // （地址欄的座標在 widget，但價格會受車種影響，預估的權威輸入放這裡才同步得了）。
  double? _estDropoffLat;
  double? _estDropoffLng;
  int? _liveEtaSec;
  int? _liveDistM;
  double? _liveDriverLat;
  double? _liveDriverLng;
  bool _driverArrived = false;
  CompletedRideSummary? _completedSummary;
  Timer? _pollTimer;

  // 評分（B5）：剛送出的星等連同它屬於哪一趟一起記。
  // **綁 rideId 而不是只存分數**——`_completedSummary` 有六處會被重設（登出、再叫一輛、
  // 新訂單、下一次 ride.completed…），只存分數就得在每一處記得清掉它，
  // 漏一處就會讓下一趟的完成卡一出現就顯示上一趟的星星。
  int? _completedRatingScore;
  int? _completedRatingRideId;
  bool _ratingSubmitting = false;

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
  // session 失效清理中；並發的 401（輪詢＋使用者操作同時）不重入清理。
  bool _sessionExpiring = false;

  CustomerSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get busy => _busy;
  bool get wsConnected => _wsConnected;
  Position? get lastPosition => _lastPosition;
  FareEstimate? get fareEstimate => _estimate;
  bool get estimating => _estimating;
  CustomerRide? get activeRide => _activeRide;

  /// 司機姓名。優先來自 ride.accepted WS 事件，錯過事件時由 GET active 還原
  ///（後端兩條路徑都帶司機資訊，鍵名相同）。
  String? get driverName => _driverName;

  /// 司機車輛與聯絡方式（O4／O7），來自 ride.accepted 或 GET active 還原。
  /// 未接單時為 null。車種／車牌供路邊對車；電話為明碼，**僅該趟乘客可見**。
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

  /// 司機放棄後的「正在重新派車」說明；null ＝ 沒有要顯示的。
  /// 與 [cancelNotice] 互斥使用：這個代表**行程還在**，只是換司機。
  String? get redispatchNotice => _redispatchNotice;

  /// 有新司機接單／新叫車／行程結束時清掉。
  void dismissRedispatchNotice() {
    if (_redispatchNotice == null) return;
    _redispatchNotice = null;
    notifyListeners();
  }

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
    _refreshEstimate();
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
    _refreshEstimate();
  }

  /// 設定某位乘客的上車／下車點。
  void setPassengerPoint(int index, {StopPoint? pickup, StopPoint? dropoff}) {
    if (index < 0 || index >= _passengers.length) return;
    if (pickup != null) _passengers[index].pickup = pickup;
    if (dropoff != null) _passengers[index].dropoff = dropoff;
    notifyListeners();
    _refreshEstimate();
  }

  static String _labelFor(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// 選擇車種（P2）。選寵物用車時順帶把費率查回來，讓 UI 當場顯示加價。
  Future<void> setRequiredVehicleType(VehicleType? type) async {
    _requiredVehicleType = type;
    notifyListeners();
    // 車種影響價格（寵物車加清潔費）→ 重算預估，讓金額與選擇同步。
    _refreshEstimate();
    if (type == VehicleType.pet && _petCleaningFeeBps == null) {
      await refreshPetCleaningFee();
    }
  }

  /// 記住地圖選點的目的地座標並算一次預估（懸而未決 #1，單點模式）。
  void setEstimateDropoff(double lat, double lng) {
    _estDropoffLat = lat;
    _estDropoffLng = lng;
    _refreshEstimate();
  }

  /// 清掉目的地座標與預估（手動改地址、或收合表單時）。
  void clearEstimate() {
    _estDropoffLat = null;
    _estDropoffLng = null;
    if (_estimate != null || _estimating) {
      _estimate = null;
      _estimating = false;
      notifyListeners();
    }
  }

  /// 依目前輸入（單點座標或多停靠點 stops ＋ 指定車種）重算車資預估。
  ///
  /// **失敗一律靜默清空**——預估只是輔助資訊，不可擋叫車、不彈錯誤（與 P5 查費率同一原則）。
  /// 單點模式需要目的地座標與上車 GPS；多停靠點模式由 stops 推導，不需 GPS。
  Future<void> _refreshEstimate() async {
    if (_session == null) return;
    final stops = buildStops(_passengers);
    final hasStops = stops.isNotEmpty;
    if (!hasStops && (_estDropoffLat == null || _estDropoffLng == null)) {
      // 沒有可預估的輸入（未選地圖目的地，也非多停靠點）→ 清空。
      if (_estimate != null || _estimating) {
        _estimate = null;
        _estimating = false;
        notifyListeners();
      }
      return;
    }
    _estimating = true;
    notifyListeners();
    try {
      var pickupLat = 0.0;
      var pickupLng = 0.0;
      if (!hasStops) {
        // 單點模式需要上車座標；優先用已取得的定位，否則現取（8 秒逾時，見 _acquirePosition）。
        final pos = _lastPosition ?? await _acquirePosition();
        if (pos == null) {
          _estimate = null;
          _estimating = false;
          notifyListeners();
          return;
        }
        _lastPosition = pos;
        pickupLat = pos.latitude;
        pickupLng = pos.longitude;
      }
      final est = await _api.estimateFare(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: hasStops ? null : _estDropoffLat,
        dropoffLng: hasStops ? null : _estDropoffLng,
        requiredVehicleType: _requiredVehicleType?.code,
        stops: stops,
      );
      _estimate = est;
    } catch (_) {
      // 任何失敗（網路、權限、路線）都不顯示預估，也不擋叫車。
      _estimate = null;
    } finally {
      _estimating = false;
      notifyListeners();
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

  /// 剛完成的行程摘要（完成卡：車資分項＋評分入口）；點「再叫一輛」後清除。
  CompletedRideSummary? get completedSummary => _completedSummary;

  /// 完成卡上剛送出的評分星等（B5）；null ＝這趟還沒評。
  /// 只在星等確實屬於**目前這張完成卡**時才回傳，換一趟就自動失效。
  int? get completedRatingScore =>
      _completedRatingRideId != null &&
              _completedRatingRideId == _completedSummary?.rideId
          ? _completedRatingScore
          : null;

  /// 評分送出中（按鈕轉圈、防連點）。
  bool get ratingSubmitting => _ratingSubmitting;

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

  /// 對已完成行程評分司機（B5）。成功回 null，失敗回可直接顯示的中文訊息。
  ///
  /// **不寫進 `_error`**：評分是使用者當下在對話框裡做的動作，錯誤要留在對話框上，
  /// 讓他知道分數沒送出去；丟到全域 error 會變成關掉對話框才看到的 SnackBar。
  ///
  /// 成功時就地更新歷史清單那一列（`copyWith`），評分入口立刻變成星等——
  /// 不重打一次 `GET /customer/rides`，避免對話框關閉時整份清單閃一下。
  Future<String?> submitRating(
    int rideId, {
    required int score,
    String comment = '',
  }) async {
    if (_session == null) return '請先登入';
    if (_ratingSubmitting) return null; // 防連點：同一次送出進行中就忽略
    _ratingSubmitting = true;
    notifyListeners();
    try {
      final rating = await _api.rateRide(rideId, score: score, comment: comment);
      _applySubmittedRating(rideId, rating.score);
      return null;
    } on ApiException catch (e) {
      // 逾時（`statusCode == null`）不代表後端沒記到；**409 更是明說「這趟已經評過」**。
      // 一趟一評有唯一索引，所以再送一次只會再拿到 409——不對帳的話乘客只剩
      // 「評分失敗」這條死路，而他其實已經評過了。查一次後端這趟的星等：
      // 有 → 當成成功（畫面直接顯示星等）；沒有 → 維持原本的錯誤訊息讓他重評。
      if (e.statusCode == null || e.statusCode == 409) {
        final existing = await _ratingScoreForReconcile(rideId);
        if (existing != null) {
          _applySubmittedRating(rideId, existing);
          return null;
        }
      }
      return e.message;
    } finally {
      _ratingSubmitting = false;
      notifyListeners();
    }
  }

  /// 評分成功後的狀態切換（真的送出成功與「其實早就評過了」共用）。
  ///
  /// 就地更新歷史清單那一列（`copyWith`），評分入口立刻變成星等——
  /// 不重打一次 `GET /customer/rides`，避免對話框關閉時整份清單閃一下。
  void _applySubmittedRating(int rideId, int score) {
    _completedRatingScore = score;
    _completedRatingRideId = rideId;
    _rideHistory = [
      for (final r in _rideHistory)
        r.rideId == rideId ? r.copyWith(ratingScore: score) : r,
    ];
  }

  /// 對帳用查詢：這一問本身失敗就回 null（不知道就不亂改，維持原本的錯誤）。
  Future<int?> _ratingScoreForReconcile(int rideId) async {
    try {
      return await _api.fetchRideRatingScore(rideId);
    } on ApiException {
      return null;
    }
  }

  // ---------- 常用地點（住家／公司／自訂）----------

  List<SavedPlace> _savedPlaces = const [];
  bool _placesLoading = false;
  String? _placesError;

  /// 我的常用地點；後端已排好序（住家 → 公司 → 其他）。
  List<SavedPlace> get savedPlaces => List.unmodifiable(_savedPlaces);
  bool get placesLoading => _placesLoading;
  String? get placesError => _placesError;

  /// 住家／公司這兩個插槽；沒設過就是 null（UI 據此顯示「設定住家」而不是空白）。
  SavedPlace? get homePlace => _placeOfKind(SavedPlaceKind.home);
  SavedPlace? get workPlace => _placeOfKind(SavedPlaceKind.work);

  SavedPlace? _placeOfKind(String kind) {
    for (final p in _savedPlaces) {
      if (p.kind == kind) return p;
    }
    return null;
  }

  /// 載入常用地點。
  ///
  /// [silent] 供背景刷新用：叫車頁那排快捷鈕是輔助功能，載不出來就不顯示即可，
  /// 不該讓乘客因為它失敗而看到錯誤橫幅、以為叫不了車。
  Future<void> loadSavedPlaces({bool silent = false}) async {
    if (_session == null) return;
    if (!silent) {
      _placesLoading = true;
      _placesError = null;
      notifyListeners();
    }
    try {
      _savedPlaces = await _api.fetchSavedPlaces();
      _placesError = null;
    } on ApiException catch (e) {
      if (!silent) _placesError = e.message;
    } finally {
      _placesLoading = false;
      notifyListeners();
    }
  }

  /// 新增／設定常用地點；成功回 null，失敗回訊息給表單顯示。
  ///
  /// kind 為 home／work 時後端是覆蓋語意，所以「設定住家」可以直接送。
  Future<String?> savePlace({
    required String kind,
    required String label,
    required String address,
    required double lat,
    required double lng,
  }) async {
    if (_session == null) return '請先登入';
    try {
      final saved = await _api.createSavedPlace(
        kind: kind,
        label: label,
        address: address,
        lat: lat,
        lng: lng,
      );
      _mergeSavedPlace(saved);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// 更新既有地點（kind 不變）。
  Future<String?> updateSavedPlace(
    int id, {
    required String label,
    required String address,
    required double lat,
    required double lng,
  }) async {
    if (_session == null) return '請先登入';
    try {
      final saved = await _api.updateSavedPlace(
        id,
        label: label,
        address: address,
        lat: lat,
        lng: lng,
      );
      _mergeSavedPlace(saved);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// 刪除常用地點。
  Future<String?> deleteSavedPlace(int id) async {
    if (_session == null) return '請先登入';
    try {
      await _api.deleteSavedPlace(id);
      _savedPlaces = [
        for (final p in _savedPlaces)
          if (p.id != id) p,
      ];
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// 把一筆新鮮的地點合併進清單（同 id 覆蓋，否則插入）。
  ///
  /// **插槽類要另外比對 kind**：住家從無到有時後端給的是新 id，但語意上是取代
  /// 原本那個空插槽；只比 id 的話清單會同時出現兩筆 kind=home。
  void _mergeSavedPlace(SavedPlace saved) {
    final next = <SavedPlace>[];
    var replaced = false;
    for (final p in _savedPlaces) {
      final sameRow = p.id == saved.id;
      final sameSlot = saved.isSlot && p.kind == saved.kind;
      if (sameRow || sameSlot) {
        if (!replaced) {
          next.add(saved);
          replaced = true;
        }
        continue;
      }
      next.add(p);
    }
    if (!replaced) next.add(saved);
    // 維持後端的排序約定：住家 → 公司 → 其他。
    next.sort((a, b) => _placeRank(a).compareTo(_placeRank(b)));
    _savedPlaces = next;
  }

  static int _placeRank(SavedPlace p) {
    if (p.isHome) return 0;
    if (p.isWork) return 1;
    return 2;
  }

  // ---------- 預約行程 ----------

  List<ScheduledRide> _scheduledRides = const [];
  bool _schedulesLoading = false;
  String? _schedulesError;
  int _scheduleLeadMinutes = 0;
  int _scheduleMinLeadMinutes = 0;

  /// 我的預約（近的在前）。
  List<ScheduledRide> get scheduledRides => List.unmodifiable(_scheduledRides);
  bool get schedulesLoading => _schedulesLoading;
  String? get schedulesError => _schedulesError;

  /// 後端會提前這麼多分鐘開始派單；0 ＝還沒問過後端。
  /// **不要在 UI 寫死這個數字**——後端改了 App 就會說謊。
  int get scheduleLeadMinutes => _scheduleLeadMinutes;

  /// 建立預約時距現在至少要有的分鐘數；還沒問過後端時退回保底值。
  ///
  /// 退路是「App 自己的保底值」而不是 0：0 會讓時間選擇器完全不擋，
  /// 乘客選了 3 分鐘後，填完整張表才被後端以 400 拒絕。
  int get scheduleMinLeadMinutes =>
      _scheduleMinLeadMinutes > 0 ? _scheduleMinLeadMinutes : fallbackMinLeadMinutes;

  /// 問不到後端時用的保底門檻（與後端當前的 ScheduledRideMinLeadMinutes 一致）。
  static const fallbackMinLeadMinutes = 20;

  /// 還沒轉單的預約，供首頁那張「即將到來」的卡。
  List<ScheduledRide> get upcomingSchedules =>
      List.unmodifiable(_scheduledRides.where((s) => s.isUpcoming));

  /// 載入預約清單。[silent] 同 [loadSavedPlaces]。
  Future<void> loadScheduledRides({bool silent = false}) async {
    if (_session == null) return;
    if (!silent) {
      _schedulesLoading = true;
      _schedulesError = null;
      notifyListeners();
    }
    try {
      final res = await _api.fetchScheduledRides();
      _scheduledRides = res.rides;
      if (res.leadMinutes > 0) _scheduleLeadMinutes = res.leadMinutes;
      if (res.minLeadMinutes > 0) _scheduleMinLeadMinutes = res.minLeadMinutes;
      _schedulesError = null;
    } on ApiException catch (e) {
      if (!silent) _schedulesError = e.message;
    } finally {
      _schedulesLoading = false;
      notifyListeners();
    }
  }

  /// 建立預約；成功回 null，失敗回訊息。
  Future<String?> createScheduledRide({
    required DateTime scheduledAt,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    String note = '',
  }) async {
    if (_session == null) return '請先登入';
    try {
      final created = await _api.createScheduledRide(
        scheduledAt: scheduledAt,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        requiredVehicleType: requiredVehicleType,
        note: note,
      );
      _mergeScheduledRide(created);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// 取消預約；成功回 null，失敗回訊息。
  ///
  /// **撞上「已被轉成真訂單」時不算失敗的一種**：後端會把該筆預約的現況一起回來，
  /// 這裡直接把它併進清單，畫面立刻變成「已為你派車」。若只丟一句「取消失敗，請稍後再試」，
  /// 乘客會一直按取消，而那張訂單照樣派出去、司機照樣開過來
  /// （同一個病在第二十輪的 admin 端抓過一次）。
  Future<String?> cancelScheduledRide(int id) async {
    if (_session == null) return '請先登入';
    try {
      final cancelled = await _api.cancelScheduledRide(id);
      _mergeScheduledRide(cancelled);
      notifyListeners();
      return null;
    } on ScheduledRideConflict catch (e) {
      _mergeScheduledRide(e.current);
      notifyListeners();
      return '這筆預約已經為你派車了，要取消請到行程頁取消該趟訂單。';
    } on ApiException catch (e) {
      // 逾時／連線類失敗：不宣稱取消成功，但重讀一次對帳——
      // 後端可能其實已經取消了，只是回應在路上掉了。
      await loadScheduledRides(silent: true);
      for (final s in _scheduledRides) {
        if (s.id == id && !s.isPending) return null;
      }
      return e.message;
    }
  }

  void _mergeScheduledRide(ScheduledRide row) {
    final next = <ScheduledRide>[];
    var replaced = false;
    for (final s in _scheduledRides) {
      if (s.id == row.id) {
        next.add(row);
        replaced = true;
        continue;
      }
      next.add(s);
    }
    if (!replaced) next.add(row);
    next.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    _scheduledRides = next;
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
      // 常用地點與預約都走 silent：它們是輔助功能，載不出來就先不顯示，
      // 不該讓叫車主流程因為它們失敗而冒錯誤橫幅。
      await loadSavedPlaces(silent: true);
      await loadScheduledRides(silent: true);
    }
    await _bindPushListener();
  }

  /// 訂閱推播：事件本身只當**對帳訊號**，token 輪替則重新註冊。
  Future<void> _bindPushListener() async {
    await _pushSub?.cancel();
    _pushSub = _push.rideEvents.listen((event) {
      // 對話訊息不必重讀行程與協尋：它只影響未讀角標，多打兩支 API 是浪費。
      if (isChatPush(event)) {
        _onChatPush();
        return;
      }
      if (isLostItemPush(event)) {
        // 協尋單的狀態變了，但行程沒有——只重讀協尋清單就夠。
        unawaited(refreshLostItems());
        return;
      }
      unawaited(_handlePushEvent());
    });
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub =
        _push.tokenRefresh.listen((_) => unawaited(_syncDeviceToken()));
  }

  /// 收到推播（前景或點通知喚醒）→ **跟後端對一次帳**。
  ///
  /// **刻意不把 payload 套進畫面**：FCM data 的值一律是字串、欄位又稀疏
  /// （見 pitfall-fcm-data-all-strings），直接餵進 `_handleWsEvent` 會把
  /// 司機姓名／車牌／ETA 洗成空的——推播喚醒的畫面反而比不開還糟。
  /// REST 是權威且一定完整，推播只需要告訴我們「有事發生了，去問一次」。
  ///
  /// **靜默**：乘客可能只是點了通知，沒按 App 裡的任何東西，失敗不該冒錯誤橫幅。
  Future<void> _handlePushEvent() async {
    if (_session == null) return;
    await refreshActive(silent: true);
    await refreshLostItems();
  }

  /// 收到「司機傳來訊息」的推播：只把未讀角標點亮，內容等聊天室自己以 REST 補齊。
  ///
  /// 聊天室開著時忽略：那代表 App 在前景、WS 也連著，同一則訊息已經由 WS 送到並顯示，
  /// 這裡再加一次會把角標加在乘客正在看的訊息上。
  void _onChatPush() {
    if (_chatVisible) return;
    _unreadChat++;
    notifyListeners();
  }

  /// 登入後向後端註冊推播 token；token 輪替時亦會重註冊。
  ///
  /// **靜默降級**：這是登入與輪替時的背景動作，乘客沒按任何東西。註冊失敗只代表
  /// 「推播喚醒」這條退路暫時不可用，WS 與輪詢照常運作——為此在首頁掛一條紅色橫幅
  /// 只會讓乘客以為叫不到車（同司機端 `_syncDeviceToken` 的規則）。
  Future<void> _syncDeviceToken() async {
    if (!_push.isAvailable || _session == null) return;
    try {
      final token = await _push.getToken();
      if (token == null || token.isEmpty) return;
      await _api.registerDeviceToken(platform: 'fcm', token: token);
      _fcmToken = token;
    } on ApiException {
      // 下一次輪替或重新登入會自動再試。
    }
  }

  /// App 從背景回到前景（由 `AppLifecycleReactor` 呼叫）。
  ///
  /// 背景期間 WS 可能已被系統關掉，15 秒的輪詢 timer 在 iOS 也是凍結的——
  /// 回前景後最壞情況要再等一輪才對得上帳，這段時間畫面顯示的是背景前的舊狀態
  /// （司機早就接單了卻還寫「配對中」）。所以立刻重連 WS ＋ 主動對帳一次。
  ///
  /// **靜默**：使用者只是把 App 切回來，沒按任何東西；失敗不該冒出錯誤
  /// （同背景輪詢的規則，見 `refreshActive` 的 silent 說明）。
  Future<void> onAppResumed() async {
    if (_session == null) return;
    _ws.ensureConnected();
    await refreshActive(silent: true);
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
    await _syncDeviceToken();
    notifyListeners();
  }

  /// token 過期／失效（401）：**本地登出**並讓乘客知道要重新登入。
  ///
  /// 沒有這條路，過期後乘客會停在叫車首頁，每按一次「叫車」只得到一句
  /// 「token 無效或已過期」——他既不知道那是什麼，也沒有畫面可以重新登入
  /// （地圖版首頁只有一顆不起眼的登出鈕）。JWT 預設 72 小時，長期使用者必然遇到。
  void _handleUnauthorized() {
    if (_session == null || _sessionExpiring) return;
    _sessionExpiring = true;
    unawaited(() async {
      try {
        // **不打 `unregisterDeviceToken`**：token 已經失效，那支 API 只會再回一次 401
        // （並再觸發一次這裡）。所以走 `_clearSession()` 而不是 `logout()`。
        await _clearSession();
        _error = sessionExpiredMessage;
      } finally {
        _sessionExpiring = false;
      }
      notifyListeners();
    }());
  }

  Future<void> logout() async {
    // 註銷推播 token：不註銷的話，下一個在這台裝置登入的人會收到上一位乘客的行程通知。
    // 失敗只吞掉——登出不能因為網路而卡住。
    final token = _fcmToken;
    if (token != null) {
      try {
        await _api.unregisterDeviceToken(token: token);
      } catch (_) {}
    }
    await _clearSession();
  }

  /// 清掉本機 session 與所有跟著它的狀態（登出與 session 失效共用）。
  Future<void> _clearSession() async {
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
    _redispatchNotice = null;
    _requiredVehicleType = null;
    _passengers.clear();
    _estimate = null;
    _estimating = false;
    _estDropoffLat = null;
    _estDropoffLng = null;
    _liveEtaSec = null;
    _liveDistM = null;
    _liveDriverLat = null;
    _liveDriverLng = null;
    _driverArrived = false;
    _completedSummary = null;
    _unreadChat = 0;
    _chatVisible = false;
    _lostItems = [];
    // 歷史行程是**上一個帳號的個人資料**：不清的話，換人登入後一進「我的行程」
    // 就會在自己的資料載入前先看到前一位乘客的行程與車資。
    _rideHistory = [];
    _historyError = null;
    // 常用地點與預約同一個道理，而且更敏感——住家與公司是**實體位置**，
    // 預約則是「這個人什麼時候會不在家」。不清的話，下一位在這台裝置登入的人
    // 一打開叫車頁，快捷列上就是上一位乘客的住家地址。
    _savedPlaces = const [];
    _placesError = null;
    _scheduledRides = const [];
    _schedulesError = null;
    _scheduleLeadMinutes = 0;
    _scheduleMinLeadMinutes = 0;
    _completedRatingScore = null;
    _completedRatingRideId = null;
    _fcmToken = null;
    _api.setToken(null);
    notifyListeners();
  }

  /// 錯誤已呈現給使用者後清掉，讓**下一次同樣的失敗仍會再提示一次**
  /// （畫面層以「和上次一樣就不重複顯示」去重，不清就會把第二次吃掉）。
  void clearError() {
    if (_error == null) return;
    _error = null;
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
      // WS 事件觸發，不是使用者按的 → 失敗靜默，交給輪詢補
      refreshActive(silent: true);
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
        // 新司機接單＝「重新派車中」已經結束，通知留著會與畫面上的司機卡片矛盾。
        _redispatchNotice = null;
        refreshActive(silent: true);
      // 司機放棄，行程回到派單中——**不是取消**，訂單還在，只是重新找司機。
      // 這裡必須把上一位司機的所有痕跡清乾淨：車牌／撥號按鈕若留著，
      // 乘客會打給一個已經不來的司機；ETA 與地圖上的車也是舊的。
      case FleetEventTypes.rideRedispatched:
        _driverName = null;
        _driverInfo = null;
        _driverArrived = false;
        _liveEtaSec = null;
        _liveDistM = null;
        _liveDriverLat = null;
        _liveDriverLng = null;
        _redispatchNotice = '司機取消了行程，正在為您重新派車';
        notifyListeners();
        refreshActive(silent: true);
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
        refreshActive(silent: true);
      case FleetEventTypes.rideCancelled:
        // P4：以機器可讀的 cancel_reason 判斷，不 parse 後端文案（文案會改）。
        // 只有逾時取消會帶這兩個鍵；乘客主動取消／司機放棄不帶 → 解析為 null，
        // UI 走泛用訊息。
        _cancelReason = CancelReason.fromCode(event.payload?['cancel_reason'] as String?);
        _cancelledVehicleType = event.payload?['required_vehicle_type'] as String?;
        _rideCancelled = true;
        // 行程真的結束了，「正在重新派車」不能再留著（重派沒成功才會走到這裡）。
        _redispatchNotice = null;
        refreshActive(silent: true);
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
  ///
  /// 逾時對帳的判準是「這趟出現了一張未結案的單」——進這個畫面時已經確認過沒有
  /// （`_load` 查到 null 才顯示回報表單），所以查到 active 單就是這次建的。
  Future<LostItemRequest> reportLostItem(int rideId, String description) =>
      _writeLostItem(
        () => _api.createLostItem(rideId, description),
        rideId: rideId,
        applied: (fresh) => fresh.isActive,
      );

  /// 支付處理費（司機尋獲後）。
  ///
  /// **這是三條裡最不能沉默的一條**：逾時後乘客不知道自己付了沒有，
  /// 而處理費是有金額後果的狀態。判準是後端記到了 `paid_at`。
  Future<LostItemRequest> payLostItem(int itemId, {required int rideId}) =>
      _writeLostItem(
        () => _api.payLostItem(itemId),
        rideId: rideId,
        applied: (fresh) => fresh.id == itemId && fresh.paidAt != null,
      );

  /// 取消協尋（open/found）。判準是這張單已經不在未結案狀態。
  Future<LostItemRequest> closeLostItem(int itemId, {required int rideId}) =>
      _writeLostItem(
        () => _api.closeLostItem(itemId),
        rideId: rideId,
        applied: (fresh) =>
            fresh.id == itemId && fresh.status == LostItemStatus.closed,
      );

  /// 協尋單的寫入 ＋ 逾時對帳（三條寫入路徑共用）。
  ///
  /// 失敗且是**連線類**（`statusCode == null`）或 **409**（後端在說「這張單當下不能這樣做」，
  /// 多半就是上一次逾時其實生效了）時，向後端問一次這趟的最新協尋單：
  /// [applied] 判定那個動作其實已經生效 → 套用後端現況、當成成功回傳；
  /// 否則把原本的例外丟回畫面（`lost_item_screen` 的 `_run` 會顯示它）。
  ///
  /// 不對帳的話，一次其實成功的付款會被報成「請求逾時，請稍後再試」，
  /// 乘客再按一次只會撞 409——與建單／取消同一個病（見 docs/TODO.md 第十五、十六輪）。
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
      // 這裡重擲的必須是**原本那個動作的例外**，不能是對帳查詢的失敗——
      // 對帳的 try/catch 收在 `_lostItemForReconcile` 裡（失敗回 null），
      // 所以這個 rethrow 擲的仍然是 e。**別把那個 catch 搬進來**。
      if (fresh == null || !applied(fresh)) rethrow;
      _applyLostItem(fresh);
      notifyListeners();
      return fresh;
    }
  }

  /// 對帳用查詢：這一問本身失敗就回 null（不知道就不亂改，維持原本的錯誤）。
  Future<LostItemRequest?> _lostItemForReconcile(int rideId) async {
    try {
      return await _api.fetchLostItemByRide(rideId);
    } on ApiException {
      return null;
    }
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

  Future<RideMessage> sendMessage(int rideId, String body,
          {String? clientMsgId}) =>
      _api.sendMessage(rideId, body, clientMsgId: clientMsgId);

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
      final double pickupLat;
      final double pickupLng;
      final String pickup;
      if (stops.isNotEmpty) {
        // N3：多停靠點行程的上車點就是第一個 pickup（後端 prepareStops 也是這樣推導，
        // 並且會忽略下面這幾個欄位）——**這條路徑不需要裝置定位**。
        // 原本卻照樣先要權限再等 GPS fix，於是定位服務關著、或室內拿不到 fix 時，
        // 連根本不看座標的多停靠點行程都叫不了車。
        // `buildStops` 保證 pickup 全排在 dropoff 之前，故 first 就是第一個上車點。
        final firstPickup = stops.first;
        pickupLat = firstPickup.lat;
        pickupLng = firstPickup.lng;
        pickup = firstPickup.address.isNotEmpty
            ? firstPickup.address
            : pickupAddress.trim();
      } else {
        final pos = await _resolvePickupPosition();
        if (pos == null) return; // 失敗原因已寫進 _error
        _lastPosition = pos;
        pickupLat = pos.latitude;
        pickupLng = pos.longitude;
        pickup = pickupAddress.trim().isNotEmpty
            ? pickupAddress.trim()
            : '目前位置 (${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)})';
      }
      final ride = await _api.createRide(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
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
      _applyCreatedRide(ride);
    } on ApiException catch (e) {
      await _handleCreateFailure(e);
    } finally {
      _setBusy(false);
    }
  }

  /// 建單失敗的處理（`placeOrder` 的 catch 全部走這裡）。
  ///
  /// 弱網：逾時／連線失敗**不代表後端沒建單**——請求可能已經送達、訂單已經成立，
  /// 只是回應沒回來。什麼都不做的話乘客會停在叫車畫面（沒有進行中訂單就不會輪詢），
  /// 車已經在派了他卻看不到；再按一次則會拿到「已有進行中的訂單」這條死路。
  /// 所以先問後端：我現在到底有沒有訂單。
  ///
  /// **只有連線類（`statusCode == null`）才對帳**：後端明確拒絕（車種不合、限流…）
  /// 時它本來就沒建單，再問一次只是白跑。
  ///
  /// 直接可測：正式入口 `placeOrder` 一定會先經過 geolocator 的 platform channel，
  /// 單元測試環境沒有它（既有測試也只驗得到 placeOrder 送出前那一段）。
  @visibleForTesting
  Future<void> handleCreateFailure(ApiException e) => _handleCreateFailure(e);

  Future<void> _handleCreateFailure(ApiException e) async {
    _error = e.message;
    // **409 也要對帳**：那句話是後端在明說「你已經有一張進行中的訂單」，
    // 而畫面上一張都沒有——多半就是上一次逾時其實建成了（或訂單來自 LINE／另一台裝置）。
    // 只把這句話原樣丟給乘客，他無事可做：再按一次還是 409，唯一出路是重開 App。
    if (e.statusCode == null || e.statusCode == 409) {
      await _adoptRideIfCreated();
    }
  }

  /// 建單失敗後向後端確認訂單到底有沒有成立。
  ///
  /// 有 → 套用它（畫面直接進入追蹤）並清掉那句錯誤（他其實叫到車了）。
  /// 沒有 → 什麼都不動，錯誤訊息留著讓他重試。
  /// 查詢本身也失敗 → 同樣什麼都不動（不知道就不亂改）。
  Future<void> _adoptRideIfCreated() async {
    try {
      final ride = await _api.activeRide();
      if (ride == null || RideStatus.isTerminal(ride.status)) return;
      // 這趟其實成立了 → 走**與建單成功同一套**狀態切換。
      // 只做 `_applyActiveRide` 是不夠的：編輯中的多乘客清單、預估車資、
      // 上一趟的取消通知都會留著，下一次叫車就帶著別趟的殘骸。
      _applyCreatedRide(ride);
      // 這段空窗可能已經被司機接走了：把司機姓名／車牌／電話補回來，
      // 不必等下一個輪詢週期才顯示。
      _applyActiveRide(ride);
      _error = null;
    } on ApiException {
      // 弱網下這一問也可能逾時；維持原本的錯誤訊息。
    }
  }

  /// 一趟新訂單成立後的狀態切換（建單成功與「其實已經建好了」共用）。
  ///
  /// 兩條路徑必須共用同一份清單：漏掉其中一項，就會把上一趟的司機、取消通知或
  /// 完成卡帶進這一趟。
  void _applyCreatedRide(CustomerRide ride) {
    _activeRide = ride;
    _lastActiveRide = ride;
    // 這趟已送出，編輯狀態不該留到下一趟。
    _passengers.clear();
    // 預估屬於「建單前」的輔助資訊，送出後就該收掉，不留到下一趟。
    _estimate = null;
    _estimating = false;
    _estDropoffLat = null;
    _estDropoffLng = null;
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
  }

  /// [silent] ＝ 這次刷新不是使用者按出來的（背景輪詢），失敗時**不寫全域 error**。
  /// 15 秒一次的輪詢若把失敗丟給畫面層，後端一斷線就變成每 15 秒彈一次 SnackBar
  /// 蓋住 sheet 上的按鈕，而使用者沒有任何辦法讓它停——他根本沒按過什麼。
  /// 使用者自己觸發的刷新（下拉、登入還原）維持照舊回報。
  Future<void> refreshActive({bool silent = false}) async {
    if (_session == null) return;
    try {
      final ride = await _api.activeRide();
      _applyActiveRide(ride);
      notifyListeners();
    } on ApiException catch (e) {
      if (silent) return;
      _error = e.message;
      notifyListeners();
    }
  }

  /// 套用 GET active 結果，清除終態/非接客階段的 stale 即時欄位。
  void _applyActiveRide(CustomerRide? ride) {
    if (ride == null || RideStatus.isTerminal(ride.status)) {
      _activeRide = null;
      _driverName = null;
      _driverInfo = null;
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
      _driverInfo = null;
      _driverArrived = false;
    } else if (ride.driver != null) {
      // O7：ride.accepted 是即時來源，但**只送一次**——app 在背景被接單、
      // WS 重連或重開 app 都收不到它。後端 GET active 一直都帶司機姓名／
      // 車牌／電話，這裡補上還原，否則撥號按鈕永遠不出現。
      // 已有 WS 值時不覆蓋（那是最即時的）。
      _driverName ??= ride.driver!.name;
      _driverInfo ??= ride.driver;
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
      // 逾時／連線失敗（statusCode == null）**不代表後端沒取消**——請求可能已經送達、
      // 訂單已經取消，只是回應沒回來。不對帳的話乘客得到的唯一回饋是
      // 「請求逾時，請稍後再試」，而他其實已經取消成功了
      // （2026-07-30 模擬器實跑：blackhole cancel ＋ ws_block 下，
      // 訂單卡被輪詢收掉、螢幕上卻只留這句謊，乘客無從判斷到底取消了沒有）。
      //
      // **409 也要對帳**：那是後端在說「這張單當下不能取消」，
      // 多半就是上一次逾時其實已經生效了（與建單的 `_handleCreateFailure` 同一個道理）。
      if (e.statusCode == null || e.statusCode == 409) {
        await _reconcileAfterCancel(ride.rideId);
      }
    } finally {
      _setBusy(false);
    }
  }

  /// 取消失敗後向後端確認這張單到底還在不在。
  ///
  /// 已經不在（沒有進行中訂單／已是終態）→ 取消其實成功了：套用後端現況、
  /// 補上與 WS `ride.cancelled` 同一條「行程已取消」通知，並清掉那句錯誤。
  /// **WS 斷線時沒有那個事件，這條通知就是乘客唯一的確認**。
  /// 還在 → 什麼都不動，錯誤留著讓他重試。
  /// 這一問本身也失敗 → 同樣什麼都不動（不知道就不亂改）。
  Future<void> _reconcileAfterCancel(int rideId) async {
    try {
      final fresh = await _api.activeRide();
      if (fresh != null && fresh.rideId != rideId) {
        // 已經換成另一張進行中訂單（來自 LINE／另一台裝置）：套用它，
        // 但不掛取消通知——那會讓乘客以為眼前這張單也被取消了。
        _applyActiveRide(fresh);
        _error = null;
        return;
      }
      if (fresh != null && !RideStatus.isTerminal(fresh.status)) return;
      _applyActiveRide(fresh);
      _rideCancelled = true;
      _error = null;
    } on ApiException {
      // 弱網下這一問也可能逾時；維持原本的錯誤訊息。
    }
  }

  /// 取得目前位置：高精度定位在模擬器／室內可能長時間拿不到 fix，
  /// 故設 8 秒逾時；逾時後退回最後已知位置，避免叫車一直卡在載入轉圈。
  ///
  /// **只攔逾時**：定位服務被關、權限被撤都要往上丟，由 `_resolvePickupPosition`
  /// 翻成乘客看得懂的下一步（原本沒人攔，整個例外穿出 `placeOrder`，
  /// 畫面一句話都沒有）。
  Future<Position?> _acquirePosition() async {
    try {
      return await _locator.getCurrentPosition(
        const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } on TimeoutException {
      return _locator.getLastKnownPosition();
    }
  }

  /// 單點模式的上車座標。回傳 null ＝ 已設好 `_error`，呼叫端放棄這次建單。
  ///
  /// **三種失敗要分開講**（比照司機端第二十一輪）：乘客的下一步完全不同——
  /// 去系統設定給權限／把定位服務打開／換個位置再試。含糊的「定位失敗」等於沒說。
  Future<Position?> _resolvePickupPosition() async {
    final perm = await _ensureLocationPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      // deniedForever 之後 `requestPermission` 不會再彈任何視窗——
      // 只說「需要定位權限」的話，乘客會一直重按叫車，App 裡永遠按不出結果。
      _error = perm == LocationPermission.deniedForever
          ? '定位權限已被永久拒絕，請到系統設定開啟才能叫車'
          : '需要定位權限才能叫車';
      return null;
    }
    try {
      final pos = await _acquirePosition();
      if (pos == null) {
        _error = '目前無法取得定位，請確認 GPS 已開啟後再試';
      }
      return pos;
    } on LocationServiceDisabledException {
      // 權限給了、系統定位服務關著（Android 快捷設定一鍵就關掉）。
      _error = '裝置定位服務已關閉，請開啟後再叫車';
      return null;
    } on PermissionDeniedException {
      // 檢查通過到取座標之間權限被撤（例如在通知欄操作）。
      _error = '定位權限已被關閉，請到系統設定開啟才能叫車';
      return null;
    }
  }

  /// 回傳**目前的權限狀態**而不是 bool：deniedForever 與 denied 的出路不一樣。
  Future<LocationPermission> _ensureLocationPermission() async {
    var perm = await _locator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await _locator.requestPermission();
    }
    return perm;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refreshActive(silent: true));
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
    _pushSub?.cancel();
    _tokenRefreshSub?.cancel();
    _chatStream.close();
    _ws.disconnect();
    super.dispose();
  }
}
