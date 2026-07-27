import 'package:flutter/material.dart';

import '../customer_controller.dart';

/// 評分對話框（B5）：1–5 星必選、評論選填。
///
/// 送出成功回 `true`（呼叫端不必再問 controller，`ctrl.rateXxx` 已更新狀態）；
/// 取消或送出失敗回 null／false。
///
/// **失敗時對話框不關**：分數沒送出去就把畫面收掉，乘客會以為評好了；
/// 錯誤訊息留在原地，重試不必重選星等。
Future<bool?> showRatingSheet(
  BuildContext context, {
  required CustomerController ctrl,
  required int rideId,
  String? driverName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true, // 鍵盤彈出時整張表單跟著上移
    builder: (_) => _RatingSheet(
      ctrl: ctrl,
      rideId: rideId,
      driverName: driverName,
    ),
  );
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({
    required this.ctrl,
    required this.rideId,
    this.driverName,
  });

  final CustomerController ctrl;
  final int rideId;
  final String? driverName;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final _commentCtrl = TextEditingController();
  int _score = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score < 1 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.ctrl.submitRating(
      widget.rideId,
      score: _score,
      comment: _commentCtrl.text,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _submitting = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // viewInsets：鍵盤高度；不加的話評論欄會被鍵盤蓋住。
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('為這趟行程評分', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.driverName == null
                ? '行程 #${widget.rideId}'
                : '司機：${widget.driverName}（行程 #${widget.rideId}）',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _StarRow(
            score: _score,
            enabled: !_submitting,
            onChanged: (v) => setState(() => _score = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            enabled: !_submitting,
            maxLines: 3,
            maxLength: 200, // 與後端 ratingCommentMaxRunes 對齊
            decoration: const InputDecoration(
              labelText: '想說的話（選填）',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            // 沒選星等就不能送——評論可以空，星等不行（後端也擋 1–5）。
            onPressed: _score >= 1 && !_submitting ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_submitting ? '送出中…' : '送出評分'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('稍後再說'),
          ),
        ],
      ),
    );
  }
}

/// 可點選的 5 顆星。
class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.score,
    required this.enabled,
    required this.onChanged,
  });

  final int score;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: enabled ? () => onChanged(i) : null,
            iconSize: 40,
            // 語意標籤讓螢幕閱讀器唸得出「第 N 顆星」，而不是五個一樣的按鈕。
            tooltip: '$i 顆星',
            icon: Icon(
              i <= score ? Icons.star : Icons.star_border,
              color: i <= score ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

/// 唯讀星等（已評分後顯示）。
class RatingStars extends StatelessWidget {
  const RatingStars({required this.score, this.size = 20, super.key});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= score ? Icons.star : Icons.star_border,
            size: size,
            color: i <= score ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
      ],
    );
  }
}
