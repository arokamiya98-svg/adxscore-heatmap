# コー指示書 — ②自動集計 ADX_Weekly EA化（v1）

> 発行: 2026-06-26（おぱ）
> 設計根拠: 週次パイプライン②自動集計のVPS無人化（[[vps-daily-automation-ea-design]]）
> あろさん判断（2026-06-26）: **別々2EA採用**。チャート計4枚でVPS稼働可。
> 関連指示書: `コー_指示書_②自動集計_H4PhaseAuto_EA化_v1.md`（対の片割れ）

---

## 0. これは何

週次ヒートマップの **ADXスコア計算元CSV を焼く `ADX_Weekly_Above_v4` の Script を常駐EA化** する。
H4PhaseAuto と並んで②自動集計の上流。現状は手動Scriptで MT5側 2週遅れ。
EA化して毎時自動実行 → VPSが毎時CSV更新 → push → Mac `hourly_sync` 受信 → 週次heatmap毎時再生成。
**狙い：進行中週は手描きBU/PD空のまま、ADXスコアだけ毎時最新。**

### 移植元（**触らず温存** — 正本）
- `signals/ADX_Weekly_Above_v4.mq5`（OnStart / **17列** / 銘柄ループ内で iADX 都度生成・解放 / UTF-16出力 / 342行）

### 成果物（新規）
- `signals/ADX_Weekly_Above_EA_v1.mq5`

---

## 1. 絶対原則（最優先）

1. **集計ロジックは1ミリも変えない**。H4週集計（移植元138-175行）・H1ループFLUSH集計（187-246行）・`GetPipFactor`/`FindWeek`/`GetWeekKey`/`GetWeekStart` は**全て無改変コピペ**。周期（H1=32/H4=46）・閾値（`InpThresh_Low=20`/`InpThresh_H4Hi=25`）・列順・ヘッダー文字列・`DoubleToString` 桁、すべて移植元のまま。
2. **出力は UTF-16 のまま**（`FILE_WRITE|FILE_CSV|FILE_UNICODE`・移植元31行）。ファイル名 `ADX_Weekly_Above_v4.csv`・**17列**不変。
   ※ 系統B/CはUTF-8 BOMだが、**こいつはUTF-16**。揃えない。
3. **銘柄ループ構造（`InpSymbols` 分割・48行〜）は温存**。グローバルハンドル化しない（後述）。

---

## 2. EA骨格（3イベント）— H4Phaseと違い「本体まるごとOnTimer」方式

ADX_Weekly は **銘柄ループ内で iADX を都度生成→`CopyBuffer(日付範囲)`→`IndicatorRelease`** する構造（移植元64-82・102-120行）。
系統B/Cの「固定ハンドルをグローバル常駐」とは相性が悪いので、**ハンドル管理は移植元のまま無改変**にし、OnStart本体まるごとを `OnTimer` から呼ぶ。

```cpp
int OnInit()
{
   if(_Symbol != Allowed_Symbol)  return(INIT_FAILED);   // XAUUSD H1チャート運用前提（誤アタッチ防止）
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);                    // 初回は短く（既定15秒）
   return(INIT_SUCCEEDED);
   // ※ ハンドルはOnInitで作らない（本体内で銘柄ループ都度生成のため）
}

void OnTimer()
{
   if(!DataReady()) return;                      // H1/H4バーが十分ロードされるまで持ち越し（後述）
   if(g_first_run) {                             // ready初回だけ本間隔へ張り替え
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);   // 既定 60分
      g_first_run = false;
   }
   RunWeeklyAggregate();   // 旧 OnStart 本体まるごと（FileOpen→銘柄ループ→FileClose）
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // ハンドルは本体内で都度 IndicatorRelease 済み → 追加解放不要
}
```

- **`DataReady()` ゲート（新規・重要）**：グローバルハンドルが無いので `BarsCalculated` は使えない。代わりに
  `Bars(_Symbol, PERIOD_H1) > InpH1_Period+100 && Bars(_Symbol, PERIOD_H4) > InpH4_Period+100`
  でゲートする。**データ未ロード時に本体を走らせて「ヘッダだけの空CSV」を吐く事故を防ぐ**（空CSVがpushされるとMac heatmapが壊れる）。系統B/Cの `HandlesReady()` に相当する役割。
- 本体内の既存SKIP（`if(h1_n_adx<=0) continue` 等・移植元84-91/122-128行）は**そのまま残す**＝二重のフェイルセーフ。
- 本体冒頭の `FileOpen(FILE_WRITE)` は**フル上書き**（移植元31行）＝追記事故なし。毎時まるごと焼き直す。

---

## 3. 移植マッピング（旧OnStart → EA）

| 移植元 OnStart | 行 | EAでの行き先 |
|---|---|---|
| OnStart 本体まるごと（FileOpen→銘柄ループ→FileClose→完了Print） | 25-266 | **`RunWeeklyAggregate()`** にリネームし OnTimer から呼ぶ |
| ┗ 銘柄ループ内のハンドル生成/CopyBuffer/Release | 64-134 | **無改変**（都度生成・都度解放のまま） |
| ┗ H4週集計・H1ループFLUSH | 138-246 | **無改変**（FLUSH機構が進行中週を出す・§5） |
| 純粋関数（GetPipFactor/FindWeek/GetWeekKey/GetWeekStart） | 271-341 | **無改変コピペ** |

- 実質「`void OnStart()` → `void RunWeeklyAggregate()` にリネームし、OnInit/OnTimer/OnDeinit と `DataReady()` を足すだけ」。本体は触らない。

---

## 4. input 整理（group で見やすく）

```
=== 共通 ===
  Allowed_Symbol="XAUUSD"          ← 新規（誤アタッチ防止）
=== EA制御（新規）===
  Update_Interval_Min=60 / First_Run_Delay_Sec=15 / Verbose=true
=== 集計対象（移植元から維持）===
  InpSymbols="XAUUSD" / InpStartDate=2023.01.01 / InpEndDate=2027.12.31
  InpH1_Period=32 / InpH4_Period=46
  InpThresh_Low=20.0 / InpThresh_H4Hi=25.0
=== 出力 ===
  InpFileName="ADX_Weekly_Above_v4.csv"
```

- `#property script_show_inputs` は **削除**。`#property strict` / `#property version "1.00"` を付与（移植元には無いので追加）。
- ⚠️ `InpSymbols="XAUUSD"` は温存するが、`Allowed_Symbol` チェックで実質XAUUSD単一運用。**将来複数銘柄に戻す時は `_Symbol` チェックを外す**旨コメントを残す。

---

## 5. 進行中週 ＝ 毎時更新の肝（コーに明示）★

移植元の **H1ループ FLUSH機構（187-246行）はそのまま維持**。
ループは `for(i=0; i<=h1_n; i++)`、`i==h1_n` で `wk="FLUSH"` を立て、直前の週（=最後の実週）を必ず FileWrite する。
`CopyTime` が返す最後のバー＝**今このさっき確定した今週(W26)のH1バー** なので、**進行中週（今週・暫定値）が最終行に出る**。H4側も全週集計済みで `FindWeek` から今週分が引ける。**ここを削ったら毎時更新が死ぬ。絶対維持。**

---

## 6. 受け入れ条件（コー自己チェック）

1. コンパイル **0 error / 0 warning**（MetaEditor F7。.ex5不可・mq5が正本）
2. XAUUSD **H1** チャートにアタッチ → 初回（最大 `First_Run_Delay_Sec`+計算待ち）で `ADX_Weekly_Above_v4.csv` が再生成される
3. ヘッダー行・**17列**・**UTF-16** が Script版と**完全一致**
4. **回帰テスト**: EA起動直後に Script版（`ADX_Weekly_Above_v4.mq5`）も同時刻で手動実行 → 出力CSVを比較。**確定済みの過去週は完全一致**すること。
   ※ **最新週（進行中週）は実行時刻で ADX/バー数が動くため一致しないのが正常**＝比較対象外。
5. 1時間後、2回目の `OnTimer` が発火し CSV が更新される
6. **空CSV事故が出ないこと**：データ未ロード状態で起動しても `DataReady()` が持ち越し、ヘッダだけのCSVを書かない

---

## 7. 触らないもの

- Script版（`ADX_Weekly_Above_v4.mq5`）= 温存（正本）
- 集計ロジック全部・FLUSH機構・列仕様（17列）・**UTF-16エンコード**・ファイル名
- ⚠️ `ADX２８検証ファイル/` は**参照禁止**（あろさん明言・周期混在防止）。移植元は `signals/` の現物のみ。
- AutoTrading は運用側でON

---

## 8. 完了後にメインおぱへ返すこと

- 新規 `ADX_Weekly_Above_EA_v1.mq5` のパスとコンパイル結果（error/warning数）
- 回帰テストの diff 結果（確定週が一致したか / 最新週のズレ幅）
- `DataReady()` のしきい値（H1/H4最小バー数）に使った値と根拠
- 実装中に気づいた移植上の注意点（あれば）

> VPSへの配置・チャートアタッチ・schtasks/AutoTrading は **ブン担当**（コーはローカル実装＋コンパイル＋回帰まで）。
> 戦略判断・閾値変更・列追加は **しない**。判断が要る箇所はメインおぱへ質問で返す。
