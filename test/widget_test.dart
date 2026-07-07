import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/models/models.dart';

void main() {
  test('RideOffer 從 WS payload 解析', () {
    final offer = RideOffer.fromEvent(42, {
      'address': '台北車站',
      'eta_sec': 300,
      'dist_m': 1200,
    });
    expect(offer.rideId, 42);
    expect(offer.address, '台北車站');
    expect(offer.etaLabel, '約 5 分鐘');
  });
}
