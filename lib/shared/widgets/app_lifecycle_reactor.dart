import 'package:flutter/material.dart';

/// 監看 App 生命週期，**從背景回到前景時**呼叫 [onResumed]。
///
/// 存在的理由：背景期間系統可能關掉 WebSocket、也會凍結 timer（iOS 一定會，
/// Android Doze 也會延後）。回前景那一刻，WS 的退避重連可能才剛開始倒數、
/// 乘客端的 15 秒輪詢也可能還要等一輪——這段空窗裡畫面顯示的是背景前的舊狀態。
/// 誰該在回前景做什麼由 controller 決定（見 `onAppResumed`），這裡只負責通知。
class AppLifecycleReactor extends StatefulWidget {
  const AppLifecycleReactor({
    required this.onResumed,
    required this.child,
    super.key,
  });

  /// 從背景（paused／hidden／detached）回到前景時呼叫。
  final VoidCallback onResumed;

  final Widget child;

  @override
  State<AppLifecycleReactor> createState() => _AppLifecycleReactorState();
}

class _AppLifecycleReactorState extends State<AppLifecycleReactor>
    with WidgetsBindingObserver {
  /// 是否真的離開過前景。**inactive 不算**——通知列下拉、來電橫幅、權限對話框
  /// 都會進 inactive 再回 resumed，連線並不會斷；把它當成回前景只會讓使用者
  /// 每點一次通知就多打兩支 API。
  bool _leftForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _leftForeground = true;
      case AppLifecycleState.resumed:
        if (_leftForeground) {
          _leftForeground = false;
          widget.onResumed();
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
