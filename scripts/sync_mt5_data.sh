#!/bin/bash
# ============================================================
# sync_mt5_data.sh
# MT5 MQL5/Files から ADXSCORE/mt5_data/ へ自動コピー
# ============================================================
# 使い方:
#   ./scripts/sync_mt5_data.sh
#   または: bash scripts/sync_mt5_data.sh
# ============================================================

set -e
cd "$(dirname "$0")/.."

MT5_FILES="/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files"
DEST="mt5_data"

echo "=== MT5 → mt5_data 同期 ==="
echo "  From: $MT5_FILES"
echo "  To:   $DEST"
echo ""

mkdir -p "$DEST"

# コピー対象ファイル一覧
FILES=(
  "FractalWaveLog_D1_v3_1.csv"       # D1 波形レベル（必須）
  "FractalWaveLog_D1_weekly.csv"      # D1 週次時系列（v3.2スクリプトで生成）
  "FractalWaveLog_H4_XAU.csv"        # H4 波形レベル（必須）
  "FractalWaveLog_H4_weekly.csv"     # H4 週次時系列（H4 v3.1スクリプトで生成）
  "ADX_Weekly_Above_v4.csv"          # H1/H4 ADX週次集計 v4（ADXスコア計算元・H1=32 H4=46）
  "ADX_Weekly_Above_v3.csv"          # H1/H4 ADX週次集計 v3（旧版・フォールバック用）
)

COPIED=0
SKIPPED=0
MISSING=0

for fname in "${FILES[@]}"; do
  src="$MT5_FILES/$fname"
  dst="$DEST/$fname"

  if [ ! -f "$src" ]; then
    echo "  ⚠️  未生成: $fname"
    MISSING=$((MISSING+1))
    continue
  fi

  # ファイルが存在する場合、更新されているかチェック
  if [ -f "$dst" ] && [ "$src" -ot "$dst" ]; then
    echo "  ✓  変更なし: $fname"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  cp "$src" "$dst"
  SIZE=$(du -h "$dst" | cut -f1)
  MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$dst")
  echo "  📋 コピー: $fname  ($SIZE, $MTIME)"
  COPIED=$((COPIED+1))
done

echo ""
echo "=== 結果: コピー=$COPIED, 変更なし=$SKIPPED, 未生成=$MISSING ==="

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "💡 未生成ファイルは以下のMT5スクリプトで生成してください："
  echo "   D1 weekly → ARO_FractalWaveLog_D1_v3_2    (D1 XAUUSDチャートで実行)"
  echo "   H4 weekly → ARO_FractalWaveLog_H4_XAU_v3_1 (H4 XAUUSDチャートで実行)"
fi
