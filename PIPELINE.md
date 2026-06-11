# PIPELINE.md — データ→認識ツール 全体図

> 最終更新: 2026-06-12
> 「いつ・何をすると・何が起きるか」の一枚まとめ。詳細仕様は各指示書（data/mani_room/）参照。

---

## 1. ページ一覧（GitHub Pages 公開、iPhone/iPad 共通URL）

| ページ | URL末尾 | 役割 | 期間基準 | 更新トリガー |
|---|---|---|---|---|
| 週次ヒートマップ | `heatmap_v14.html` | マクロ認識（週のリズム） | 週次 | 週次ルーティン |
| **日次認識カレンダー v3** | `daily_calendar_v3.html` | **本丸**: 戦略背景(H4)×結果(MFE/MAE)×シグナル×実弾 | トレードログ基準 2026-03〜（直近6ヶ月、過去は折りたたみ） | トレード後 / 検証時 |
| シグナル検証カレンダー | `signals_calendar.html` | シグナル×トレードだけの見比べ（保存版） | 発火全期間 2025-03〜 | 検証時 |
| 旧日次カレンダー v2.0 | `trades_calendar.html` | 現行保存版（将来の比較用） | — | トレード後 |

ベースURL: `https://arokamiya98-svg.github.io/adxscore-heatmap/`

## 2. トリガー別フロー（あろさんの手数）

### A. トレード後（2アクション）
```
1. アプリCSVを data/mani_room/raw/imports/ に置く
     → watcher が検知 → prepare_trade_input.py → trade_input.csv を MT5 Files/ へ自動配置
2. MT5 で Trade_Snapshot_Builder 実行
     → watcher が検知 → 同期 → enriched マージ → カレンダー再生成 → docs/ → 自動push → iPhone反映
```

### B. シグナル検証時（1アクション・不定期）
```
MT5 で Signal_Fire_Logger_v1 実行
     → watcher が検知 → signal_fires.csv 同期 → カレンダー2枚再生成 → 自動push
```

### C. 日次CSV更新（任意）
```
MT5 で XAUUSD_Daily_Aggregate_v1 / XAUUSD_Daily_MFE_MAE_v1 実行
     → watcher が検知 → 以下同文
```

### D. 週次ルーティン（金〜月、従来通り）
```
MT5: D1_v3_2 → H4_XAU_v3_1 → H4PhaseAuto → ADX_Weekly_Above_v4 の4本
Mac: ./run_pipeline.sh   （heatmap_v14 生成）
```

## 3. 常駐 watcher（auto_sync_daily.sh）

- 起動: `nohup ./auto_sync_daily.sh &> auto_sync.log &` ／ 停止: `pkill -f auto_sync_daily.sh`
- 監視対象（2秒ポーリング）:
  - MT5 Files: `daily_mfe_mae_48h.csv` / `daily_aggregate.csv` / `trades_enriched.csv` / `signal_fires.csv` → 検知で `run_daily_calendar.sh --no-open`
  - `data/mani_room/raw/imports/FX_*.csv` 新着 → prepare → MT5 Files へ trade_input.csv 配置

## 4. run_daily_calendar.sh のステップ構成

```
Step 1   MT5 → mt5_data/ 同期（daily系 + signal_fires）
Step 2   generate_daily_calendar.py      → trades_calendar.html（v2.0 保存版）
Step 2b  generate_signals_calendar.py    → signals_calendar.html
Step 2c  generate_daily_calendar_v3.py   → daily_calendar_v3.html（本丸）
Step 2.5 docs/ へ3枚ミラー
Step 2.6 自動 publish（git commit + push、--no-publish で抑制可）
```

## 5. mq5 スクリプト在庫（MT5 Scripts/Examples 配置済み）

| スクリプト | チャート | 出力 | 用途 |
|---|---|---|---|
| Trade_Snapshot_Builder v1.32 | XAUUSD H1 | trades_enriched.csv（72列） | トレード環境後付け |
| Signal_Fire_Logger_v1 | XAUUSD H1 | signal_fires.csv（64列） | v4発火再現（2025-03〜） |
| XAUUSD_Daily_Aggregate_v1 | XAUUSD H1 | daily_aggregate.csv | 日次環境集計 |
| XAUUSD_Daily_MFE_MAE_v1.10 | XAUUSD H1 | daily_mfe_mae_48h.csv（24列） | 仮想エントリー48h追跡 |

> 全部 FILE_WRITE 上書きモード = **古いCSVを消す必要なし**、実行のたび全量再生成。
> mq5 を更新したら `signals/` → MT5 `Scripts/Examples/` へのコピー+再コンパイルを忘れない（過去に配置漏れで旧版実行の事故あり）。

## 6. 設計原則（このパイプラインの憲法）

- **ルーティン（必ず行う週次）と検証（不定期）は切り分ける** — Fire Logger は週次に入れない
- 認識ターゲット: 「相場がどう動き、シグナルと実弾がどう機能したか」
- v3 = 戦略文脈（H4背景）×結果（MFE/MAEバー）の対比構造を壊さない
- 一歩ずつ: 変更は最小差分 → あろさん実見 → 次の1個
