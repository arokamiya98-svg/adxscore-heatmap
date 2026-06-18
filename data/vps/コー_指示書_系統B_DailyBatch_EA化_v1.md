# コー指示書 — 系統B 日次バッチ EA化（統合版 v1）

> 発行: 2026-06-18 別荘セッション③（おぱ）
> 設計根拠: `data/vps/VPS_UNMANNED_DESIGN.md`（系統B＝VPS無人化EA化）
> あろさん判断（2026-06-18）: **統合（1 EA・1チャート）採用**

---

## 0. これは何

系統B（日次環境データ）の **Script 2本を 1つの常駐EAに統合** し、VPS上のMT5で24h無人生成する。
理由＝MT5は1チャートに1EAしか付かない。統合すれば XAUUSD H1 チャート **1枚** で2本のCSVを両方吐ける（CPU/メモリ最小）。

### 移植元（**触らず温存** — 分析用に残す）
- `signals/XAUUSD_Daily_Aggregate_v1.mq5`（OnStart / 29列 / iATR・iADX **9ハンドル**）
- `signals/XAUUSD_Daily_MFE_MAE_v1.mq5`（OnStart / 24列 / CopyHigh・CopyLow、**ハンドル無し**）

### 成果物（新規）
- `signals/XAUUSD_DailyBatch_EA_v1.mq5`

---

## 1. 絶対原則（最優先）

1. **集計・トレースの計算ロジックは1ミリも変えない**。式・周期・JST境界の取り方・DoubleToStringの桁・列順・ヘッダー文字列・四捨五入、すべて移植元のまま。**コピペ移植**であって書き直しではない。
2. **研究目的固定**（MFE_MAE ヘッダーの禁止事項をそのまま継承）: 勝率/PF/月別/損益の目的化禁止、12h/24h/36h セグメントの評価ラベル化禁止、推定値・補完値の混入禁止。
3. 出力は **UTF-8 BOM** のまま。ファイル名据え置き（`daily_aggregate.csv` / `daily_mfe_mae_48h.csv`）、列数（29 / 24）も不変。

---

## 2. EA骨格（3イベント）

```cpp
int OnInit()
{
   if(_Symbol != Allowed_Symbol)       return(INIT_FAILED);   // XAUUSD以外で起動拒否
   if(!Agg_InitHandles())              return(INIT_FAILED);   // iATR/iADX 9本
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);                         // 初回は短く（既定15秒）
   return(INIT_SUCCEEDED);
}

void OnTimer()
{
   if(!HandlesReady()) return;                  // 9ハンドル BarsCalculated>0 まで持ち越し
   if(g_first_run) {                            // ready初回だけ本間隔へ張り替え
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);  // 既定 60分
      g_first_run = false;
   }
   Agg_GenerateCsv();   // 旧 Daily_Aggregate OnStart 本体（FileOpen→120日ループ→FileClose）
   Mfe_GenerateCsv();   // 旧 Daily_MFE_MAE  OnStart 本体（同上）
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Agg_ReleaseHandles();
}
```

- **旧 OnStart の `Sleep(2000)` は移植しない**。`HandlesReady()`（BarsCalculatedゲート）で代替する。
- 旧 OnStart の FATAL時 `return;` は、Generate関数内では「その回はスキップして return」に読み替える。

---

## 3. 名前衝突の解消 ★統合の肝

2本に同名の関数・input・グローバルが散在する。下記ルールで解消。

### (a) 共通化する（両者で同一ロジック → 1セットだけ残す）
`JstToServer` / `ServerToJst` / `FormatJstDate` / `FormatJstDateTime` / `WriteUtf8Bom` / `WriteUtf8String` / `ParseHHMM`
> ※ `FormatJstDate` は引数名違い（jst_midnight / jst）だがロジック同一 → 1本に統一。

### (b) 接頭辞 `Agg_` / `Mfe_` で分離する（同名だが中身が違う）
- `Agg_ProcessDay` / `Mfe_ProcessDay`
- `Agg_WriteHeaderUtf8` / `Mfe_WriteHeaderUtf8`
- `Agg_WriteRow` / `Mfe_WriteRow`
- Agg専用: `Agg_InitHandles` `Agg_ReleaseHandles` `Agg_AggregateH4` `Agg_AggregateH1` `Agg_AggregateRange` `Agg_GetBufValue` `Agg_ClassifyDiDir`
- Mfe専用: `Mfe_TraceMaeMfe_Segmented`
- 新規: `Agg_GenerateCsv`（旧Agg OnStartのCSV生成部）/ `Mfe_GenerateCsv`（旧Mfe OnStartのCSV生成部）/ `HandlesReady`

### (c) グローバル変数
- カウンタ: `g_agg_rows_written` `g_agg_rows_skipped` / `g_mfe_rows_written` `g_mfe_rows_skipped` `g_mfe_rows_partial`
- ハンドル: `hAgg_ATR_S_H1` … のように `hAgg_` 接頭辞（9本）
- `bool g_first_run`

---

## 4. input 整理（group で見やすく）

```
=== 共通 ===
  Allowed_Symbol="XAUUSD" / Lookback_Days=120
  JST_Offset_Hours=9 / Use_Auto_Server_Offset=true / Manual_Server_Offset_Hours=2 / Verbose=true
=== EA制御（新規）===
  Update_Interval_Min=60 / First_Run_Delay_Sec=15
=== 出力ファイル ===
  Agg_Output_File="daily_aggregate.csv" / Mfe_Output_File="daily_mfe_mae_48h.csv"
=== Aggregate 指標周期 ===
  H1_ATR_Short=16 / H1_ATR_Long=32 / H1_ADX_Period=32
  H4_ATR_Short=8  / H4_ATR_Long=46 / H4_ADX_Period=46
  D1_ATR_Short=22 / D1_ATR_Long=42 / D1_ADX_Period=22
  DI_Spread_Flat_Thresh=1.0
=== MFE/MAE ===
  Virtual_Entry_Time_JST="14:00" / H1_Trace_Bars_48h=48
```

- `Lookback_Days` は両者とも120で意味も同じ → **共通input 1個**に統合。各Generate関数内のループ方向は移植元のまま（Aggは新→古、Mfeは古→新）維持。
- `#property script_show_inputs` は **削除**（EAはinput自動表示）。`#property strict` は残す。`#property version "1.00"`。

---

## 5. 受け入れ条件（コー自己チェック）

1. コンパイル **0 error / 0 warning**
2. XAUUSD H1 にアタッチ → 初回（最大 `First_Run_Delay_Sec` + 計算待ち）で `daily_aggregate.csv` と `daily_mfe_mae_48h.csv` が**両方**再生成される
3. ヘッダー行・列数（**29 / 24**）・**UTF-8 BOM** が Script版と**完全一致**
4. **回帰テスト**: EA起動直後に Script版2本も同時刻で手動実行 → 出力CSVを比較。
   **3営業日より前の行（48h確定済みゾーン）が完全一致**すること。
   ※直近2〜3営業日は「実行時刻」でMFE48hが伸びるため一致しない＝正常。比較対象外。
5. 1時間後、2回目の `OnTimer` が発火しCSVが更新される（タイムスタンプ進む）

---

## 6. 触らないもの

- Script版2本（`XAUUSD_Daily_Aggregate_v1.mq5` / `XAUUSD_Daily_MFE_MAE_v1.mq5`）= 温存
- 他の mq5、CSVの列仕様・ファイル名・エンコード
- AutoTrading は運用側でON（EAは売買しないがデータ出力にEA稼働が要る）

---

## 7. 完了後にメインおぱへ返すこと

- 新規 `XAUUSD_DailyBatch_EA_v1.mq5` のパスとコンパイル結果
- 回帰テストの diff 結果（一致した行範囲 / 不一致は直近何日か）
- 実装中に気づいた移植上の注意点（あれば）

> 戦略判断・フィルター・列追加は **しない**。この指示書の範囲を忠実に実装する。判断が要る箇所はメインおぱへ質問で返す。
