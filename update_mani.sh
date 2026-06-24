#!/bin/bash
# ============================================================
# update_mani.sh — 系統A（成績・マニv3）前後事務を1コマンドに束ねる
# ============================================================
# 半自動化建て直し v1（ブン指示書 §4(B)）。
# 旧 auto_sync_daily.sh の「常駐 watcher × 60秒 git-pull ループ」を廃止し、
# 系統Aエンリッチを「トレード時だけ手動起動・自動終了・gitループ無し」の
# 前景ジョブに落とす。watch対象はローカルファイルの mtime のみ（git を触らない）。
#
# 2モード:
#   ./update_mani.sh           単発: iCloud→imports橋渡し → prepare(trade_input生成+MT5配置)
#                              → [MT5 Snapshot 手動ゲート] → merge → generate → publish
#   ./update_mani.sh --watch   前景watch: FX_*.csv 新着 → prepare → MT5配置 →「Snapshot回して」
#                              → trades_enriched.csv 更新検知 → merge → generate → publish
#                              → 1回成功で自動exit（Ctrl+C でも終了）
#
# 安全要件（厳守・指示書§4(B)）:
#   - git pull の常時ループを入れない。watch対象はローカルmtimeのみ。
#   - git操作は最後の公開pushの1回だけ（run_to 付き・push前 git pull）。
#   - 前景実行（デーモン化・nohup常駐禁止）。終わったら消える。多重起動ガードあり。
# ============================================================

set -e
cd "$(dirname "$0")"

MT5_FILES="/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files"
DEST="mt5_data"
ICLOUD_IMPORTS="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ADXSCORE"
LOCAL_IMPORTS="data/mani_room/raw/imports"
ENRICHED_FULL="data/mani_room/enriched/trades_enriched_full.csv"

GIT_PULL_TIMEOUT=45
GIT_PUSH_TIMEOUT=30

POLL_INTERVAL=2
WRITE_SETTLE=2

LOCKDIR="/tmp/adxscore_update_mani.lock"

ts() { date +"%H:%M:%S"; }

# ── ポータブル timeout（auto_sync_daily.sh から流用・同一実装）──
run_to() {
  local secs="$1"; shift
  "$@" >/dev/null 2>&1 &
  local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null; sleep 2; kill -KILL "$cmd_pid" 2>/dev/null ) >/dev/null 2>&1 &
  local killer_pid=$!
  local rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?
  kill -TERM "$killer_pid" 2>/dev/null || true
  wait "$killer_pid" 2>/dev/null || true
  return $rc
}

# ── 多重起動ガード ──
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "[$(ts)] 別の update_mani が稼働中（lock: $LOCKDIR）→ 即exit"
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT INT TERM

# ── iCloud入口 → ローカルimports 橋渡し（auto_sync_daily.sh の sync_icloud_imports 流用）──
sync_icloud_imports() {
  [ -d "$ICLOUD_IMPORTS" ] || return 0
  local src base dst
  while IFS= read -r src; do
    [ -z "$src" ] && continue
    base=$(basename "$src")
    dst="$LOCAL_IMPORTS/$base"
    if [ ! -f "$dst" ]; then
      brctl download "$src" 2>/dev/null || true
      if cp "$src" "$dst" 2>/dev/null; then
        echo "[$(ts)] ☁️→💻 iCloud入口から取込: $base"
      fi
    fi
  done < <(find "$ICLOUD_IMPORTS" -maxdepth 2 -iname "FX_*.csv" 2>/dev/null | grep -v "/.Trash/")
}

get_latest_input() { ls -t "$LOCAL_IMPORTS"/FX_*.csv 2>/dev/null | head -1; }

# ── prepare: FX_*.csv → trade_input.csv 生成 → MT5 Files へ配置 ──
do_prepare() {
  local input_csv="$1"
  echo "[$(ts)] ▶ prepare_trade_input.py --input $(basename "$input_csv")"
  if python3 scripts/prepare_trade_input.py \
       --input "$input_csv" \
       --output "$DEST/trade_input.csv" 2>&1 | tail -3; then
    cp "$DEST/trade_input.csv" "$MT5_FILES/trade_input.csv"
    echo "[$(ts)] ✅ trade_input.csv を MT5 Files/ へ配置"
    echo "[$(ts)] 👉 MT5 で Trade_Snapshot_Builder を実行してください（環境再取得→trades_enriched.csv 出力）"
    return 0
  else
    echo "[$(ts)] ⚠️ prepare_trade_input.py 失敗"
    return 1
  fi
}

# ── merge: MT5出力 trades_enriched.csv → mt5_dataへ → enriched-full マージ ──
do_merge() {
  local input_csv="$1"
  cp "$MT5_FILES/trades_enriched.csv" "$DEST/trades_enriched.csv"
  echo "[$(ts)] ▶ merge（prepare_trade_input.py --enriched）"
  python3 scripts/prepare_trade_input.py \
    --input "$input_csv" \
    --output "$DEST/trade_input.csv" \
    --enriched "$DEST/trades_enriched.csv" \
    --enriched-full "$ENRICHED_FULL" 2>&1 | tail -5
}

# ── generate + publish: 日次カレンダー再生成 → docs公開 ──
# generate は run_daily_calendar.sh --no-open --no-publish に集約（publish は当方で run_to 付き）。
do_generate_publish() {
  echo "[$(ts)] ▶ generate（run_daily_calendar.sh --no-open --no-publish）"
  local rc=0
  ./run_daily_calendar.sh --no-open --no-publish > /tmp/_mani_rdc.txt 2>&1 || rc=$?
  grep -E "(OK 出力|トレード日数|期間|日次CSV|完了|Error|Traceback|❌|失敗|未受信)" /tmp/_mani_rdc.txt | head -10 || true
  if [ "$rc" -ne 0 ]; then
    echo "[$(ts)] ⚠️ run_daily_calendar 失敗 rc=$rc"
    echo "[$(ts)]    末尾: $(tail -3 /tmp/_mani_rdc.txt 2>/dev/null | tr '\n' ' ')"
    return 1
  fi
  echo "[$(ts)] ✅ 日次カレンダー再生成完了"

  # publish（最後の公開pushの1回だけ・run_to 付き・push前 pull）
  local PUBLISH_FILES=(
    "docs/trades_calendar.html"
    "docs/signals_calendar.html"
    "docs/daily_calendar_v3.html"
  )
  local TO_ADD=()
  for f in "${PUBLISH_FILES[@]}"; do
    [ -f "$f" ] || continue
    if [ -n "$(git status --porcelain -- "$f" 2>/dev/null)" ]; then
      TO_ADD+=("$f")
    fi
  done
  if [ ${#TO_ADD[@]} -eq 0 ]; then
    echo "[$(ts)] publish: 公開ファイルに差分なし（push不要）"
    return 0
  fi
  echo "[$(ts)] ▶ publish: ${TO_ADD[*]}"
  echo "[$(ts)]   push前 git pull --rebase --autostash（timeout ${GIT_PULL_TIMEOUT}s）"
  run_to "$GIT_PULL_TIMEOUT" git pull --rebase --autostash origin main \
    || echo "[$(ts)] ⚠️ push前 pull 失敗/timeout（続行）"
  if git add "${TO_ADD[@]}" 2>/dev/null \
     && git commit -q -m "data: update mani v3 calendar" -- "${TO_ADD[@]}"; then
    if run_to "$GIT_PUSH_TIMEOUT" git push origin main; then
      echo "[$(ts)] ✅ push 完了 → 数十秒で iPhone/iPad に反映"
    else
      echo "[$(ts)] ⚠️ git push 失敗/timeout（手動で git push してください）"
    fi
  else
    echo "[$(ts)] publish: commit対象なし"
  fi
}

# ============================================================
# モード分岐
# ============================================================
MODE="single"
for arg in "$@"; do
  case "$arg" in
    --watch) MODE="watch" ;;
  esac
done

if [ "$MODE" = "single" ]; then
  # ── 単発モード ──
  echo "[$(ts)] ── update_mani 単発 開始 ──"
  sync_icloud_imports
  INPUT_CSV=$(get_latest_input)
  if [ -z "$INPUT_CSV" ]; then
    echo "[$(ts)] ⚠️ FX_*.csv が見つからない（$LOCAL_IMPORTS）。iPhoneからCSVを投入してから再実行してください。"
    exit 1
  fi

  if [ -f "$MT5_FILES/trades_enriched.csv" ]; then
    # 既に enriched があれば prepare をスキップして merge→generate へ進める
    echo "[$(ts)] trades_enriched.csv が既に存在 → prepare をスキップして merge へ"
    do_merge "$INPUT_CSV"
    do_generate_publish
  else
    do_prepare "$INPUT_CSV" || exit 1
    echo ""
    echo "[$(ts)] ⏸ 手動ゲート: MT5 で Trade_Snapshot_Builder を実行 → trades_enriched.csv が出たら"
    echo "             もう一度 './update_mani.sh' を叩く（または '--watch' で自動検知）。"
    exit 0
  fi

  echo "[$(ts)] ── update_mani 単発 終了 ──"
  exit 0
fi

# ── watch モード（前景・ローカルmtime監視のみ・git pull ループ厳禁・1回成功で自動exit）──
echo "[$(ts)] ── update_mani --watch 開始（前景・ローカルmtime監視のみ・gitループ無し）──"
echo "[$(ts)]   FX_*.csv 新着 → prepare → MT5配置／trades_enriched.csv 更新 → merge→generate→publish→自動exit"
echo "[$(ts)]   停止: Ctrl+C"

sync_icloud_imports
# ベースライン: 現在の FX 最新シグネチャ と enriched mtime を記録（これ以降の変化だけ拾う）
last_fx=$(get_latest_input)
last_fx_sig="none"
[ -n "$last_fx" ] && last_fx_sig="$last_fx:$(stat -f %m "$last_fx" 2>/dev/null || echo 0)"

ENRICHED_SRC="$MT5_FILES/trades_enriched.csv"
if [ -f "$ENRICHED_SRC" ]; then
  last_enriched_mtime=$(stat -f %m "$ENRICHED_SRC" 2>/dev/null || echo 0)
else
  last_enriched_mtime=0
fi

prepared_input=""

while true; do
  # ── iCloud → imports 橋渡し（ローカルファイル操作のみ・git不使用）──
  sync_icloud_imports

  # ── FX_*.csv 新着検知 → prepare → MT5配置 ──
  cur_fx=$(get_latest_input)
  cur_fx_sig="none"
  [ -n "$cur_fx" ] && cur_fx_sig="$cur_fx:$(stat -f %m "$cur_fx" 2>/dev/null || echo 0)"
  if [ "$cur_fx_sig" != "$last_fx_sig" ] && [ "$cur_fx_sig" != "none" ]; then
    last_fx_sig="$cur_fx_sig"
    echo ""
    echo "[$(ts)] ▶ FX_*.csv 新着検知: $(basename "$cur_fx")"
    sleep "$WRITE_SETTLE"
    if do_prepare "$cur_fx"; then
      prepared_input="$cur_fx"
    fi
  fi

  # ── trades_enriched.csv 更新検知 → merge → generate → publish → 自動exit ──
  if [ -f "$ENRICHED_SRC" ]; then
    cur_enriched_mtime=$(stat -f %m "$ENRICHED_SRC" 2>/dev/null || echo 0)
    if [ "$cur_enriched_mtime" -gt "$last_enriched_mtime" ]; then
      last_enriched_mtime="$cur_enriched_mtime"
      echo ""
      echo "[$(ts)] ▶ trades_enriched.csv 更新検知 → merge→generate→publish"
      sleep "$WRITE_SETTLE"
      INPUT_CSV="$prepared_input"
      [ -z "$INPUT_CSV" ] && INPUT_CSV=$(get_latest_input)
      if [ -z "$INPUT_CSV" ]; then
        echo "[$(ts)] ⚠️ FX_*.csv が見つからない → merge スキップ（FX投入後にやり直し）"
      else
        do_merge "$INPUT_CSV"
        if do_generate_publish; then
          echo ""
          echo "[$(ts)] ✅ 系統A 反映完了 → 自動exit"
          exit 0
        else
          echo "[$(ts)] ⚠️ generate/publish 失敗。enriched を再出力すれば再検知します。"
        fi
      fi
    fi
  fi

  sleep "$POLL_INTERVAL"
done
