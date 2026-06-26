# コー指示書 — ②自動集計 H4PhaseAuto EA化（v1）

> 発行: 2026-06-26（おぱ）
> 設計根拠: 週次パイプライン②自動集計のVPS無人化（[[vps-daily-automation-ea-design]]）
> あろさん判断（2026-06-26）: **別々2EA採用**（H4PhaseAuto単独EA / ADX_Weekly単独EA）。チャート計4枚でVPS稼働可。
> 関連指示書: `コー_指示書_②自動集計_ADX_Weekly_EA化_v1.md`（対の片割れ）

---

## 0. これは何

週次ヒートマップの上流CSVを焼く **H4 Phase Auto（5段階）の Script を常駐EA化** する。
現状あろさんが週末に手動でMT5を回すまで更新されない → MT5側で 6/13〜15 から停止し2週遅れ（W26なのに中身W24）。
EA化して毎時自動実行 → VPSが毎時CSV更新 → push → Mac `hourly_sync` 受信 → 週次heatmap毎時再生成。
**狙い：進行中週は手描きBU/PD空のまま、H4Phaseだけ毎時最新**＝「蓄積データで相場を見ながら戦略確認」を実現する。

### 移植元（**触らず温存** — 分析用に残す）
- `signals/ARO_H4PhaseAuto_v1.mq5`（OnStart / 10列 / iATR **2ハンドル**・既にグローバル / UTF-16出力）

### 成果物（新規）
- `signals/ARO_H4PhaseAuto_EA_v1.mq5`

---

## 1. 絶対原則（最優先）

1. **判定ロジックは1ミリも変えない**。`IsoWeek` / `FindATRCross` / `CrossDirLabel` / `H4PhaseAuto` / `WriteHeader` / `WriteRow` は**全て無改変コピペ**。閾値（`Nagi_Thresh=0.97` / `Nagi_Diff_Thresh=1.0`）・周期（ATR8/46・CrossLookBack=30）・列順・ヘッダー文字列・`DoubleToString` 桁・`\r\n` 改行、すべて移植元のまま。
2. **出力は UTF-16 のまま**（`FILE_WRITE|FILE_TXT|FILE_UNICODE`・移植元80行）。ファイル名 `H4PhaseAuto_weekly.csv`・**10列**不変。
   ※ 系統B/CはUTF-8 BOMだが、**こいつはUTF-16**。揃えない。間違えるとMac側 `process_wavelog.py` のデコードが壊れる。
3. 認識ツール思想厳守：**点数化禁止・ラベル（BU/PD/凪/収束底/凪離脱/—）のまま**。

---

## 2. EA骨格（3イベント）— 系統B/C型に乗せる

H4PhaseAutoは **ハンドルが既にグローバル**（`hATR_S_H4`/`hATR_L_H4`・移植元52-53行）なので系統B/C型にそのまま乗る。

```cpp
int OnInit()
{
   if(_Symbol != Allowed_Symbol)  return(INIT_FAILED);   // XAUUSD以外で起動拒否（誤アタッチ防止）
   if(!InitHandles())             return(INIT_FAILED);   // iATR 2本（移植元71-76行を切り出し）
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);                    // 初回は短く（既定15秒）
   return(INIT_SUCCEEDED);
}

void OnTimer()
{
   if(!HandlesReady()) return;                   // 2ハンドル BarsCalculated>0 まで持ち越し
   if(g_first_run) {                             // ready初回だけ本間隔へ張り替え
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);   // 既定 60分
      g_first_run = false;
   }
   GenerateCsv();   // 旧 OnStart 本体（FileOpen→週次ループ→FileClose）
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseHandles();
}
```

- **旧 `Sleep(2000)`（移植元77行）は移植しない**。`HandlesReady()`（`BarsCalculated>0` ゲート）で代替。
- **FATAL時の return は「その回スキップ」**に読み替え（FileOpen失敗・Data copy失敗 → CSVを書かずに return、EAは生かして次回 OnTimer 再試行）。

---

## 3. 移植マッピング（旧OnStart → EA）

| 移植元 OnStart | 行 | EAでの行き先 |
|---|---|---|
| ハンドル初期化（`iATR`×2 + INVALID チェック） | 71-76 | **`InitHandles()`** へ切り出し（OnInitから呼ぶ） |
| `Sleep(2000)` | 77 | **削除**（HandlesReady で代替） |
| FileOpen〜WriteHeader〜CopyTime/CopyBuffer〜週次ループ〜FileClose | 79-146 | **`GenerateCsv()`** 本体（OnTimerから呼ぶ） |
| 末尾 `IndicatorRelease`×2 | 148-149 | **`ReleaseHandles()`** へ（OnDeinitからのみ。常駐維持） |
| 純粋関数群（IsoWeek/FindATRCross/CrossDirLabel/H4PhaseAuto/WriteHeader/WriteRow） | 155-307 | **無改変コピペ** |

- **数少ない改変点**：`GenerateCsv()` 内の FATAL return 直前にある `IndicatorRelease`（移植元83-84・105-106行）は**削除**する。ハンドルは常駐維持し OnDeinit でのみ解放するため。
- `HandlesReady()` は新規（`hATR_S_H4`/`hATR_L_H4` が `!=INVALID_HANDLE` かつ `BarsCalculated>0` で true）。

---

## 4. input 整理（group で見やすく）

```
=== 共通 ===
  Allowed_Symbol="XAUUSD"
=== EA制御（新規）===
  Update_Interval_Min=60 / First_Run_Delay_Sec=15 / Verbose=true
=== 期間設定（移植元から維持）===
  Start_Time=D'2020.01.01 00:00' / End_Time=D'2027.12.31 23:59'
=== H4 ATR パラメータ（移植元から維持）===
  H4_ATR_Short=8 / H4_ATR_Long=46 / Cross_LookBack=30
=== 凪判定閾値（移植元から維持）===
  Nagi_Thresh=0.97 / Nagi_Diff_Thresh=1.0
=== 出力 ===
  OutputFile="H4PhaseAuto_weekly.csv"
```

- `#property script_show_inputs` は **削除**（EAはinput自動表示）。`#property strict` / `#property version "1.00"` は残す。

---

## 5. 進行中週 ＝ 毎時更新の肝（コーに明示）★

移植元の **古→新ループ後「最後の週も出力」（137-141行）はそのまま維持**。
`i=0`（series最新＝今このさっき確定したH4バー）まで通過するので、**進行中週（今週・月曜〜現時点までの暫定値）が最終行に出る**。これが「週確定を待たず毎時最新」を成立させる本体。**ここを削ったり「週が閉じてから」に変えたら設計が死ぬ。絶対維持。**

---

## 6. 受け入れ条件（コー自己チェック）

1. コンパイル **0 error / 0 warning**（MetaEditor F7。.ex5不可・mq5が正本）
2. XAUUSD チャートにアタッチ → 初回（最大 `First_Run_Delay_Sec`+計算待ち）で `H4PhaseAuto_weekly.csv` が再生成される
3. ヘッダー行・**10列**・**UTF-16**・`\r\n` 改行が Script版と**完全一致**
4. **回帰テスト**: EA起動直後に Script版（`ARO_H4PhaseAuto_v1.mq5`）も同時刻で手動実行 → 出力CSVを比較。**確定済みの過去週は完全一致**すること。
   ※ **最新週（進行中週）は実行時刻でATR値が動くため一致しないのが正常**＝比較対象外。
5. 1時間後、2回目の `OnTimer` が発火し CSV が更新される（最新週の行が動く）

---

## 7. 触らないもの

- Script版（`ARO_H4PhaseAuto_v1.mq5`）= 温存（分析用）
- 判定関数全部・列仕様（10列）・**UTF-16エンコード**・ファイル名
- 他の mq5
- AutoTrading は運用側でON（EAは売買しないがデータ出力にEA稼働が要る）

---

## 8. 完了後にメインおぱへ返すこと

- 新規 `ARO_H4PhaseAuto_EA_v1.mq5` のパスとコンパイル結果（error/warning数）
- 回帰テストの diff 結果（確定週が一致したか / 最新週のズレ幅）
- 実装中に気づいた移植上の注意点（あれば）

> VPSへの配置・チャートアタッチ・schtasks/AutoTrading は **ブン担当**（コーはローカル実装＋コンパイル＋回帰まで）。
> 戦略判断・閾値変更・列追加は **しない**。判断が要る箇所はメインおぱへ質問で返す。
