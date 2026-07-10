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
  for (final key in ['address', 'dropoff_address']) {
    if (data.containsKey(key)) payload[key] = data[key];
  }
  // FCM data 的值一律是字串，數值欄位要先轉型；否則下游 `as num?` 會丟 TypeError。
  for (final key in ['eta_sec', 'dist_m', 'dropoff_lat', 'dropoff_lng']) {
    final num? value = _asNum(data[key]);
    if (value != null) payload[key] = value;
  }

  return FleetWsEvent(type: type, rideId: rideId, payload: payload);
}

num? _asNum(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  return num.tryParse(raw.toString());
}

/// 是否為派單相關推播（喚醒後應顯示接單卡）。
bool isRideOfferPush(FleetWsEvent? event) =>
    event?.type == FleetEventTypes.rideAssigned && event?.rideId != null;
