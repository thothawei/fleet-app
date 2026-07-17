import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/models/models.dart';

void main() {
  group('CancelReason（P4：用機器可讀欄位，不 parse 文案）', () {
    test('code 解析', () {
      expect(CancelReason.fromCode('no_vehicle_of_type'), CancelReason.noVehicleOfType);
      expect(CancelReason.fromCode('no_driver_available'), CancelReason.noDriverAvailable);
    });

    test('缺席或未知 code 回 null（不崩潰）', () {
      // 後端只有「逾時取消」帶 cancel_reason；乘客主動取消／司機放棄不帶。
      expect(CancelReason.fromCode(null), isNull);
      expect(CancelReason.fromCode(''), isNull);
      // 後端日後新增原因而 App 未更新 → 走泛用文案。
      expect(CancelReason.fromCode('future_reason'), isNull);
    });

    test('指定車種找不到 → 訊息要說是車種問題，並帶車種名', () {
      final msg = cancelMessage(CancelReason.noVehicleOfType, 'pet');
      expect(msg, contains('寵物用車'));
      // 泛用訊息會讓乘客一直重試；正確引導是改用不指定車種。
      expect(msg, contains('不指定車種'));
      expect(shouldSuggestAnyVehicle(CancelReason.noVehicleOfType), isTrue);
    });

    test('未知車種 code 時訊息仍讀得通', () {
      expect(cancelMessage(CancelReason.noVehicleOfType, 'spaceship'), contains('該車種'));
    });

    test('泛用取消不編故事', () {
      expect(cancelMessage(CancelReason.noDriverAvailable, null), contains('暫無可用司機'));
      expect(shouldSuggestAnyVehicle(CancelReason.noDriverAvailable), isFalse);
      // 乘客主動取消／司機放棄 → 只說事實。
      expect(cancelMessage(null, null), '行程已取消。');
      expect(shouldSuggestAnyVehicle(null), isFalse);
    });
  });

  group('CompletedRideSummary 清潔費分項（O6）', () {
    test('有加收 → 分項與合計', () {
      const s = CompletedRideSummary(
        rideId: 1,
        fareAmountCents: 21500,
        cleaningFeeCents: 4300,
      );
      expect(s.hasCleaningFee, isTrue);
      expect(s.totalCents, 25800); // 車資 + 清潔費
    });

    test('未加收時後端不帶該鍵 → null，完成卡不顯示清潔費', () {
      // 後端「未加收就不帶鍵」（不是帶 0），所以 null 是正常情況。
      const s = CompletedRideSummary(rideId: 1, fareAmountCents: 21500);
      expect(s.hasCleaningFee, isFalse);
      expect(s.totalCents, 21500);
    });

    test('無車資（舊後端）→ 合計為 null', () {
      const s = CompletedRideSummary(rideId: 1);
      expect(s.totalCents, isNull);
      expect(s.hasCleaningFee, isFalse);
    });
  });

  group('RideDriverInfo（O4／O7）', () {
    test('由 ride.accepted payload 解析', () {
      final d = RideDriverInfo.fromPayload({
        'driver_name': '王司機',
        'driver_vehicle_type': 'pet',
        'driver_plate_number': 'PET-0001',
        'driver_phone': '0912345678',
      });
      expect(d.name, '王司機');
      expect(d.type, VehicleType.pet);
      expect(d.hasVehicle, isTrue);
      expect(d.hasPhone, isTrue);
    });

    test('後端空值不帶鍵 → 缺鍵即沒有該資訊', () {
      // 後端約定：空值不帶鍵，寧可少一個鍵也不要讓 App 顯示空白車牌。
      final d = RideDriverInfo.fromPayload({'driver_name': '王司機'});
      expect(d.hasVehicle, isFalse);
      expect(d.hasPhone, isFalse);
      expect(d.type, isNull);
    });
  });
}
