#!/bin/bash
# ============================================================
# run_pipeline.sh  — ADXSCORE 全パイプライン一発実行
# ============================================================
# 手順:
#   1. MT5 → mt5_data/ にCSVをコピー
#   2. process_wavelog.py  → weekly_waves.json 生成
#   3. generate_heatmap_v14.py → heatmap_v14.html 生成
#   4. iCloud Drive に自動同期
#   5. ブラウザで自動オープン（オプション）
# ============================================================
# 使い方:
#   ./run_pipeline.sh          # 同期 + 処理 + HTMLオープン
#   ./run_pipeline.sh --no-open  # HTMLオープンなし
# ============================================================

set -e
cd "$(dirname "$0")"

OPEN_BROWSER=true
for arg in "$@"; do
  if [ "$arg" = "--no-open" ]; then OPEN_BROWSER=false; fi
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     ADXSCORE パイプライン 実行                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Step 1: MT5同期 ───────────────────────────────────────
echo "▶ Step 1: MT5データ同期"
bash scripts/sync_mt5_data.sh
echo ""

# ── Step 2: 週次データ生成 ────────────────────────────────
echo "▶ Step 2: 週次波形データ処理 (process_wavelog.py)"
python3 scripts/process_wavelog.py
echo ""

# ── Step 3: ヒートマップ生成 ─────────────────────────────
echo "▶ Step 3: ヒートマップ生成 (generate_heatmap_v14.py)"
python3 scripts/generate_heatmap_v14.py
echo ""

echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ パイプライン完了                               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  📊 ヒートマップ: docs/heatmap_v14.html"
echo "  📦 週次データ:   data/weekly_waves.json"
echo ""

# ── Step 4: iCloud Drive 同期 ─────────────────────────────
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
ICLOUD_DEST="$ICLOUD/ADXSCORE"
HEATMAP_PATH="$(pwd)/docs/heatmap_v14.html"

if [ -d "$ICLOUD" ] && [ -f "$HEATMAP_PATH" ]; then
  mkdir -p "$ICLOUD_DEST"
  cp "$HEATMAP_PATH" "$ICLOUD_DEST/heatmap_v14.html"
  echo "☁️  iCloud同期: ADXSCORE/heatmap_v14.html"
else
  echo "⚠️  iCloud Drive が見つかりません（スキップ）"
fi
echo ""

# ── Step 5: ブラウザオープン ──────────────────────────────
if [ "$OPEN_BROWSER" = true ]; then
  if [ -f "$HEATMAP_PATH" ]; then
    echo "🌐 ブラウザでオープン中..."
    open "$HEATMAP_PATH"
  fi
fi
