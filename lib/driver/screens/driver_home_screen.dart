import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ride_status_colors.dart';
import '../../core/util/maps.dart';
import '../../shared/screens/ride_chat_screen.dart';
import '../driver_controller.dart';
import '../widgets/connection_details_tile.dart';
import '../widgets/driver_ride_map.dart';
import '../widgets/ride_stops_list.dart';
import '../widgets/offer_overlay.dart';
import '../widgets/online_hero_card.dart';
import 'driver_earnings_screen.dart';
import 'driver_lost_items_screen.dart';
import 'driver_vehicle_screen.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text('你好，${ctrl.session?.name ?? '司機'}'),
            actions: [
              IconButton(
                tooltip: '遺失物協尋',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DriverLostItemsScreen(),
                  ),
                ),
                icon: Badge(
                  isLabelVisible: ctrl.lostItems.isNotEmpty,
                  label: Text('${ctrl.lostItems.length}'),
                  child: const Icon(Icons.travel_explore),
                ),
              ),
              IconButton(
                tooltip: '我的收入',
                // DriverController 由 App 層 Provider 提供，位於 MaterialApp 之上，
                // pushed route 仍可透過 context.read 取得，故不需重新 provide。
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DriverEarningsScreen(),
                  ),
                ),
                icon: const Icon(Icons.payments_outlined),
              ),
              IconButton(
                tooltip: '車輛資訊',
                // 修改情境（可返回）；未填車輛的強制情境由 _DriverRoot 直接導向設定頁。
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DriverVehicleScreen(),
                  ),
                ),
                icon: const Icon(Icons.directions_car_outlined),
              ),
              IconButton(
                tooltip: '登出',
                onPressed: ctrl.loading ? null : () => ctrl.logout(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              OnlineHeroCard(ctrl: ctrl),
              const SizedBox(height: 12),
              if (ctrl.error != null) _ErrorBanner(message: ctrl.error!),
              if (ctrl.activeRide != null) _ActiveRideCard(ctrl: ctrl),
              if (ctrl.activeRide == null && ctrl.pendingOffer == null)
                _IdleHint(),
              const SizedBox(height: 12),
              ConnectionDetailsTile(ctrl: ctrl),
            ],
          ),
        ),
        if (ctrl.pendingOffer != null) OfferOverlay(ctrl: ctrl),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ctrl});

  final DriverController ctrl;

  /// 概覽地圖（有目標座標才顯示）。前往上車點時目標為上車點，行程中為目的地；
  /// 多停靠點行程（N）改畫全程：依序的停靠點＋折線＋下一站醒目。
  List<Widget> _buildRideMap(DriverController ctrl, ActiveRide ride) {
    final pos = ctrl.lastPosition;
    if (ride.hasStops) {
      return [
        DriverRideMap(
          stops: ride.stops,
          driverLat: pos?.latitude,
          driverLng: pos?.longitude,
        ),
        const SizedBox(height: 16),
      ];
    }
    final toPickup = ride.phase == DriverRidePhase.enRouteToPickup;
    final lat = toPickup ? ride.pickupLat : ride.dropoffLat;
    final lng = toPickup ? ride.pickupLng : ride.dropoffLng;
    if (lat == null || lng == null) return const [];
    return [
      DriverRideMap(
        targetLat: lat,
        targetLng: lng,
        targetLabel: toPickup ? '上車點' : '目的地',
        targetIsPickup: toPickup,
        driverLat: pos?.latitude,
        driverLng: pos?.longitude,
      ),
      const SizedBox(height: 16),
    ];
  }

  /// 外部導航按鈕（開 Google Maps）。
  ///
  /// **多停靠點行程要導去「下一站」，不是最終目的地**——司機依序停靠，
  /// 導去終點會把中間的乘客載過頭。全部站處理完（`nextStop == null`）後
  /// 才退回最終目的地。
  ///
  /// 目標一律優先給座標：地址字串在 Google Maps 可能解析到同名的錯誤地點
  /// （與 `mapsNavigationUri` 的既有語意一致）。
  List<Widget> _buildNavigationButton(ActiveRide ride, ButtonStyle style) {
    final next = ride.hasStops ? ride.nextStop : null;
    final (label, address, lat, lng) = next != null
        ? ('導航去下一站（${next.title}）', next.address ?? '', next.lat, next.lng)
        : ride.phase == DriverRidePhase.enRouteToPickup
            ? ('導航去上車點', ride.address, ride.pickupLat, ride.pickupLng)
            : ('導航去目的地', ride.dropoffAddress ?? '', ride.dropoffLat, ride.dropoffLng);
    // 地址與座標都沒有就不給按鈕（按了只會開出無意義的搜尋）。
    if (address.isEmpty && (lat == null || lng == null)) return const [];
    return [
      OutlinedButton.icon(
        onPressed: () => openMapsNavigation(address, lat: lat, lng: lng),
        style: style,
        icon: const Icon(Icons.navigation),
        label: Text(label),
      ),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phaseLabel = switch (ride.phase) {
      DriverRidePhase.enRouteToPickup => '前往上車點',
      DriverRidePhase.onTrip => '行程中',
      _ => '進行中',
    };
    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(kPrimaryActionHeight),
      textStyle: text.titleMedium,
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(kPrimaryActionHeight),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '行程 #${ride.rideId}',
                    style: text.titleLarge,
                  ),
                ),
                Chip(
                  label: Text(phaseLabel),
                  backgroundColor:
                      driverPhaseColor(context, ride.phase).withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('上車點：${ride.address}'),
            const SizedBox(height: 12),
            // 概覽地圖：前往上車點時標上車點，行程中標目的地；無座標（舊後端／
            // LINE 建的無目的地訂單）就不顯示，其餘操作不受影響。
            ..._buildRideMap(ctrl, ride),
            // 多停靠點行程的全程清單＋到站／跳過標記（N6／N7）；
            // 單點訂單為空 list → 整塊不顯示，既有畫面不變。
            RideStopsList(ctrl: ctrl, ride: ride),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RideChatScreen(
                    rideId: ride.rideId,
                    selfRole: 'driver',
                    title: '聯絡乘客（行程 #${ride.rideId}）',
                    loadHistory: ctrl.fetchMessages,
                    send: ctrl.sendMessage,
                    incoming: ctrl.chatStream,
                    onVisibilityChanged: ctrl.setChatVisible,
                  ),
                ),
              ),
              style: secondaryStyle,
              icon: Badge(
                isLabelVisible: ctrl.unreadChat > 0,
                label: Text('${ctrl.unreadChat}'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              label: const Text('聯絡乘客'),
            ),
            const SizedBox(height: 8),
            if (ride.phase == DriverRidePhase.enRouteToPickup) ...[
              ..._buildNavigationButton(ride, secondaryStyle),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.pickUpPassenger,
                style: primaryStyle,
                child: const Text('乘客已上車'),
              ),
            ],
            if (ride.phase == DriverRidePhase.onTrip) ...[
              if (ride.hasDropoff && !ride.hasStops) ...[
                Text('目的地：${ride.dropoffAddress ?? '（地圖選點）'}'),
                const SizedBox(height: 16),
              ],
              ..._buildNavigationButton(ride, secondaryStyle),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.completeTrip,
                style: primaryStyle,
                child: const Text('完成行程'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: ctrl.loading
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('確定放棄這筆訂單？'),
                          content: const Text('放棄後這筆訂單會回到派單池。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(false),
                              child: const Text('返回'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(true),
                              child: const Text('確定放棄'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await ctrl.abandonTrip();
                    },
              child: const Text('放棄此單'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '上線後將自動回報位置並接收派單。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
