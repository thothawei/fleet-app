import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../screens/saved_places_screen.dart';

/// 常用地點快捷列：一排晶片，點下去把該地點帶進目的地（或上車點）。
///
/// **一個地點都還沒設時整條不顯示**，只留一顆「管理」入口——空的快捷列佔著版面卻
/// 什麼也做不到，反而讓叫車表單變長。
class SavedPlacesBar extends StatelessWidget {
  const SavedPlacesBar({
    required this.ctrl,
    required this.onPick,
    this.title = '常用地點',
    super.key,
  });

  final CustomerController ctrl;

  /// 選中某個地點時回呼（帶回地址與座標，呼叫端決定要填進哪一欄）。
  final void Function(SavedPlace place) onPick;

  final String title;

  @override
  Widget build(BuildContext context) {
    final places = ctrl.savedPlaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedPlacesScreen()),
              ),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(places.isEmpty ? '設定住家／公司' : '管理'),
            ),
          ],
        ),
        if (places.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in places)
                ActionChip(
                  avatar: Icon(savedPlaceIcon(p), size: 18),
                  label: Text(p.label),
                  onPressed: () => onPick(p),
                ),
            ],
          ),
      ],
    );
  }
}

/// 依語意插槽給圖示。**看 kind 不看 label**——乘客把住家改名成「家」之後，
/// 比對文字的寫法會無聲地掉回預設圖示。
IconData savedPlaceIcon(SavedPlace place) {
  if (place.isHome) return Icons.home;
  if (place.isWork) return Icons.work;
  return Icons.star;
}
