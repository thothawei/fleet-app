import '../config/app_config.dart';
// RideDriverInfo 用得到 VehicleType、ActiveRide 用得到 RideStop；
// export 只對外，本檔自己用仍需 import。
import 'ride_stop.dart';
import 'vehicle.dart';

// 車種與司機車輛（O1／O2）、取消原因（P4）。獨立成檔避免這份已經很長的 models.dart
// 再膨脹；以 export 讓既有 `import 'models.dart'` 的檔案不必改 import。
export 'cancel_reason.dart';
export 'ride_stop.dart';
export 'vehicle.dart';

class AuthSession {
  const AuthSession({
    required this.driverId,
    required this.token,
    this.name,
  });

  final int driverId;
  final String token;
  final String? name;
}

class LoginResult {
  const LoginResult({
    required this.driverId,
    required this.token,
    this.name,
  });

  final int driverId;
  final String token;
  final String? name;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      driverId: (json['driver_id'] as num).toInt(),
      token: json['token'] as String,
      name: json['name'] as String?,
    );
  }
}

class RideOffer {
  const RideOffer({
    required this.rideId,
    required this.address,
    this.etaSec,
    this.distM,
    this.pickupLat,
    this.pickupLng,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.stops = const [],
  });

  final int rideId;
  final String address;
  final int? etaSec;
  final int? distM;

  /// 多停靠點行程的全程（N4，ride.assigned 帶入）；空 ＝ 單點訂單。
  /// 接單前就看得到是多乘客行程；接單後帶進 ActiveRide 供清單與多點地圖。
  final List<RideStop> stops;

  bool get hasStops => stops.isNotEmpty;

  /// 上車點座標（ride.assigned 帶入）；接單後供司機端地圖標出上車點。
  final double? pickupLat;
  final double? pickupLng;

  /// 目的地（派單事件 ride.assigned 帶入，接單前可預覽）。
  final String? dropoffAddress;

  /// 目的地座標；後端訂單未指定 dropoff_point 時為 null。
  final double? dropoffLat;
  final double? dropoffLng;

  factory RideOffer.fromEvent(int rideId, Map<String, dynamic>? payload) {
    final dropoff = payload?['dropoff_address'] as String?;
    return RideOffer(
      rideId: rideId,
      address: payload?['address'] as String? ?? '未知地址',
      etaSec: (payload?['eta_sec'] as num?)?.toInt(),
      distM: (payload?['dist_m'] as num?)?.toInt(),
      pickupLat: (payload?['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (payload?['pickup_lng'] as num?)?.toDouble(),
      dropoffAddress:
          (dropoff != null && dropoff.isNotEmpty) ? dropoff : null,
      dropoffLat: (payload?['dropoff_lat'] as num?)?.toDouble(),
      dropoffLng: (payload?['dropoff_lng'] as num?)?.toDouble(),
      // 缺鍵回空 list（單點訂單／FCM data 不帶陣列時）。
      stops: RideStop.listFrom(payload?['stops']),
    );
  }

  String get etaLabel {
    if (etaSec == null) return '';
    final min = (etaSec! / 60).ceil();
    return '約 $min 分鐘';
  }
}

/// 乘客端登入會話。
class CustomerSession {
  const CustomerSession({
    required this.customerId,
    required this.token,
    this.name,
  });

  final int customerId;
  final String token;
  final String? name;
}

/// 乘客端登入/註冊回應（對齊後端 customer.go）。
class CustomerLoginResult {
  const CustomerLoginResult({
    required this.customerId,
    required this.token,
    this.name,
  });

  final int customerId;
  final String token;
  final String? name;

  factory CustomerLoginResult.fromJson(Map<String, dynamic> json) {
    return CustomerLoginResult(
      customerId: (json['customer_id'] as num).toInt(),
      token: json['token'] as String,
      name: json['name'] as String?,
    );
  }
}

/// 行程剛完成時的摘要（B5 評分／付款入口佔位用）。
class CompletedRideSummary {
  const CompletedRideSummary({
    required this.rideId,
    this.dropoffAddress,
    this.driverName,
    this.fareAmountCents,
    this.cleaningFeeCents,
  });

  final int rideId;
  final String? dropoffAddress;
  final String? driverName;

  /// 車資（分）；來自 ride.completed 事件的 fare_amount_cents（E2）。無則 null。
  final int? fareAmountCents;

  /// 寵物車清潔費（分，O6）；來自 ride.completed 的 cleaning_fee_cents。
  ///
  /// **只有乘客指定寵物車的行程才有**：後端未加收時**不帶這個鍵**（不是帶 0），
  /// 故 null ＝ 沒加收 → 完成卡不該出現清潔費欄位。
  final int? cleaningFeeCents;

  /// 是否有加收清潔費（供完成卡決定要不要拆分項）。
  bool get hasCleaningFee => (cleaningFeeCents ?? 0) > 0;

  /// 乘客實付總額（分）＝車資 ＋ 清潔費；無車資（舊後端）時為 null。
  int? get totalCents =>
      fareAmountCents == null ? null : fareAmountCents! + (cleaningFeeCents ?? 0);
}

/// 司機資訊（ride.accepted payload，O4／O7）。
///
/// 車種／車牌來自 ride 快照（司機換車後歷史不變），電話為 drivers 即時值
/// （換號碼後乘客要撥得通的是新號碼）——兩者來源不同，後端刻意沒統一。
class RideDriverInfo {
  const RideDriverInfo({
    this.name,
    this.vehicleType,
    this.plateNumber,
    this.phone,
  });

  final String? name;

  /// 車種 code（後端只送 code，顯示名由 VehicleType 對應）。
  final String? vehicleType;
  final String? plateNumber;

  /// 明碼電話（O7 拍板）；**僅該趟乘客可見**，不可用於任何列表。
  final String? phone;

  VehicleType? get type => VehicleType.fromCode(vehicleType);

  /// 是否有車輛資訊可顯示（路邊對車用）。
  bool get hasVehicle => (vehicleType?.isNotEmpty ?? false) && (plateNumber?.isNotEmpty ?? false);

  bool get hasPhone => phone?.isNotEmpty ?? false;

  /// 由 WS payload 解析。**空值不帶鍵**是後端的約定，故缺鍵＝沒有該資訊。
  factory RideDriverInfo.fromPayload(Map<String, dynamic> payload) {
    return RideDriverInfo(
      name: payload['driver_name'] as String?,
      vehicleType: payload['driver_vehicle_type'] as String?,
      plateNumber: payload['driver_plate_number'] as String?,
      phone: payload['driver_phone'] as String?,
    );
  }
}

/// 司機當月收入（對齊後端 GET /api/driver/earnings，F7）。金額欄位皆為「分」。
class DriverEarnings {
  const DriverEarnings({
    required this.month,
    required this.tripCount,
    required this.totalRevenueCents,
    required this.totalCommissionCents,
    this.totalCleaningFeeCents = 0,
    required this.driverNetCents,
    required this.membershipFeeCents,
    required this.owedToHqCents,
  });

  final String month;
  final int tripCount;

  /// 營業額＝車資合計，**不含清潔費**（O6）。
  final int totalRevenueCents;
  final int totalCommissionCents;

  /// 寵物車清潔費合計（O6）：不計入營業額與抽成，全額歸司機。
  /// driverNetCents 已含它，故等式為「營業額 − 手續費 + 清潔費 = 實得」。
  final int totalCleaningFeeCents;
  final int driverNetCents;
  final int membershipFeeCents;

  /// 應付總公司 = 手續費 + 月會費（後端算好帶回）；**不受清潔費影響**。
  final int owedToHqCents;

  factory DriverEarnings.fromJson(Map<String, dynamic> json) {
    return DriverEarnings(
      month: json['month'] as String? ?? '',
      tripCount: (json['trip_count'] as num?)?.toInt() ?? 0,
      totalRevenueCents: (json['total_revenue_cents'] as num?)?.toInt() ?? 0,
      totalCommissionCents: (json['total_commission_cents'] as num?)?.toInt() ?? 0,
      totalCleaningFeeCents: (json['total_cleaning_fee_cents'] as num?)?.toInt() ?? 0,
      driverNetCents: (json['driver_net_cents'] as num?)?.toInt() ?? 0,
      membershipFeeCents: (json['membership_fee_cents'] as num?)?.toInt() ?? 0,
      owedToHqCents: (json['owed_to_hq_cents'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 訂單狀態碼，對齊 line-fleet-dispatch/internal/constants/ride.go
abstract final class RideStatus {
  static const requested = 0;
  static const assigned = 1;
  static const accepted = 2;
  static const pickedUp = 3;
  static const completed = 4;
  static const cancelled = 9;

  static bool isActive(int status) =>
      status == requested ||
      status == assigned ||
      status == accepted ||
      status == pickedUp;

  static bool isTerminal(int status) =>
      status == completed || status == cancelled;
}

/// 乘客端當前訂單。狀態碼對齊後端 constants.RideStatus*。
/// 來源可能是下單回應（snake key: ride_id/status）或查詢 model.Ride
/// （無 json tag → PascalCase key: ID/Status），故解析時兩者皆容。
class CustomerRide {
  const CustomerRide({
    required this.rideId,
    required this.status,
    this.dropoffAddress,
    this.etaPickupSec,
    this.pickupLat,
    this.pickupLng,
  });

  final int rideId;
  final int status;
  final String? dropoffAddress;

  /// 接單時後端估算的到達上車點秒數（model.Ride.EtaPickupSec）。
  final int? etaPickupSec;

  /// 上車點座標（model.Ride.PickupPoint），供地圖追蹤顯示。
  final double? pickupLat;
  final double? pickupLng;

  /// 尚可由乘客取消（上車前）。
  bool get cancellable => status < RideStatus.pickedUp;

  /// 上車點 ETA 標籤，僅在司機前往上車點且有估算時有意義。
  String get etaLabel {
    if (etaPickupSec == null || etaPickupSec! <= 0) return '';
    return '約 ${(etaPickupSec! / 60).ceil()} 分鐘抵達';
  }

  String get statusLabel {
    switch (status) {
      case RideStatus.requested:
        return '尋找司機中';
      case RideStatus.assigned:
        return '派單中';
      case RideStatus.accepted:
        return '司機前往上車點';
      case RideStatus.pickedUp:
        return '行程中';
      case RideStatus.completed:
        return '已完成';
      case RideStatus.cancelled:
        return '已取消';
      default:
        return '狀態 $status';
    }
  }

  /// 乘客端分階段文案。`driverArrived` 來自 WS `driver.arrived`
  ///（後端狀態仍為 Accepted，不另存 DB flag）。
  String phaseLabel({bool driverArrived = false}) {
    if (status == RideStatus.accepted && driverArrived) {
      return '司機已抵達上車點';
    }
    return statusLabel;
  }

  factory CustomerRide.fromJson(Map<String, dynamic> json) {
    final id = json['ride_id'] ?? json['ID'] ?? json['id'];
    final status = json['status'] ?? json['Status'];
    final dropoff = json['dropoff_address'] ?? json['DropoffAddress'];
    final eta = json['eta_pickup_sec'] ?? json['EtaPickupSec'];
    double? pickupLat;
    double? pickupLng;
    final pickupPoint = json['pickup_point'] ?? json['PickupPoint'];
    if (pickupPoint is Map) {
      pickupLat = (pickupPoint['lat'] as num?)?.toDouble();
      pickupLng = (pickupPoint['lng'] as num?)?.toDouble();
    }
    return CustomerRide(
      rideId: (id as num).toInt(),
      status: (status as num).toInt(),
      dropoffAddress: (dropoff is String && dropoff.isNotEmpty) ? dropoff : null,
      etaPickupSec: (eta as num?)?.toInt(),
      pickupLat: pickupLat,
      pickupLng: pickupLng,
    );
  }
}

/// 行程內對話訊息（乘客↔司機）。來源：REST 歷史查詢或 WS `chat.message` payload，
/// 兩者欄位相同（後端 rideMessagePayload 與 model JSON 對齊）。
class RideMessage {
  const RideMessage({
    required this.id,
    required this.rideId,
    required this.senderRole,
    required this.senderId,
    required this.body,
    this.createdAt,
  });

  final int id;
  final int rideId;

  /// 'customer' 或 'driver'。
  final String senderRole;
  final int senderId;
  final String body;
  final DateTime? createdAt;

  factory RideMessage.fromJson(Map<String, dynamic> json) {
    return RideMessage(
      id: (json['id'] as num).toInt(),
      rideId: (json['ride_id'] as num).toInt(),
      senderRole: json['sender_role'] as String? ?? '',
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}

/// 遺失物協尋單狀態（對齊後端 constants/lost_item.go）。
abstract final class LostItemStatus {
  static const open = 'open'; // 待司機確認尋獲
  static const found = 'found'; // 已尋獲，待乘客支付處理費
  static const paid = 'paid'; // 已支付，待歸還
  static const returned = 'returned'; // 已歸還，結案
  static const closed = 'closed'; // 未尋獲／取消，結案

  static String label(String status) {
    switch (status) {
      case open:
        return '等待司機確認';
      case found:
        return '司機已尋獲，待支付處理費';
      case paid:
        return '已付款，等待歸還';
      case returned:
        return '已歸還';
      case closed:
        return '已結案';
      default:
        return status;
    }
  }

  static bool isActive(String status) =>
      status == open || status == found || status == paid;
}

/// 遺失物協尋單（對齊後端 model.LostItemRequest JSON / WS lost_item.* payload）。
/// 處理費 feeCents 為建立當下「車資 × 處理費%」的快照，後台調整%不影響既有單。
class LostItemRequest {
  const LostItemRequest({
    required this.id,
    required this.rideId,
    required this.customerId,
    required this.driverId,
    required this.description,
    required this.feeCents,
    required this.status,
    this.paidAt,
  });

  final int id;
  final int rideId;
  final int customerId;
  final int driverId;
  final String description;

  /// 處理費（分）。
  final int feeCents;
  final String status;
  final DateTime? paidAt;

  bool get isActive => LostItemStatus.isActive(status);
  String get statusLabel => LostItemStatus.label(status);

  factory LostItemRequest.fromJson(Map<String, dynamic> json) {
    return LostItemRequest(
      id: (json['id'] as num).toInt(),
      rideId: (json['ride_id'] as num).toInt(),
      customerId: (json['customer_id'] as num?)?.toInt() ?? 0,
      driverId: (json['driver_id'] as num?)?.toInt() ?? 0,
      description: json['description'] as String? ?? '',
      feeCents: (json['fee_cents'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? LostItemStatus.open,
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
    );
  }
}

/// `POST /api/driver/rides/:id/pickup` 回傳的目的地資訊。
/// 後端未指定目的地時 address 為 null、座標為 null。
class DropoffInfo {
  const DropoffInfo({this.address, this.lat, this.lng});

  final String? address;
  final double? lat;
  final double? lng;

  factory DropoffInfo.fromJson(Map<String, dynamic>? json) {
    final address = json?['dropoff_address'] as String?;
    return DropoffInfo(
      address: (address != null && address.isNotEmpty) ? address : null,
      lat: (json?['dropoff_lat'] as num?)?.toDouble(),
      lng: (json?['dropoff_lng'] as num?)?.toDouble(),
    );
  }
}

class ActiveRide {
  const ActiveRide({
    required this.rideId,
    required this.address,
    required this.phase,
    this.pickupLat,
    this.pickupLng,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.stops = const [],
  });

  final int rideId;
  final String address;
  final DriverRidePhase phase;

  /// 多乘客／多停靠點行程的全程（N4／N6）；**空 ＝ 傳統單點訂單**。
  /// 依 seq 排序，司機據此知道「下一站是誰、在哪、處理了沒」。
  final List<RideStop> stops;

  /// 是否為多停靠點行程。
  bool get hasStops => stops.isNotEmpty;

  /// 下一個待處理的停靠點（未到達也未跳過）；全部處理完回 null。
  RideStop? get nextStop {
    for (final s in stops) {
      if (s.pending) return s;
    }
    return null;
  }

  /// 上車點座標；供司機端地圖標出上車點（address 字串無法定位）。
  /// 來源：ride.assigned 事件的 pickup_lat/lng，或 rides/active 的 pickup_point。
  final double? pickupLat;
  final double? pickupLng;

  /// 目的地地址，供司機端 onTrip 階段「導航去目的地」。
  /// 後端未指定目的地時為 null；來源為接單事件或 pickup 回應。
  final String? dropoffAddress;

  /// 目的地座標；導航優先用它，地址僅供顯示與退路。
  final double? dropoffLat;
  final double? dropoffLng;

  /// 有地址或座標任一即可導航。
  bool get hasDropoff =>
      (dropoffAddress != null && dropoffAddress!.isNotEmpty) ||
      (dropoffLat != null && dropoffLng != null);

  ActiveRide copyWith({
    DriverRidePhase? phase,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
  }) {
    return ActiveRide(
      rideId: rideId,
      address: address,
      phase: phase ?? this.phase,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      // 漏了這行，「乘客已上車」（copyWith 換 phase）後 stops 掉回空 list，
      // 多停靠點的全程清單與多點地圖在行程中直接消失（模擬器實跑抓到）。
      stops: stops,
    );
  }

  /// 從 GET /api/driver/rides/active 回傳的 model.Ride JSON 還原司機端行程。
  factory ActiveRide.fromBackendJson(Map<String, dynamic> json) {
    final status = (json['status'] as num).toInt();
    final dropoff = json['dropoff_address'] as String?;
    final pickupPoint = json['pickup_point'] as Map<String, dynamic>?;
    final dropoffPoint = json['dropoff_point'] as Map<String, dynamic>?;
    return ActiveRide(
      rideId: (json['id'] as num).toInt(),
      address: json['pickup_address'] as String? ?? '未知地址',
      phase: status == RideStatus.pickedUp
          ? DriverRidePhase.onTrip
          : DriverRidePhase.enRouteToPickup,
      pickupLat: (pickupPoint?['lat'] as num?)?.toDouble(),
      pickupLng: (pickupPoint?['lng'] as num?)?.toDouble(),
      dropoffAddress:
          (dropoff != null && dropoff.isNotEmpty) ? dropoff : null,
      dropoffLat: (dropoffPoint?['lat'] as num?)?.toDouble(),
      dropoffLng: (dropoffPoint?['lng'] as num?)?.toDouble(),
      // N6：DriverRideView 攤平 ride 欄位並多帶 stops；
      // 單點訂單沒有這個鍵（後端 omitempty）→ 空 list ＝ 既有行為。
      stops: RideStop.listFrom(json['stops']),
    );
  }
}
