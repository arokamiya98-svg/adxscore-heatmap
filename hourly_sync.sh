#!/bin/bash
# ============================================================
# hourly_sync.sh — 毎時1回の単発同期ジョブ（常駐しない）
# ============================================================
# 半自動化建て直し v1（ブン指示書 §4(A)）。
# 旧 auto_sync_daily.sh の「常時24h × 60秒 git-pull ループ」を廃止し、
# VPS受信(②)＋週次再生成(④)を「毎時1回走って必ず終わる」ジョブに隔離する。
# スケジューリングは launchd（com.aro.adxscore.hourly / Minute=10）に委ねる。
#
# 役割:
#   - VPSの毎時pushを git pull で受信（run_to で timeout 囲い）
#   - daily/*.csv が日次生成HTMLより新しければ run_daily_calendar.sh を回す
#   - 週次CSV(MT5 Files→mt5_data同期込み)が週次生成物より新しければ run_pipeline.sh を回す
#   - 変更があった分だけ publish push（push前 git pull・run_to 付き）
#   - 終了する（while/sleep の常駐ループ禁止）
#
# 使い方:
#   ./hourly_sync.sh            # 単発実行（launchd が毎時起動）
#
# 禁止:
#   while/sleep 常駐ループ・nohup デーモン化。1回走って必ず終わる。
# ============================================================

set -e
cd "$(dirname "$0")"

MT5_FILES="/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files"
DEST="mt5_data"

# 週次CSV（MT5 Files → mt5_data 同期対象。run_pipeline.sh が sync_mt5_data.sh で同期する）
WEEKLY_TARGETS=(
  "FractalWaveLog_D1_v3_1.csv"
  "FractalWaveLog_D1_weekly.csv"
  "FractalWaveLog_H4_XAU.csv"
  "FractalWaveLog_H4_weekly.csv"
  "FractalWaveLog_H4_XAU_Vlines.csv"
  "H4PhaseAuto_weekly.csv"
  "ADX_Weekly_Above_v4.csv"
)

# 日次カレンダー publish 対象（run_daily_calendar.sh と同一。--no-publish で publish を当方に集約）
PUBLISH_FILES_DAILY=(
  "docs/trades_calendar.html"
  "docs/signals_calendar.html"
  "docs/daily_calendar_v3.html"
)

GIT_FETCH_TIMEOUT=15
GIT_PULL_TIMEOUT=45
GIT_PUSH_TIMEOUT=30

LOCKDIR="/tmp/adxscore_hourly_sync.lock"

ts() { date +"%H:%M:%S"; }

# ── ポータブル timeout（auto_sync_daily.sh から流用・同一実装）──
# run_to <秒> <コマンド...> : 最大<秒>で実行、超過で TERM→2s後 KILL。戻り値=コマンドrc。
# git は内蔵 timeout が無く、ロック競合/CPU飢餓で無限待ち → Bashハングの温床。ここで強制的に断つ。
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

# ── 多重起動ガード（atomic mkdir lock）──
# mkdir はアトミック。既に走っていれば即 exit。終了時に必ず lock を外す。
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "[$(ts)] 別の hourly_sync が稼働中（lock: $LOCKDIR）→ 即exit"
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT INT TERM

echo "[$(ts)] ── hourly_sync 開始 ──────────────────────────"

# ── Step 1: VPS受信（git fetch → pull）run_to で囲う ───────────
# 失敗/timeout はログして続行（次の毎時で自己回復）。
echo "[$(ts)] git fetch origin main（timeout ${GIT_FETCH_TIMEOUT}s）"
if run_to "$GIT_FETCH_TIMEOUT" git fetch origin main --quiet; then
  LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo local)
  REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo remote)
  if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    echo "[$(ts)] origin/main 更新検知 → git pull --rebase --autostash（timeout ${GIT_PULL_TIMEOUT}s）"
    if run_to "$GIT_PULL_TIMEOUT" git pull --rebase --autostash origin main; then
      echo "[$(ts)] ✅ git pull 完了"
    else
      echo "[$(ts)] ⚠️ git pull 失敗/timeout（続行・次の毎時で自己回復）"
    fi
  else
    echo "[$(ts)] origin/main 変更なし（pull不要）"
  fi
else
  echo "[$(ts)] ⚠️ git fetch 失敗/timeout（続行・次の毎時で自己回復）"
fi

DID_DAILY=false
DID_WEEKLY=false

# ── Step 2: 日次（②）鮮度照合 → run_daily_calendar.sh ─────────
# daily/*.csv が生成HTML(daily_calendar_v3.html)より新しければ再生成。
GEN_HTML="data/trades/processed/daily_calendar_v3.html"
CSV_LATEST=$(ls -t mt5_data/daily/*.csv 2>/dev/null | head -1)
if [ -n "$CSV_LATEST" ]; then
  CSV_MTIME=$(stat -f %m "$CSV_LATEST" 2>/dev/null || echo 0)
  if [ -f "$GEN_HTML" ]; then
    HTML_MTIME=$(stat -f %m "$GEN_HTML" 2>/dev/null || echo 0)
  else
    HTML_MTIME=0
  fi
  if [ "$CSV_MTIME" -gt "$HTML_MTIME" ]; then
    echo "[$(ts)] ▶ 日次: daily/CSV > 生成HTML → run_daily_calendar.sh --no-open --no-publish"
    rc=0
    ./run_daily_calendar.sh --no-open --no-publish > /tmp/_hourly_rdc.txt 2>&1 || rc=$?
    grep -E "(OK 出力|トレード日数|期間|日次CSV|完了|Error|Traceback|❌|失敗|未受信)" /tmp/_hourly_rdc.txt | head -10 || true
    if [ "$rc" -eq 0 ]; then
      echo "[$(ts)] ✅ 日次カレンダー再生成完了"
      DID_DAILY=true
    else
      echo "[$(ts)] ⚠️ run_daily_calendar 失敗 rc=$rc（次の毎時で再試行）"
      echo "[$(ts)]    末尾: $(tail -3 /tmp/_hourly_rdc.txt 2>/dev/null | tr '\n' ' ')"
    fi
  else
    echo "[$(ts)] 日次: daily/CSV は生成HTMLより新しくない（再生成不要）"
  fi
else
  echo "[$(ts)] 日次: mt5_data/daily/*.csv 未受信（スキップ）"
fi

# ── Step 3: 週次（④）鮮度照合 → run_pipeline.sh ──────────────
# MT5 Files の週次CSV が週次生成物(weekly_waves.json)より新しければ再生成。
# run_pipeline.sh が sync_mt5_data.sh で MT5 Files → mt5_data 同期する。
WEEKLY_GEN="data/weekly_waves.json"
if [ -f "$WEEKLY_GEN" ]; then
  WEEKLY_GEN_MTIME=$(stat -f %m "$WEEKLY_GEN" 2>/dev/null || echo 0)
else
  WEEKLY_GEN_MTIME=0
fi
WEEKLY_NEWER=false
for f in "${WEEKLY_TARGETS[@]}"; do
  SRC="$MT5_FILES/$f"
  if [ -f "$SRC" ]; then
    M=$(stat -f %m "$SRC" 2>/dev/null || echo 0)
    if [ "$M" -gt "$WEEKLY_GEN_MTIME" ]; then
      WEEKLY_NEWER=true
      break
    fi
  fi
done
if [ "$WEEKLY_NEWER" = true ]; then
  echo "[$(ts)] ▶ 週次: MT5 Files 週次CSV > weekly_waves.json → run_pipeline.sh --no-open"
  rc=0
  ./run_pipeline.sh --no-open > /tmp/_hourly_pipe.txt 2>&1 || rc=$?
  grep -E "(Step|完了|iCloud|GitHub|push|更新|⚠️|Error|Traceback)" /tmp/_hourly_pipe.txt | head -15 || true
  if [ "$rc" -eq 0 ]; then
    echo "[$(ts)] ✅ 週次パイプライン完了"
    DID_WEEKLY=true
  else
    echo "[$(ts)] ⚠️ run_pipeline.sh 失敗 rc=$rc（次の毎時で再試行）"
    echo "[$(ts)]    末尾: $(tail -3 /tmp/_hourly_pipe.txt 2>/dev/null | tr '\n' ' ')"
  fi
else
  echo "[$(ts)] 週次: 週次CSV は weekly_waves.json より新しくない（再生成不要）"
fi

# ── Step 4: publish push（変更分だけ・run_to 付き・push前 pull）─
# 日次は --no-publish で当方に集約。週次(run_pipeline.sh)は内蔵で既にpush済の可能性が
# あるが、その場合ここは差分なしで no-op になる（二重push防止）。
PUBLISH_FILES=("${PUBLISH_FILES_DAILY[@]}")
# 週次成果物も拾う（run_pipeline.sh が push 済なら git status は clean → no-op）
PUBLISH_FILES+=("docs/heatmap_v14.html" "data/weekly_waves.json")

if [ "$DID_DAILY" = true ] || [ "$DID_WEEKLY" = true ]; then
  # 実在し、かつ差分があるファイルだけを add 対象にする
  TO_ADD=()
  for f in "${PUBLISH_FILES[@]}"; do
    [ -f "$f" ] || continue
    if [ -n "$(git status --porcelain -- "$f" 2>/dev/null)" ]; then
      TO_ADD+=("$f")
    fi
  done
  if [ ${#TO_ADD[@]} -gt 0 ]; then
    echo "[$(ts)] ▶ publish: ${TO_ADD[*]}"
    echo "[$(ts)]   push前 git pull --rebase --autostash（timeout ${GIT_PULL_TIMEOUT}s）"
    run_to "$GIT_PULL_TIMEOUT" git pull --rebase --autostash origin main \
      || echo "[$(ts)] ⚠️ push前 pull 失敗/timeout（続行・push が衝突したら次の毎時で回復）"
    if git add "${TO_ADD[@]}" 2>/dev/null \
       && git commit -q -m "chore: hourly_sync auto-publish" -- "${TO_ADD[@]}"; then
      if run_to "$GIT_PUSH_TIMEOUT" git push origin main; then
        echo "[$(ts)] ✅ push 完了"
      else
        echo "[$(ts)] ⚠️ git push 失敗/timeout（次の毎時で再試行）"
      fi
    else
      echo "[$(ts)] publish: commit対象なし（既にpush済 or 差分消失）"
    fi
  else
    echo "[$(ts)] publish: 公開ファイルに差分なし（再生成したが内容同一 or 内蔵pushで済）"
  fi
else
  echo "[$(ts)] publish: 日次・週次とも再生成なし → push不要"
fi

echo "[$(ts)] ── hourly_sync 終了 ──────────────────────────"
exit 0
