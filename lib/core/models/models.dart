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

class ActiveRide {
  const ActiveRide({
    required this.rideId,
    required this.address,
    required this.phase,
  });

  final int rideId;
  final String address;
  final DriverRidePhase phase;

  ActiveRide copyWith({DriverRidePhase? phase}) {
    return ActiveRide(
      rideId: rideId,
      address: address,
      phase: phase ?? this.phase,
    );
  }
}
