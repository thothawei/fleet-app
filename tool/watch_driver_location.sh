#!/usr/bin/env bash
# A1 背景定位實機驗收（iOS 階段 5-4）：監看司機位置在鎖屏期間是否持續更新。
#
# 資料來源：後端把每次 POST /api/driver/location 寫進 Redis hash
#           driver:<id>:loc（lat/lng/updated_at，見 internal/redis/store.go）。
#           後端沒有掛 gin.Logger()，請求層不印 log，所以用 Redis 當真相來源。
#
# 用法：watch_driver_location.sh <driver_id> [監看秒數，預設 660＝11 分鐘]

set -u

DRIVER_ID="${1:?請給 driver_id}"
DURATION="${2:-660}"
DISPATCH_DIR="/Users/mac/Documents/line-fleet-dispatch"
POLL_SEC=5

# App 端每 8 秒回報一次（AppConfig.locationIntervalSec），
# 容忍網路抖動與 iOS 的 distanceFilter，超過 60 秒沒更新就算「背景被系統凍結」。
STALE_THRESHOLD=60

cd "$DISPATCH_DIR" || exit 1

redis_get() {
  docker compose exec -T redis redis-cli HGET "driver:${DRIVER_ID}:loc" updated_at 2>/dev/null | tr -d '\r'
}

first_ts=""
last_ts=""
last_change_at=$(date +%s)
max_gap=0
updates=0
samples=0
start_at=$(date +%s)
end_at=$((start_at + DURATION))

echo "監看 driver:${DRIVER_ID}:loc，共 ${DURATION} 秒（每 ${POLL_SEC} 秒取樣一次）"
echo "開始時間：$(date '+%H:%M:%S')"
echo

while [ "$(date +%s)" -lt "$end_at" ]; do
  ts=$(redis_get)
  now=$(date +%s)
  samples=$((samples + 1))

  if [ -z "$ts" ]; then
    echo "$(date '+%H:%M:%S')  ⚠️  Redis 裡還沒有這位司機的位置（司機上線了嗎？）"
  else
    if [ -z "$first_ts" ]; then
      first_ts="$ts"
      last_ts="$ts"
      last_change_at="$now"
      echo "$(date '+%H:%M:%S')  ✅ 首次取得位置 updated_at=${ts}"
    elif [ "$ts" != "$last_ts" ]; then
      gap=$((now - last_change_at))
      [ "$gap" -gt "$max_gap" ] && max_gap="$gap"
      updates=$((updates + 1))
      last_ts="$ts"
      last_change_at="$now"
      echo "$(date '+%H:%M:%S')  ✅ 位置更新（距上次 ${gap}s，累計 ${updates} 次）"
    else
      stale=$((now - last_change_at))
      if [ "$stale" -ge "$STALE_THRESHOLD" ]; then
        echo "$(date '+%H:%M:%S')  ❌ 已 ${stale}s 沒有新位置——背景定位可能被系統停掉"
      fi
    fi
  fi
  sleep "$POLL_SEC"
done

# 收尾把最後一段靜止期也算進最大間隔，否則「結束前就斷掉」會被漏掉
final_stale=$(( $(date +%s) - last_change_at ))
[ "$final_stale" -gt "$max_gap" ] && max_gap="$final_stale"

echo
echo "==================== 驗收結果 ===================="
echo "監看時長      ：${DURATION}s"
echo "取樣次數      ：${samples}"
echo "位置更新次數  ：${updates}"
echo "最大更新間隔  ：${max_gap}s（門檻 ${STALE_THRESHOLD}s）"
if [ "$updates" -eq 0 ]; then
  echo "判定          ：❌ FAIL — 全程沒有任何位置更新"
elif [ "$max_gap" -ge "$STALE_THRESHOLD" ]; then
  echo "判定          ：❌ FAIL — 曾有 ${max_gap}s 的空窗，背景定位沒有持續"
else
  echo "判定          ：✅ PASS — 全程位置持續更新，無超過門檻的空窗"
fi
echo "=================================================="
