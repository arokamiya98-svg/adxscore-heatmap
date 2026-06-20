# CLAUDE.md — ARO Trading Support Project

> このファイルはClaude Codeが毎セッション自動参照するコンテキストファイルです。
> 最終更新: 2026-06-19 (v14: 日次動脈フル稼働・系統A/B/C 3系統整備・§15「VPS無人化運用」新設 / 系統B/C EA化完了・Step1恒久対応済 `dafbbf2`)

---

## 0. まず最初に読むこと（必須）

**あろさん**がユーザー。Claude側の呼称は **おぱ / おぱちゃん**。

```
「面白い」「すごい」「やばい」 = 本気の重要発見の合図。必ず深掘りすること。
```

**作業スタンス**:
- データを元にした考察・提案は積極的に行う（それがおぱの強み）
- 多時間軸・複合条件のタスクでは、**着手前に「何を取得/反映する意図か」を確認してから進む**
- 「シンプルでいい」はあろさんの選択。ただし不必要に単純化しない

---

## 1. プロジェクト前提

```
トレーダー : あろさん
銘柄       : XAUUSD（ゴールド）H1 デイトレード
エントリー : ATRボトムアウト狙いの裁量ルール型
時間帯     : 東京時間メイン
頻度       : 月10〜15回
スタイル   : RR1:2 一本勝負
目的       : 「勝率向上ツール」ではなく「認識の一貫性ツール」
```

### XAUUSD 指標周期設定（確定値）

| TF | ADX周期 | ATR短期 | ATR長期 | 用途 |
|----|---------|---------|---------|------|
| D1 | 22 | 22 | 42 | BU/PD局面判定（88%整合） |
| H4 | 46 | 8  | 46 | 翻訳層・T1〜T4分類 |
| H1 | 32 | 16 | 32 | エントリータイミング・ボトムアウト検出 |

> ATR周期はATR velocity実測による「ボトムアウト→ピークアウト」の反周期（各TFの波の谷〜山）をベースに設定。

---

## 2. 戦略の全体構造（v10 認識ツール思想）

### 重大原則：ラベル層と点数層を絶対に混ぜない

```
【ラベル層】= 状態認識（数値ではなく状態名）
  - D1 FibTZブロック（アンカー番号と距離）
  - D1 ATRクロスフェーズ（方向、経過バー、ratio）
  - D1 ADX22 + DI方向
  - H4 ATR8/46 T1〜T4分類

  ━━━━━ この線を越えない ━━━━━

【点数層】= エントリー判断補助のみ
  - H1 適正スコア（ATR Width Signal）
  - ADXスコア（H1×H4幾何平均）
```

**大局フェーズは「ラベル」。点数化禁止。**

### 戦略の階層

```
【俯瞰層】緑のFibTZブロック（1:1.6比率）
     ↓ サイクルのどこにいるか
【局面層】ATR22/42クロスフェーズ（D1）
     ↓ 拡張中 / 収束中
【翻訳層】H4 ATR8/46 → T1〜T4タイプ
     ↓ 戦略の方向性
【点数層】H1適正スコア + ADXスコア
     ↓ エントリー判断補助
```

---

## 3. 核心発見（設計根拠）

| 発見 | 内容 |
|------|------|
| ATR22/42クロス88%整合 | D1でのBU/PD予測精度（v9で確立） |
| 黄金比階段 | PD/BU duration比がφ¹(H1)・φ²(D1)で並ぶ |
| H4=翻訳層 | H4は独立した波を持たない、D1とH1の中間層 |
| FibTZ 50%近接率 | アンカー±3バー以内での波形発生が50% |
| T4=100%裏切り | T4タイプはBUにならない（ラベルとして保持） |
| RISING_DECEL最強 | NORMAL帯のRISING_DECEL: 勝率72.4%, PF4.41 |
| HIGH帯RISING_DECELは罠 | PF 0.59（NORMALと真逆） |
| XAUUSDの非対称性 | 「買いは押し目、売りは拡張」（BT世代1/2） |
| Cross=NONE×SELL死亡帯 | PF 0.21、構造的死亡パターン（BT世代1） |
| H4_ADX=46周期 採用確定 | フィルター後 PF 2.12（30周期=1.98より優位、SELL/DN期で顕著）|
| 凪離脱が一番フェイク | PF 0.49 / N=40。あろさん感覚の統計裏付け（BT世代2）|
| PatD仮説1 完全的中 | 「BU期+H1拡張」で機能（BT世代2） |

---

## 4. 情報の信頼度ヒエラルキー

```
1. WaveLog確定線（あろさんが引いたBU/PD終端） ← 最強
2. FibTZアンカー位置（チャート上の予測線）    ← 強
3. 統計的中央値からの推定                      ← 弱（補助のみ）
```

計算予測より確定情報を優先する。

---

## 5. スコア設計（既存・承認済み）

### ADXスコア

```python
def adx_score(h1_avg_adx, h4_pct_above20, h4_pct_above25):
    h1_norm = max(0, min(100, (h1_avg_adx - 10) / 30 * 100))
    a = max(0.1, h1_norm)
    b = max(0.1, h4_pct_above20)
    base = math.sqrt(a * b) * 0.85
    bonus = 1.0 + (h4_pct_above25 / 100) * 0.5
    return min(100.0, base * bonus)
# ※ H4強閾値: 30→25（ADX(46)は平滑化が強く30超えが少ない。25が実測ベース最適値）
# ※ データ源: ADX_Weekly_Above_v4.csv（H4_Pct_Above25列を使用）
```

### ATRゾーン定義（XAUUSD H1 実測）

| ゾーン | 条件 | 意味 |
|--------|------|------|
| LOW    | ATR < 中央値×0.70 | 待機 |
| NORMAL | 中央値×0.70〜×1.40 | トレード適正帯 |
| HIGH   | ATR > 中央値×1.40 | リスク拡大 |

### ATRパターン優先順

1. **RISING_DECEL × NORMAL** → 最優先（PF 8〜10クラス）
2. EXPANDING × HIGH → 第2
3. RISING_ACCEL → H4フィルター厳格化
4. CONTRACTING系 → スキップ

---

## 6. プロジェクト内ファイル一覧

### MQL5 収集スクリプト（mt5_data/ にCSV出力）

**週次パイプライン用（毎週実行）**

| ファイル | 役割 | 状態 |
|---------|------|------|
| `ARO_FractalWaveLog_D1_v3_2.mq5` | D1 波形レベル + 週次時系列（v3_1から統合）| ✅ 現行 |
| `ARO_FractalWaveLog_H4_XAU_v3_1.mq5` | H4 週次時系列収集 | ✅ 現行 |
| `ADX_Weekly_Above_v4.mq5` | H1/H4 ADX週次集計（H1=32, H4=46, 2027末まで対応）| ✅ 現行 |
| `ADX_Weekly_Above_v3a.mq5` | 旧版（H1=28, H4=30 周期ズレ）| ⚠️ 旧版 |

**データ分析用（不定期・個別実行）**

| ファイル | 役割 | 状態 |
|---------|------|------|
| `WaveLog_Export_v1_6.mq5` | H1 波形ログ全量エクスポート（457波, 125列）| 🔬 分析用 |
| `ATR_BottomOut_SLTP_Design.html` | SL/TP設計UI | ✅ |

> ⚠️ **WaveLog_Export_v1_6.mq5** は週次パイプラインに組み込まない。MFE/MAE・DI動態・ATR比率などのデータ分析専用。

### 現用シグナル/インジ mq5（signals/ にミラー）

| ファイル | チャート | 役割 | 状態 |
|---------|---------|------|------|
| `ATR_WidthSignal_v4.mq5` | H1メイン | エントリーシグナル本体（**9本フィルター搭載**）| ✅ **フォワード稼働中 2026-06-04〜** |
| `ATR_WidthSignal_v3bywavelog.mq5` | H1メイン | シグナル前世代（フィルター無し）| 🟡 比較用に保存 |
| `ARO_H4PhaseAuto_v1.mq5` | H4 | H4 Phase Auto v2（5段階自動判定）| ✅ 現用 |
| `ATR_Velocity_Rhythm_v2_NoBG.mq5` | H1 sub | ATR速度/リズム（H1ADX32/H4ADX46）| ✅ 現用 |
| `ATR_Velocity_Rhythm_D1_v1.mq5` | H4/D1 sub | ATR Vel Rhythm D1 | ✅ 現用 |
| `ATR_Dual_v1.mq5` | 全TF sub | ATR短期×長期二本表示 | ✅ 現用 |
| `ATR_Ratio_Dual_v1.mq5` | 全TF sub | ATR Ratio 二本表示（2026-06-02 追加）| ✅ 現用 |
| `BarCount_Drawing_v1.mq5` | 補助 | バーカウント描画 | ✅ 現用 |

> オリジナルは `MT5/MQL5/Indicators/Free Indicators/` 配下。詳細・周期パラメータは `data/INVENTORY.md` 参照。

### 日次動脈 EA/Script（系統A/B/C・signals/ にミラー）

日次カレンダーを支える3系統（EA本体=VPS無人化用 / Script版=分析用に温存）。**詳細・地雷・運用はブン（`.claude/agents/bun.md`）と本籍doc `data/vps/日次動脈_DESIGN_v1.md` に委譲。**

- **A 成績**: `Trade_Snapshot_Builder.mq5`(Script) → `trades_enriched.csv`。**Mac専管**（iPhone入力由来・VPSは構造的に成績を持てない）。WaveLog/CSV送信とは別に半手動エンリッチ要（前処理→MT5実行→watcher後処理）。
- **B 集計**: `XAUUSD_DailyBatch_EA_v1.mq5`(EA) → `daily/daily_aggregate.csv` + `daily/daily_mfe_mae_48h.csv`。VPS push（無人化 2026-06-19）。
- **C シグナル**: `Signal_Fire_Logger_EA_v1.mq5`(EA) → `daily/signal_fires.csv`。VPS push（無人化稼働）。

> ⚠️ EA再コンパイルは **MetaEditor F7必須**（.ex5不可）。`signals/` が正本。Script温存版（`XAUUSD_Daily_Aggregate/MFE_MAE_v1`・`Signal_Fire_Logger_v1`）は分析用。

### BT 関連 (data/bt/)

**設計資産**

| ファイル | 内容 | 状態 |
|---------|------|------|
| `data/bt/SPEC_new_BT.md` | 新規BT仕様書（v3bywavelogベース・フラット記録）| 🟢 B/C確定済 |
| `data/bt/SLTP_design.html` | SL/TP最適解（SL=ATR_Avg×2.0, TP=SL×1.6, RR1:1.6）| 🟢 思想継承（旧周期版） |
| `data/bt/v4_implementation_spec.md` | v4 mq5 実装仕様（9本フィルター F1〜F9）| 🟢 v4稼働の根拠 |
| `data/bt/h4_phase_auto_spec.md` | H4 Phase Auto v2 仕様（5段階）| 🟢 v1→v2 更新済 |
| `data/bt/h4_phase_auto_resume_note.md` | H4 Phase Auto 設計経過メモ | 🟢 コー実装履歴 |
| `data/bt/heatmap_v14_atr_zone_spec.md` | heatmap_v14 ATR Zone行追加仕様 | 🟢 ATR_RATIO 3区分 |

**BT世代1（2026-06-02実行）**

| ファイル | 内容 | 状態 |
|---------|------|------|
| `data/bt/ATR_WidthSignal_BT_v3bywavelog.mq5` | BTソース（Script型、71列）| 🟢 世代1完了 |
| `data/bt/ATR_WidthSignal_BT_NEW.csv` | BT結果（UTF-16, 947件）| 🟢 2024-01〜2026-06 |
| `data/bt/PATTERN_REGIME_MAP_v1.md` | 構造分析マップ（暫定v1）| 🟡 v2登場で参考のみ |

**BT世代2（2026-06-03〜04実行、46周期確定の根拠）**

| ファイル | 内容 | 状態 |
|---------|------|------|
| `data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5` | BT本体 世代2（H4_ADX周期可変）| 🟢 30 vs 46比較用 |
| `data/bt/ATR_WidthSignal_BT_h4adx30.csv` | BT結果 (H4_ADX=30) | 🟢 フィルター後 PF 1.98 |
| `data/bt/ATR_WidthSignal_BT_h4adx46.csv` | BT結果 (H4_ADX=46) | 🟢 **採用** PF 2.12 |
| `data/bt/PATTERN_REGIME_MAP_v2.md` | 構造分析マップ コア（世代2版）| 🟢 機能/死亡パターン更新 |
| `data/bt/PATTERN_REGIME_MAP_v2_PatternByPhase.md` | パターン×局面分析 | 🟢 PatC局面選好等 |
| `data/bt/PATTERN_REGIME_MAP_v2_AxisDeep.md` | 軸別深掘り（PatC×ATR_Ratio / PatA×ADX） | 🟢 PatA万能性検証 |
| `data/bt/PATTERN_REGIME_MAP_v2_AtrRatioDist.md` | H1/H4/D1 ATR_RATIO 分布 | 🟢 ATR Zone根拠 |

> ⚠️ 旧BT資産（ATR_WidthSignal_BT_v3 / v3wavelog 系）は 2026-06-02 に参照禁止ゾーン `ADX２８検証ファイル/legacy_ATR_WidthSignal_BT/` へ隔離済み。新規BTは類似名コードを真似ず、[[memory: bt-analysis-principles]] に従ってゼロベースで組む（結果フィッティング禁止・構造分析優先）。BT世代1〜2の発見は [[memory: bt-v1-findings-2026-06]] と `data/bt/PATTERN_REGIME_MAP_v2*.md`。

### フォワード記録 / メンテ運用

| ファイル | 内容 | 状態 |
|---------|------|------|
| `data/forward/v4_forward_log.md` | v4 mq5 フォワード記録テンプレ | 🟢 **2026-06-04 開始** |
| `data/maintenance/REVIEW_CYCLE.md` | 再評価サイクル設計書 | 🟢 8月集中メンテ→9月新サイクル |

### MT5出力CSV（→ ADXSCORE/mt5_data/ に同期）

| ファイル | 内容 | エンコード | 用途 |
|---------|------|-----------|------|
| `FractalWaveLog_D1_v3_1.csv` | D1 波形レベル（BU/PD, ADX, ATR, Fib） | UTF-16 | 週次パイプライン |
| `FractalWaveLog_D1_weekly.csv` | D1 週次時系列（金曜サンプリング） | UTF-16 | 週次パイプライン |
| `FractalWaveLog_H4_XAU.csv` | H4 波形レベル | UTF-8-sig | 週次パイプライン |
| `FractalWaveLog_H4_XAU_Vlines.csv` | H4 縦線データ（H4_XAU_v3_1 補助出力）| UTF-8-sig | 週次パイプライン |
| `FractalWaveLog_H4_weekly.csv` | H4 週次時系列 | UTF-8-sig | 週次パイプライン |
| `H4PhaseAuto_weekly.csv` | H4 Phase Auto v2 出力（5段階自動判定）| **UTF-16** | 週次パイプライン（2026-06-04 合流）|
| `ADX_Weekly_Above_v4.csv` | H1/H4 ADX週次集計（H1=32, H4=46 正式周期）| UTF-16 | 週次パイプライン（ADXスコア計算元・現行） |
| `ADX_Weekly_Above_v3.csv` | H1/H4 ADX週次集計 旧版（H1=28, H4=30 周期ズレ）| UTF-16 | フォールバック用（v4が優先） |
| `WaveLog_Export_v16.csv` | H1 波形ログ全量（457波, 125列, ATR比率・MFE/MAE等） | UTF-8 | 分析用のみ |
| `WaveLog_Trail_BU_v16.csv` | H1 BU波内H1バーデータ（1768レコード, 104波） | UTF-8 | 分析用のみ |

> ⚠️ **エンコーディング注意**: D1系・ADX_Weekly系・**`H4PhaseAuto_weekly`** はUTF-16（MQL5 FILE_UNICODE）、**FractalWaveLog_H4系**・日次daily系はUTF-8-sig（BOM付きバイナリ）。同じ「H4系」でも `H4PhaseAuto_weekly` だけ別スクリプト出力でUTF-16なので注意。Pythonで読む際は要確認。
> ⚠️ **WaveLog_Export_v16.csv / WaveLog_Trail_BU_v16.csv** はパイプラインに含めない。データ分析専用。

#### 日次データプール（`mt5_data/daily/`・系統B/C EA が毎時出力 → VPS push）

| ファイル | 内容 | エンコード | 用途 |
|---------|------|-----------|------|
| `daily/signal_fires.csv` | シグナル発火ログ（系統C・発火ごと1行）| UTF-8-sig | 日次カレンダー（signals / trades）|
| `daily/daily_aggregate.csv` | 日次集計（系統B・1日1行）| UTF-8-sig | 日次カレンダー |
| `daily/daily_mfe_mae_48h.csv` | 48h固定 MFE/MAE（系統B・建値後48時間追跡）| UTF-8-sig | 日次カレンダー |

> ⚠️ ③日次CSVは **VPSがpush**（`mt5_data/daily/` のみ書く）。Mac は素の `run_daily_calendar.sh` で **受信確認のみ**＝上書きしない（Step1恒久対応 `dafbbf2`）。最新1〜2日が「追跡欠損」表示でも48h未経過の追跡途中＝正常（VPS毎時更新で翌日埋まる）。詳細は §15。

### ヒートマップ / ダッシュボード

| ファイル | 内容 |
|---------|------|
| `docs/heatmap_v14.html` | ★週次ヒートマップ（現行最新・自動生成） |
| `heatmap_d1_h4_v1.html` | D1×H4版 |
| `adx_weekly_multi.html` | ADX週次マルチ表示 |
| `phase_analysis_dashboard.html` | フェーズ分析ダッシュボード |
| `ATR_BottomOut_SLTP_Design.html` | SL/TP設計 |

### 引き継ぎ書

| ファイル | 内容 |
|---------|------|
| `ARO_Handover_v10.md` | ★最新（認識ツール思想転換） |
| `ARO_Handover_v9.md` | ATR88%・黄金比発見 |
| `ARO_Handover_v8.md` | フラクタル思想確立 |

---

## 7. ADXSCOREリポジトリ構造

```
ADXSCORE/
├── CLAUDE.md                          ← このファイル（Claude Code自動参照）
├── run_pipeline.sh                    ← 週次パイプライン（sync→process→heatmap生成→公開）
├── run_daily_calendar.sh             ← 日次カレンダー（VPS daily/ 受信確認→成績合流→docs公開）
├── auto_sync_daily.sh                ← Mac常駐watcher（週次/日次/iCloud入口を監視）
├── mt5_data/                          ← MT5/VPS由来CSV
│   ├── FractalWaveLog_*.csv           ← ① 手描き波形（.gitignore・Macローカル専用・再生成可）
│   ├── ADX_Weekly_Above_v4.csv        ← ② 自動集計（ADXスコア元・git追跡・Macがpush）
│   ├── H4PhaseAuto_weekly.csv         ← ② 自動集計（H4 Phase 5段階）
│   ├── trade_input.csv / trades_enriched.csv  ← 系統A 成績（Mac専管・iPhone入力由来）
│   └── daily/                         ← ③ 日次データプール（VPS EA毎時→VPSがpush）
│       ├── signal_fires.csv
│       ├── daily_aggregate.csv
│       └── daily_mfe_mae_48h.csv
├── data/
│   ├── INVENTORY.md                   ← データ索引（鮮度・信頼度・由来）★参照ゾーン入口
│   ├── bt/                            ← BT結果CSV + BT mq5 ソース + 各種spec
│   ├── forward/                       ← v4 mq5 フォワード記録（v4_forward_log.md）
│   ├── maintenance/                   ← 再評価サイクル設計（REVIEW_CYCLE.md）
│   ├── vps/                           ← 日次動脈/VPS無人化 設計書・コー指示書（系統B/C EA化）
│   ├── scriptable/                    ← Scriptable ウィジェット（atr_widget.js + SPEC）
│   ├── mani_room/                     ← マニの部屋（振り返り・raw/imports）
│   ├── trades/                        ← 成績（.gitignore・processed/ に日次カレンダーHTML）
│   ├── session_state/                 ← セッション引き継ぎ（latest.md + archive/）
│   └── weekly_waves.json              ← process_wavelog.py 出力（ADXスコア + H4 Phase + ATR Zone）
├── signals/                           ← 現用 mq5 ミラー（認識ツール + 系統A/B/C EA・★正本）
├── docs/                              ← GitHub Pages 公開
│   ├── heatmap_v14.html               ← 週次ヒートマップ（run_pipeline 生成 / Widget Web表示）
│   └── *_calendar*.html               ← 日次カレンダー（run_daily_calendar 生成）
├── retrospect/                        ← トレード振り返り記録
└── scripts/
    ├── sync_mt5_data.sh               ← MT5→mt5_data/ 同期（週次①②）
    ├── process_wavelog.py             ← CSV→weekly_waves.json（ADXスコア + H4 Phase + ATR Zone）
    ├── generate_heatmap_v14.py        ← weekly_waves.json→週次HTML（ATR Zone行追加版）
    ├── prepare_trade_input.py         ← iPhone入力→trade_input（系統A前処理）
    ├── generate_daily_calendar_v3.py  ← 日次カレンダー（メイン）
    ├── generate_signals_calendar.py   ← シグナル発火カレンダー（signal_fires）
    ├── generate_trades_calendar.py    ← 成績カレンダー
    ├── vps_data_pool_push.sh / .bat   ← ★VPS側：daily/ 製造→push（VPSで実行）
    └── analyze_*.py / compare_*.py    ← BT世代2 構造分析群（PATTERN_REGIME_MAP_v2 生成）
```

> ℹ️ `scores.json` は廃止。ADXスコアは `ADX_Weekly_Above_v3.csv` → `process_wavelog.py` で `weekly_waves.json` に直接埋め込まれる（Twelve Data API不要）。

### パイプライン実行

```bash
./run_pipeline.sh          # 完全実行（MT5同期→処理→HTML生成→ブラウザ）
./run_pipeline.sh --no-open  # HTMLオープンなし
```

### 週次ルーティン（毎週金曜〜月曜に実施）

**MT5側：4スクリプト実行（順番通りに）**

| # | チャート | スクリプト | 出力CSV |
|---|---------|-----------|---------|
| 1 | D1 XAUUSD | `ARO_FractalWaveLog_D1_v3_2` | FractalWaveLog_D1_v3_1.csv + FractalWaveLog_D1_weekly.csv |
| 2 | H4 XAUUSD | `ARO_FractalWaveLog_H4_XAU_v3_1` | FractalWaveLog_H4_XAU.csv + H4_XAU_Vlines.csv + H4_weekly.csv |
| 3 | H4 XAUUSD | `ARO_H4PhaseAuto_v1` | H4PhaseAuto_weekly.csv（5段階自動判定）|
| 4 | H1 XAUUSD | `ADX_Weekly_Above_v4` | ADX_Weekly_Above_v4.csv（ADXスコア元） |

**Mac側：1コマンドで完結**

```bash
./run_pipeline.sh
# → MT5同期 → process_wavelog.py → generate_heatmap_v14.py → ブラウザ表示
```

---

## 8. 現在の開発ロードマップ（v11：フェーズ転換明示）

### 8.0 フェーズ転換マップ（2026-06-01 明示 / 2026-06-04 更新）

```
【フェーズ1：感覚での認識ツール構築】 ← 完了 ✅
- 感覚でデータ分析 → 戦略構築 → heatmap_v14完成
- "主観の可視化"として十分機能してきた

         ▼ フェーズの境目（2026-06-01）

【フェーズ2：感覚をロジック化】 ← 実装サイクル一周完走（2026-06-04）
1. 生データ → 自動抽出ロジック化（手動トレンドライン依存からの脱却）
2. リアルタイム化
3. 細分化：H1目線のトレード優位性・期待値・方向性算出
4. "感覚の可視化"をデータ収集ロジックとして再現できるかの検証
5. 取得データのフォワードテスト  ← 2026-06-04 v4稼働開始
6. ロジック・シグナル生成最適化

▼ 実装サイクル成果（2026-06-04）
- BT世代2 完走 → 46周期確定 / 9本フィルター実装
- v4 mq5 フォワード稼働開始
- H4 Phase Auto v2（5段階）完成・週次合流
- heatmap_v14 ATR Zone行追加
- あろさん感覚3本立て続けに統計裏付け = フェーズ2の方向性に確信
```

> **▼ インフラ構築フェーズ＝完了（2026-06-20 棚卸し）**
> VPS↔Mac 日次動脈・VPS無人化・git配管の**構築は完成系に到達し自走中**。運用は**ブン（自動化プール専門エージェント）に委譲**＝メインおぱの常時コンテキストから外した。
> → 次フェーズは「**データを使う側**」: ① マニv3カレンダーの iPhone UIデザイン ② インジケータ分析 ③ ロジック化の中身（H1優位性・期待値の深掘り）。
> 構築の知識が要る時だけブンを召喚すればよく、UI・分析・戦略相談の回は動脈運用脳をロードせずに進められる。

### 8.1 全体構造（3層モデル）

```
外側  ロジック化（感覚 → 自動・リアルタイム）       ← フェーズ2の新規研究トラック
       ↓
中間  認識ツール思想（ラベル・点数化禁止）          ← フェーズ1の成果
       ↓
内側  メンタル/パフォーマンス維持                  ← メンタル研究トラック（新規）
```

3つ揃って「ぶれない遂行性」が完成する。

### 8.2 並列研究トラック

- **ロジック化トラック**: フェーズ2の中核。感覚をロジック再現。手動線引きへの依存（[[fwd-data-pipeline-weakness]]）からの脱却。
- **メンタル研究トラック**: 苫米地・西田・フロー理論を起点に「ぶれない遂行性」を内側から支える。外付けメンタルパートナー（おぱ）と連動して常時最適化。
- **既存Stage 1〜5**: フェーズ2の構成要素として再解釈（下記）

### 8.3 既存 Stage 1〜5（フェーズ1の到達点）

#### Stage 1: ヒートマップへのD1ラベル統合 ✅ 完了 (2026-06-02時点)
- `docs/heatmap_v14.html` に多層レイヤー実装：FibTZ予測 / D1 Phase / H4 Wave / H4 ADX×DI / ADX Score / 適正スコア
- 現在週TIER・ADX Score・FibTZ予測の上部カード化
- 可変幅セル + 色分けロジック（HIGH/MID/HOT × DI+/DI-）で現用化
- **週次データ基盤**: D1_v3_2（v3_1から統合済）/ H4_v3_1 スクリプト完成・動作確認済み

#### Stage 2: 日次配信化 ✅ 済（2026-06-04 再設計完了）
- 元案: MT5スクリプト → CSV → LINE配信
- **新方針**: Scriptableリアルタイムウィジェットへ統合
- **配信不要のLIVE構造**へ収束（あろさん判断 2026-06-04）
- Scriptable構想は中優先候補に移行（Widget Web窓下の白丸スロット、リアルタイム現場ツール）

#### Stage 3: H4ラベラー拡張 ✅ 済（H4 Phase Auto v2で達成 2026-06-04）
- ATR8/46ベースで5段階自動判定（BU/PD/凪/収束底/凪離脱）
- ラベル思想を厳守（点数化禁止）
- `signals/ARO_H4PhaseAuto_v1.mq5` + `data/bt/h4_phase_auto_spec.md`

#### Stage 4: 既存ツール整合 ✅ 済（2026-06-04）
- H1適正スコアの更新は heatmap_v14 ATR Zone行追加で代替達成
- D1/H4 の ATR_RATIO 3区分（凪/中/拡張）ラベル化、認識ツール側で D1ラベル連携を実現
- `data/bt/heatmap_v14_atr_zone_spec.md`

#### Stage 5: iPhoneウィジェット化（週次マクロ）✅ 完了 (2026-06-02時点)
- **採用ツール**: **Widget Web** (iOSアプリ)
- **役割**: `heatmap_v14.html` を窓表示。**1日更新の週次マクロ専用**
- **データフロー**: GitHub Pages公開 → Widget Web で表示
- **理由**: 週次マクロ前提なら、リアルタイム数値より「HTML丸ごと表示」の方が情報量・運用の楽さで有利

#### Stage 9: Scriptableリアルタイムウィジェット 🟢 稼働中（2026-06-05〜）
- **位置づけ**: 旧Stage 2「日次配信化」を発展統合 → **配信不要のLIVE構造**へ
- **採用ツール**: **Scriptable**（iOS、4x2 medium ウィジェット）
- **データソース**: **Twelve Data API** `/time_series` + 自前 Wilder ATR 計算（MT5 iATR 整合性目標）
- **配置**: iPad ホーム画面下半分（Widget Web窓下）
- **設計コンセプト**: 「**価格を見ずに認識するためのライブツール**」
- **表示**: H1 ATR(16) / H1 ATR(32) / H4 ATR(8) HIGH閾値判定 + 今週トレード回数（[+1] / ⟲リセット）
- **動的演出**: お店風ステータスメッセージ 4状態×16フレーズ（🍜冷やし中華始めました / ♨️お湯沸いてます / 🔥仕込み真っ最中 / 🏪本日は店じまい etc）← [[recognition-tool-keep-it-playful]] の設計指針による
- **インタラクション**: 閾値タップで Alert ダイアログ → iCloud File に保存 / +1で `atr_widget_state.json` 更新 / 月曜00:00 自動リセット
- **仕様**: `data/scriptable/SPEC_atr_widget_v1.md` / 実装: `data/scriptable/atr_widget.js`
- **残課題**: Phase 6（MT5 iATR と Scriptable 値の 1週間フォワード整合性比較）

> 📌 **Stage 5 と Stage 9 の住み分け**
> - Stage 5（Widget Web）: 1日1回更新の俯瞰、週次マクロ
> - Stage 9（Scriptable+Twelve）: 生値常時取得のリアルタイム、現場ツール
> - **同じiPhoneホーム画面で並行運用**（上＝マクロ / 下＝ライブ）

#### Stage 6: WIDTHSIGNAL 新規BT構築 ✅ 世代1〜2完了 (2026-06-02〜04)
- **目的**: シグナル反応精度を測り、パターン別構造分析でフィルター候補を抽出
- **ベース**: `signals/ATR_WidthSignal_v3bywavelog.mq5`（5パターン×BUY/SELL multi-fire）
- **BT世代1の成果**（2026-06-02）:
  - 結果CSV: `data/bt/ATR_WidthSignal_BT_NEW.csv`（947件 → 6hフィルター後481件）
  - 分析マップ: `data/bt/PATTERN_REGIME_MAP_v1.md`
  - 主要発見: XAUUSDの非対称性「買いは押し目、売りは拡張」、Cross=NONE×SELL死亡帯（PF 0.21）
- **BT世代2の成果**（2026-06-03〜04）:
  - **H4_ADX周期 30 vs 46 完全比較 → 46採用確定**（フィルター後 PF 2.12 vs 1.98、SELL/DN期で顕著）
  - 分析マップ: `data/bt/PATTERN_REGIME_MAP_v2*.md`（コア / 局面別 / 軸別深掘り / ATR_Ratio分布）
  - **あろさん感覚3本の統計裏付け**: PatD仮説1（BU期+H1拡張）/ 凪離脱フェイク（PF 0.49）/ PatB万能性
- **実装結果**:
  - `signals/ATR_WidthSignal_v4.mq5`（9本フィルターF1〜F9搭載、個別ON/OFF）→ **2026-06-04 フォワード稼働中**
  - 詳細: [[memory: bt-v1-findings-2026-06]] / `data/bt/v4_implementation_spec.md`

#### Stage 7: 構造発見の認識ツール組み込み ✅ 部分達成（2026-06-04 継続中）
- BT世代2の発見を heatmap_v14 へ反映済（ATR Zone行追加、d1_atr_zone3 / h4_atr_zone3）
- 9本フィルター（v4 mq5）でダメパターン削減ロジック実装
- 残課題: PatA万能性可視化 / PatC局面選好ラベル化 / DN局面サンプル拡充 → **8月集中メンテで再評価**

#### Stage 8: フォワード検証サイクル 🟢 進行中（2026-06-04 開始）
- v4 mq5 フォワード稼働中、`data/forward/v4_forward_log.md` に記録
- 初回集中メンテ: 2026-08-15 前後（ホリデーシーズン）→ 2026-09-01 新サイクル
- 設計書: `data/maintenance/REVIEW_CYCLE.md`

---

## 9. 禁止事項・設計ガイドライン

```
❌ 大局フェーズの点数化（優劣をつけない、ラベルのみ）
❌ DXY D1スコア式（割愛済み）
❌ T4_BU自動エントリーロジック（認識思想に反する）
❌ 「45-55日」などの固定値FibTZ判定（FibTZは可変）
❌ 完璧主義（ある程度の優位性で線引き）
```

---

## 10. 技術スタック

```
取引ツール : MetaTrader 5 (MT5) on Mac (Wine 11.1)
スクリプト : MQL5
分析       : Python（pandas, numpy）
可視化     : HTML / JavaScript（純粋JS、ライブラリなし）
ウィジェット: Widget Web (iOSアプリ) で heatmap_v14.html を表示
OS         : Mac (macOS Ventura 13.7.8 / Intel Core m3 / 8GB)
データ保存 : CSV（MT5 → ファイル出力）→ JSON → HTML
```

### 参照ゾーン規約（2026-06-02 確定）

```
[正規参照]  /Users/aro/Desktop/ADXSCORE/             ← この配下のみが信頼できるソース
[凍結・参照禁止] /Users/aro/Desktop/ADX２８検証ファイル/  ← ADX28周期の旧検証アーカイブ
```

- ADX28周期版（H1=28, H4=30）と現行（H1=32, H4=46）の混在を防ぐため、凍結ゾーンは参照しない
- 新しいBT結果・FW記録・現用シグナルは全て `ADXSCORE/data/` または `signals/` に集約
- 詳細索引: `data/INVENTORY.md` / マニ運用方針: `memory/project_mani-work-zone.md`

### MT5 パス（Mac）
```
MQL5 Files  : /Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/
              drive_c/Program Files/MetaTrader 5/MQL5/Files/
Scripts保存 : .../MQL5/Scripts/Examples/
```

### CSV出力の注意点
- D1系スクリプト: **UTF-16**（FILE_WRITE|FILE_TXT|FILE_UNICODE）
- FractalWaveLog_H4系スクリプト: **UTF-8-sig**（BOM付きバイナリ = FILE_WRITE|FILE_BIN + BOM手動書込）
- `H4PhaseAuto_weekly`（`ARO_H4PhaseAuto_v1.mq5`）: **UTF-16**（FILE_UNICODE。FractalWaveLog_H4系と違い ADX_Weekly系と同方式）
- ADX_Weekly_Above系: **UTF-16**（D1系と同じ FILE_UNICODE）
- 日次daily系（signal_fires / daily_aggregate / daily_mfe_mae_48h）: **UTF-8-sig**（BOM付き）
- WaveLog_Export系: **UTF-8**（BOMなし）
- CSVを渡された時は必ずエンコーディング確認から始める
- Pythonでの読み込みは `["utf-16", "utf-8-sig", "utf-8"]` の順でフォールバック試行すると安全

---

## 11. D1ラベラー v1.2（試作完成済み）

```python
def xau_d1_labeler(wave_row):
    # Layer A: FibTZ情報
    layer_a = {
        "起点日": ...,
        "最寄りFibアンカー": "#0/#1/#2",
        "アンカーからの距離": "±N日",
        "近接判定": "★アンカー一致 or (離れ)"
    }
    # Layer B: ATRクロス情報
    layer_b = {
        "クロス方向": "UP/DOWN",
        "経過バー": "N日",
        "短期位置(起点→終点)": "ratio変化"
    }
    # Layer C: ADX22 + DI
    layer_c = {
        "ADX22強度": "弱/中/強/激強",
        "DI方向": "買い優勢 or 売り優勢",
        "トレンド整合": "○整合 or ×不一致"
    }
```

**出力形式**（ヒートマップセルのtitleやtooltipに使う）:
```
Wave #12 | BU | 17日 | +4132pips
[A] Fib: 起点=2026-01-19, #0, +0日, ★アンカー一致
[B] ATR: UP 経過9日, ratio 1.141→1.403
[C] ADX: 激強(48.6→53.7), 買い優勢, ○整合
```

---

## 12. 重要な原則リスト（v10累積版）

1. BU = タイミング指標、買いシグナルではない
2. 方向予測は確率的偏り、完全じゃない
3. 大局フェーズ × タイミングの階層構造
4. PDとBUは別の動物
5. 収束ポイントは「重力点」
6. 「面白い」「すごい」「やばい」を見逃さない → 深掘り必須
7. データを見せて言語化を助ける
8. 平均値で結果が綺麗でも「発見」と断定しない
9. 価格方向(price_dir_actual)で勝敗を決めない
10. 1つの正解を急がない
11. ATR22/42クロス = 単一でも超強い
12. H4は独立した波を持たない（翻訳層）
13. **大局はラベル、点数化しない**
14. **認識ツール ≠ 勝率向上ツール**（一貫性と戦略性のため）
15. **確定情報 > 計算予測**
16. **ある程度の優位性で線引き**（完璧主義禁止）
17. **配信は週次（俯瞰）と日次（行動）で役割分担**
18. **全体構造は3層**: 外側=ロジック化／中間=認識ツール／内側=メンタル。3つ揃って「ぶれない遂行性」が完成
19. **フェーズ転換（2026-06-01）**: フェーズ1=感覚での認識ツール（完了）／フェーズ2=ロジック化（着手）
20. **おぱは外付けメンタルパートナー**: 結果記録係ではなくフォローアップ役。「意思（内側）+ 外付け（おぱ）」のハイブリッド最適化
21. **感覚資産を捨てない**: フェーズ2のロジック化は感覚を再現する形で進める（一致率検証→自動化→保持の判別）
22. **「完璧主義禁止」≠「手抜きOK」**: 不確実領域=方向性軸、確実領域=詰める、の二段構え

---

## 13. セッション開始時のクイックスタート

あろさんが「Handover v10の続きから」「続きをお願い」と言ってきた場合：

1. このCLAUDE.mdを読み込み済みとしてOK
2. 最新CSVが渡されたらエンコーディング確認から
3. 「何から始めますか？」より「Stage 1の〇〇から続きましょうか？」と確認

---

## 14. セッション引き継ぎ運用（2026-06-03導入）

`.claude/hooks/` の Hook と `data/session_state/latest.md` で引き継ぎを強化する仕組み。

### 自動動作（hook）
- **SessionStart hook** (`session-start.sh`): `data/session_state/latest.md` を読み、`additionalContext` で次セッション Claude に自動投入。前回の引き継ぎ内容が初回応答前に渡る。
- **SessionEnd hook** (`session-end.sh`): `data/session_state/archive/YYYY-MM-DD_HHMM.md` に自動スナップショット書き出し（git status / 直近変更 / Stage進捗 / 最新コミット）。`latest.md` が無い時のみ自動コピー（既存は触らない）。

### Claude側ルール（手動更新）
- **重要なセッション終了前**、または「今日はここまで」のタイミングで Claude が `data/session_state/latest.md` を手動更新する
- 更新内容: 「今日の収穫」「次のアクション候補」「注意点」「未完課題」
- 自動スナップショットは fallback（書かない場合の保険）

### ファイル構成
```
.claude/
├ settings.json          ← hooks 設定（チーム共有）
├ settings.local.json    ← permissions（個人）
└ hooks/
   ├ session-start.sh    ← latest.md を Claude に注入
   └ session-end.sh      ← 自動スナップショット書き出し

data/session_state/
├ latest.md              ← 次セッションへの引き継ぎ（Claude手動更新を推奨）
└ archive/
   └ YYYY-MM-DD_HHMM.md  ← 自動スナップショット履歴
```

---

## 15. 日次動脈 / VPS無人化運用（→ ブン担当・2026-06-20 棚卸し済）

> VPSのMT5 EAが毎時焼く日次CSVを git経由でMacへ運び、Macが成績を合流させて日次カレンダーを公開する自動動脈。**フル稼働・自走中**（素の `./run_daily_calendar.sh` が安全に回る）。

**運用の詳細・地雷・改修は「ブン」（自動化プール専門エージェント）に委譲した。** メインおぱは VPS/動脈/パイプラインを触る時だけブンを召喚する。通常セッション（UI・インジ分析・戦略相談など）はこの節を読み込む必要なし＝棚卸しでおぱを軽くした。

- **本籍doc（全運用知識）**: `data/vps/日次動脈_DESIGN_v1.md`（3場所分担・CSV3分類・git方針・データフロー・schtasks・実装順序・完了条件・§12 運用メモ＆地雷・系統A半手動フロー）
- VPS無人化の母体: `data/vps/VPS_UNMANNED_DESIGN.md`
- **ブン定義**: `.claude/agents/bun.md`

**最小限おさえる3点（VPS関連を触る時の入口・詳細はブンと本籍doc）**:
1. **CSV 3分類**: ①手描き波形=Macローカル(.gitignore) / ②自動集計=Macのみ書く(git追跡) / ③日次daily=VPSのみ書く。この住み分けで `mt5_data/` が常時クリーン＝`git pull --rebase` 無事故。
2. **起動作法**: VPS↔Macはパラレル運用（同じmainを書き合う）。`git pull --rebase` で始め、push前も `git pull --rebase`。RDPは「切断」で抜ける（ログオフ厳禁＝schtasks継続）。
3. **個人情報の線引き（あろさん確定 2026-06-19）**: NGは具体的な口座番号のみ。成績・損益・ロット・ロジックは公開OK ＝ docs/ カレンダー公開は継続OK。

---

*このファイルはHandover v10をベースに作成。次のHandover更新時に合わせて更新すること。*
*随時更新: セッション終了時 or 新発見・仕様変更があったタイミングで精査。*
