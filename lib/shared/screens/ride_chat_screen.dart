import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/fleet_api_client.dart' show ApiException;
import '../../core/models/models.dart';

/// 乘客↔司機共用聊天室。
/// - 歷史：進場以 REST 載入，之後以 afterId 增量補讀（WS 斷線重連保底）。
/// - 即時：訂閱 controller 的 chatStream（WS chat.message），以訊息 id 去重。
/// - 發送：走 REST，後端持久化後即時推播給雙方。
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
  final Future<RideMessage> Function(int rideId, String body) send;
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

  Future<void> _loadHistory() async {
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
        _error = e.message;
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
    setState(() => _sending = true);
    try {
      final msg = await widget.send(widget.rideId, body);
      if (!mounted) return;
      setState(() {
        _append(msg);
        _input.clear();
        _error = null;
      });
      _jumpToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
