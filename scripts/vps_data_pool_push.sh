#!/usr/bin/env bash
# ============================================================
# vps_data_pool_push.sh — VPS日次データプール 製造→push（全自動）
# ============================================================
# 設計書: data/vps/日次動脈_DESIGN_v1.md §5 / §13（②VPS書き移行 2026-06-26）
# 役割  : VPSのMT5 EAが毎時焼く ②自動集計(mt5_data/直下) と ③日次CSV(mt5_data/daily/) を集め、
#         git経由でMacへ渡す「データプール製造」の動脈。
# 起動  : Windowsタスクスケジューラから Git Bash 経由（§7）
#         例) "C:\Program Files\Git\bin\bash.exe" -lc \
#              "/c/Users/Administrator/adxscore-heatmap/scripts/vps_data_pool_push.sh"
# 注意  : 運ぶのは ②(ADX_Weekly_Above_v4 / H4PhaseAuto_weekly・UTF-16) と ③(daily/) のみ。
#         ①手描き波形(FractalWaveLog) は Mac聖域＝絶対に add しない。
# 詰まり対策(2026-07-05): git push が網/認証で無限ハング→IgnoreNewと相まって
#         動脈が56h沈黙した（7/3 00:00〜7/5 08:00）。対話プロンプト禁止＋
#         git通信にタイムアウト＝固まる代わりに即failし、次の毎時起動が
#         フル上書き済みCSVと未pushコミットごと回収する設計に倒す。
# ============================================================
set -uo pipefail

# git を対話不能に（Credential Manager のUI待ちハング防止）
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never
GIT_TIMEOUT=120   # git pull / push の上限秒（超えたら殺して次の毎時に回す）

REPO="/c/Users/Administrator/adxscore-heatmap"
MT5_FILES="/c/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Files"
POOL="$REPO/mt5_data/daily"
MT5DATA="$REPO/mt5_data"
LOG="$REPO/vps_pool.log"
DAILY_FILES=( "signal_fires.csv" "daily_aggregate.csv" "daily_mfe_mae_48h.csv" "dxy_env.csv" )
# dxy_env.csv: DXY環境札（系統B EA v1.10 出力・2026-07-15追加）。EA差替え前は
# 「WARN: 未生成」が出るが正常（デプロイ後に自己回復）。git add側は
# mt5_data/daily/ 丸ごとなので、追加箇所はこのコピー用リストだけ。
# ② 自動集計（2026-06-26 VPS書き移行）。UTF-16のまま mt5_data/ 直下へコピー（daily/ ではない）。
# EA出力名: ADX_Weekly_Above_EA_v1→ADX_Weekly_Above_v4.csv / ARO_H4PhaseAuto_EA_v1→H4PhaseAuto_weekly.csv
AGG_FILES=( "ADX_Weekly_Above_v4.csv" "H4PhaseAuto_weekly.csv" )
# git pathspec 用（mt5_data/ 直下の相対パス）
AGG_PATHS=()
for _f in "${AGG_FILES[@]}"; do AGG_PATHS+=( "mt5_data/$_f" ); done

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
      log "  would copy [③daily]: $f ($(wc -l <"$MT5_FILES/$f")行 / $(date -r "$MT5_FILES/$f" '+%m-%d %H:%M')) → mt5_data/daily/"
    else
      log "  MISSING [③daily]: $f（③EA未稼働?）"
    fi
  done
  for f in "${AGG_FILES[@]}"; do
    if [ -f "$MT5_FILES/$f" ]; then
      log "  would copy [②agg]:   $f ($(wc -l <"$MT5_FILES/$f")行 / $(date -r "$MT5_FILES/$f" '+%m-%d %H:%M')) → mt5_data/直下"
    else
      log "  MISSING [②agg]:   $f（②EA未アタッチ?）"
    fi
  done
  log "DRY_RUN end"
  exit 0
fi

# 1. MT5 Files → コピー（_EA suffix は検証名残なので拾わない）
#    ③日次 → mt5_data/daily/ ／ ②自動集計 → mt5_data/直下
copied=0
for f in "${DAILY_FILES[@]}"; do
  if [ -f "$MT5_FILES/$f" ]; then
    cp "$MT5_FILES/$f" "$POOL/$f" && copied=$((copied+1))
  else
    log "WARN: 未生成 $f（③EA未稼働?）"
  fi
done
agg_copied=0
for f in "${AGG_FILES[@]}"; do
  if [ -f "$MT5_FILES/$f" ]; then
    cp "$MT5_FILES/$f" "$MT5DATA/$f" && agg_copied=$((agg_copied+1))
  else
    log "WARN: 未生成 $f（②EA未アタッチ?）"
  fi
done
log "copied: ③daily=$copied/${#DAILY_FILES[@]} ②agg=$agg_copied/${#AGG_FILES[@]}"

# 2. 変更が無ければ無駄commitしない（②③両方を見る）
#    ただし commit済み・push未達 の取り残しがあれば、変更ゼロでも回収しに行く
unpushed=$(git rev-list --count origin/main..main 2>/dev/null || echo 1)
if [ -z "$(git status --porcelain mt5_data/daily/ "${AGG_PATHS[@]}")" ] && [ "$unpushed" = "0" ]; then
  log "no change → skip"; exit 0
fi

# 3. 合流（Mac watcherと同main）。--autostash で念のため安全に
#    タイムアウト時は中途rebaseを掃除してから次の毎時に回す
if ! timeout "$GIT_TIMEOUT" git pull --rebase --autostash origin main >>"$LOG" 2>&1; then
  git rebase --abort >/dev/null 2>&1 || true
  log "ERROR: pull --rebase 失敗/タイムアウト → 次回毎時で再試行"; exit 2
fi

# 4. ②(mt5_data/直下)＋③(daily/) を add（①手描きwavelogには触らない）→ commit → push
#    commit対象が無くても未pushコミットが残っていれば push は実行する
git add mt5_data/daily/ "${AGG_PATHS[@]}"
git commit -q -m "data: VPS pool update $(ts)" || log "commit なし（未push分の回収のみ）"
if [ "$(git rev-list --count origin/main..main 2>/dev/null || echo 1)" = "0" ]; then
  log "push対象なし → skip"; exit 0
fi
if timeout "$GIT_TIMEOUT" git push -q origin main >>"$LOG" 2>&1; then
  log "OK push 完了 (③daily=$copied ②agg=$agg_copied)"
else
  log "WARN push 失敗/タイムアウト（次回起動でフル上書き済みCSVと未pushコミットごと回収）"; exit 3
fi
