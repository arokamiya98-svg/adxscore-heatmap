# CLAUDE.md — ARO Trading Support Project

> このファイルはClaude Codeが毎セッション自動参照するコンテキストファイルです。
> 最終更新: 2026-05-28 (Handover v10 準拠 + ADXSCORE実装情報追記 + ADX_Weekly/WaveLog体制更新)

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

### MQL5スクリプト（現行）

**週次パイプライン用（毎週実行）**

| ファイル | 役割 | 状態 |
|---------|------|------|
| `ARO_FractalWaveLog_D1_v3_1.mq5` | D1 波形レベル収集 | ✅ 現行 |
| `ARO_FractalWaveLog_D1_v3_2.mq5` | D1 週次時系列収集（金曜サンプリング） | ✅ 現行 |
| `ARO_FractalWaveLog_H4_XAU_v3_1.mq5` | H4 週次時系列収集 | ✅ 現行 |
| `ADX_Weekly_Above_v4.mq5` | H1/H4 ADX週次集計 → ADX_Weekly_Above_v4.csv（H1=32, H4=46, 2027末まで対応）| ✅ 現行 |
| `ADX_Weekly_Above_v3a.mq5` | H1/H4 ADX週次集計 旧版（H1=28, H4=30 → 周期ズレあり） | ⚠️ 旧版 |
| `ATR_WidthSignal_v3.mq5` | H1適正スコア表示 | ✅ 現行 |

**データ分析用（不定期・個別実行）**

| ファイル | 役割 | 状態 |
|---------|------|------|
| `WaveLog_Export_v1_6.mq5` | H1 波形ログ全量エクスポート（457波, 125列）| 🔬 分析用 |
| `ATR_Velocity_Rhythm_D1_v1.mq5` | D1 ATRリズム | ✅ |
| `ATR_BottomOut_SLTP_Design.html` | SL/TP設計UI | ✅ |

> ⚠️ **WaveLog_Export_v1_6.mq5** は週次パイプラインに組み込まない。MFE/MAE・DI動態・ATR比率などのデータ分析専用。

### MT5出力CSV（→ ADXSCORE/mt5_data/ に同期）

| ファイル | 内容 | エンコード | 用途 |
|---------|------|-----------|------|
| `FractalWaveLog_D1_v3_1.csv` | D1 波形レベル（BU/PD, ADX, ATR, Fib） | UTF-16 | 週次パイプライン |
| `FractalWaveLog_D1_weekly.csv` | D1 週次時系列（金曜サンプリング） | UTF-16 | 週次パイプライン |
| `FractalWaveLog_H4_XAU.csv` | H4 波形レベル | UTF-8-sig | 週次パイプライン |
| `FractalWaveLog_H4_weekly.csv` | H4 週次時系列 | UTF-8-sig | 週次パイプライン |
| `ADX_Weekly_Above_v4.csv` | H1/H4 ADX週次集計（H1=32, H4=46 正式周期）| UTF-16 | 週次パイプライン（ADXスコア計算元・現行） |
| `ADX_Weekly_Above_v3.csv` | H1/H4 ADX週次集計 旧版（H1=28, H4=30 周期ズレ）| UTF-16 | フォールバック用（v4が優先） |
| `WaveLog_Export_v16.csv` | H1 波形ログ全量（457波, 125列, ATR比率・MFE/MAE等） | UTF-8 | 分析用のみ |
| `WaveLog_Trail_BU_v16.csv` | H1 BU波内H1バーデータ（1768レコード, 104波） | UTF-8 | 分析用のみ |

> ⚠️ **エンコーディング注意**: D1系・ADX_Weekly系はUTF-16（MQL5 FILE_UNICODE）、H4系はUTF-8-sig（BOM付きバイナリ）。Pythonで読む際は要確認。
> ⚠️ **WaveLog_Export_v16.csv / WaveLog_Trail_BU_v16.csv** はパイプラインに含めない。データ分析専用。

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
├── run_pipeline.sh                    ← 一発実行（sync→process→generate）
├── mt5_data/                          ← MT5から同期されるCSV（週次パイプライン用）
│   ├── FractalWaveLog_D1_v3_1.csv
│   ├── FractalWaveLog_D1_weekly.csv
│   ├── FractalWaveLog_H4_XAU.csv
│   ├── FractalWaveLog_H4_weekly.csv
│   └── ADX_Weekly_Above_v4.csv        ← ADXスコア計算元（H1=32, H4=46, 閾値25）
├── data/
│   └── weekly_waves.json              ← process_wavelog.py の出力（ADXスコア含む）
├── docs/
│   └── heatmap_v14.html               ← 最終出力（GitHub Pages公開）
└── scripts/
    ├── sync_mt5_data.sh               ← MT5→mt5_data/ 同期
    ├── process_wavelog.py             ← CSV→weekly_waves.json 変換（ADXスコア計算込み）
    └── generate_heatmap_v14.py        ← weekly_waves.json→HTML 生成
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
| 1 | D1 XAUUSD | `ARO_FractalWaveLog_D1_v3_1` | FractalWaveLog_D1_v3_1.csv（波形レベル） |
| 2 | D1 XAUUSD | `ARO_FractalWaveLog_D1_v3_2` | FractalWaveLog_D1_weekly.csv（週次時系列） |
| 3 | H4 XAUUSD | `ARO_FractalWaveLog_H4_XAU_v3_1` | FractalWaveLog_H4_XAU.csv + H4_weekly.csv |
| 4 | H1 XAUUSD | `ADX_Weekly_Above_v4` | ADX_Weekly_Above_v4.csv（ADXスコア元） |

**Mac側：1コマンドで完結**

```bash
./run_pipeline.sh
# → MT5同期 → process_wavelog.py → generate_heatmap_v14.py → ブラウザ表示
```

---

## 8. 現在の開発ロードマップ（v10時点）

### Stage 1（最優先）: ヒートマップへのD1ラベル統合 ✅ 進行中
- D1 Layer A/B/C ラベラー（Python試作済み）をヒートマップに統合
- 可変幅セルでのD1ラベル描画
- 色分けロジック：🟦（ADX強+DI+）/ 🟥（ADX強+DI-）/ ⬜（ADX弱）
- **週次データ基盤**: D1_v3_2 / H4_v3_1 スクリプト完成・動作確認済み ✅

### Stage 2: 日次配信化
- MT5スクリプト → CSV → LINE配信
- 通知ロジック（クロス接近・過加熱・シグナル）

### Stage 3: H4ラベラー拡張
- ATR8/46ベースで同思想を適用
- T1〜T4をラベルとして組み込む

### Stage 4: 既存ツール整合
- H1適正スコアの更新（D1ラベルとの連携）

### Stage 5: iPhoneウィジェット化（Scriptable）
- **目的**: 戦略をブラさずに行うための必要な情報を常に参照できるウィジェット
- **技術**: Scriptable（iOS/iPadOS）＋ iCloud Drive経由でMT5データを受け取る
- **データフロー**: MT5 → CSV/JSON → iCloud Drive → Scriptable → ホーム画面
- **2層構造**:
  - 上段（静的・週次）: D1フェーズラベル、ATRクロス方向、FibTZ状況 → 今週どちら側で戦うかの土台
  - 下段（動的・MT5連動）: H1 ATRゾーン、ATRパターン、ADXスコア現在値
- **実装順**: 静的土台から作り → 動的データ連携に拡張

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
取引ツール : MetaTrader 5 (MT5) on Mac (Wine)
スクリプト : MQL5
分析       : Python（pandas, numpy）
可視化     : HTML / JavaScript（純粋JS、ライブラリなし）
OS         : Mac
データ保存 : CSV（MT5 → ファイル出力）→ JSON → HTML
```

### MT5 パス（Mac）
```
MQL5 Files  : /Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/
              drive_c/Program Files/MetaTrader 5/MQL5/Files/
Scripts保存 : .../MQL5/Scripts/Examples/
```

### CSV出力の注意点
- D1系スクリプト: **UTF-16**（FILE_WRITE|FILE_TXT|FILE_UNICODE）
- H4系スクリプト: **UTF-8-sig**（BOM付きバイナリ = FILE_WRITE|FILE_BIN + BOM手動書込）
- ADX_Weekly_Above系: **UTF-16**（D1系と同じ FILE_UNICODE）
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

---

## 13. セッション開始時のクイックスタート

あろさんが「Handover v10の続きから」「続きをお願い」と言ってきた場合：

1. このCLAUDE.mdを読み込み済みとしてOK
2. 最新CSVが渡されたらエンコーディング確認から
3. 「何から始めますか？」より「Stage 1の〇〇から続きましょうか？」と確認

---

*このファイルはHandover v10をベースに作成。次のHandover更新時に合わせて更新すること。*
*随時更新: セッション終了時 or 新発見・仕様変更があったタイミングで精査。*
