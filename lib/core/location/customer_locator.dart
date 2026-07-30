import 'package:geolocator/geolocator.dart';

/// 乘客端叫車路徑用到的定位相依，抽成介面**只為了能測**。
///
/// geolocator 是靜態方法，單元測試環境沒有 platform channel，一碰就
/// `MissingPluginException`——於是「權限被永久拒絕」「定位服務被關閉」這幾條出口
/// 在測試裡完全碰不到，壞掉也不會有人知道（第二十二輪就是這樣壞的）。
///
/// 接縫刻意開在**最外層的 geolocator 呼叫**，而不是「直接餵一個錯誤給錯誤處理函式」：
/// 後者測不到「哪一種例外會從哪一支呼叫冒出來」，把 `on ...` 分支拔掉照樣會綠。
abstract class CustomerLocator {
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition(LocationSettings settings);
  Future<Position?> getLastKnownPosition();
}

/// 正式實作：原樣轉給 geolocator。
class GeolocatorCustomerLocator implements CustomerLocator {
  const GeolocatorCustomerLocator();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);

  @override
  Future<Position?> getLastKnownPosition() =>
      Geolocator.getLastKnownPosition();
}
