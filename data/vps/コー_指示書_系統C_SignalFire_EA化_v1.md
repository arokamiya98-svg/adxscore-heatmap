# コー指示書 — 系統C シグナル発火ログ EA化（専用EA v1）

> 発行: 2026-06-19 別荘セッション④（おぱ）
> 設計根拠: `data/vps/VPS_UNMANNED_DESIGN.md`（系統C＝signal_fires のVPS無人化、★最重要）
> あろさん判断（2026-06-19）: **系統C専用EA・新規（XAUUSD H1 もう1チャートに単独アタッチ）採用**
> 前例: `data/vps/コー_指示書_系統B_DailyBatch_EA化_v1.md`（同じ移植パターン）

---

## 0. これは何

系統C（シグナル発火ログ）の **Script 1本を専用の常駐EAに移植** し、VPS上のMT5で24h無人生成する。

### 設計上の確定事項（重要・OnTick案は不採用）
- 設計書では「OnTick化が本命」とあったが、**コード突き合わせの結果 OnTimerフル上書き（過去再現）を採用**。
- 理由: `signal_fires.csv` の核心列である **MFE/MAE 48h（12/24/36/48hの12列）は発火時点では計算不能**（発火バーの先48本がまだ存在しない）。過去再現でしか出せない。
- OnTimerで毎回 `BT_StartTime`〜直近確定足を**フル再生成・上書き**すれば、設計書のゴール（取りこぼしゼロ・フォワード完全化・軸Aと同じMT5常駐基盤）は完全達成。かつ最近の発火はMFE/MAEが時間経過で自動的に48hまで埋まる（系統Bの「穴埋まる」と同思想）。

### 移植元（**触らず温存** — 分析用に残す）
- `signals/Signal_Fire_Logger_v1.mq5`（OnStart / 65列 / iATR・iADX・iMA **10ハンドル** / series一括コピー方式）

### v4本体（**絶対に不可侵**）
- `signals/ATR_WidthSignal_v4.mq5` は読むだけ・一切変更しない（Loggerヘッダー L10 の固定原則を継承）。本EAも v4 を import/参照せず、Loggerに移植済みの定数・ロジックをそのまま使う。

### 成果物（新規）
- `signals/Signal_Fire_Logger_EA_v1.mq5`

---

## 1. 絶対原則（最優先）

1. **発火判定・フィルター・MFE/MAE の計算ロジックは1ミリも変えない**。式・周期・閾値・shift規約・`DoubleToString`の桁・列順・ヘッダー文字列・四捨五入、すべて移植元のまま。**コピペ移植**であって書き直しではない。
2. **研究目的固定**（Loggerヘッダー L7-13 を継承）: v4発火の過去再現でシグナル理解を深めるのが目的。シグナル改良・最適化・結果フィッティングは目的に含まない。MFE/MAEはシグナル評価文脈なのでOK。
3. 出力は **UTF-8 BOM** のまま。ファイル名据え置き（`signal_fires.csv`）、**65列**・列順も不変。
4. **走査期間は `BT_StartTime`/`BT_EndTime` 方式を維持**（系統Bの `Lookback_Days` 方式には変えない）。フォワードは検証開始日からの連続積み上げが自然なため。

---

## 2. EA骨格（3イベント）— 系統Bと同型

```cpp
int OnInit()
{
   if(_Symbol != ALLOWED_SYMBOL)  return(INIT_FAILED);   // XAUUSD以外で起動拒否
   if(!Fire_InitHandles())        return(INIT_FAILED);   // iATR/iADX/iMA 10本
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);                    // 初回は短く（既定15秒）
   return(INIT_SUCCEEDED);
}

void OnTimer()
{
   if(!HandlesReady()) return;                   // 10ハンドル BarsCalculated>0 まで持ち越し
   if(g_first_run) {                             // ready初回だけ本間隔へ張り替え
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);   // 既定 60分
      g_first_run = false;
   }
   RunFullScan();   // 旧 OnStart 本体（データ取得→FileOpen→走査ループ→FileClose）
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Fire_ReleaseHandles();
}
```

- **旧 OnStart の `Sleep(3000)` は移植しない**。`HandlesReady()`（BarsCalculatedゲート）で代替する。
- 旧 OnStart の FATAL時 `return;` は、`RunFullScan()` 内では「その回はスキップして return」に読み替える（EAは生かしたまま次回OnTimerで再試行）。
- **ハンドル解放は `RunFullScan()` 内で呼ばない**。ハンドルは常駐維持し、`OnDeinit` の `Fire_ReleaseHandles()` でのみ解放（旧 OnStart 末尾の `ReleaseAll` はここへ移設）。

---

## 3. 系統Bとの最大の違い ＝ 名前衝突の解消は不要

- 系統Bは2本統合だったため `Agg_`/`Mfe_` 接頭辞でリネームが必要だった。
- **系統CはScript 1本の単独移植** → 関数名・構造体・定数の衝突は起きない。**Loggerの中身をそのまま使える**（`CalcATRMedian` / `FindATRCross` / `AtrPattern` / `FindBarIndexAtOrBefore` / `ServerToJst` / `FormatDateTime` / `RecordFire` / `ComputeFilters` / `TraceFireMaeMfe` / `BoolStr` / `WriteUtf8Bom` / `WriteUtf8String` / `WriteHeaderUtf8` / `WriteRow` / 構造体 `FireRow` / 定数群 すべてリネーム不要）。
- 別EA・別チャートで系統B DailyBatch EA と同居するが、**.ex5は独立コンパイル**なので関数名がDailyBatch側と被っても無関係（同一ファイル内衝突ではない）。

---

## 4. OnStart → RunFullScan() 切り出しの具体

旧 `OnStart`（L235-663）を下記のように分解する。

### (a) OnInit へ移すもの
- 開始Print（任意）／シンボル制約チェック（`_Symbol != ALLOWED_SYMBOL` → `INIT_FAILED`）
- **ハンドル生成（10本）**を `Fire_InitHandles()` に切り出し、**グローバル変数化**（接頭辞 `hFire_` 推奨・任意）。
  - `hFire_ATR_S_H1` `hFire_ATR_L_H1` `hFire_ADX_H1` `hFire_MA_H1`（H1=4）
  - `hFire_ATR_S_H4` `hFire_ATR_L_H4` `hFire_ADX_H4`（H4=3）
  - `hFire_ATR_S_D1` `hFire_ATR_L_D1` `hFire_ADX_D1`（D1=3）

### (b) HandlesReady() 新設（旧 Sleep(3000) の代替）
- 上記10ハンドルすべて `!= INVALID_HANDLE` かつ `BarsCalculated(h) > 0` で `true`。

### (c) RunFullScan() ＝ 旧 OnStart の残り全部
旧 OnStart から「開始Print・シンボルチェック・ハンドル生成・`Sleep(3000)`・末尾`ReleaseAll`」を除いた本体を移植:
1. カウンタを冒頭で0リセット（`g_fire_count=0; g_pass_count=0; g_bars_scanned=0;`）← 毎回フル再生成のため
2. `iBarShift(BT_StartTime)` → `start_idx`（不正なら return でその回スキップ）
3. `copy_size` 計算 + H1/H4/D1 一括 `CopyBuffer`・`CopyClose/High/Low/Time`（移植元のまま）
4. `FileOpen(OUTPUT_FILE, FILE_WRITE|FILE_BIN)` + `WriteUtf8Bom` + `WriteHeaderUtf8`
5. メインループ `for(i = scan_oldest; i >= 1; i--)`（i=0形成中は判定しない）＝移植元のまま
6. `FileClose` + 完了Print（`ReleaseAll`は呼ばない）

### (d) Fire_ReleaseHandles() ＝ 旧 ReleaseAll をグローバル参照に
- 旧 `ReleaseAll(h1..h10)`（引数10個）を、グローバルハンドルを直接解放する引数なし関数に。OnDeinit から呼ぶ。

### (e) ServerToJst は移植元のまま
- `TimeTradeServer()-TimeGMT()` 自動算出のまま（input化しない）。過去のDST跨ぎは `time_server` 列が厳密値（移植元コメント L913-914 の仕様を維持）。

---

## 5. input 整理（group で見やすく）

```
=== 走査期間（移植元から維持）===
  BT_StartTime = D'2025.03.01 00:00'   // 走査開始（サーバー時刻）
  BT_EndTime   = 0                      // 0 = 実行時点まで
=== EA制御（新規）===
  Update_Interval_Min = 60   // ready後の再生成周期（分）
  First_Run_Delay_Sec = 15   // 初回タイマー（ready待ちの短間隔, 秒）
=== 出力 ===
  Output_File = "signal_fires.csv"
=== デバッグ ===
  Verbose = true
```

- 移植元で `const` だった v4由来の定数（周期・閾値群 L71-139）は **const のまま据え置き**（input化禁止＝Loggerの原則）。
- `#property script_show_inputs` は **削除**。`#property strict` は残す。`#property version "1.00"`。`#property indicator_chart_window` 等は付けない（EAなので不要）。
- `OUTPUT_FILE` は const から input `Output_File` へ昇格（回帰検証で一時的に別名出力するため。既定は `signal_fires.csv`）。

---

## 6. 受け入れ条件（コー自己チェック）

1. コンパイル **0 error / 0 warning**
2. XAUUSD H1 にアタッチ → 初回（最大 `First_Run_Delay_Sec` + 計算待ち）で `signal_fires.csv` が再生成され、ヘッダー65列・**UTF-8 BOM** がScript版と一致
3. **回帰テスト（バイト一致）**: EA起動直後にScript版 `Signal_Fire_Logger_v1` も**同じ `BT_StartTime` で近接時刻に手動実行** → 両CSVを比較。
   - 比較は **発火時刻が実行時点から48h以前の発火行が完全一致**すること（`fire_id`/全列）。
   - ※直近48h以内の発火は MFE/MAE 48h がまだ伸びる＆最新確定足の有無で発火数が前後する → 末尾は不一致＝正常（比較対象外）。
   - ※DSTオフセットは実行時自動算出のため、両者を近接時刻で実行して揃える。
   - 検証時は EA側 `Output_File` を `signal_fires_EA.csv` にしてScript版 `signal_fires.csv` とdiff（系統Bと同じ流儀）。一致確認後 `signal_fires.csv` に戻す。
4. 1時間後、2回目の `OnTimer` が発火し `signal_fires.csv` が更新される（タイムスタンプ進む）

---

## 7. 触らないもの

- `signals/ATR_WidthSignal_v4.mq5`（読むだけ・不可侵）
- Script版 `signals/Signal_Fire_Logger_v1.mq5`（温存・分析用に残す）
- 他の mq5、CSVの列仕様（65列）・ファイル名・エンコード（UTF-8 BOM）
- AutoTrading は運用側でON（EAは売買しないがデータ出力にEA稼働が要る）

---

## 8. 運用上の注意（VPS_UNMANNED_DESIGN.md より）

- VPS MT5 は **XAUUSD のヒストリーDL必須**。`BT_StartTime=2025.03.01` 起点だと H1 約11000本＋中央値960本＋48hトレース分の履歴が要る。チャートの「最大バー数」を十分に（履歴不足だと期間前半がskipされる＝移植元と同挙動）。
- 全期間フル走査がVPSで重い場合、`BT_StartTime` を直近（例 `2026.01.01`）に狭めて負荷調整可能（input操作のみ・あろさん判断）。まず回帰検証は移植元と同じ期間で。
- `FileOpen` は相対パス（MQL5/Files基準）＝Mac→VPSでコード不変。
- **★.ex5は必ず MetaEditor F7 で再コンパイル**（コマンドライン.ex5はMT5起動中ロード不可＝前回の556ハマり教訓）。

---

## 9. 完了後にメインおぱへ返すこと

- 新規 `signals/Signal_Fire_Logger_EA_v1.mq5` のパスとコンパイル結果（error/warning数）
- 旧 OnStart → RunFullScan/OnInit/OnTimer/OnDeinit への分解で、移植元から動かした箇所の一覧（ロジック非改変の確認）
- 実装中に気づいた移植上の注意点（あれば）

> 戦略判断・フィルター変更・列追加は **しない**。この指示書の範囲を忠実に実装する。判断が要る箇所はメインおぱへ質問で返す。
