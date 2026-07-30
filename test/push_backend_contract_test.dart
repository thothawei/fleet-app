import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/push_payload.dart';

/// 推播 data 的**跨端契約**：這裡的每一筆都是後端真的送出來的東西，不是手寫的假資料。
///
/// 來源：2026-07-30 在本機起 dispatch（`docker compose up -d postgis redis` ＋ `go run ./cmd/server`）
/// 跑 dispatch repo 的 `scripts/push_e2e.sh`，從後端 log 的「App 推播（stub）」逐則抄下來
/// （沒有 Firebase 憑證時後端走 LogPusher stub，data 與真 FCM 完全一樣）。
///
/// **為什麼要另外釘一支**：既有的推播測試（`chat_push_test`／`push_payload_test`）
/// 驗的是「App 收到某個 type 會做什麼」，payload 是我們自己寫的——
/// 後端哪天改了鍵名或收件人，那些測試照樣全綠。這支釘的是另一件事：
/// **後端實際送出的那組鍵值，App 解得開、而且分流到對的那一端**。
///
/// 值全部是字串——FCM data 的硬性限制（見 `pitfall-fcm-data-all-strings`：
/// 這正是「推播接單一啟用就崩」的那個坑）。
void main() {
  /// 司機端收到的派單邀請（唯一帶完整欄位的一則，因為它要直接開接單卡）。
  const offerData = <String, dynamic>{
    'address': '台北101',
    'dist_m': '105',
    'dropoff_address': '台北車站',
    'dropoff_lat': '25.0478',
    'dropoff_lng': '121.517',
    'eta_sec': '12',
    'pickup_lat': '25.0335',
    'pickup_lng': '121.5655',
    'ride_id': '19',
    'type': 'ride.assigned',
  };

  /// 其餘九則的 data 一律只有這兩鍵——推播只當「訊號」，內容由 App 自己以 REST 補齊。
  Map<String, dynamic> signal(String type) => {'ride_id': '19', 'type': type};

  group('後端實際送出的 data，App 解得開', () {
    test('派單邀請：字串值要轉回數值，接單卡才生得出來', () {
      final event = fleetEventFromPushData(offerData);
      expect(event, isNotNull);
      expect(event!.type, FleetEventTypes.rideAssigned);
      expect(event.rideId, 19);

      final offer = RideOffer.fromEvent(event.rideId!, event.payload);
      expect(offer.address, '台北101');
      expect(offer.distM, 105);
      expect(offer.etaSec, 12);
      expect(offer.pickupLat, closeTo(25.0335, 1e-9));
      expect(offer.pickupLng, closeTo(121.5655, 1e-9));
      expect(offer.dropoffAddress, '台北車站');
      expect(offer.dropoffLat, closeTo(25.0478, 1e-9));
      expect(offer.dropoffLng, closeTo(121.517, 1e-9));
      expect(offer.hasStops, isFalse,
          reason: '結構化陣列刻意不放進 data，多停靠點接單後由 rides/active 補齊');
    });

    test('其餘九則只有 type 與 ride_id，payload 是空的', () {
      for (final type in [
        FleetEventTypes.rideAccepted,
        FleetEventTypes.driverArrived,
        FleetEventTypes.rideCompleted,
        FleetEventTypes.chatMessage,
        FleetEventTypes.lostItemCreated,
        FleetEventTypes.lostItemUpdated,
      ]) {
        final event = fleetEventFromPushData(signal(type));
        expect(event?.type, type, reason: type);
        expect(event?.rideId, 19, reason: type);
        expect(event?.payload, isEmpty, reason: type);
      }
    });
  });

  group('後端送給誰，App 那一端就收得下來', () {
    // 左邊是後端 log 的 token_prefix（DRIVER-… / CUSTOMER-…），右邊是 App 的白名單。
    test('推給司機的三種，司機端收、乘客端不收', () {
      expect(isDriverPush(fleetEventFromPushData(offerData)!), isTrue);
      for (final type in [
        FleetEventTypes.chatMessage, // 「乘客傳來訊息」
        FleetEventTypes.lostItemCreated, // 「乘客回報遺失物」
        FleetEventTypes.lostItemUpdated, // 「乘客已支付處理費」
      ]) {
        expect(isDriverPush(fleetEventFromPushData(signal(type))!), isTrue,
            reason: type);
      }
      expect(isCustomerPush(fleetEventFromPushData(offerData)!), isFalse,
          reason: '派單邀請只推司機');
    });

    test('推給乘客的五種，乘客端收得下來', () {
      for (final type in [
        FleetEventTypes.rideAccepted, // 「司機已接單」
        FleetEventTypes.driverArrived, // 「司機已抵達」
        FleetEventTypes.rideCompleted, // 「行程已完成」
        FleetEventTypes.chatMessage, // 「司機傳來訊息」
        FleetEventTypes.lostItemUpdated, // 「司機找到你的遺失物了」／「遺失物已歸還」
      ]) {
        expect(isCustomerPush(fleetEventFromPushData(signal(type))!), isTrue,
            reason: type);
      }
    });

    test('行程狀態推播不會被誤判成派單邀請（分流寫錯會把接單卡開在乘客身上）', () {
      for (final type in [
        FleetEventTypes.rideAccepted,
        FleetEventTypes.driverArrived,
        FleetEventTypes.rideCompleted,
      ]) {
        expect(isRideOfferPush(fleetEventFromPushData(signal(type))), isFalse,
            reason: type);
        expect(isDriverPush(fleetEventFromPushData(signal(type))!), isFalse,
            reason: '$type 後端只推乘客，司機端收下只會多打兩支 API');
      }
    });
  });
}
