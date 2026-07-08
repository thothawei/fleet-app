import '../config/app_config.dart';
import '../ws/fleet_ws_client.dart';

/// 推播事件轉成與 WebSocket 相同的 FleetWsEvent，司機端可共用處理邏輯。
FleetWsEvent? fleetEventFromPushData(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  if (type == null || type.isEmpty) return null;

  final rideRaw = data['ride_id'];
  final rideId = rideRaw == null
      ? null
      : (rideRaw is num ? rideRaw.toInt() : int.tryParse(rideRaw.toString()));

  final payload = <String, dynamic>{};
  for (final key in [
    'address',
    'dropoff_address',
    'eta_sec',
    'dist_m',
  ]) {
    if (data.containsKey(key)) payload[key] = data[key];
  }

  return FleetWsEvent(type: type, rideId: rideId, payload: payload);
}

/// 是否為派單相關推播（喚醒後應顯示接單卡）。
bool isRideOfferPush(FleetWsEvent? event) =>
    event?.type == FleetEventTypes.rideAssigned && event?.rideId != null;
