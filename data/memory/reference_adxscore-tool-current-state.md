---
name: adxscore-tool-current-state
description: ADXSCOREプロジェクトの現状ツール一覧・データフロー。フェーズ2着手前のスナップショット（2026-06-01）
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9680f5e6-e416-42b9-9329-3c878ab13dc9
---

ADXSCOREプロジェクトの現状ツール構成。[[roadmap-sensory-to-logic-phase]] のフェーズ2着手前の前提知識として整備。

## ファイル構成

```
ADXSCORE/
├── run_pipeline.sh (86行)            ← 一発実行スクリプト
├── CLAUDE.md                          ← プロジェクトコンテキスト（v11）
├── scripts/
│   ├── sync_mt5_data.sh              ← MT5→mt5_data同期
│   ├── process_wavelog.py (601行)    ← データ処理・ADXスコア計算
│   ├── generate_heatmap_v14.py (516行) ← HTML生成
│   ├── generate_heatmap_v12.py       ← 旧版
│   ├── send_line_v2.py / send_line_weekly.py ← LINE配信
│   ├── fetch_and_calc_v2.py          ← 旧スコア取得（廃止予定）
│   ├── initialize_history.py
│   └── generate_html.py
├── mt5_data/                          ← MT5から同期されるCSV（週次パイプライン用）
├── data/
│   ├── weekly_waves.json (現行、290KB、326週)  ← process出力
│   ├── adx_weekly.csv / adx_weekly_xau.csv (旧)
│   └── scores.json (廃止)
└── docs/
    ├── heatmap_v14.html (現行)
    ├── heatmap_v12.html (旧)
    └── index.html (1.4MB)
```

## データフロー（現行）

```
[MT5側 - 手動実行]
  ARO_FractalWaveLog_D1_v3_2.mq5  → FractalWaveLog_D1_v3_1.csv (波形)
                                     FractalWaveLog_D1_weekly.csv (週次時系列)
  ARO_FractalWaveLog_H4_XAU_v3_1.mq5 → FractalWaveLog_H4_XAU.csv (波形)
                                        FractalWaveLog_H4_weekly.csv (週次時系列)
  ADX_Weekly_Above_v4.mq5            → ADX_Weekly_Above_v4.csv (H1×H4 ADX週次)

[Mac側 - run_pipeline.sh 一発]
  Step 1: sync_mt5_data.sh           → mt5_data/ に同期
  Step 2: process_wavelog.py         → data/weekly_waves.json (326週)
  Step 3: generate_heatmap_v14.py    → docs/heatmap_v14.html
  Step 4: iCloud Drive 同期
  Step 5: GitHub Pages 自動push
  Step 6: ブラウザオープン
```

## process_wavelog.py の主要関数

- `iso_week()` - ISO週変換
- `atr_to_class()` - ATR分類（EXPAND/CONTRACT/NEUTRAL）
- `load_d1_weekly`, `load_d1_waves`, `load_h4_weekly`, `load_h4_waves`, `load_adx_weekly` - CSV読み込み
- `map_waves_to_weeks()` - 波形を週次にマップ
- `calc_adx_score()` - **ADXスコア計算（H1×H4幾何平均×0.85×ボーナス）**
- `calc_tier()` - Tier計算（S/A/A*/B/C/D）
- `merge_weekly_with_waves()` / `merge_weekly_with_waves_h4()` - データマージ
- `main()` - エントリポイント

## generate_heatmap_v14.py の主要関数

- `current_iso_week()` - 今日の週取得（[[fwd-data-pipeline-weakness]] 参照：データ最終週へフォールバック仕様）
- `generate_html()` - HTML生成（テーブル・色分けロジック・サマリーパネル）

## 出力ヒートマップの構成

heatmap_v14.html の表示要素:
- 現在週サマリー（TIER / D1 PHASE / H4 WAVE / H4 ADX×DI / ADX SCORE）
- 週次マトリクス（FibTZ予測 / D1 Phase / H4 Wave / H4 ADX×DI / ADX Score / 適正スコア）
- 凡例（FIBTZ予測, D1 PHASE, H4 WAVE, H4 ADX×DI matrix, ADX SCORE結果評価, 適正スコア先行指標）

## 重要な接続関係

- 波形抽出（D1/H4）はMT5側で**手動トレンドラインに依存** → [[fwd-data-pipeline-weakness]]
- ADXスコア計算ロジック（[[anti-perfectionism-true-meaning]] の「確実領域」例）
- Tierシステム → 「適正スコア」として表示
- フェーズ2の中核はこのデータフロー全体を「感覚→自動」に書き換えていく作業 → [[roadmap-sensory-to-logic-phase]]

## バックアップ状況（2026-06-01）

- Wine prefix 完全バックアップ: `~/Library/Application Support/net.metaquotes.wine.metatrader5.backup-20260601` (11GB)
- 旧 Wine prefix（移行参照用）: `.old` (11GB)
- 新環境: Wine 11.1 / MT5 build 5834
