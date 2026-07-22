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

/// 車輛審核狀態（O5）。對齊後端 constants.VehicleReview*。
enum VehicleReviewStatus {
  none(''), // 未提交（沒填車輛）
  pending('pending'), // 待審核
  approved('approved'), // 已核准（可接單）
  rejected('rejected'); // 已退回（附原因，可重填）

  const VehicleReviewStatus(this.code);
  final String code;

  static VehicleReviewStatus fromCode(String? code) {
    for (final s in VehicleReviewStatus.values) {
      if (s.code == code) return s;
    }
    return VehicleReviewStatus.none; // 後端日後新增狀態而 App 未更新 → 當作未提交，走設定頁
  }
}

/// 司機車輛資訊（O2／O5：GET/PUT /api/driver/vehicle）。
class DriverVehicle {
  const DriverVehicle({
    required this.vehicleType,
    required this.plateNumber,
    required this.hasVehicle,
    this.phone = '',
    this.reviewStatus = VehicleReviewStatus.none,
    this.reviewNote = '',
    this.canAccept = false,
  });

  /// 車種 code；'' ＝未設定。
  final String vehicleType;

  /// 車牌；'' ＝未設定。後端已正規化（去空白、轉大寫）。
  final String plateNumber;

  /// 是否已填妥（O2）。App 用它決定是否顯示強制設定頁；不代表能接單（見 canAccept）。
  final bool hasVehicle;

  /// 聯絡電話（O7）；'' ＝未填。乘客在「司機前往上車點」階段會直接撥打它，
  /// 沒填的話乘客端整顆撥號按鈕都不會出現。**唯讀**——寫入走 PUT /driver/profile。
  final String phone;

  /// 審核狀態（O5）：App 四態路由用（pending 審核中／rejected 已退回）。
  final VehicleReviewStatus reviewStatus;

  /// 退回原因（O5）：rejected 時給司機看。
  final String reviewNote;

  /// 能不能接單（O5 gate ＝已核准）。**以後端回的 can_accept 為準**，App 不自行推導。
  final bool canAccept;

  VehicleType? get type => VehicleType.fromCode(vehicleType);

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      vehicleType: json['vehicle_type'] as String? ?? '',
      plateNumber: json['plate_number'] as String? ?? '',
      hasVehicle: json['has_vehicle'] as bool? ?? false,
      phone: json['phone'] as String? ?? '',
      reviewStatus: VehicleReviewStatus.fromCode(json['review_status'] as String?),
      reviewNote: json['review_note'] as String? ?? '',
      // 舊後端沒有 can_accept 時退回 has_vehicle（維持 O3 語意，不誤鎖）。
      canAccept: json['can_accept'] as bool? ?? (json['has_vehicle'] as bool? ?? false),
    );
  }

  /// 只換掉電話（存電話成功後同步本地狀態，其餘欄位維持後端最後一次回傳值）。
  DriverVehicle withPhone(String newPhone) => DriverVehicle(
        vehicleType: vehicleType,
        plateNumber: plateNumber,
        hasVehicle: hasVehicle,
        phone: newPhone,
        reviewStatus: reviewStatus,
        reviewNote: reviewNote,
        canAccept: canAccept,
      );

  static const empty = DriverVehicle(vehicleType: '', plateNumber: '', hasVehicle: false);
}
