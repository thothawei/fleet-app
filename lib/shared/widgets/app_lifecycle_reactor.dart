import 'package:flutter/material.dart';

/// 監看 App 生命週期，在回到前景（resumed）時通知呼叫端補做對帳。
///
/// 兩端的 root 都包一層：司機端與乘客端在背景期間都可能與後端脫節
/// （WS 斷線或變成半開、輪詢 timer 不跑），而回前景是使用者**正要看畫面**的那一刻，
/// 畫面上的東西這時候必須是真的。
class AppLifecycleReactor extends StatefulWidget {
  const AppLifecycleReactor({
    super.key,
    required this.onResumed,
    required this.child,
  });

  final VoidCallback onResumed;
  final Widget child;

  @override
  State<AppLifecycleReactor> createState() => _AppLifecycleReactorState();
}

class _AppLifecycleReactorState extends State<AppLifecycleReactor>
    with WidgetsBindingObserver {
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
    // 只在 resumed 動作。inactive／hidden 也會在切換過程中出現（例如拉下通知欄），
    // 對它們反應會在使用者根本沒離開 App 時打一堆沒必要的請求。
    if (state == AppLifecycleState.resumed) widget.onResumed();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
