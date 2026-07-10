import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/models.dart';

/// 行程狀態 → 語意色（spec §1.1：等待=琥珀、進行=藍、完成=綠、取消=紅）
/// [status] 為 [RideStatus] int 常數（非 enum）。
Color rideStatusColor(BuildContext context, int status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    RideStatus.requested || RideStatus.assigned => const Color(0xFFFAAD14),
    RideStatus.accepted || RideStatus.pickedUp => const Color(0xFF1677FF),
    RideStatus.completed => scheme.primary,
    RideStatus.cancelled => scheme.error,
    _ => scheme.outline,
  };
}

/// 司機端行程階段 → 語意色
Color driverPhaseColor(BuildContext context, DriverRidePhase phase) {
  final scheme = Theme.of(context).colorScheme;
  return switch (phase) {
    DriverRidePhase.enRouteToPickup || DriverRidePhase.onTrip =>
      const Color(0xFF1677FF),
    _ => scheme.outline,
  };
}
