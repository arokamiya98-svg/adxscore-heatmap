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

# ── Step 1: MT5 → mt5_data/ 同期 ──────────────────────────
if [ "$DO_SYNC" = true ]; then
  echo "▶ Step 1: MT5 → mt5_data/ 同期"
  mkdir -p "$DEST"

  DAILY_FILES=(
    "daily_mfe_mae_48h.csv"   # C1: 非トレード日 48h MFE/MAE
    "daily_aggregate.csv"      # C2: 日次集計 D1/H4/H1 ADX/DI/ATR
  )

  COPIED=0
  MISSING=0
  for fname in "${DAILY_FILES[@]}"; do
    src="$MT5_FILES/$fname"
    dst="$DEST/$fname"
    if [ ! -f "$src" ]; then
      echo "  ⚠️  未生成: $fname (MT5 で対応スクリプトを実行)"
      MISSING=$((MISSING+1))
      continue
    fi
    cp "$src" "$dst"
    SIZE=$(du -h "$dst" | cut -f1)
    MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$dst")
    echo "  📋 コピー: $fname  ($SIZE, $MTIME)"
    COPIED=$((COPIED+1))
  done

  echo ""
  echo "  結果: コピー=$COPIED, 未生成=$MISSING"

  if [ $MISSING -gt 0 ]; then
    echo ""
    echo "💡 未生成のCSVは MT5 で以下を実行して生成:"
    echo "   daily_mfe_mae_48h.csv  → XAUUSD_Daily_MFE_MAE_v1   (XAUUSD H1 チャート)"
    echo "   daily_aggregate.csv    → XAUUSD_Daily_Aggregate_v1 (XAUUSD H1 チャート)"
    echo ""
  fi
else
  echo "▶ Step 1: MT5 同期スキップ (--no-sync)"
fi
echo ""

# signal_fires.csv は検証タイミングのみ生成される (Signal_Fire_Logger)
# 存在すれば同期し、シグナル検証カレンダーも再生成する
if [ "$DO_SYNC" = true ] && [ -f "$MT5_FILES/signal_fires.csv" ]; then
  cp "$MT5_FILES/signal_fires.csv" "$DEST/signal_fires.csv"
  echo "  📋 コピー: signal_fires.csv"
fi

# ── Step 2: HTML 生成 ──────────────────────────────────────
echo "▶ Step 2: HTML 生成 (generate_daily_calendar.py)"
python3 scripts/generate_daily_calendar.py
echo ""

if [ -f "$DEST/signal_fires.csv" ]; then
  echo "▶ Step 2b: シグナル検証カレンダー生成 (generate_signals_calendar.py)"
  python3 scripts/generate_signals_calendar.py
  echo ""
fi

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
echo ""

# ── Step 2.6: 自動 publish (docs/ のカレンダー2枚のみ) ─────
# 失敗 (オフライン等) してもパイプラインは止めない
if [ "$DO_PUBLISH" = true ] && [ -f docs/trades_calendar.html ]; then
  if ! git diff --quiet -- docs/trades_calendar.html docs/signals_calendar.html 2>/dev/null \
     || [ -n "$(git status --porcelain docs/signals_calendar.html 2>/dev/null)" ]; then
    echo "▶ Step 2.6: GitHub Pages へ自動 publish"
    if git add docs/trades_calendar.html docs/signals_calendar.html 2>/dev/null \
       && git commit -q -m "chore: auto-publish calendars" -- docs/trades_calendar.html docs/signals_calendar.html \
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
