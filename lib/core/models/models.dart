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
  });

  final int rideId;
  final String address;
  final int? etaSec;
  final int? distM;

  factory RideOffer.fromEvent(int rideId, Map<String, dynamic>? payload) {
    return RideOffer(
      rideId: rideId,
      address: payload?['address'] as String? ?? '未知地址',
      etaSec: (payload?['eta_sec'] as num?)?.toInt(),
      distM: (payload?['dist_m'] as num?)?.toInt(),
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

/// 乘客端當前訂單。狀態碼對齊後端 constants.RideStatus*。
/// 來源可能是下單回應（snake key: ride_id/status）或查詢 model.Ride
/// （無 json tag → PascalCase key: ID/Status），故解析時兩者皆容。
class CustomerRide {
  const CustomerRide({
    required this.rideId,
    required this.status,
    this.dropoffAddress,
    this.etaPickupSec,
  });

  final int rideId;
  final int status;
  final String? dropoffAddress;

  /// 接單時後端估算的到達上車點秒數（model.Ride.EtaPickupSec）。
  final int? etaPickupSec;

  /// 尚可由乘客取消（上車前）。
  bool get cancellable => status < 3;

  /// 上車點 ETA 標籤，僅在司機前往上車點且有估算時有意義。
  String get etaLabel {
    if (etaPickupSec == null || etaPickupSec! <= 0) return '';
    return '約 ${(etaPickupSec! / 60).ceil()} 分鐘抵達';
  }

  String get statusLabel {
    switch (status) {
      case 0:
        return '尋找司機中';
      case 1:
        return '派單中';
      case 2:
        return '司機前往上車點';
      case 3:
        return '行程中';
      case 4:
        return '已完成';
      case 5:
        return '已取消';
      default:
        return '狀態 $status';
    }
  }

  factory CustomerRide.fromJson(Map<String, dynamic> json) {
    final id = json['ride_id'] ?? json['ID'] ?? json['id'];
    final status = json['status'] ?? json['Status'];
    final dropoff = json['dropoff_address'] ?? json['DropoffAddress'];
    final eta = json['eta_pickup_sec'] ?? json['EtaPickupSec'];
    return CustomerRide(
      rideId: (id as num).toInt(),
      status: (status as num).toInt(),
      dropoffAddress: (dropoff is String && dropoff.isNotEmpty) ? dropoff : null,
      etaPickupSec: (eta as num?)?.toInt(),
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
}
