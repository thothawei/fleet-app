import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/push/pending_push_replay.dart';

/// 「點推播喚醒被殺的 App」這條路徑先前是死的：
/// `getInitialMessage()` 在 `runApp` 之前就把事件 add 進廣播串流，
/// 而 controller 要到 `init()` 才訂閱——廣播串流不緩衝，事件當場消失。
///
/// 這組測試釘住補送行為。移掉 [PendingReplaySink] 的補送邏輯，第一支就會 FAIL。
void main() {
  test('沒人訂閱時到達的事件，第一個訂閱者上來要補送', () async {
    final sink = PendingReplaySink<String>();
    sink.add('ride.assigned'); // 冷啟動：此刻沒有任何訂閱者
    expect(sink.hasPending, isTrue);

    final received = <String>[];
    sink.stream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    expect(received, ['ride.assigned']);
    expect(sink.hasPending, isFalse);
    await sink.close();
  });

  test('補送只做一次，之後的訂閱者不會再收到同一則', () async {
    final sink = PendingReplaySink<String>();
    sink.add('driver.arrived');

    final first = <String>[];
    final sub = sink.stream.listen(first.add);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    final second = <String>[];
    sink.stream.listen(second.add);
    await Future<void>.delayed(Duration.zero);

    expect(first, ['driver.arrived']);
    expect(second, isEmpty, reason: '登出後重新訂閱不該再收到同一則舊事件');
    await sink.close();
  });

  test('只留最後一則：補送一整串過期狀態只會讓畫面閃過舊資料', () async {
    final sink = PendingReplaySink<String>();
    sink.add('ride.accepted');
    sink.add('driver.arrived');
    sink.add('ride.completed');

    final received = <String>[];
    sink.stream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    expect(received, ['ride.completed']);
    await sink.close();
  });

  test('已經有訂閱者時照常即時送達，不進補送佇列', () async {
    final sink = PendingReplaySink<String>();
    final received = <String>[];
    sink.stream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sink.add('chat.message');
    expect(sink.hasPending, isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(received, ['chat.message']);
    await sink.close();
  });

  test('補送前訂閱者就取消時不 panic（事件丟掉即可）', () async {
    final sink = PendingReplaySink<String>();
    sink.add('ride.cancelled');

    final sub = sink.stream.listen((_) {});
    await sub.cancel(); // 補送的 microtask 還沒跑就取消
    await Future<void>.delayed(Duration.zero);

    await sink.close();
  });
}
