import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../driver_controller.dart';

/// 診斷資訊收納：WS/FCM/API/GPS 移入可展開區塊，預設收合（spec §3）
class ConnectionDetailsTile extends StatelessWidget {
  const ConnectionDetailsTile({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final pos = ctrl.lastPosition;
    final healthy = ctrl.wsConnected;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          Icons.circle,
          size: 12,
          color: healthy ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        title: const Text('連線狀態'),
        subtitle: Text(healthy ? '即時連線正常' : '未連線，派單可能延遲'),
        shape: const Border(),
        children: [
          _row(context, 'WebSocket', ctrl.wsConnected ? '已連線' : '未連線'),
          _row(
            context,
            'FCM 推播',
            ctrl.fcmAvailable
                ? (ctrl.fcmTokenPrefix != null
                    ? '已註冊 ${ctrl.fcmTokenPrefix}'
                    : '已啟用（待 token）')
                : '未設定 Firebase',
          ),
          _row(context, 'API', AppConfig.apiBase),
          if (pos != null)
            _row(
              context,
              'GPS',
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
