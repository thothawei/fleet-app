import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../screens/map_picker_screen.dart';

/// 多乘客／多停靠點編輯（N3）。
///
/// **預設不啟用**：多數行程只有一位乘客，維持既有的「單一目的地」流程最簡單。
/// 按「多位乘客同行」才展開，且**預設只有 1 位**、按「+ 新增乘客」漸進增加——
/// 一次逼使用者填滿 5 位太繁瑣（App 端待拍板項，此為建議方案）。
///
/// 啟用後上方的「要去哪裡？」不再使用：每位乘客各自有上／下車點，
/// 最終目的地由後端取「seq 最大的 dropoff」（見 buildStops）。
class StopsEditor extends StatelessWidget {
  const StopsEditor({required this.ctrl, super.key});

  final CustomerController ctrl;

  Future<void> _pick(
    BuildContext context,
    int index, {
    required bool isPickup,
  }) async {
    final pos = ctrl.lastPosition;
    final picked = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initial: pos != null ? LatLng(pos.latitude, pos.longitude) : null,
        ),
      ),
    );
    if (picked == null) return;
    final point = StopPoint(lat: picked.lat, lng: picked.lng, address: picked.address);
    ctrl.setPassengerPoint(
      index,
      pickup: isPickup ? point : null,
      dropoff: isPickup ? null : point,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!ctrl.multiStopEnabled) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: ctrl.busy ? null : ctrl.enableMultiStop,
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('多位乘客同行（各自上下車）'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '同行乘客（${ctrl.passengers.length}/$maxRidePassengers）',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: ctrl.busy ? null : ctrl.disableMultiStop,
              child: const Text('改回單一目的地'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '每位乘客各自設定上車與下車點，司機會依序停靠。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < ctrl.passengers.length; i++)
          _PassengerCard(
            trip: ctrl.passengers[i],
            // 只剩一位時不給刪——刪光了等於回到單一目的地，那該用「改回單一目的地」。
            onRemove: ctrl.passengers.length > 1 && !ctrl.busy
                ? () => ctrl.removePassenger(i)
                : null,
            onPickPickup: ctrl.busy ? null : () => _pick(context, i, isPickup: true),
            onPickDropoff: ctrl.busy ? null : () => _pick(context, i, isPickup: false),
          ),
        if (ctrl.canAddPassenger)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: ctrl.busy ? null : ctrl.addPassenger,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('新增乘客'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // 上限是後端拍板的（5 位各自上下車＝10 個停靠點），超過後端會回 400。
              '最多 $maxRidePassengers 位乘客',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.trip,
    required this.onRemove,
    required this.onPickPickup,
    required this.onPickDropoff,
  });

  final PassengerTrip trip;
  final VoidCallback? onRemove;
  final VoidCallback? onPickPickup;
  final VoidCallback? onPickDropoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text(trip.label, style: theme.textTheme.labelSmall),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('乘客 ${trip.label}', style: theme.textTheme.titleSmall),
                ),
                if (!trip.complete)
                  // 未填完的乘客不會被送出（buildStops 會略過），要讓使用者看得到。
                  Text('尚未填完', style: theme.textTheme.labelSmall),
                if (onRemove != null)
                  IconButton(
                    tooltip: '移除乘客 ${trip.label}',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            _PointRow(
              icon: Icons.my_location,
              label: '上車點',
              point: trip.pickup,
              onPick: onPickPickup,
            ),
            const SizedBox(height: 4),
            _PointRow(
              icon: Icons.place_outlined,
              label: '下車點',
              point: trip.dropoff,
              onPick: onPickDropoff,
            ),
          ],
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.icon,
    required this.label,
    required this.point,
    required this.onPick,
  });

  final IconData icon;
  final String label;
  final StopPoint? point;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = point;
    return InkWell(
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  Text(
                    p == null
                        ? '點此在地圖上選擇'
                        : (p.address.isNotEmpty
                            ? p.address
                            : '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: p == null ? theme.colorScheme.outline : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.map_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}
