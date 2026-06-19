#!/usr/bin/env bash
# ============================================================
# vps_data_pool_push.sh — VPS日次データプール 製造→push（全自動）
# ============================================================
# 設計書: data/vps/日次動脈_DESIGN_v1.md §5
# 役割  : VPSのMT5 EAが毎時焼く日次CSV(③)を mt5_data/daily/ へ集め、
#         git経由でMacへ渡す「データプール製造」の動脈。
# 起動  : Windowsタスクスケジューラから Git Bash 経由（§7）
#         例) "C:\Program Files\Git\bin\bash.exe" -lc \
#              "/c/Users/Administrator/adxscore-heatmap/scripts/vps_data_pool_push.sh"
# 注意  : ③(daily/)以外には絶対 add しない＝①手描き波形/②自動集計のMac領域を侵さない
# ============================================================
set -uo pipefail

REPO="/c/Users/Administrator/adxscore-heatmap"
MT5_FILES="/c/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Files"
POOL="$REPO/mt5_data/daily"
LOG="$REPO/vps_pool.log"
DAILY_FILES=( "signal_fires.csv" "daily_aggregate.csv" "daily_mfe_mae_48h.csv" )

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG"; }

cd "$REPO" || { log "ERROR: repo not found ($REPO)"; exit 1; }
mkdir -p "$POOL"

# DRY_RUN=1 で読み取りのみ（コピー/pull/push せず対象を表示）= フェーズ2の安全テスト用
#   使い方: DRY_RUN=1 bash scripts/vps_data_pool_push.sh
DRY_RUN="${DRY_RUN:-0}"
if [ "$DRY_RUN" = "1" ]; then
  log "=== DRY_RUN（読み取りのみ・git不変）==="
  for f in "${DAILY_FILES[@]}"; do
    if [ -f "$MT5_FILES/$f" ]; then
      log "  would copy: $f ($(wc -l <"$MT5_FILES/$f")行 / $(date -r "$MT5_FILES/$f" '+%m-%d %H:%M'))"
    else
      log "  MISSING: $f（EA未稼働?）"
    fi
  done
  log "DRY_RUN end"
  exit 0
fi

# 1. MT5 Files → daily/ コピー（_EA suffix は検証名残なので拾わない）
copied=0
for f in "${DAILY_FILES[@]}"; do
  if [ -f "$MT5_FILES/$f" ]; then
    cp "$MT5_FILES/$f" "$POOL/$f" && copied=$((copied+1))
  else
    log "WARN: 未生成 $f（EA未稼働?）"
  fi
done
log "copied=$copied/3"

# 2. 変更が無ければ無駄commitしない
if [ -z "$(git status --porcelain mt5_data/daily/)" ]; then
  log "no change → skip"; exit 0
fi

# 3. 合流（Mac watcherと同main）。--autostash で念のため安全に
if ! git pull --rebase --autostash origin main >>"$LOG" 2>&1; then
  log "ERROR: pull --rebase 失敗 → 手動介入要"; exit 2
fi

# 4. daily/ のみ add（②週次や①手描きには触らない）→ commit → push
git add mt5_data/daily/
git commit -q -m "data: VPS pool update $(ts)" || { log "commit skip"; exit 0; }
if git push -q origin main >>"$LOG" 2>&1; then
  log "OK push 完了 (copied=$copied)"
else
  log "WARN push 失敗（次回起動でフル上書き済みCSVごと回収）"; exit 3
fi
