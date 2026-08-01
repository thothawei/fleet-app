import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 依 **rune 數**（Unicode code point）限制輸入長度，並提供同一單位的計數器。
///
/// **為什麼不直接用 `TextField.maxLength`**：它數的是 grapheme cluster
/// （使用者感知的「一個字」），而後端每一支上限數的都是 rune
/// （`utf8.RuneCountInString` / `len([]rune(...))`）。兩者對 ASCII 與中文相同，
/// 對 emoji 差很多——實測 `maxLength: 5` 會放行 5 個 ZWJ 家庭 emoji ＝ **35 個 rune**：
///
/// ```
/// 「👨‍👩‍👧‍👦」characters=1 runes=7    「🇹🇼」characters=1 runes=2    「👍🏽」characters=1 runes=2
/// ```
///
/// 於是畫面上的計數器顯示「200/200 沒超過」，送出卻被後端以 400 擋下，
/// 而錯誤訊息（「評論長度超過上限」）**不會告訴使用者到底該砍掉多少**——
/// 對照計數器只會更困惑。擋在同一個單位上，這條路才不會出現。
class RuneLimitingTextInputFormatter extends TextInputFormatter {
  const RuneLimitingTextInputFormatter(this.maxRunes)
    : assert(maxRunes > 0, 'maxRunes 必須為正');

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (runeCount(newValue.text) <= maxRunes) return newValue;
    // **以 grapheme cluster 為單位裁切**，不是直接砍 rune 陣列：
    // 從 ZWJ 序列中間切下去會留下半個字（孤立的修飾符／ZWJ 尾巴），
    // 畫面會出現使用者沒打過的東西。寧可少收一個完整的字。
    final buffer = StringBuffer();
    var used = 0;
    for (final cluster in newValue.text.characters) {
      final n = cluster.runes.length;
      if (used + n > maxRunes) break;
      buffer.write(cluster);
      used += n;
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}

/// 與後端同一單位的長度計算。
int runeCount(String s) => s.runes.length;

/// `TextField.buildCounter` 用的計數器，顯示的數字與後端檢查的是同一個。
///
/// 沿用 `maxLength` 的 `x/y` 形狀（使用者已經認得），只是把 x 換成 rune 數。
/// **要傳 controller**：counter 不是 `EditableText` 的後代，用 context 往上找拿不到
/// 目前文字，只能退回 framework 給的 `currentLength`——那正是 grapheme 數。
/// `TextField` 會跟著 controller 變動重建，所以這裡讀到的一定是最新值。
InputCounterWidgetBuilder runeCounter(
  int maxRunes,
  TextEditingController controller,
) {
  return (
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) {
    final used = runeCount(controller.text);
    return Text(
      '$used/$maxRunes',
      style: Theme.of(context).textTheme.bodySmall,
      semanticsLabel: '已輸入 $used 字，上限 $maxRunes 字',
    );
  };
}
