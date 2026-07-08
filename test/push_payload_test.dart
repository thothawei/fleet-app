import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/push/push_payload.dart';

void main() {
  test('fleetEventFromPushData 解析派單 payload', () {
    final event = fleetEventFromPushData({
      'type': FleetEventTypes.rideAssigned,
      'ride_id': '42',
      'address': '台北車站',
      'dropoff_address': '松山機場',
      'eta_sec': '300',
      'dist_m': '1200',
    });
    expect(event, isNotNull);
    expect(event!.rideId, 42);
    expect(event.payload?['address'], '台北車站');
    expect(event.payload?['dropoff_address'], '松山機場');
    expect(isRideOfferPush(event), isTrue);
  });

  test('缺少 type 回 null', () {
    expect(fleetEventFromPushData({'ride_id': '1'}), isNull);
  });
}
