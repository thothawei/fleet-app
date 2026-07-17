/// 停靠點種類（後端 N1 的 kind）。
enum StopKind {
  pickup('pickup', '上車'),
  dropoff('dropoff', '下車');

  const StopKind(this.code, this.label);

  final String code;
  final String label;

  static StopKind? fromCode(String? code) {
    if (code == null) return null;
    for (final k in StopKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// 多乘客／多停靠點行程的單一停靠點（N1）。
///
/// **ride_stops 為空 ＝ 傳統單點訂單**——後端保證 `rides.pickup_point`／`dropoff_point`
/// 照樣有值，所以單點行程的既有畫面完全不受影響。
class RideStop {
  const RideStop({
    required this.id,
    required this.seq,
    required this.kind,
    required this.lat,
    required this.lng,
    this.address,
    this.passengerLabel = '',
    this.arrivedAt,
    this.skippedAt,
  });

  final int id;

  /// 停靠順序，1 起算；同一趟內唯一。
  final int seq;
  final StopKind? kind;
  final double lat;
  final double lng;
  final String? address;

  /// 給司機辨識用（A/B/C…）。
  final String passengerLabel;

  /// 到達／跳過時間（N7）。**後端只在真的發生時才帶這兩個鍵**，
  /// 兩者皆 null ＝ 待處理。
  final DateTime? arrivedAt;
  final DateTime? skippedAt;

  bool get arrived => arrivedAt != null;

  /// 乘客沒出現、司機標記跳過 → 這一段不計入車資（後端 N5 排除已跳過的站）。
  bool get skipped => skippedAt != null;

  /// 待處理（可標記到達或跳過）。
  bool get pending => !arrived && !skipped;

  /// 「A 上車」「B 下車」。
  String get title {
    final who = passengerLabel.isEmpty ? '乘客' : '乘客 $passengerLabel';
    return '$who${kind?.label ?? ''}';
  }

  static DateTime? _parseTime(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  /// 由 WS payload／API 回應解析。
  ///
  /// 座標一律取 num 再轉 double——FCM data 值全是字串（見 pitfall-fcm-data-all-strings），
  /// 但 WS 是真 JSON，兩邊都吃得下才不會在推播路徑上炸。
  factory RideStop.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    int toInt(Object? v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return RideStop(
      id: toInt(json['id']),
      seq: toInt(json['seq']),
      kind: StopKind.fromCode(json['kind'] as String?),
      lat: toDouble(json['lat']),
      lng: toDouble(json['lng']),
      address: json['address'] as String?,
      passengerLabel: json['passenger_label'] as String? ?? '',
      arrivedAt: _parseTime(json['arrived_at']),
      skippedAt: _parseTime(json['skipped_at']),
    );
  }

  /// 由 payload 的 stops 陣列解析；缺鍵或空陣列回空 list（＝單點訂單）。
  static List<RideStop> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RideStop.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
  }
}

/// 建單時要送的停靠點（N3）。
class StopInput {
  const StopInput({
    required this.seq,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.passengerLabel,
    this.address = '',
  });

  final int seq;
  final StopKind kind;
  final double lat;
  final double lng;
  final String address;
  final String passengerLabel;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'kind': kind.code,
        'lat': lat,
        'lng': lng,
        if (address.isNotEmpty) 'address': address,
        'passenger_label': passengerLabel,
      };
}

/// 一位乘客的上／下車點（乘客端編輯用的中間表示）。
///
/// 後端要的是**扁平的 stops 陣列**，但乘客編輯時是以「人」為單位思考的——
/// 這層負責轉換，並保證產生的 stops 一定滿足後端 N2 的配對規則
/// （每位成對出現、dropoff.seq > pickup.seq）。
class PassengerTrip {
  PassengerTrip({required this.label, this.pickup, this.dropoff});

  final String label;
  StopPoint? pickup;
  StopPoint? dropoff;

  bool get complete => pickup != null && dropoff != null;
}

/// 一個地點（座標＋地址）。
class StopPoint {
  const StopPoint({required this.lat, required this.lng, this.address = ''});

  final double lat;
  final double lng;
  final String address;
}

/// 多乘客行程的上限（後端 N2 拍板：5 位乘客、各自上下車 → 10 個停靠點）。
///
/// 與後端 `constants.MaxRidePassengers`／`MaxRideStops` 對齊；超過後端會回 400，
/// App 端先擋只是提早給回饋。
const int maxRidePassengers = 5;
const int maxRideStops = maxRidePassengers * 2;

/// 把「以人為單位」的行程轉成後端要的扁平 stops（N3）。
///
/// 順序：**所有人先依序上車，再依序下車**——這是最直覺的包車情境，
/// 且天然滿足「dropoff.seq > pickup.seq」（後端 N2 會擋先送再接）。
/// 未填完的乘客直接略過。
List<StopInput> buildStops(List<PassengerTrip> trips) {
  final complete = trips.where((t) => t.complete).toList();
  if (complete.isEmpty) return const [];
  final stops = <StopInput>[];
  var seq = 1;
  for (final t in complete) {
    stops.add(StopInput(
      seq: seq++,
      kind: StopKind.pickup,
      lat: t.pickup!.lat,
      lng: t.pickup!.lng,
      address: t.pickup!.address,
      passengerLabel: t.label,
    ));
  }
  for (final t in complete) {
    stops.add(StopInput(
      seq: seq++,
      kind: StopKind.dropoff,
      lat: t.dropoff!.lat,
      lng: t.dropoff!.lng,
      address: t.dropoff!.address,
      passengerLabel: t.label,
    ));
  }
  return stops;
}
