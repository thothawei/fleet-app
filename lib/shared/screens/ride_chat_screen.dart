import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/fleet_api_client.dart' show ApiException;
import '../../core/models/models.dart';
import '../widgets/app_lifecycle_reactor.dart';

/// 乘客↔司機共用聊天室。
/// - 歷史：進場以 REST 載入，之後以 afterId 增量補讀（WS 斷線重連保底）。
/// - 即時：訂閱 controller 的 chatStream（WS chat.message），以訊息 id 去重。
/// - 發送：走 REST，後端持久化後即時推播給雙方。
/// - **回前景時補讀一次**：WS 重連不會補送斷線期間的訊息，見 [_loadHistory]。
class RideChatScreen extends StatefulWidget {
  const RideChatScreen({
    required this.rideId,
    required this.selfRole, // 'customer' | 'driver'
    required this.title,
    required this.loadHistory,
    required this.send,
    required this.incoming,
    this.onVisibilityChanged,
    super.key,
  });

  final int rideId;
  final String selfRole;
  final String title;
  final Future<List<RideMessage>> Function(int rideId, {int afterId})
      loadHistory;
  /// 送出一則訊息。[clientMsgId] 是冪等鍵——同一則訊息的重試沿用同一個鍵，
  /// 後端據此去重（dispatch #68），所以重送不會讓對方看到同一句話兩次。
  final Future<RideMessage> Function(int rideId, String body,
      {String? clientMsgId}) send;
  final Stream<RideMessage> incoming;

  /// 進出聊天室通知 controller（清未讀／暫停未讀累計）。
  final void Function(bool visible)? onVisibilityChanged;

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  final _messages = <RideMessage>[];
  final _ids = <int>{};
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<RideMessage>? _sub;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // 目前這一則「還沒確認落地」的訊息用的冪等鍵。
  // 送出成功（或對帳確認其實成功）就清掉，讓下一則拿新的鍵；
  // **失敗時要留著**——重試沿用同一個鍵才不會在後端變成兩則。
  String? _pendingClientMsgId;
  var _clientMsgSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.onVisibilityChanged?.call(true);
    _sub = widget.incoming.listen(_onIncoming);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.onVisibilityChanged?.call(false);
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 補讀歷史：進場（此時 `_messages` 為空 ＝ 全量）、錯誤橫幅按「重試」、
  /// 以及**從背景回到前景時**。
  ///
  /// 最後那個觸發點原本沒有，於是這支方法的增量補讀（afterId）**只有進場那次會走到**——
  /// 聊天室開著切背景、或 WS 斷線的期間，對方送的訊息就永遠不會出現在畫面上
  /// （WS 重連**不會補送**漏掉的事件，見 docs/TODO.md 第四輪），
  /// 而且連未讀角標都不會亮——聊天室開著時本來就不累計未讀。
  /// 使用者只能離開聊天室再進來才看得到。
  /// [silent] 給回前景那條路徑用：使用者只是把 App 切回來、沒按任何東西，
  /// 補讀失敗不該冒出錯誤橫幅（同 2026-07-28 修掉的「背景動作汙染錯誤出口」那一族）。
  Future<void> _loadHistory({bool silent = false}) async {
    try {
      final afterId = _messages.isEmpty ? 0 : _messages.last.id;
      final history =
          await widget.loadHistory(widget.rideId, afterId: afterId);
      if (!mounted) return;
      setState(() {
        for (final m in history) {
          _append(m);
        }
        _loading = false;
        _error = null;
      });
      _jumpToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  void _onIncoming(RideMessage msg) {
    if (msg.rideId != widget.rideId) return;
    setState(() => _append(msg));
    _jumpToBottom();
  }

  void _append(RideMessage msg) {
    if (!_ids.add(msg.id)) return; // 以 id 去重（自己發送的 WS 回聲）
    _messages.add(msg);
    _messages.sort((a, b) => a.id.compareTo(b.id));
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    // 這一則的鍵：第一次送出時產生，重試時**沿用**（後端據此去重）。
    final clientMsgId = _pendingClientMsgId ??= _newClientMsgId();
    setState(() => _sending = true);
    try {
      final msg =
          await widget.send(widget.rideId, body, clientMsgId: clientMsgId);
      if (!mounted) return;
      _acceptSent(msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      // **逾時不代表沒送出**：後端可能已經寫入，只是回應遺失。
      // 訊息沒有唯一狀態可查（「同內容再送一次」本來就合法），所以補讀回來
      // 用**冪等鍵**比對——找到就是上一次其實送出了。
      final recovered = e.statusCode == null
          ? await _findSentByClientMsgId(clientMsgId)
          : null;
      if (!mounted) return;
      if (recovered != null) {
        _acceptSent(recovered);
        return;
      }
      // 沒找到（或這一問也失敗）→ 留著錯誤、輸入內容與同一個鍵，讓他重試。
      // 重試是安全的：後端帶同鍵不會多一則。
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 訊息確認落地：附加到畫面、清空輸入框與錯誤，並讓下一則取得新的鍵。
  void _acceptSent(RideMessage msg) {
    setState(() {
      _append(msg);
      _input.clear();
      _error = null;
      _pendingClientMsgId = null;
    });
    _jumpToBottom();
  }

  /// 逾時後的對帳：補讀最後一則之後的訊息，看有沒有帶著這個鍵的那一則。
  ///
  /// 補讀到的其他訊息（對方同時說的話）也一併顯示——既然問了就別浪費。
  /// 這一問本身失敗時回 null（不知道就不亂改，維持原本的錯誤）。
  Future<RideMessage?> _findSentByClientMsgId(String clientMsgId) async {
    try {
      final afterId = _messages.isEmpty ? 0 : _messages.last.id;
      final fresh = await widget.loadHistory(widget.rideId, afterId: afterId);
      RideMessage? mine;
      for (final m in fresh) {
        if (m.clientMsgId == clientMsgId) {
          mine = m;
        } else {
          setState(() => _append(m));
        }
      }
      return mine;
    } on ApiException {
      return null;
    }
  }

  /// 產生這一則訊息的冪等鍵。
  ///
  /// 不需要全域唯一——後端的去重範圍是「同一趟行程的同一位發話者」，
  /// 所以「同一個聊天室內、同一支 App 執行期間不重複」就夠了。
  /// 時間戳（毫秒）＋序號可避開同一毫秒連送兩則的碰撞。
  String _newClientMsgId() =>
      '${widget.selfRole}-${DateTime.now().millisecondsSinceEpoch}-${_clientMsgSeq++}';

  @override
  Widget build(BuildContext context) {
    // 沿用 app root 那支 reactor：`inactive` 不算回前景（通知列下拉、來電橫幅都會觸發它，
    // 連線並沒有斷），只有真的離開過前景才補讀。
    return AppLifecycleReactor(
      onResumed: () => _loadHistory(silent: true),
      child: _buildChat(context),
    );
  }

  Widget _buildChat(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('知道了'),
                ),
                TextButton(
                  onPressed: _loadHistory,
                  child: const Text('重試'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          '還沒有訊息，說聲哈囉吧',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) => _MessageBubble(
                          message: _messages[i],
                          isSelf:
                              _messages[i].senderRole == widget.selfRole,
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '輸入訊息…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '發送',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isSelf});

  final RideMessage message;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isSelf ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = isSelf ? scheme.onPrimaryContainer : scheme.onSurface;
    final time = message.createdAt?.toLocal();
    final timeLabel = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isSelf ? 16 : 4),
            bottomRight: Radius.circular(isSelf ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.body, style: TextStyle(color: fg)),
            if (timeLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                timeLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: fg.withValues(alpha: 0.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
