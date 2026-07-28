import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../screens/lost_item_screen.dart';

/// 進行中的遺失物協尋摘要卡：點擊進入詳情（付款／與司機對話）。
///
/// **兩版首頁共用同一份**——先前這段只寫在卡片版首頁裡，
/// 換成地圖版當 production 後就整個掉了：乘客建了協尋單、司機標記「已尋獲」，
/// 但乘客沒有任何畫面可以進去付處理費把東西拿回來（2026-07-28 對帳抓到）。
/// 抽成共用元件是為了讓「再換一次首頁」時不會又漏掉。
class LostItemBanner extends StatelessWidget {
  const LostItemBanner({required this.item, super.key});

  final LostItemRequest item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.travel_explore),
        title: Text('遺失物協尋：${item.description}'),
        subtitle: Text(item.statusLabel),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CustomerLostItemScreen(rideId: item.rideId),
          ),
        ),
      ),
    );
  }
}
