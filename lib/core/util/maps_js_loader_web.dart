import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../config/app_config.dart';

/// 同一個 session 只注入一次，重複呼叫共用同一個 Future。
Future<void>? _loading;

/// 注入 Google Maps JS API 並等它載完。
///
/// 未設定 API key 時直接 no-op——呼叫端（`AppConfig.mapsConfigured`）本來就會
/// 把地圖 widget 降級成文字提示，不該因為缺 key 就卡住 App 啟動。
/// 載入失敗同樣不拋出，讓 App 以「無地圖」模式繼續跑。
Future<void> ensureMapsJsLoaded() {
  if (!AppConfig.mapsConfigured || _mapsReady) return Future.value();
  return _loading ??= _injectScript();
}

/// `google.maps` 已在 window 上（例如 index.html 另外載過）就不重複注入。
bool get _mapsReady {
  final google = globalContext['google'];
  return google.isA<JSObject>() && (google as JSObject).has('maps');
}

Future<void> _injectScript() {
  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js'
        '?key=${Uri.encodeQueryComponent(AppConfig.googleMapsApiKey)}'
    ..async = true
    ..defer = true;

  script.addEventListener(
    'load',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      // key 無效／被限制擋下時走這裡；不拋出，地圖區塊自行降級。
      if (!completer.isCompleted) completer.complete();
    }).toJS,
  );

  web.document.head!.appendChild(script);
  return completer.future;
}
