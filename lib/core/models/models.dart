import '../config/app_config.dart';

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
    this.dropoffAddress,
  });

  final int rideId;
  final String address;
  final int? etaSec;
  final int? distM;

  /// 目的地（派單事件 ride.assigned 帶入，接單前可預覽）。
  final String? dropoffAddress;

  factory RideOffer.fromEvent(int rideId, Map<String, dynamic>? payload) {
    final dropoff = payload?['dropoff_address'] as String?;
    return RideOffer(
      rideId: rideId,
      address: payload?['address'] as String? ?? '未知地址',
      etaSec: (payload?['eta_sec'] as num?)?.toInt(),
      distM: (payload?['dist_m'] as num?)?.toInt(),
      dropoffAddress:
          (dropoff != null && dropoff.isNotEmpty) ? dropoff : null,
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
/// 後端 Phase C 就緒後可擴充金額、帳單 id 等欄位。
class CompletedRideSummary {
  const CompletedRideSummary({
    required this.rideId,
    this.dropoffAddress,
    this.driverName,
  });

  final int rideId;
  final String? dropoffAddress;
  final String? driverName;
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

class ActiveRide {
  const ActiveRide({
    required this.rideId,
    required this.address,
    required this.phase,
    this.dropoffAddress,
  });

  final int rideId;
  final String address;
  final DriverRidePhase phase;

  /// 目的地地址，供司機端 onTrip 階段「導航去目的地」。
  /// 後端未指定目的地時為 null；來源為接單事件或 pickup 回應。
  final String? dropoffAddress;

  ActiveRide copyWith({DriverRidePhase? phase, String? dropoffAddress}) {
    return ActiveRide(
      rideId: rideId,
      address: address,
      phase: phase ?? this.phase,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
    );
  }

  /// 從 GET /api/driver/rides/active 回傳的 model.Ride JSON 還原司機端行程。
  factory ActiveRide.fromBackendJson(Map<String, dynamic> json) {
    final status = (json['status'] as num).toInt();
    final dropoff = json['dropoff_address'] as String?;
    return ActiveRide(
      rideId: (json['id'] as num).toInt(),
      address: json['pickup_address'] as String? ?? '未知地址',
      phase: status == RideStatus.pickedUp
          ? DriverRidePhase.onTrip
          : DriverRidePhase.enRouteToPickup,
      dropoffAddress:
          (dropoff != null && dropoff.isNotEmpty) ? dropoff : null,
    );
  }
}
