/// 車種（後端 O1 定義的 code）。
///
/// 後端 API／WS 一律只送 code，**顯示名由前端對應**——這份對照表就是那個對應。
/// （例外：LINE 推播文案由後端自產，後端另有一份中文名，見 dispatch 的 VehicleTypeDisplayName。）
enum VehicleType {
  sedan('sedan', '轎車'),
  suv('suv', '休旅車'),
  van7('van7', '七人座'),
  accessible('accessible', '無障礙車'),
  pet('pet', '寵物用車');

  const VehicleType(this.code, this.label);

  /// 送後端的值；不可改（DB CHECK 與派單過濾都吃它）。
  final String code;

  /// 給使用者看的中文名。
  final String label;

  /// 由後端 code 解析；未知 code（含空字串）回 null——
  /// 後端日後新增車種而 App 尚未更新時，寧可不顯示，也不要顯示原始 code 或崩潰。
  static VehicleType? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final v in VehicleType.values) {
      if (v.code == code) return v;
    }
    return null;
  }

  /// 顯示名；未知或未設定回 fallback。
  static String labelOf(String? code, {String fallback = '—'}) {
    return fromCode(code)?.label ?? fallback;
  }
}

/// 司機車輛資訊（O2：GET/PUT /api/driver/vehicle）。
class DriverVehicle {
  const DriverVehicle({
    required this.vehicleType,
    required this.plateNumber,
    required this.hasVehicle,
  });

  /// 車種 code；'' ＝未設定。
  final String vehicleType;

  /// 車牌；'' ＝未設定。後端已正規化（去空白、轉大寫）。
  final String plateNumber;

  /// 是否已填妥——**與後端 O3 gate 同一條件**，App 不自行判斷「兩欄皆非空」。
  final bool hasVehicle;

  VehicleType? get type => VehicleType.fromCode(vehicleType);

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      vehicleType: json['vehicle_type'] as String? ?? '',
      plateNumber: json['plate_number'] as String? ?? '',
      hasVehicle: json['has_vehicle'] as bool? ?? false,
    );
  }

  static const empty = DriverVehicle(vehicleType: '', plateNumber: '', hasVehicle: false);
}
