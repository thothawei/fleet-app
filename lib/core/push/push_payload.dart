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
  for (final key in [
    'eta_sec',
    'dist_m',
    'pickup_lat',
    'pickup_lng',
    'dropoff_lat',
    'dropoff_lng',
  ]) {
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

/// 是否為派單相關推播（喚醒後應顯示接單卡）。**司機端**用。
bool isRideOfferPush(FleetWsEvent? event) =>
    event?.type == FleetEventTypes.rideAssigned && event?.rideId != null;

/// **乘客端**關心的推播：這趟車的狀態變了。
///
/// 不含 `driver.location`——司機每 8 秒回報一次，拿它當推播只會把電池與額度燒光，
/// 而且乘客 App 沒在前景時本來就看不到地圖上的移動。
const _customerPushTypes = {
  FleetEventTypes.rideAccepted,
  FleetEventTypes.driverArrived,
  FleetEventTypes.rideCompleted,
  FleetEventTypes.rideCancelled,
  FleetEventTypes.rideRedispatched,
};

bool isCustomerRidePush(FleetWsEvent? event) =>
    event != null && _customerPushTypes.contains(event.type);
