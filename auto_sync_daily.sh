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

# iCloud入口（iPhoneアプリ → 共有シート"ファイルに保存" → ここ）→ ローカルimportsへ橋渡し
# AirDrop手動を廃止。ADXSCORE直下/imports どちらに保存されても拾う
ICLOUD_IMPORTS="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ADXSCORE"
LOCAL_IMPORTS="data/mani_room/raw/imports"

# 監視対象（Mac MT5 mq5 が出力する CSV）— 系統A 成績のみ（Mac専管・iPhone入力由来）
# ⚠️ VPS由来3つ（signal_fires / daily_aggregate / daily_mfe_mae_48h）は Mac MT5 Files に
#    出力されない＝ここで監視しても永遠に空振り。VPSが git push する → 下部「git pull検知」で拾う。
TARGETS=("trades_enriched.csv")

# 監視対象（週次マップ用）— 更新されたら run_pipeline.sh で週次ヒートマップを再生成
# WaveLog にライン引き → MT5 週次スクリプトを回す → ここが検知して自動で最新版＆push
WEEKLY_TARGETS=(
  "FractalWaveLog_D1_v3_1.csv"
  "FractalWaveLog_D1_weekly.csv"
  "FractalWaveLog_H4_XAU.csv"
  "FractalWaveLog_H4_weekly.csv"
  "FractalWaveLog_H4_XAU_Vlines.csv"
  "H4PhaseAuto_weekly.csv"
  "ADX_Weekly_Above_v4.csv"
)

POLL_INTERVAL=2
WRITE_SETTLE=2     # MT5 書き込み完了待ち（日次・単発出力）
WEEKLY_SETTLE=10   # 週次は4スクリプト連続出力のためデバウンス長め
GIT_CHECK_INTERVAL=60  # VPS push 取込: git fetch/pull は60秒に1回（2秒ポーリングとは別カウンタ）

# 入力 CSV の最新版（FX_*.csv）
get_latest_input() {
  ls -t data/mani_room/raw/imports/FX_*.csv 2>/dev/null | head -1
}

# FX_*.csv の状態シグネチャ（最新ファイルパス + mtime）
get_fx_signature() {
  local f
  f=$(get_latest_input)
  if [ -n "$f" ]; then
    echo "$f:$(stat -f %m "$f")"
  else
    echo "none"
  fi
}

# iCloud入口の新着 FX_*.csv をローカル imports へ橋渡し（AirDrop不要化）
# ADXSCORE直下と imports/ の両方を拾う（maxdepth 2）。プレースホルダは実体DLしてからcp
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

ts() { date +"%H:%M:%S"; }

# ── run_daily_calendar を exit code 検知付きで実行（穴2修正）──
# 旧コードは `run_daily_calendar | grep | head` のパイプで exit code を握りつぶし、
# 失敗しても無条件「✅完了」と出していた（サイレント失敗）。ここで rc を直接取得して
# 成否を判定し、失敗は ⚠️ で可視化する。set -e 下で watcher 自体が死なないよう
# `|| rc=$?` でガード（|| があると set -e は発動しない）。
run_daily_safe() {
  local reason="$1"
  local rc=0
  echo "[$(ts)]   run_daily_calendar.sh --no-open 実行（trigger=$reason）"
  ./run_daily_calendar.sh --no-open > /tmp/_watcher_rdc.txt 2>&1 || rc=$?
  grep -E "(OK 出力|トレード日数|期間|日次CSV|完了|Error|Traceback|❌|失敗)" /tmp/_watcher_rdc.txt | head -10 || true
  if [ "$rc" -eq 0 ]; then
    echo "[$(ts)] ✅ 日次カレンダー再生成完了（trigger=$reason）"
  else
    echo "[$(ts)] ⚠️ run_daily_calendar 失敗 rc=$rc（trigger=$reason・次サイクルで鮮度照合が自動再試行）"
    echo "[$(ts)]    末尾: $(tail -3 /tmp/_watcher_rdc.txt 2>/dev/null | tr '\n' ' ')"
  fi
}

# ── 鮮度照合トリガー（HEAD進行に依存しない再生成保証）──
# 旧 check_git_pull は「HEADがorigin/mainより遅れてるか」だけをトリガーにしていたため、
# watcher以外がpullしてHEADが追いつくと再生成を取りこぼした。さらに一時障害(git交錯)で
# run_daily_calendar がコケても HEAD は進むので二度と再生成されなかった。
# 対策: daily/CSV が生成HTMLより新しければ無条件で再生成。誰がpullしようと・一時障害が
# あっても、次サイクルで CSV>HTML を検知して自動回復する（毎時エラーカバー思想）。
check_freshness() {
  local csv_latest csv_mtime gen_html html_mtime
  csv_latest=$(ls -t mt5_data/daily/*.csv 2>/dev/null | head -1)
  [ -z "$csv_latest" ] && return 0
  csv_mtime=$(stat -f %m "$csv_latest" 2>/dev/null || echo 0)
  gen_html="data/trades/processed/daily_calendar_v3.html"
  if [ -f "$gen_html" ]; then
    html_mtime=$(stat -f %m "$gen_html" 2>/dev/null || echo 0)
  else
    html_mtime=0
  fi
  if [ "$csv_mtime" -gt "$html_mtime" ]; then
    echo ""
    echo "[$(ts)] ▶ 鮮度照合: daily/CSV($(date -r "$csv_mtime" +%H:%M:%S)) > 生成HTML($(date -r "$html_mtime" +%H:%M:%S)) → 再生成漏れ検知"
    run_daily_safe "鮮度照合"
  fi
}

# ── VPS が push した daily/ を git pull で取込 ──
# Mac MT5 には出ないCSV（系統B/C）はファイル監視では拾えない。VPSが GitHub main へ
# push する → ここで origin/main の進行を検知 → pull → daily/ に差分あれば日次カレンダー再生成。
# set -e 下でも watcher が死なないよう、各 git 呼び出しは || / if でガードする。
check_git_pull() {
  git fetch origin main --quiet >/dev/null 2>&1 || return 0
  local local_head=$(git rev-parse HEAD 2>/dev/null || echo local)
  local remote_head=$(git rev-parse origin/main 2>/dev/null || echo remote)
  [ "$local_head" = "$remote_head" ] && return 0
  # pull すると HEAD が進むため、daily/ の差分有無は pull 前に判定する
  local daily_changed=$(git diff --name-only HEAD origin/main -- mt5_data/daily/ 2>/dev/null)
  echo ""
  echo "[$(ts)] ▶ origin/main 更新検知 → git pull --rebase --autostash"
  if git pull --rebase --autostash origin main >/dev/null 2>&1; then
    if [ -n "$daily_changed" ]; then
      echo "[$(ts)]   daily/ 更新あり（git pull検知）"
      run_daily_safe "VPS daily 合流"
    else
      echo "[$(ts)] ✅ git pull 完了（daily/ 変更なし＝週次②等の取込のみ）"
    fi
  else
    echo "[$(ts)] ⚠️ git pull 失敗（watcher継続・次回 ${GIT_CHECK_INTERVAL}s 後に再試行）"
  fi
}

echo "╔══════════════════════════════════════════════════╗"
echo "║   MT5 自動同期 watcher 起動                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  MT5 Files: $MT5_FILES"
echo "  ターゲット(Mac MT5): ${TARGETS[*]}"
echo "  VPS push取込: git pull検知 ${GIT_CHECK_INTERVAL}s毎 → daily/ 更新で日次カレンダー再生成"
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
# 週次CSV の初期 mtime（既存ファイルは初回スキップ）
LAST_WEEKLY_MTIMES=()
for i in "${!WEEKLY_TARGETS[@]}"; do
  f="${WEEKLY_TARGETS[$i]}"
  SRC="$MT5_FILES/$f"
  if [ -f "$SRC" ]; then
    LAST_WEEKLY_MTIMES[$i]=$(stat -f %m "$SRC")
  else
    LAST_WEEKLY_MTIMES[$i]=0
  fi
done
echo "  [初期] 週次CSV ${#WEEKLY_TARGETS[@]}本を監視"
# FX_*.csv（アプリ書き出しCSV）の新着監視
LAST_FX_SIG=$(get_fx_signature)
echo "  [初期] FX_*.csv sig=$LAST_FX_SIG"
echo ""
echo "[$(ts)] 監視開始..."

trap 'echo ""; echo "[$(ts)] 監視停止"; exit 0' INT TERM

GIT_CHECK_COUNTER=0  # ループ累積秒。GIT_CHECK_INTERVAL 到達で check_git_pull 発火

while true; do
  # ── iCloud入口 → ローカルimports 橋渡し（AirDrop不要化）──
  sync_icloud_imports

  # ── FX_*.csv 新着検知 → trade_input.csv 生成 → MT5 Files/ へ自動配置 ──
  FX_SIG=$(get_fx_signature)
  if [ "$FX_SIG" != "$LAST_FX_SIG" ] && [ "$FX_SIG" != "none" ]; then
    LAST_FX_SIG="$FX_SIG"
    echo ""
    echo "[$(ts)] ▶ FX_*.csv 新着検知: ${FX_SIG%%:*}"
    sleep $WRITE_SETTLE
    if PREP_OUT=$(python3 scripts/prepare_trade_input.py \
        --input "${FX_SIG%%:*}" \
        --output "$DEST/trade_input.csv" 2>&1); then
      echo "$PREP_OUT" | tail -3
      cp "$DEST/trade_input.csv" "$MT5_FILES/trade_input.csv"
      echo "[$(ts)] ✅ trade_input.csv を MT5 Files/ へ配置 — MT5 で Trade_Snapshot_Builder を実行してね"
    else
      echo "$PREP_OUT" | tail -5
      echo "[$(ts)] ⚠️ prepare_trade_input.py 失敗、MT5 配置スキップ"
    fi
  fi

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
    run_daily_safe "trades_enriched 更新"
  fi

  # ── 週次CSV 更新検知 → run_pipeline.sh で週次ヒートマップ再生成 ──
  WEEKLY_CHANGED=()
  for i in "${!WEEKLY_TARGETS[@]}"; do
    f="${WEEKLY_TARGETS[$i]}"
    SRC="$MT5_FILES/$f"
    if [ -f "$SRC" ]; then
      NEW_MTIME=$(stat -f %m "$SRC")
      if [ "$NEW_MTIME" -gt "${LAST_WEEKLY_MTIMES[$i]}" ]; then
        WEEKLY_CHANGED+=("$f")
        LAST_WEEKLY_MTIMES[$i]=$NEW_MTIME
      fi
    fi
  done

  if [ ${#WEEKLY_CHANGED[@]} -gt 0 ]; then
    echo ""
    echo "[$(ts)] ▶ 週次CSV 更新検知: ${WEEKLY_CHANGED[*]}"
    echo "[$(ts)]   週次は複数スクリプト連続出力 → ${WEEKLY_SETTLE}s デバウンス待ち..."
    sleep $WEEKLY_SETTLE
    # デバウンス中に書かれた残りの週次CSVの mtime も取り込む（多重起動防止）
    for i in "${!WEEKLY_TARGETS[@]}"; do
      f="${WEEKLY_TARGETS[$i]}"
      SRC="$MT5_FILES/$f"
      [ -f "$SRC" ] && LAST_WEEKLY_MTIMES[$i]=$(stat -f %m "$SRC")
    done
    echo "[$(ts)]   run_pipeline.sh --no-open 実行（週次HM再生成→iCloud→push）"
    if ./run_pipeline.sh --no-open 2>&1 | grep -E "(Step|完了|iCloud|GitHub|push|更新|⚠️)" | head -15; then
      echo "[$(ts)] ✅ 週次パイプライン完了 — Widget Web は次回更新で最新版"
    else
      echo "[$(ts)] ⚠️ run_pipeline.sh でエラー（watcher は継続）"
    fi
  fi

  # ── VPS push 取込: origin/main の進行を GIT_CHECK_INTERVAL 毎に git pull検知 ──
  GIT_CHECK_COUNTER=$((GIT_CHECK_COUNTER + POLL_INTERVAL))
  if [ "$GIT_CHECK_COUNTER" -ge "$GIT_CHECK_INTERVAL" ]; then
    GIT_CHECK_COUNTER=0
    check_git_pull
    # 鮮度照合: check_git_pull が(HEAD依存で)取りこぼしても、CSV>HTMLなら再生成して自動回復
    check_freshness
  fi

  sleep $POLL_INTERVAL
done
