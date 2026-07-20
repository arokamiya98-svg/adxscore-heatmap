#!/bin/bash
# ============================================================
# run_daily_calendar.sh — 日次研究カレンダー パイプライン
# ============================================================
# 振り返りフェーズ専用: 過去環境と過去トレードの照合を視覚化
# 戦略・実行とは分離 (フロー理論ベース)
# ============================================================
# 手順:
#   1. MT5 出力 (daily_*.csv) を mt5_data/ にコピー
#   2. generate_daily_calendar.py 実行 → trades_calendar.html 生成
#   3. ブラウザで開く (optional)
# ============================================================
# 使い方:
#   ./run_daily_calendar.sh             # 同期 + 生成 + 開く
#   ./run_daily_calendar.sh --no-open   # ブラウザ開かない
#   ./run_daily_calendar.sh --no-sync   # MT5同期スキップ
# ============================================================

set -e
cd "$(dirname "$0")"

OPEN_BROWSER=true
DO_SYNC=true
DO_PUBLISH=true
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN_BROWSER=false ;;
    --no-sync) DO_SYNC=false ;;
    --no-publish) DO_PUBLISH=false ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   日次研究カレンダー パイプライン (振り返り)      ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

MT5_FILES="/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files"
DEST="mt5_data"

# ── Step 1: 日次データプール daily/ の受信確認 ────────────────
# daily/ の③(signal_fires / daily_aggregate / daily_mfe_mae_48h)は
# VPSのEA(DailyBatch/SignalFire)が毎時焼いて push する「正本」。
# Macは git pull で受信するだけ＝ここではコピーせず存在確認のみ行う。
#   設計: data/vps/日次動脈_DESIGN_v1.md §1 / 原則「daily/はVPS正本・Macは上書きしない」
# ※Macは日次EAを回さない。Mac MT5は週次(手描きWaveLog)専用＝VPSとの専管住み分け。
if [ "$DO_SYNC" = true ]; then
  echo "▶ Step 1: 日次データプール daily/ 受信確認（VPS正本・Macは上書きしない）"
  POOL_FILES=(
    "daily_aggregate.csv"     # C2: 日次集計 D1/H4/H1 ADX/DI/ATR
    "daily_mfe_mae_48h.csv"   # C1: 非トレード日 48h MFE/MAE
    "signal_fires.csv"        # シグナル発火ログ
  )
  MISSING=0
  for fname in "${POOL_FILES[@]}"; do
    if [ ! -f "$DEST/daily/$fname" ]; then
      echo "  ⚠️  未受信: mt5_data/daily/$fname"
      MISSING=$((MISSING+1))
    else
      MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$DEST/daily/$fname")
      echo "  ✅ $fname  ($MTIME)"
    fi
  done

  if [ $MISSING -gt 0 ]; then
    echo ""
    echo "❌ daily/ のデータプールが未受信です（$MISSING 本不足）。"
    echo "   先に 'git pull --rebase origin main' で VPS のプールを受信してください。"
    echo "   ※daily/ はVPSが正本。Mac MT5 からはコピーしません（設計書§1）。"
    exit 1
  fi
else
  echo "▶ Step 1: daily/ 受信確認スキップ (--no-sync)"
fi
echo ""

# ── Step 2: HTML 生成 ──────────────────────────────────────
echo "▶ Step 2: HTML 生成 (generate_daily_calendar.py)"
python3 scripts/generate_daily_calendar.py
echo ""

if [ -f "$DEST/daily/signal_fires.csv" ]; then
  echo "▶ Step 2b: シグナル検証カレンダー生成 (generate_signals_calendar.py)"
  python3 scripts/generate_signals_calendar.py
  echo ""
fi

echo "▶ Step 2c: 日次認識カレンダー v3 生成 (generate_daily_calendar_v3.py)"
python3 scripts/generate_daily_calendar_v3.py | tail -3
echo ""

HTML_PATH="$(pwd)/data/trades/processed/trades_calendar.html"

# ── Step 2.5: docs/ へミラー (GitHub Pages 公開用) ─────────
# iPhone/iPad からアドレス経由で閲覧するため
if [ -f "$HTML_PATH" ]; then
  cp "$HTML_PATH" docs/trades_calendar.html
  echo "  🌍 docs/trades_calendar.html へミラー"
fi
SIGNALS_HTML="$(pwd)/data/trades/processed/signals_calendar.html"
if [ -f "$SIGNALS_HTML" ]; then
  cp "$SIGNALS_HTML" docs/signals_calendar.html
  echo "  🌍 docs/signals_calendar.html へミラー"
fi
V3_HTML="$(pwd)/data/trades/processed/daily_calendar_v3.html"
if [ -f "$V3_HTML" ]; then
  cp "$V3_HTML" docs/daily_calendar_v3.html
  echo "  🌍 docs/daily_calendar_v3.html へミラー"
fi
echo ""

# ── Step 2.55: D1環境札 JSON 生成 (docs/d1_env.json) ───────
# Scriptable d1_env_widget 用（SPEC: data/scriptable/SPEC_d1_env_widget_v1.md §2/§3）
# 入力 = daily/daily_aggregate.csv（VPS正本・読み取りのみ）。
# 生成失敗してもカレンダー3枚のpublishは止めない（前回JSONのまま継続）。
echo "▶ Step 2.55: D1環境札 JSON 生成 (generate_d1_env_json.py)"
if python3 scripts/generate_d1_env_json.py; then
  :
else
  echo "  ⚠️ d1_env.json 生成失敗 — 前回JSONのまま publish 継続"
fi
echo ""

# ── Step 2.6: 自動 publish (docs/ のカレンダー3枚 + d1_env.json) ─
# 失敗 (オフライン等) してもパイプラインは止めない
# 正本 = data/vps/publish_list.txt（案D 2026-07-21: hourly_sync と共有・二重管理閉鎖）。
# 存在するファイルだけ採用（未生成物が git add を道連れにしない従来ガードを一般化）。
PUBLISH_LIST="data/vps/publish_list.txt"
PUBLISH_FILES=""
if [ -f "$PUBLISH_LIST" ]; then
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    _line="$(echo "$_line" | xargs 2>/dev/null || true)"
    [ -n "$_line" ] && [ -f "$_line" ] && PUBLISH_FILES="$PUBLISH_FILES $_line"
  done < "$PUBLISH_LIST"
fi
# リスト欠損/空のフォールバック（publishを止めない）
if [ -z "$PUBLISH_FILES" ]; then
  PUBLISH_FILES="docs/trades_calendar.html docs/signals_calendar.html docs/daily_calendar_v3.html"
  [ -f docs/d1_env.json ] && PUBLISH_FILES="$PUBLISH_FILES docs/d1_env.json"
fi
if [ "$DO_PUBLISH" = true ] && [ -f docs/trades_calendar.html ]; then
  if ! git diff --quiet -- $PUBLISH_FILES 2>/dev/null \
     || [ -n "$(git status --porcelain $PUBLISH_FILES 2>/dev/null)" ]; then
    echo "▶ Step 2.6: GitHub Pages へ自動 publish"
    if git add $PUBLISH_FILES 2>/dev/null \
       && git commit -q -m "chore: auto-publish calendars" -- $PUBLISH_FILES \
       && git push -q origin main; then
      echo "  ✅ push 完了 → 数十秒で iPhone/iPad に反映"
    else
      echo "  ⚠️ publish 失敗 (オフライン?) — 次回 push で反映される"
    fi
    echo ""
  fi
fi

echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ 振り返りカレンダー完了                          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  📊 HTML: $HTML_PATH"
echo ""

# ── Step 3: ブラウザオープン ───────────────────────────────
if [ "$OPEN_BROWSER" = true ]; then
  if [ -f "$HTML_PATH" ]; then
    echo "🌐 ブラウザでオープン中..."
    open "$HTML_PATH"
  fi
fi
