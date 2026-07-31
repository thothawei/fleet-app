#!/usr/bin/env bash
# 造一位乘客 + N 筆已取消的歷史行程——驗「我的行程」分頁、清單容量之類的題目用。
#
# 背景（第二十四輪踩到才寫這支）：直接寫個 for 迴圈打 API 會**整批靜默失敗**，
# 三個原因缺一不可地擋在路上：
#   1. 叫車限流 `AllowRateLimit`：預設 5 次／分鐘，key 是 `ratelimit:<line_user_id>`
#      （值由 admin 派單設定的 rate 決定，不是常數）→ 要配速。
#   2. `FindActiveByCustomer`：上一筆沒進終態就建不了下一筆 → 每筆建完要立刻取消。
#   3. 建單回應是 `{"ride_id":42,"status":0}`，**不是** `{"id":...}` → 解析錯會讓
#      後面每一筆都失敗，而迴圈還一路跑完，看起來像成功。
#
# 用法：
#     tool/seed_customer_rides.sh [筆數] [API base] [每筆間隔秒]
#     tool/seed_customer_rides.sh 25 http://127.0.0.1:8080/api 13
#
# 跑完會印出帳密，直接拿去 App 登入。造出來的行程一律是 status=9（已取消）終態，
# 不會卡住司機或派單池。
set -euo pipefail

COUNT="${1:-25}"
API="${2:-http://127.0.0.1:8080/api}"
INTERVAL="${3:-13}"
LINE_USER_ID="U_seed_$(date +%s)"
PASSWORD="pass1234"

json_field() { python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))"; }

TOKEN=$(curl -sS -X POST "$API/customer/register" -H 'Content-Type: application/json' \
  -d "{\"line_user_id\":\"$LINE_USER_ID\",\"name\":\"造數據乘客\",\"password\":\"$PASSWORD\"}" \
  | json_field token)
if [ -z "$TOKEN" ]; then
  echo "註冊失敗（後端起來了嗎？$API）" >&2
  exit 1
fi
echo "乘客 $LINE_USER_ID 建好，開始造 $COUNT 筆（每 ${INTERVAL}s 一筆，避開 5 次/分鐘的叫車限流）"

for i in $(seq 1 "$COUNT"); do
  [ "$i" -gt 1 ] && sleep "$INTERVAL"
  RESP=$(curl -sS -X POST "$API/rides" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"pickup_lat\":25.033,\"pickup_lng\":121.5654,\"pickup_address\":\"pickup point $i\",\"dropoff_address\":\"dropoff $i\",\"dropoff_lat\":25.0636,\"dropoff_lng\":121.5525}")
  RIDE_ID=$(echo "$RESP" | json_field ride_id)
  if [ -z "$RIDE_ID" ]; then
    # 不要吞掉——第一版就是這樣把 25 次全跑成空的。
    echo "第 $i 筆建單失敗：$RESP" >&2
    echo "（若是「叫車太頻繁」，把間隔調大或請 admin 調高派單設定的 rate）" >&2
    exit 1
  fi
  curl -sS -X POST "$API/rides/$RIDE_ID/cancel-by-customer" -H "Authorization: Bearer $TOKEN" > /dev/null
  echo "  第 $i 筆 → ride $RIDE_ID（已取消）"
done

echo
echo "完成。App 登入用："
echo "  LINE User ID: $LINE_USER_ID"
echo "  密碼:         $PASSWORD"
