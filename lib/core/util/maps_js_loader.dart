/// 執行期載入 Google Maps JavaScript API（僅 Web 平台需要）。
///
/// 原生 Android/iOS 由各自的 Maps SDK 處理，這裡是 no-op；Web 版的
/// `google_maps_flutter_web` 需要 `google.maps` 已存在於 window 才能建立地圖，
/// 否則會拋 `Cannot read properties of undefined (reading 'maps')`。
///
/// 改用執行期注入而非寫死在 `web/index.html`，是為了讓 API key 只透過
/// `--dart-define=GOOGLE_MAPS_API_KEY=...` 傳入，永遠不進版控。
library;

export 'maps_js_loader_stub.dart'
    if (dart.library.js_interop) 'maps_js_loader_web.dart';
