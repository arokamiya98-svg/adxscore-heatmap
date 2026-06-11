#!/bin/bash
# ============================================================
# auto_sync_daily.sh — MT5 Files 自動同期 + パイプライン起動
# ============================================================
# MT5 で mq5 スクリプトを実行すると、対象 CSV が MT5 Files/ に出力される。
# このスクリプトは MT5 Files/ をポーリングして変更を検知すると、
# 自動で Mac 側 mt5_data/ に同期し、HTML 再生成パイプラインを起動する。
#
# 設計:
#   - fswatch 非依存（pure bash + stat ポーリング）
#   - 2秒間隔でファイル mtime をチェック
#   - 更新検知後は MT5 の書き込み完了を待つため 2秒スリープ
#   - HTML は再生成のみ（ブラウザ自動オープンしない）
#
# 使い方:
#   ./auto_sync_daily.sh                # foreground 起動
#   nohup ./auto_sync_daily.sh &> auto_sync.log &   # background 起動
#   kill <PID>                          # 停止
# ============================================================

set -e
cd "$(dirname "$0")"

MT5_FILES="/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files"
DEST="mt5_data"

# 監視対象（MT5 mq5 が出力する CSV）
TARGETS=("daily_mfe_mae_48h.csv" "daily_aggregate.csv" "trades_enriched.csv")
POLL_INTERVAL=2
WRITE_SETTLE=2   # MT5 書き込み完了待ち

# 入力 CSV の最新版（FX_*.csv）
get_latest_input() {
  ls -t data/mani_room/raw/imports/FX_*.csv 2>/dev/null | head -1
}

ts() { date +"%H:%M:%S"; }

echo "╔══════════════════════════════════════════════════╗"
echo "║   MT5 自動同期 watcher 起動                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  MT5 Files: $MT5_FILES"
echo "  ターゲット: ${TARGETS[*]}"
echo "  ポーリング: ${POLL_INTERVAL}s"
echo ""
echo "  停止: Ctrl+C または kill <PID>"
echo ""

# 起動時の mtime を記録（既存ファイルは初回スキップ）
# bash 3.2 (macOS デフォルト) は連想配列 declare -A 非対応のため平行配列で実装
LAST_MTIMES=()
for i in "${!TARGETS[@]}"; do
  f="${TARGETS[$i]}"
  SRC="$MT5_FILES/$f"
  if [ -f "$SRC" ]; then
    LAST_MTIMES[$i]=$(stat -f %m "$SRC")
    echo "  [初期] $f mtime=$(date -r ${LAST_MTIMES[$i]} +%H:%M:%S)"
  else
    LAST_MTIMES[$i]=0
    echo "  [初期] $f (未生成)"
  fi
done
echo ""
echo "[$(ts)] 監視開始..."

trap 'echo ""; echo "[$(ts)] 監視停止"; exit 0' INT TERM

while true; do
  CHANGED=()
  for i in "${!TARGETS[@]}"; do
    f="${TARGETS[$i]}"
    SRC="$MT5_FILES/$f"
    if [ -f "$SRC" ]; then
      NEW_MTIME=$(stat -f %m "$SRC")
      if [ "$NEW_MTIME" -gt "${LAST_MTIMES[$i]}" ]; then
        CHANGED+=("$f")
        LAST_MTIMES[$i]=$NEW_MTIME
      fi
    fi
  done

  if [ ${#CHANGED[@]} -gt 0 ]; then
    echo ""
    echo "[$(ts)] ▶ 更新検知: ${CHANGED[*]}"
    echo "[$(ts)]   MT5 書き込み完了待ち ${WRITE_SETTLE}s..."
    sleep $WRITE_SETTLE

    # trades_enriched.csv が更新された場合は前処理が必要
    if [[ " ${CHANGED[*]} " =~ " trades_enriched.csv " ]]; then
      echo "[$(ts)]   trades_enriched 更新 → prepare_trade_input.py 起動"
      INPUT_CSV=$(get_latest_input)
      if [ -z "$INPUT_CSV" ]; then
        echo "[$(ts)]   ⚠️ FX_*.csv が見つからない (data/mani_room/raw/imports/)、スキップ"
      else
        cp "$MT5_FILES/trades_enriched.csv" "$DEST/trades_enriched.csv"
        python3 scripts/prepare_trade_input.py \
          --input "$INPUT_CSV" \
          --output "$DEST/trade_input.csv" \
          --enriched "$DEST/trades_enriched.csv" \
          --enriched-full "data/mani_room/enriched/trades_enriched_full.csv" \
          2>&1 | tail -5
      fi
    fi

    # HTML 再生成（同期含む。ブラウザは開かない）
    echo "[$(ts)]   run_daily_calendar.sh --no-open 実行"
    ./run_daily_calendar.sh --no-open 2>&1 | grep -E "(OK 出力|トレード日数|期間|日次CSV|完了)" | head -10
    echo "[$(ts)] ✅ パイプライン完了 — ブラウザは Cmd+R で再読み込み"
  fi

  sleep $POLL_INTERVAL
done
