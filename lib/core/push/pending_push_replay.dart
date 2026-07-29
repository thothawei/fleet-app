import 'dart:async';

/// 沒有訂閱者時把事件留著，等第一個訂閱者上來再補送。
///
/// **為什麼需要這個**：`StreamController.broadcast()` 在沒有訂閱者的當下 `add`，
/// 事件會直接消失（Dart 的廣播串流不緩衝）。而「點推播喚醒被殺的 App」正是這個情況——
///
/// ```
/// main() → createXxxPushService() → initialize() → getInitialMessage() → add(事件)
///        → runApp() → Controller.init() → rideEvents.listen(...)   ← 訂閱在這裡才發生
/// ```
///
/// 事件在 `runApp` 之前就發出去了，訂閱者晚了好幾拍，於是 A2 的招牌情境
/// 「App 被殺 → 點推播 → 接單卡」與乘客端「點推播 → 跟後端對帳」**兩邊都是死路徑**。
///
/// 只留**最後一則**：這些事件的用途都是「去跟後端對一次帳」或「開一張卡」，
/// 補送最新的那則即可，補送一整串舊事件只會讓畫面閃過一連串過期狀態。
/// 補送過就丟掉，所以登出後重新訂閱不會再收到同一則。
class PendingReplaySink<T> {
  PendingReplaySink() {
    _controller = StreamController<T>.broadcast(onListen: _flushPending);
  }

  late final StreamController<T> _controller;
  T? _pending;

  Stream<T> get stream => _controller.stream;

  /// 目前是否有事件等著補送（測試與診斷用）。
  bool get hasPending => _pending != null;

  void add(T event) {
    if (_controller.hasListener) {
      _controller.add(event);
      return;
    }
    _pending = event;
  }

  /// 第一個訂閱者上來時補送。
  ///
  /// 用 microtask 而非直接 `add`：`onListen` 在訂閱**建立過程中**被呼叫，
  /// 當下同步 add 進去的事件不保證送得到那位訂閱者。
  void _flushPending() {
    scheduleMicrotask(() {
      final pending = _pending;
      _pending = null;
      if (pending != null && _controller.hasListener) {
        _controller.add(pending);
      }
    });
  }

  Future<void> close() => _controller.close();
}
