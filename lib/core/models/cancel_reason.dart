import 'vehicle.dart';

/// 行程取消原因（P4）。來自 `ride.cancelled` payload 的 `cancel_reason`。
///
/// **用這個機器可讀欄位判斷，不要 parse 後端的中文文案**——文案會改，字串比對會無聲失效。
///
/// **後端只有「逾時無人接單」這條路徑會帶 cancel_reason**；乘客主動取消、司機放棄
/// 等路徑不帶，故解析結果為 null 是正常情況，UI 要能容忍缺席。
enum CancelReason {
  /// 逾時無人接單（未指定車種，或指定了但就是沒人接）。
  noDriverAvailable('no_driver_available'),

  /// 乘客指定了車種，但附近沒有該車種的司機。**後端不會降級改派一般車**。
  noVehicleOfType('no_vehicle_of_type');

  const CancelReason(this.code);

  final String code;

  static CancelReason? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final r in CancelReason.values) {
      if (r.code == code) return r;
    }
    return null; // 後端日後新增原因而 App 未更新 → 走泛用文案，不崩潰
  }
}

/// 取消訊息（P4）：依機器可讀的原因產生，指定車種時帶出車種名。
///
/// requiredVehicleType 為 `ride.cancelled` payload 的 `required_vehicle_type`（車種 code）。
String cancelMessage(CancelReason? reason, String? requiredVehicleType) {
  switch (reason) {
    case CancelReason.noVehicleOfType:
      final name = VehicleType.labelOf(requiredVehicleType, fallback: '該車種');
      return '附近暫無$name，請稍後再試或改用不指定車種重新叫車。';
    case CancelReason.noDriverAvailable:
      return '抱歉，附近暫無可用司機，請稍後再試。';
    case null:
      // 乘客主動取消／司機放棄／未知原因——不編故事，只說事實。
      return '行程已取消。';
  }
}

/// 是否該引導「改用不指定車種重新叫車」（P4 建議的快捷操作）。
bool shouldSuggestAnyVehicle(CancelReason? reason) =>
    reason == CancelReason.noVehicleOfType;
