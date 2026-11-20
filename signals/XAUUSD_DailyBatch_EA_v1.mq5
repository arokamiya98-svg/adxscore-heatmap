//+------------------------------------------------------------------+
//|  XAUUSD_DailyBatch_EA_v1.mq5                                     |
//|                                                                  |
//|  系統B（日次環境データ）統合EA。                                  |
//|  Script版2本（Aggregate / MFE_MAE）を1つの常駐EAに統合し、        |
//|  VPS上のMT5でXAUUSD H1チャート1枚から2本のCSVを24h無人生成する。  |
//|                                                                  |
//|  移植元（ロジックは1ミリも変えずコピペ移植）:                     |
//|    - XAUUSD_Daily_Aggregate_v1.mq5 (29列 / iATR・iADX 9ハンドル)  |
//|        → daily_aggregate.csv (UTF-8 BOM)                         |
//|    - XAUUSD_Daily_MFE_MAE_v1.mq5  (24列 / CopyHigh・CopyLow)      |
//|        → daily_mfe_mae_48h.csv (UTF-8 BOM)                       |
//|                                                                  |
//|  統合方針（コー_指示書_系統B_DailyBatch_EA化_v1.md）:             |
//|    - OnStart → OnInit / OnTimer / OnDeinit へ移植                 |
//|    - Sleep(2000) は移植せず HandlesReady()（9ハンドル            |
//|      BarsCalculated>0 ゲート）で代替                              |
//|    - 共通ヘルパ（JstToServer / ServerToJst / FormatJstDate /     |
//|      FormatJstDateTime / WriteUtf8Bom / WriteUtf8String）は1本に  |
//|      統一（ParseHHMM は D1始値方式化 2026-06-20 で廃止）          |
//|    - 中身が違う同名は Agg_ / Mfe_ 接頭辞で分離                    |
//|                                                                  |
//|  研究目的（絶対固定 / MFE_MAE ヘッダーより継承）:                 |
//|    - 勝率分析 / PF分析 / 月別集計 / 損益集計の目的化禁止          |
//|    - パターン別重み付け、加熱帯ペナルティ等の判断ロジック混入禁止 |
//|    - 推定値・補完値の混入禁止                                     |
//|    - 12h/24h/36h セグメント値の「評価ラベル化」禁止              |
//|                                                                  |
//|  v1.10 (2026-07-15): DXY環境札（迷い検出札）出力を追加            |
//|    - iADX("USDIndex", H1, 56) の最終確定バー(shift=1) を          |
//|      dxy_env.csv（UTF-8 BOM・1日1行・毎時再生成）へ出力           |
//|    - 失敗時は DXY 部のみスキップ（XAU側 2 CSV を道連れにしない・  |
//|      0値行禁止・次の毎時で自己回復）                              |
//|    - SPEC: data/scriptable/SPEC_dxy_env_card_v1.md               |
//|                                                                  |
//|  v1.11 (2026-11-20): HFM→Exness移行: DXY源を HFM USDIndex →      |
//|    合成 DXY_SYNTH（ICE式から SEK を除いた5項・定数50.14348112）   |
//|    - 合成ロジックは Phase 1 Script                               |
//|      (data/dxy/DXY_Synth_Timeseries_v1.mq5) と同一。ソースTF=M5固定|
//|    - OnInit: DXY_SYNTH 無し/範囲不足のみブートストラップ構築，    |
//|      それ以外は差分のみ                                          |
//|    - OnTimer: XAU側2CSV → DXY_SYNTH 差分更新 → H1同期待ち →       |
//|      既存 Dxy_GenerateCsv（スキーマ・UTF-8 BOM 不変）             |
//|    - 差分更新失敗の回は DXY出力のみ skip（既存 dxy_env.csv 不変） |
//|    - 指示書: data/scriptable/コー_impl_dxy_card_v3_synth.md §4    |
//|    - 検証: data/dxy/DXY_SYNTH_VALIDATION_v1.md v2節（採用）       |
//|                                                                  |
//|  作成日: 2026-06-18                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.11"
#property strict

//+==================================================================+
//| 入力パラメータ                                                    |
//+==================================================================+
input group "=== 共通 ==="
input string  Allowed_Symbol           = "XAUUSDc";  // この銘柄以外は起動拒否（2026-11-20 HFM→Exnessセント移行: XAUUSD→XAUUSDc）
input int     Lookback_Days            = 120;        // 直近 N 日分を出力（両CSV共通）
input int     JST_Offset_Hours         = 9;          // JST = UTC+9（固定）
input bool    Use_Auto_Server_Offset   = true;       // TimeTradeServer-TimeGMT 自動算出
input int     Manual_Server_Offset_Hours = 2;        // 自動算出失敗時のフォールバック
input bool    Verbose                  = true;

input group "=== EA制御 ==="
input int     Update_Interval_Min      = 60;         // 本間隔（ready後の再生成周期, 分）
input int     First_Run_Delay_Sec      = 15;         // 初回タイマー（ready待ちの短間隔, 秒）

input group "=== 出力ファイル ==="
input string  Agg_Output_File          = "daily_aggregate.csv";
input string  Mfe_Output_File          = "daily_mfe_mae_48h.csv";

input group "=== Aggregate H1 指標周期 (CLAUDE.md 確定値) ==="
input int     H1_ATR_Short             = 16;
input int     H1_ATR_Long              = 32;
input int     H1_ADX_Period            = 32;

input group "=== Aggregate H4 指標周期 ==="
input int     H4_ATR_Short             = 8;
input int     H4_ATR_Long              = 46;
input int     H4_ADX_Period            = 46;

input group "=== Aggregate D1 指標周期 ==="
input int     D1_ATR_Short             = 22;
input int     D1_ATR_Long              = 42;
input int     D1_ADX_Period            = 22;

input group "=== Aggregate DI 方向判定 ==="
input double  DI_Spread_Flat_Thresh    = 1.0;        // |spread| < これ なら FLAT 扱い

input group "=== MFE/MAE ==="
//--- 仮想エントリー起点は「その日の D1 足始値 (市場オープン)」固定。      ---
//    旧 Virtual_Entry_Time_JST="14:00" は 2026-06-20 廃止 (D1始値方式へ)。 ---
//    DST は D1 足境界が処理 → 固定時刻の server 変換ハードコードは不要。    ---
input int     H1_Trace_Bars_48h        = 48;         // H1 48本 = 48時間相当

input group "=== DXY環境札 (SPEC_dxy_env_card_v1) ==="
input string  DXY_Symbol               = "DXY_SYNTH"; // 2026-11-20 HFM→Exness移行: HFM USDIndex → 合成DXY（下の合成groupで維持）
input int     DXY_ADX_Period           = 56;          // iADX(DXY_SYNTH, H1, 56)
input string  Dxy_Output_File          = "dxy_env.csv";

input group "=== 合成DXY (DXY_Symbol == Synth_Symbol の時のみ維持) ==="
//--- 合成式: Synth_Const × Π Comp_k^Weight_k（SEK項なし・再正規化なし）---
//    ロジックは Phase 1 Script (DXY_Synth_Timeseries_v1.mq5) と同一。ソースTF=M5固定。
input string  Synth_Symbol             = "DXY_SYNTH";
input string  Synth_Path               = "Synth";     // Custom\Synth に作成
input int     Synth_Digits             = 5;
input double  Synth_Const              = 50.14348112;
input string  Comp1_Symbol             = "EURUSDc";
input double  Comp1_Weight             = -0.576;
input string  Comp2_Symbol             = "USDJPYc";
input double  Comp2_Weight             = 0.136;
input string  Comp3_Symbol             = "GBPUSDc";
input double  Comp3_Weight             = -0.119;
input string  Comp4_Symbol             = "USDCADc";
input double  Comp4_Weight             = 0.091;
input string  Comp5_Symbol             = "USDCHFc";
input double  Comp5_Weight             = 0.036;
input int     Synth_Max_Fill_Hours     = 48;          // 直前値埋めの上限（超えたら埋めない）
input int     Synth_Warmup_Days        = 120;         // ブートストラップ: Lookback_Days + この日数を構築（ADX56助走）
input int     Synth_Chunk_Days         = 7;           // 取得・書込の単位（日）
input int     Synth_Max_Rates_Per_Write = 10000;      // 1回の CustomRates 書込の上限件数
input int     Synth_Rewrite_Overlap_Min = 5;          // 差分: 最終バーのこの分数前から再合成（5=M5の1本前）
input int     Synth_Comp_Lag_Max_Min   = 30;          // 差分: 成分間の最新M5時刻ズレ上限（超えたら今回skip）
input int     Synth_H1_Wait_Sec        = 30;          // 差分後: H1同期・BarsCalculated 待ち上限（秒）

//+==================================================================+
//| グローバル: 指標ハンドル（Aggregate専用, hAgg_ 接頭辞）           |
//+==================================================================+
int hAgg_ATR_S_H1 = INVALID_HANDLE, hAgg_ATR_L_H1 = INVALID_HANDLE, hAgg_ADX_H1 = INVALID_HANDLE;
int hAgg_ATR_S_H4 = INVALID_HANDLE, hAgg_ATR_L_H4 = INVALID_HANDLE, hAgg_ADX_H4 = INVALID_HANDLE;
int hAgg_ATR_S_D1 = INVALID_HANDLE, hAgg_ATR_L_D1 = INVALID_HANDLE, hAgg_ADX_D1 = INVALID_HANDLE;

//--- DXY環境札用（初期化時に1回生成・失敗しても XAU側は道連れにしない）---
int hDxy_ADX = INVALID_HANDLE;

//+==================================================================+
//| グローバル: 出力カウンタ                                          |
//+==================================================================+
int g_agg_rows_written = 0;
int g_agg_rows_skipped = 0;   // 営業日でない日（土日・H1足なし）

int g_mfe_rows_written = 0;
int g_mfe_rows_skipped = 0;
int g_mfe_rows_partial = 0;   // 48本フル追跡できなかった行

int g_dxy_rows_written = 0;
int g_dxy_rows_skipped = 0;   // 非営業日・確定バー無し・値<=0（0値行禁止）

//+==================================================================+
//| グローバル: EA制御                                                |
//+==================================================================+
bool g_first_run = false;

//+==================================================================+
//| OnInit                                                           |
//+==================================================================+
int OnInit()
{
   Print("==== XAUUSD_DailyBatch_EA v1.11 OnInit ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, Allowed_Symbol);
   PrintFormat("Agg_Output: %s / Mfe_Output: %s / Dxy_Output: %s",
               Agg_Output_File, Mfe_Output_File, Dxy_Output_File);
   PrintFormat("Lookback_Days: %d", Lookback_Days);

   //--- シンボル制約: XAUUSD以外で起動拒否 ---
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return(INIT_FAILED);
   }

   //--- ハンドル初期化（iATR/iADX 9本）---
   if(!Agg_InitHandles())
   {
      Print("[FATAL] 指標ハンドル初期化に失敗。終了。");
      return(INIT_FAILED);
   }

   //--- 合成DXY 維持（v1.11）: 無い/範囲不足ならブートストラップ、十分なら差分のみ ---
   //    失敗しても INIT_FAILED にしない（OnTimer で毎回再試行・XAU側は道連れにしない）
   if(Synth_IsEnabled())
      Synth_Ensure();

   //--- DXYハンドル初期化（失敗しても INIT_FAILED にしない = XAU側を道連れにしない）---
   Dxy_InitHandle();

   //--- 初回は短く（ready待ち）---
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);

   return(INIT_SUCCEEDED);
}

//+==================================================================+
//| OnTimer                                                          |
//+==================================================================+
void OnTimer()
{
   //--- 9ハンドルの計算完了まで持ち越し（旧 Sleep(2000) の代替）---
   if(!HandlesReady())
   {
      if(Verbose) Print("[WAIT] indicator handles not ready yet...");
      return;
   }

   //--- ready初回だけ本間隔へ張り替え ---
   if(g_first_run)
   {
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);
      g_first_run = false;
      if(Verbose)
         PrintFormat("[INFO] handles ready. timer → %d min interval.",
                     Update_Interval_Min);
   }

   //--- 2本のCSVを再生成 ---
   Agg_GenerateCsv();
   Mfe_GenerateCsv();

   //--- DXY環境札CSV（失敗時はDXY部だけスキップ・XAU側に影響しない）---
   //    v1.11: 合成DXY の差分更新 → H1同期待ち に失敗した回は DXY出力のみ skip
   //           （FileOpen 前に return ＝ 既存 dxy_env.csv を壊さない）
   if(Synth_IsEnabled())
   {
      if(!Synth_Ensure())
      {
         Print("[SKIP] [Dxy] [Synth] 合成DXY 更新失敗 → 今回のDXY出力スキップ（既存 dxy_env.csv 不変・XAU側は出力済）.");
         return;
      }
      //--- OnInit 時に DXY_SYNTH が未構築でハンドル生成に失敗していた場合の再試行 ---
      if(hDxy_ADX == INVALID_HANDLE)
         Dxy_InitHandle();
      if(!Synth_WaitH1Ready())
      {
         Print("[SKIP] [Dxy] [Synth] H1 同期/BarsCalculated 待ちタイムアウト → 今回のDXY出力スキップ（既存 dxy_env.csv 不変）.");
         return;
      }
   }
   Dxy_GenerateCsv();
}

//+==================================================================+
//| OnDeinit                                                         |
//+==================================================================+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Agg_ReleaseHandles();
   if(hDxy_ADX != INVALID_HANDLE) IndicatorRelease(hDxy_ADX);
   PrintFormat("==== XAUUSD_DailyBatch_EA v1.11 OnDeinit (reason=%d) ====", reason);
}

//+==================================================================+
//| HandlesReady                                                     |
//|   9ハンドルすべて BarsCalculated>0 になったら true。              |
//|   旧 OnStart の Sleep(2000) ゲートの代替。                        |
//|   ※ hDxy_ADX は含めない（DXY未readyでXAU側を遅延させない。        |
//|      DXY側の ready 判定は Dxy_GenerateCsv 冒頭で個別に行う）      |
//+==================================================================+
bool HandlesReady()
{
   int handles[9];
   handles[0] = hAgg_ATR_S_H1; handles[1] = hAgg_ATR_L_H1; handles[2] = hAgg_ADX_H1;
   handles[3] = hAgg_ATR_S_H4; handles[4] = hAgg_ATR_L_H4; handles[5] = hAgg_ADX_H4;
   handles[6] = hAgg_ATR_S_D1; handles[7] = hAgg_ATR_L_D1; handles[8] = hAgg_ADX_D1;

   for(int i = 0; i < 9; i++)
   {
      if(handles[i] == INVALID_HANDLE) return false;
      if(BarsCalculated(handles[i]) <= 0) return false;
   }
   return true;
}

//+##################################################################+
//|                                                                  |
//|  Aggregate パート（旧 XAUUSD_Daily_Aggregate_v1.mq5）            |
//|  ロジックは移植元のまま。関数名・ハンドル・カウンタのみ rename。  |
//|                                                                  |
//+##################################################################+

//+==================================================================+
//| Agg_GenerateCsv                                                  |
//|   旧 Agg OnStart のCSV生成部（FileOpen→120日ループ→FileClose）。 |
//|   ※ シンボル制約・ハンドル初期化・Sleep は OnInit/HandlesReady   |
//|      側へ移したため、ここではCSV生成のみを行う。                  |
//+==================================================================+
void Agg_GenerateCsv()
{
   g_agg_rows_written = 0;
   g_agg_rows_skipped = 0;

   Print("==== [Agg] daily_aggregate generate ====");

   //--- 出力 CSV オープン (UTF-8 BOM) ---
   int fout = FileOpen(Agg_Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] [Agg] 出力CSV open失敗: %s err=%d", Agg_Output_File, GetLastError());
      return;
   }
   WriteUtf8Bom(fout);
   Agg_WriteHeaderUtf8(fout);

   //--- DST 警告 ---
   if(Use_Auto_Server_Offset && Verbose)
   {
      long ofs = (long)(TimeTradeServer() - TimeGMT());
      PrintFormat("[INFO] [Agg] Current server-GMT offset = %d sec (= %.2f h).",
                  (int)ofs, ofs/3600.0);
   }

   //--- メインループ: 今日(JST) から Lookback_Days 日前まで遡って処理 ---
   //   today_jst_midnight = 今日の JST 00:00 (UTC基準の datetime表現)
   datetime now_server = TimeTradeServer();
   datetime now_jst    = ServerToJst(now_server);
   // JST 00:00 へ truncate
   datetime today_jst_midnight = Agg_TruncateToDayJst(now_jst);

   // 古い日から処理（CSVを古い順に並べる）
   for(int d = Lookback_Days - 1; d >= 0; d--)
   {
      datetime day_jst_midnight = today_jst_midnight - (datetime)(d * 86400);
      Agg_ProcessDay(fout, day_jst_midnight);
   }

   FileClose(fout);

   Print("==== [Agg] daily_aggregate Complete ====");
   PrintFormat("  written = %d", g_agg_rows_written);
   PrintFormat("  skipped (no business day) = %d", g_agg_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Agg_Output_File);
}

//+==================================================================+
//| Agg_InitHandles                                                  |
//+==================================================================+
bool Agg_InitHandles()
{
   string sym = _Symbol;
   hAgg_ATR_S_H1 = iATR(sym, PERIOD_H1, H1_ATR_Short);
   hAgg_ATR_L_H1 = iATR(sym, PERIOD_H1, H1_ATR_Long);
   hAgg_ADX_H1   = iADX(sym, PERIOD_H1, H1_ADX_Period);
   hAgg_ATR_S_H4 = iATR(sym, PERIOD_H4, H4_ATR_Short);
   hAgg_ATR_L_H4 = iATR(sym, PERIOD_H4, H4_ATR_Long);
   hAgg_ADX_H4   = iADX(sym, PERIOD_H4, H4_ADX_Period);
   hAgg_ATR_S_D1 = iATR(sym, PERIOD_D1, D1_ATR_Short);
   hAgg_ATR_L_D1 = iATR(sym, PERIOD_D1, D1_ATR_Long);
   hAgg_ADX_D1   = iADX(sym, PERIOD_D1, D1_ADX_Period);

   if(hAgg_ATR_S_H1==INVALID_HANDLE || hAgg_ATR_L_H1==INVALID_HANDLE || hAgg_ADX_H1==INVALID_HANDLE ||
      hAgg_ATR_S_H4==INVALID_HANDLE || hAgg_ATR_L_H4==INVALID_HANDLE || hAgg_ADX_H4==INVALID_HANDLE ||
      hAgg_ATR_S_D1==INVALID_HANDLE || hAgg_ATR_L_D1==INVALID_HANDLE || hAgg_ADX_D1==INVALID_HANDLE)
   {
      PrintFormat("[ERR] ハンドル初期化失敗 err=%d", GetLastError());
      return false;
   }
   return true;
}

void Agg_ReleaseHandles()
{
   if(hAgg_ATR_S_H1 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_S_H1);
   if(hAgg_ATR_L_H1 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_L_H1);
   if(hAgg_ADX_H1   != INVALID_HANDLE) IndicatorRelease(hAgg_ADX_H1);
   if(hAgg_ATR_S_H4 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_S_H4);
   if(hAgg_ATR_L_H4 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_L_H4);
   if(hAgg_ADX_H4   != INVALID_HANDLE) IndicatorRelease(hAgg_ADX_H4);
   if(hAgg_ATR_S_D1 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_S_D1);
   if(hAgg_ATR_L_D1 != INVALID_HANDLE) IndicatorRelease(hAgg_ATR_L_D1);
   if(hAgg_ADX_D1   != INVALID_HANDLE) IndicatorRelease(hAgg_ADX_D1);
}

//+==================================================================+
//| Agg_ProcessDay                                                   |
//|   1営業日分の集計を行う。                                         |
//|   入力: day_jst_midnight = その日の JST 00:00                    |
//|                                                                  |
//|   処理:                                                            |
//|     1. その日 (JST 00:00〜24:00) に H4/H1 足が存在するか →       |
//|        無ければ skip (土日・休場)。                              |
//|        ※ 2026-06-20: 旧「JST 14:00 の H1足存在」判定から、       |
//|          下流 H4/H1 集計レンジに足があるかの判定へ統一。          |
//|          (集計レンジ JST 00:00〜24:00 / D1値取得ロジックは不変)  |
//|     2. JST 23:00 server時刻で D1足取得（その時点確定の D1値）    |
//|     3. JST 00:00〜24:00 範囲の H4/H1 足を走査して max/close/mean |
//|     4. 1行書き出し                                                |
//+==================================================================+
void Agg_ProcessDay(int fout, datetime day_jst_midnight)
{
   //--- 営業日判定: その日 (JST 00:00〜24:00) に H1足が存在するか? ---
   //   集計レンジ [range_start, range_end) の直前足を引いて、
   //   それがレンジ内に収まっていれば営業日とみなす。
   datetime biz_range_start = JstToServer(day_jst_midnight);
   datetime biz_range_end   = JstToServer(day_jst_midnight + 86400);
   int sh_h1_biz = iBarShift(_Symbol, PERIOD_H1, biz_range_end - 1, false);
   if(sh_h1_biz < 0 || iTime(_Symbol, PERIOD_H1, sh_h1_biz) < biz_range_start)
   {
      g_agg_rows_skipped++;
      if(Verbose)
         PrintFormat("[SKIP] %s (no H1 bar in JST day range)",
                     FormatJstDate(day_jst_midnight));
      return;
   }

   string date_str = FormatJstDate(day_jst_midnight);  // "yyyy-mm-dd"

   //--- D1値取得: JST 23:00 server時刻で iBarShift ---
   //   その時点で確定している直前 D1足を取る (exact=false)
   datetime jst_2300 = day_jst_midnight + (datetime)(23 * 3600);
   datetime srv_2300 = JstToServer(jst_2300);
   int sh_d1 = iBarShift(_Symbol, PERIOD_D1, srv_2300, false);
   if(sh_d1 < 0)
   {
      g_agg_rows_skipped++;
      if(Verbose) PrintFormat("[SKIP] %s D1 bar not found", date_str);
      return;
   }

   double d1_atr22 = Agg_GetBufValue(hAgg_ATR_S_D1, 0, sh_d1);
   double d1_atr42 = Agg_GetBufValue(hAgg_ATR_L_D1, 0, sh_d1);
   double d1_adx22 = Agg_GetBufValue(hAgg_ADX_D1,   0, sh_d1);
   double d1_dip   = Agg_GetBufValue(hAgg_ADX_D1,   1, sh_d1);
   double d1_din   = Agg_GetBufValue(hAgg_ADX_D1,   2, sh_d1);
   double d1_ratio = (d1_atr42 > 0) ? d1_atr22 / d1_atr42 : 0;
   double d1_spread = d1_dip - d1_din;
   string d1_di_dir = Agg_ClassifyDiDir(d1_spread);

   //--- H4/H1集計: JST 00:00 〜 翌 00:00 の範囲 ---
   //   range_start_srv (含む) ≤ bar_time < range_end_srv (含まない)
   datetime range_start_srv = JstToServer(day_jst_midnight);
   datetime range_end_srv   = JstToServer(day_jst_midnight + 86400);

   //--- H4 集計 ---
   double h4_adx46_max = 0, h4_adx46_close = 0, h4_adx46_mean = 0;
   double h4_dip_close = 0, h4_din_close = 0;
   double h4_atr8_close = 0, h4_atr46_close = 0;
   Agg_AggregateH4(range_start_srv, range_end_srv,
               h4_adx46_max, h4_adx46_close, h4_adx46_mean,
               h4_dip_close, h4_din_close,
               h4_atr8_close, h4_atr46_close);
   double h4_di_spread = h4_dip_close - h4_din_close;
   string h4_di_dir = Agg_ClassifyDiDir(h4_di_spread);
   double h4_atr_ratio = (h4_atr46_close > 0) ? h4_atr8_close / h4_atr46_close : 0;

   //--- H1 集計 ---
   double h1_adx32_max = 0, h1_adx32_close = 0, h1_adx32_mean = 0;
   double h1_dip_close = 0, h1_din_close = 0;
   double h1_atr16_close = 0, h1_atr32_close = 0;
   Agg_AggregateH1(range_start_srv, range_end_srv,
               h1_adx32_max, h1_adx32_close, h1_adx32_mean,
               h1_dip_close, h1_din_close,
               h1_atr16_close, h1_atr32_close);
   double h1_di_spread = h1_dip_close - h1_din_close;
   string h1_di_dir = Agg_ClassifyDiDir(h1_di_spread);
   double h1_atr_ratio = (h1_atr32_close > 0) ? h1_atr16_close / h1_atr32_close : 0;

   //--- 行書き出し ---
   Agg_WriteRow(fout, date_str,
            d1_adx22, d1_dip, d1_din, d1_spread, d1_di_dir,
            d1_atr22, d1_atr42, d1_ratio,
            h4_adx46_max, h4_adx46_close, h4_adx46_mean,
            h4_dip_close, h4_din_close, h4_di_spread, h4_di_dir,
            h4_atr8_close, h4_atr46_close, h4_atr_ratio,
            h1_adx32_max, h1_adx32_close, h1_adx32_mean,
            h1_dip_close, h1_din_close, h1_di_spread, h1_di_dir,
            h1_atr16_close, h1_atr32_close, h1_atr_ratio);

   g_agg_rows_written++;
   if(Verbose && (g_agg_rows_written % 20 == 0))
      PrintFormat("[INFO] [Agg] processed %d days...", g_agg_rows_written);
}

//+==================================================================+
//| Agg_AggregateH4 / Agg_AggregateH1                                |
//|   指定 server時刻範囲 [start, end) 内の H4/H1 足を走査して       |
//|   max/close/mean を集計する。                                     |
//|                                                                  |
//|   close = 範囲内最終足（範囲内で最も新しい確定足）の値           |
//|   max   = 範囲内全足の最大値                                      |
//|   mean  = 範囲内全足の単純平均                                    |
//|   DI系  = close のみ（範囲内最終足の DI値）                       |
//|   ATR   = close のみ（範囲内最終足の ATR値）                      |
//+==================================================================+
void Agg_AggregateH4(datetime range_start_srv, datetime range_end_srv,
                 double &adx46_max, double &adx46_close, double &adx46_mean,
                 double &dip_close, double &din_close,
                 double &atr8_close, double &atr46_close)
{
   adx46_max = 0; adx46_close = 0; adx46_mean = 0;
   dip_close = 0; din_close = 0;
   atr8_close = 0; atr46_close = 0;

   Agg_AggregateRange(PERIOD_H4, hAgg_ADX_H4, hAgg_ATR_S_H4, hAgg_ATR_L_H4,
                  range_start_srv, range_end_srv,
                  adx46_max, adx46_close, adx46_mean,
                  dip_close, din_close,
                  atr8_close, atr46_close);
}

void Agg_AggregateH1(datetime range_start_srv, datetime range_end_srv,
                 double &adx32_max, double &adx32_close, double &adx32_mean,
                 double &dip_close, double &din_close,
                 double &atr16_close, double &atr32_close)
{
   adx32_max = 0; adx32_close = 0; adx32_mean = 0;
   dip_close = 0; din_close = 0;
   atr16_close = 0; atr32_close = 0;

   Agg_AggregateRange(PERIOD_H1, hAgg_ADX_H1, hAgg_ATR_S_H1, hAgg_ATR_L_H1,
                  range_start_srv, range_end_srv,
                  adx32_max, adx32_close, adx32_mean,
                  dip_close, din_close,
                  atr16_close, atr32_close);
}

//+==================================================================+
//| Agg_AggregateRange                                               |
//|   汎用ヘルパ: tf の足を range_start_srv ≤ bar_time < range_end_srv|
//|   の範囲で走査して max/close/mean を計算。                        |
//|                                                                  |
//|   走査方針:                                                       |
//|     range_end_srv の直前足を iBarShift(range_end_srv-1, false)で  |
//|     探し、そこから古い側へ range_start_srv 直前まで遡る。         |
//|     最新側の足 = close 値（DI/ATR の close もこの足から取る）     |
//+==================================================================+
void Agg_AggregateRange(ENUM_TIMEFRAMES tf,
                    int hADX, int hATR_S, int hATR_L,
                    datetime range_start_srv, datetime range_end_srv,
                    double &adx_max, double &adx_close, double &adx_mean,
                    double &dip_close, double &din_close,
                    double &atr_s_close, double &atr_l_close)
{
   string sym = _Symbol;

   //--- 範囲内最終足 (close用) を探す ---
   //   range_end_srv-1 秒の iBarShift で「end未満の最新確定足」を取る
   datetime probe = range_end_srv - 1;
   int sh_close = iBarShift(sym, tf, probe, false);
   if(sh_close < 0) return;

   datetime t_close = iTime(sym, tf, sh_close);
   if(t_close < range_start_srv)
   {
      // 範囲内に1本も足が無い (取引停止日など)
      return;
   }

   //--- 範囲内全足を新しい順に遡って収集 ---
   //   sh_close (= 範囲内最終足) から、t < range_start_srv になるまで遡る
   double adx_arr[];
   ArrayResize(adx_arr, 0);
   int sh = sh_close;
   while(sh >= 0)
   {
      datetime t_bar = iTime(sym, tf, sh);
      if(t_bar < range_start_srv) break;
      if(t_bar >= range_end_srv) { sh++; continue; }  // 念のため

      double adx_val = Agg_GetBufValue(hADX, 0, sh);
      if(adx_val > 0)
      {
         int n = ArraySize(adx_arr);
         ArrayResize(adx_arr, n + 1);
         adx_arr[n] = adx_val;
      }
      sh++;  // 新しい index → 古い index へ (series=false ベースだと sh+1 が古い)
      // ※ iTime は series=true 前提（shift=0 が最新）。なので sh++ で過去へ。
      // 安全策として大量ループ防止 (1日でも H1=24本程度)
      if(sh > sh_close + 200) break;
   }

   if(ArraySize(adx_arr) == 0) return;

   //--- max / mean 計算 ---
   double sum = 0;
   double mx  = 0;
   for(int i = 0; i < ArraySize(adx_arr); i++)
   {
      sum += adx_arr[i];
      if(adx_arr[i] > mx) mx = adx_arr[i];
   }
   adx_max  = mx;
   adx_mean = sum / ArraySize(adx_arr);

   //--- close 値 (sh_close の足から) ---
   adx_close   = Agg_GetBufValue(hADX,    0, sh_close);
   dip_close   = Agg_GetBufValue(hADX,    1, sh_close);
   din_close   = Agg_GetBufValue(hADX,    2, sh_close);
   atr_s_close = Agg_GetBufValue(hATR_S,  0, sh_close);
   atr_l_close = Agg_GetBufValue(hATR_L,  0, sh_close);
}

//+==================================================================+
//| Agg_ClassifyDiDir                                                |
//|   DI+ - DI- = spread → BULL / BEAR / FLAT                       |
//+==================================================================+
string Agg_ClassifyDiDir(double spread)
{
   if(MathAbs(spread) < DI_Spread_Flat_Thresh) return "FLAT";
   if(spread > 0) return "BULL";
   return "BEAR";
}

//+==================================================================+
//| Agg_GetBufValue                                                  |
//+==================================================================+
double Agg_GetBufValue(int handle, int buf, int shift)
{
   if(handle == INVALID_HANDLE) return 0;
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buf, shift, 1, tmp) <= 0) return 0;
   return tmp[0];
}

//+==================================================================+
//| Agg_TruncateToDayJst                                             |
//|   JST の datetime を 00:00 に切り下げる                           |
//+==================================================================+
datetime Agg_TruncateToDayJst(datetime jst)
{
   MqlDateTime t;
   TimeToStruct(jst, t);
   t.hour = 0;
   t.min  = 0;
   t.sec  = 0;
   return StructToTime(t);
}

//+==================================================================+
//| Agg_WriteHeaderUtf8                                              |
//|   28列:                                                           |
//|     [1]    date                                                   |
//|     [2-9]  D1 (8列: adx22,dip,din,spread,dir,atr22,atr42,ratio)   |
//|     [10-19] H4 (10列: adx46×3, dip_close, din_close, spread, dir, |
//|                       atr8_close, atr46_close, ratio_close)       |
//|     [20-29] H1 (10列: adx32×3, dip_close, din_close, spread, dir, |
//|                       atr16_close, atr32_close, ratio_close)      |
//|   合計: 1 + 8 + 10 + 10 = 29列                                    |
//+==================================================================+
void Agg_WriteHeaderUtf8(int fh)
{
   string line =
      "date,"
      // [2-9] D1
      "d1_adx22,d1_di_plus,d1_di_minus,d1_di_spread,d1_di_dir,"
      "d1_atr22,d1_atr42,d1_atr22_42_ratio,"
      // [10-19] H4 (max/close/mean)
      "h4_adx46_max,h4_adx46_close,h4_adx46_mean,"
      "h4_di_plus_close,h4_di_minus_close,h4_di_spread_close,h4_di_dir,"
      "h4_atr8_close,h4_atr46_close,h4_atr8_46_ratio_close,"
      // [20-29] H1 (max/close/mean)
      "h1_adx32_max,h1_adx32_close,h1_adx32_mean,"
      "h1_di_plus_close,h1_di_minus_close,h1_di_spread_close,h1_di_dir,"
      "h1_atr16_close,h1_atr32_close,h1_atr16_32_ratio_close";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| Agg_WriteRow                                                     |
//+==================================================================+
void Agg_WriteRow(int fh, const string &date_str,
              double d1_adx22, double d1_dip, double d1_din,
              double d1_spread, const string &d1_di_dir,
              double d1_atr22, double d1_atr42, double d1_ratio,
              double h4_adx46_max, double h4_adx46_close, double h4_adx46_mean,
              double h4_dip_close, double h4_din_close,
              double h4_di_spread, const string &h4_di_dir,
              double h4_atr8_close, double h4_atr46_close, double h4_atr_ratio,
              double h1_adx32_max, double h1_adx32_close, double h1_adx32_mean,
              double h1_dip_close, double h1_din_close,
              double h1_di_spread, const string &h1_di_dir,
              double h1_atr16_close, double h1_atr32_close, double h1_atr_ratio)
{
   string line = "";
   line += date_str + ",";
   //--- D1 ---
   line += DoubleToString(d1_adx22, 2) + ",";
   line += DoubleToString(d1_dip,   2) + ",";
   line += DoubleToString(d1_din,   2) + ",";
   line += DoubleToString(d1_spread,2) + ",";
   line += d1_di_dir + ",";
   line += DoubleToString(d1_atr22, 4) + ",";
   line += DoubleToString(d1_atr42, 4) + ",";
   line += DoubleToString(d1_ratio, 4) + ",";
   //--- H4 ---
   line += DoubleToString(h4_adx46_max,   2) + ",";
   line += DoubleToString(h4_adx46_close, 2) + ",";
   line += DoubleToString(h4_adx46_mean,  2) + ",";
   line += DoubleToString(h4_dip_close,   2) + ",";
   line += DoubleToString(h4_din_close,   2) + ",";
   line += DoubleToString(h4_di_spread,   2) + ",";
   line += h4_di_dir + ",";
   line += DoubleToString(h4_atr8_close,  4) + ",";
   line += DoubleToString(h4_atr46_close, 4) + ",";
   line += DoubleToString(h4_atr_ratio,   4) + ",";
   //--- H1 ---
   line += DoubleToString(h1_adx32_max,   2) + ",";
   line += DoubleToString(h1_adx32_close, 2) + ",";
   line += DoubleToString(h1_adx32_mean,  2) + ",";
   line += DoubleToString(h1_dip_close,   2) + ",";
   line += DoubleToString(h1_din_close,   2) + ",";
   line += DoubleToString(h1_di_spread,   2) + ",";
   line += h1_di_dir + ",";
   line += DoubleToString(h1_atr16_close, 4) + ",";
   line += DoubleToString(h1_atr32_close, 4) + ",";
   line += DoubleToString(h1_atr_ratio,   4);
   WriteUtf8String(fh, line + "\n");
}

//+##################################################################+
//|                                                                  |
//|  MFE/MAE パート（旧 XAUUSD_Daily_MFE_MAE_v1.mq5）                |
//|  ロジックは移植元のまま。関数名・カウンタのみ rename。            |
//|                                                                  |
//+##################################################################+

//+==================================================================+
//| Mfe_GenerateCsv                                                  |
//|   旧 Mfe OnStart のCSV生成部（FileOpen→120日ループ→FileClose）。 |
//+==================================================================+
void Mfe_GenerateCsv()
{
   g_mfe_rows_written = 0;
   g_mfe_rows_skipped = 0;
   g_mfe_rows_partial = 0;

   Print("==== [Mfe] daily_mfe_mae_48h generate ====");
   PrintFormat("Lookback: %d days, Virtual entry: D1 OPEN (market open of the day)",
               Lookback_Days);
   PrintFormat("Time-segmented MFE/MAE: 12h / 24h / 36h / 48h (H1 only)");

   //--- 出力 CSV オープン (UTF-8 BOM) ---
   int fout = FileOpen(Mfe_Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] [Mfe] 出力CSV open失敗: %s err=%d", Mfe_Output_File, GetLastError());
      return;
   }
   WriteUtf8Bom(fout);
   Mfe_WriteHeaderUtf8(fout);

   //--- DST 境界跨ぎ警告 ---
   //   ※ 仮想エントリー起点は D1 足の境界（市場オープン）に変更。
   //      DST 切替は MT5 が D1 足の境界処理で自動吸収するため、
   //      固定時刻の server 変換ハードコードは不要になった。
   if(Use_Auto_Server_Offset && Verbose)
   {
      long ofs = (long)(TimeTradeServer() - TimeGMT());
      PrintFormat("[INFO] [Mfe] Current server-GMT offset = %d sec (= %.2f h). "
                  "起点=D1足始値。DST は足境界で吸収.",
                  (int)ofs, ofs/3600.0);
   }

   //--- 走査範囲: 直近 Lookback_Days 本の D1 足を、古い順に処理 ---
   //   営業日 = D1 足が存在する日（土日・休場は D1 足が無い → 自動 skip）。
   //   shift = Lookback_Days-1 (古い側) → 0 (最新側=進行中の当日 D1 足)。
   //   進行中の当日 D1 足は 48h 未経過 → bars_traced<48 の partial として出力。
   for(int sh_d1 = Lookback_Days - 1; sh_d1 >= 0; sh_d1--)
   {
      Mfe_ProcessDay(fout, sh_d1);
   }

   FileClose(fout);

   Print("==== [Mfe] daily_mfe_mae_48h Complete ====");
   PrintFormat("  written = %d", g_mfe_rows_written);
   PrintFormat("  partial (some bars missing in 48h) = %d", g_mfe_rows_partial);
   PrintFormat("  skipped (no D1 bar) = %d", g_mfe_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Mfe_Output_File);
}

//+==================================================================+
//| Mfe_ProcessDay                                                   |
//|   1日分の仮想エントリー → 48h MFE/MAE 計算 → 1行書き出し         |
//|                                                                  |
//|   起点 (2026-06-20 変更): その日の D1 足の始値 (= 市場オープン)。 |
//|     virtual_entry_price = iOpen(D1, sh_d1)                       |
//|     virtual_entry_jst   = ServerToJst(iTime(D1, sh_d1))         |
//|     固定時刻のハードコード変換は廃止。DST は足が処理。           |
//|                                                                  |
//|   営業日判定: その日の D1 足が存在するか否か                     |
//|     (土日・祝日・年末年始は MT5 が D1 足を持たない → 自動 skip)  |
//|                                                                  |
//|   48h 追跡: D1 始値の時刻に対応する H1 足から前方 48 本 (48h固定).|
//|     D1 始値 = その日の先頭 H1 足の Open。その H1 足自身を含めて   |
//|     48 本を追跡するため、trace 関数へは entry_shift = sh_h1+1 を  |
//|     渡す (関数内 start_shift = entry_shift-1 = sh_h1 となる)。    |
//+==================================================================+
void Mfe_ProcessDay(int fout, int sh_d1)
{
   string sym = _Symbol;

   //--- 営業日判定: その日の D1 足が存在するか ---
   datetime d1_bar_server = iTime(sym, PERIOD_D1, sh_d1);
   if(d1_bar_server == 0)
   {
      if(Verbose) PrintFormat("[SKIP] no D1 bar at shift %d", sh_d1);
      g_mfe_rows_skipped++;
      return;
   }

   //--- 仮想エントリー時刻 (JST) = D1 足の始値時刻 ---
   datetime virtual_entry_jst = ServerToJst(d1_bar_server);

   //--- 仮想エントリー価格 = その日の D1 足の始値 (Open) ---
   double entry_open = iOpen(sym, PERIOD_D1, sh_d1);
   if(entry_open <= 0)
   {
      if(Verbose) PrintFormat("[SKIP] iOpen(D1) fail @ %s",
                               FormatJstDateTime(virtual_entry_jst));
      g_mfe_rows_skipped++;
      return;
   }

   //--- D1 始値時刻に対応する H1 足 shift (= その日の先頭 H1 足) ---
   int sh_h1 = iBarShift(sym, PERIOD_H1, d1_bar_server, false);
   if(sh_h1 < 0)
   {
      if(Verbose) PrintFormat("[SKIP] iBarShift(H1) fail @ %s (server=%s)",
                               FormatJstDateTime(virtual_entry_jst),
                               TimeToString(d1_bar_server, TIME_DATE|TIME_MINUTES));
      g_mfe_rows_skipped++;
      return;
   }

   //--- 48h MFE/MAE 追跡 (BUY/SELL 両方) ---
   //   時間別セグメント (12h / 24h / 36h / 48h) も同時に計算するため、
   //   全48本の high/low を一度に取得して4段階に集約する
   //   (BUY 基準で MFE/MAE を算出し、SELL は対称関係で導出)
   //   ※ entry_shift = sh_h1+1 を渡すことで、D1 始値の H1 足自身を
   //     含めて前方 48 本を追跡する (その日のレンジを頭から捉える)。
   double entry_close = entry_open;   // 起点価格 = D1 始値
   int    entry_shift = sh_h1 + 1;

   double buy_mfe_12=0, buy_mae_12=0;
   double buy_mfe_24=0, buy_mae_24=0;
   double buy_mfe_36=0, buy_mae_36=0;
   double buy_mfe_48=0, buy_mae_48=0;
   int    buy_mfe_idx_48 = -1, buy_mae_idx_48 = -1;
   int    bars_traced = 0;

   bool ok = Mfe_TraceMaeMfe_Segmented(entry_shift, H1_Trace_Bars_48h, entry_close,
                                    buy_mfe_12, buy_mae_12,
                                    buy_mfe_24, buy_mae_24,
                                    buy_mfe_36, buy_mae_36,
                                    buy_mfe_48, buy_mae_48,
                                    buy_mfe_idx_48, buy_mae_idx_48,
                                    bars_traced);

   //--- SELL 側は BUY 側の符号を入れ替えた対称関係 ---
   //   BUY: favor = high - entry,    adverse = entry - low
   //   SELL: favor = entry - low,    adverse = high - entry
   //   → SELL_MFE は BUY_MAE と同値、SELL_MAE は BUY_MFE と同値    ---
   //   (同じH1足群を見るので、極値は同じ)                            ---
   double sell_mfe_12 = buy_mae_12, sell_mae_12 = buy_mfe_12;
   double sell_mfe_24 = buy_mae_24, sell_mae_24 = buy_mfe_24;
   double sell_mfe_36 = buy_mae_36, sell_mae_36 = buy_mfe_36;
   double sell_mfe_48 = buy_mae_48, sell_mae_48 = buy_mfe_48;
   int    sell_mfe_idx_48 = buy_mae_idx_48;
   int    sell_mae_idx_48 = buy_mfe_idx_48;

   if(!ok)
   {
      if(Verbose) PrintFormat("[SKIP] TraceMaeMfe fail @ %s",
                               FormatJstDateTime(virtual_entry_jst));
      g_mfe_rows_skipped++;
      return;
   }

   //--- date 文字列 (JST, YYYY-MM-DD) ---
   string date_str = FormatJstDate(virtual_entry_jst);
   string ve_str   = FormatJstDateTime(virtual_entry_jst);

   //--- 行書き出し ---
   Mfe_WriteRow(fout, date_str, ve_str, entry_close,
            buy_mfe_48, buy_mae_48,
            sell_mfe_48, sell_mae_48,
            buy_mfe_idx_48, buy_mae_idx_48,
            sell_mfe_idx_48, sell_mae_idx_48,
            bars_traced,
            buy_mfe_12, buy_mae_12, sell_mfe_12, sell_mae_12,
            buy_mfe_24, buy_mae_24, sell_mfe_24, sell_mae_24,
            buy_mfe_36, buy_mae_36, sell_mfe_36, sell_mae_36);

   g_mfe_rows_written++;
   if(bars_traced < H1_Trace_Bars_48h) g_mfe_rows_partial++;

   if(Verbose && (g_mfe_rows_written % 20 == 0))
      PrintFormat("[INFO] [Mfe] processed %d days...", g_mfe_rows_written);
}

//+==================================================================+
//| Mfe_TraceMaeMfe_Segmented                                        |
//|   エントリーバー (entry_shift) より新しい N 本のH1バーを走査して |
//|   BUY側の MFE/MAE を 12h / 24h / 36h / 48h セグメント別に計算。   |
//|   SELL側は対称関係 (符号逆転) で呼び出し側が算出する。            |
//|                                                                  |
//|   セグメント定義:                                                  |
//|     12h = エントリー後 1本目 〜 12本目                            |
//|     24h = エントリー後 1本目 〜 24本目                            |
//|     36h = エントリー後 1本目 〜 36本目                            |
//|     48h = エントリー後 1本目 〜 48本目 (= 全体)                  |
//|   ※累積型 (12h ⊆ 24h ⊆ 36h ⊆ 48h)                              |
//|                                                                  |
//|   bar_idx は 48h セグメントのみ返す。12h/24h/36h は省略           |
//|   (Q3 「bar_idx は 48h 維持で OK」指示通り、軌跡解像度は十分)     |
//|                                                                  |
//|   bars_traced が trace_n 未満の場合 (休場跨ぎ等)、                |
//|     - 取得できた本数までで各セグメント値を確定                    |
//|     - 例: bars_traced=20 なら 12h と 24h は完全、36h と 48h は    |
//|       「実取得20本まで」の値となる (部分値、partial)              |
//|                                                                  |
//|   旧版 TraceMaeMfe48h_DualSide から拡張 (2026-06-10)              |
//+==================================================================+
bool Mfe_TraceMaeMfe_Segmented(int entry_shift, int trace_n, double entry_price,
                            double &buy_mfe_12, double &buy_mae_12,
                            double &buy_mfe_24, double &buy_mae_24,
                            double &buy_mfe_36, double &buy_mae_36,
                            double &buy_mfe_48, double &buy_mae_48,
                            int    &buy_mfe_idx_48, int &buy_mae_idx_48,
                            int    &bars_traced)
{
   buy_mfe_12=0; buy_mae_12=0;
   buy_mfe_24=0; buy_mae_24=0;
   buy_mfe_36=0; buy_mae_36=0;
   buy_mfe_48=0; buy_mae_48=0;
   buy_mfe_idx_48 = -1; buy_mae_idx_48 = -1;
   bars_traced = 0;

   if(entry_shift < 0) return false;
   if(trace_n <= 0)   return false;

   string sym = _Symbol;

   //--- 走査開始 shift = entry_shift - 1 (エントリーバーの次の新しいバー) ---
   //--- エントリーバー自身はエントリー前の動きを含むので除外する         ---
   int start_shift = entry_shift - 1;
   if(start_shift < 0)
   {
      // エントリーバー自体が現在バー = 直近すぎて追跡開始できない
      return false;
   }

   //--- 取得可能本数を確定 ---
   //   start_shift = entry_shift-1 (新しい側)
   //   end_shift   = entry_shift-trace_n (古い側、ただし 0 が下限)
   int desired_end = entry_shift - trace_n;
   int end_shift   = (desired_end < 0) ? 0 : desired_end;
   int n_bars      = start_shift - end_shift + 1;
   if(n_bars <= 0) return false;

   //--- High/Low を取得 (series=true で end_shift から n_bars 本) ---
   //    series 配列 index:                                             ---
   //      [0]       = start_shift (新しい側、entry の次のバー = idx 1)---
   //      [n_bars-1]= end_shift   (古い側、entry の n_bars 本後)       ---
   //    → entry から数えて何本目 = n_bars - k                          ---
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(sym, PERIOD_H1, end_shift, n_bars, highs) <= 0) return false;
   if(CopyLow (sym, PERIOD_H1, end_shift, n_bars, lows)  <= 0) return false;

   //--- セグメント走査: entry 後 1..12, 1..24, 1..36, 1..48 ---
   //    series index k に対する「entry 後の何本目」 = n_bars - k       ---
   //    → entry 後 1..H 本目を取るには n_bars - k <= H、即ち k >= n_bars - H
   double best_favor_12=-DBL_MAX, worst_adverse_12=-DBL_MAX;
   double best_favor_24=-DBL_MAX, worst_adverse_24=-DBL_MAX;
   double best_favor_36=-DBL_MAX, worst_adverse_36=-DBL_MAX;
   double best_favor_48=-DBL_MAX, worst_adverse_48=-DBL_MAX;
   int    best_idx_48  = -1, worst_idx_48 = -1;

   for(int k = 0; k < n_bars; k++)
   {
      double hi = highs[k];
      double lo = lows[k];
      if(hi <= 0 || lo <= 0) continue;

      //--- BUY 側 ---
      double favor   = hi - entry_price;   // 上が有利
      double adverse = entry_price - lo;   // 下抜けが逆行

      //--- entry 後の何本目 (1..n_bars) ---
      int bar_no = n_bars - k;

      //--- 48h (全体) ---
      if(bar_no <= 48)
      {
         if(favor > best_favor_48)        { best_favor_48 = favor;        best_idx_48 = k; }
         if(adverse > worst_adverse_48)   { worst_adverse_48 = adverse;   worst_idx_48 = k; }
      }
      //--- 36h ---
      if(bar_no <= 36)
      {
         if(favor > best_favor_36)        best_favor_36 = favor;
         if(adverse > worst_adverse_36)   worst_adverse_36 = adverse;
      }
      //--- 24h ---
      if(bar_no <= 24)
      {
         if(favor > best_favor_24)        best_favor_24 = favor;
         if(adverse > worst_adverse_24)   worst_adverse_24 = adverse;
      }
      //--- 12h ---
      if(bar_no <= 12)
      {
         if(favor > best_favor_12)        best_favor_12 = favor;
         if(adverse > worst_adverse_12)   worst_adverse_12 = adverse;
      }
   }

   //--- 48h セグメント (bar_idx 付き) ---
   if(best_idx_48 >= 0)
   {
      buy_mfe_48     = MathMax(0.0, best_favor_48);
      buy_mfe_idx_48 = n_bars - best_idx_48;
   }
   if(worst_idx_48 >= 0)
   {
      buy_mae_48     = MathMax(0.0, worst_adverse_48);
      buy_mae_idx_48 = n_bars - worst_idx_48;
   }

   //--- 12h / 24h / 36h セグメント (bar_idx 省略) ---
   //    sentinel (-DBL_MAX) のままなら 0 のまま、それ以外は max(0, value)
   if(best_favor_12 > -DBL_MAX)    buy_mfe_12 = MathMax(0.0, best_favor_12);
   if(worst_adverse_12 > -DBL_MAX) buy_mae_12 = MathMax(0.0, worst_adverse_12);
   if(best_favor_24 > -DBL_MAX)    buy_mfe_24 = MathMax(0.0, best_favor_24);
   if(worst_adverse_24 > -DBL_MAX) buy_mae_24 = MathMax(0.0, worst_adverse_24);
   if(best_favor_36 > -DBL_MAX)    buy_mfe_36 = MathMax(0.0, best_favor_36);
   if(worst_adverse_36 > -DBL_MAX) buy_mae_36 = MathMax(0.0, worst_adverse_36);

   bars_traced = n_bars;
   return true;
}

//+==================================================================+
//| Mfe_WriteHeaderUtf8                                              |
//|                                                                  |
//|   出力カラム (v1.1 / 19列):                                        |
//|     [1]  date                  YYYY-MM-DD (JST)                  |
//|     [2]  virtual_entry_jst     YYYY-MM-DD HH:MM:SS (JST)         |
//|     [3]  virtual_entry_price   その時刻の H1 close               |
//|     [4]  buy_mfe_usd           BUY 仮想 48h MFE (USD) ★既存維持 |
//|     [5]  buy_mae_usd           BUY 仮想 48h MAE (USD) ★既存維持 |
//|     [6]  sell_mfe_usd          SELL 仮想 48h MFE (USD) ★既存維持|
//|     [7]  sell_mae_usd          SELL 仮想 48h MAE (USD) ★既存維持|
//|     [8]  buy_mfe_bar_idx       BUY MFE 到達バー (entry 後 1..48)|
//|     [9]  buy_mae_bar_idx       BUY MAE 到達バー                  |
//|     [10] sell_mfe_bar_idx      SELL MFE 到達バー (= buy_mae 同値)|
//|     [11] sell_mae_bar_idx      SELL MAE 到達バー (= buy_mfe 同値)|
//|     [12] bars_traced           実追跡 H1 足数 (48h 基準)         |
//|     [13] buy_mfe_12h_usd       ★新規 BUY 仮想 12h MFE (USD)    |
//|     [14] buy_mae_12h_usd       ★新規 BUY 仮想 12h MAE (USD)    |
//|     [15] sell_mfe_12h_usd      ★新規 SELL 仮想 12h MFE (USD)   |
//|     [16] sell_mae_12h_usd      ★新規 SELL 仮想 12h MAE (USD)   |
//|     [17] buy_mfe_24h_usd 〜 sell_mae_24h_usd (4列)               |
//|     [21] buy_mfe_36h_usd 〜 sell_mae_36h_usd (4列)               |
//|                                                                  |
//|   合計: 12 + 4×3 = 24列                                          |
//|                                                                  |
//|   方針 (Q3): 既存カラム名は不変、新規カラム追加のみ。            |
//|     後方互換維持のため (マニ generate_daily_calendar.py 等)      |
//+==================================================================+
void Mfe_WriteHeaderUtf8(int fh)
{
   string line =
      // [1-3] 基本
      "date,virtual_entry_jst,virtual_entry_price,"
      // [4-7] 48h MFE/MAE (★既存維持: リネームせず 48h 値として扱う)
      "buy_mfe_usd,buy_mae_usd,sell_mfe_usd,sell_mae_usd,"
      // [8-11] 48h bar_idx (★既存維持)
      "buy_mfe_bar_idx,buy_mae_bar_idx,sell_mfe_bar_idx,sell_mae_bar_idx,"
      // [12] 実追跡本数 (★既存維持)
      "bars_traced,"
      // [13-16] 12h セグメント (★新規)
      "buy_mfe_12h_usd,buy_mae_12h_usd,sell_mfe_12h_usd,sell_mae_12h_usd,"
      // [17-20] 24h セグメント (★新規)
      "buy_mfe_24h_usd,buy_mae_24h_usd,sell_mfe_24h_usd,sell_mae_24h_usd,"
      // [21-24] 36h セグメント (★新規)
      "buy_mfe_36h_usd,buy_mae_36h_usd,sell_mfe_36h_usd,sell_mae_36h_usd";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| Mfe_WriteRow                                                     |
//|   v1.1 24列出力                                                   |
//+==================================================================+
void Mfe_WriteRow(int fh,
              const string &date_str, const string &ve_str, double entry_price,
              double buy_mfe_48, double buy_mae_48,
              double sell_mfe_48, double sell_mae_48,
              int buy_mfe_idx, int buy_mae_idx,
              int sell_mfe_idx, int sell_mae_idx,
              int bars_traced,
              double buy_mfe_12, double buy_mae_12, double sell_mfe_12, double sell_mae_12,
              double buy_mfe_24, double buy_mae_24, double sell_mfe_24, double sell_mae_24,
              double buy_mfe_36, double buy_mae_36, double sell_mfe_36, double sell_mae_36)
{
   string line = "";
   //--- [1-3] 基本 ---
   line += date_str + ",";
   line += ve_str + ",";
   line += DoubleToString(entry_price, 3) + ",";
   //--- [4-7] 48h MFE/MAE (既存維持) ---
   line += DoubleToString(buy_mfe_48, 3) + ",";
   line += DoubleToString(buy_mae_48, 3) + ",";
   line += DoubleToString(sell_mfe_48, 3) + ",";
   line += DoubleToString(sell_mae_48, 3) + ",";
   //--- [8-11] 48h bar_idx (既存維持) ---
   line += IntegerToString(buy_mfe_idx) + ",";
   line += IntegerToString(buy_mae_idx) + ",";
   line += IntegerToString(sell_mfe_idx) + ",";
   line += IntegerToString(sell_mae_idx) + ",";
   //--- [12] bars_traced (既存維持) ---
   line += IntegerToString(bars_traced) + ",";
   //--- [13-16] 12h セグメント (新規) ---
   line += DoubleToString(buy_mfe_12, 3) + ",";
   line += DoubleToString(buy_mae_12, 3) + ",";
   line += DoubleToString(sell_mfe_12, 3) + ",";
   line += DoubleToString(sell_mae_12, 3) + ",";
   //--- [17-20] 24h セグメント (新規) ---
   line += DoubleToString(buy_mfe_24, 3) + ",";
   line += DoubleToString(buy_mae_24, 3) + ",";
   line += DoubleToString(sell_mfe_24, 3) + ",";
   line += DoubleToString(sell_mae_24, 3) + ",";
   //--- [21-24] 36h セグメント (新規) ---
   line += DoubleToString(buy_mfe_36, 3) + ",";
   line += DoubleToString(buy_mae_36, 3) + ",";
   line += DoubleToString(sell_mfe_36, 3) + ",";
   line += DoubleToString(sell_mae_36, 3);
   WriteUtf8String(fh, line + "\n");
}

//+##################################################################+
//|                                                                  |
//|  DXY環境札パート（v1.10 追加 / SPEC_dxy_env_card_v1.md）          |
//|                                                                  |
//|  出力: dxy_env.csv (UTF-8 BOM・他daily系と同方式)                 |
//|    列: date,dxy_adx56,dxy_di_plus,dxy_di_minus,                  |
//|        dxy_di_spread,dxy_di_dir                                  |
//|  更新機構: daily_aggregate と同じ「毎時フル再生成」               |
//|    （Lookback_Days 遡り・1日1行・当日行は最終確定バーで毎時更新） |
//|  防御: 履歴未ロード/空バッファ/値<=0 → その行/その回をスキップ    |
//|    （0値行禁止・ログのみ・次の毎時で自己回復）。                  |
//|    ready前・ハンドル無効時は既存 dxy_env.csv を truncate しない。 |
//+##################################################################+

//+==================================================================+
//| Dxy_InitHandle                                                   |
//|   SymbolSelect で気配値登録の保険 → iADX ハンドルを1回生成。      |
//|   失敗しても false ログのみ（XAU側の INIT を止めない）。          |
//+==================================================================+
void Dxy_InitHandle()
{
   //--- 気配値登録の保険（板に無いと iADX が失敗するため）---
   if(!SymbolSelect(DXY_Symbol, true))
      PrintFormat("[WARN] [Dxy] SymbolSelect(%s) 失敗 err=%d "
                  "(シンボル名が板に無い?) → DXY出力はスキップされます.",
                  DXY_Symbol, GetLastError());

   hDxy_ADX = iADX(DXY_Symbol, PERIOD_H1, DXY_ADX_Period);
   if(hDxy_ADX == INVALID_HANDLE)
      PrintFormat("[WARN] [Dxy] iADX(%s,H1,%d) ハンドル生成失敗 err=%d "
                  "→ DXY出力のみスキップ（XAU側 2 CSV は継続）.",
                  DXY_Symbol, DXY_ADX_Period, GetLastError());
   else
      PrintFormat("[INFO] [Dxy] iADX(%s,H1,%d) handle OK.",
                  DXY_Symbol, DXY_ADX_Period);
}

//+==================================================================+
//| Dxy_GenerateCsv                                                  |
//|   Agg_GenerateCsv と同じ流儀の毎時フル再生成。                    |
//|   ready前チェックを FileOpen より先に行い、書けない回は           |
//|   既存ファイルを壊さない（truncate回避）。                        |
//+==================================================================+
void Dxy_GenerateCsv()
{
   //--- ハンドル無効（OnInitで生成失敗）→ DXY部まるごとスキップ ---
   if(hDxy_ADX == INVALID_HANDLE)
   {
      if(Verbose) Print("[SKIP] [Dxy] handle invalid → DXY出力スキップ.");
      return;
   }

   //--- 計算未完（履歴未ロード等）→ 今回はスキップ（次の毎時で自己回復）---
   if(BarsCalculated(hDxy_ADX) <= 0)
   {
      if(Verbose) Print("[SKIP] [Dxy] BarsCalculated<=0 (履歴未ロード?) → 今回のDXY出力スキップ.");
      return;
   }

   g_dxy_rows_written = 0;
   g_dxy_rows_skipped = 0;

   Print("==== [Dxy] dxy_env generate ====");

   //--- 出力 CSV オープン (UTF-8 BOM・他daily系と同方式) ---
   int fout = FileOpen(Dxy_Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[ERR] [Dxy] 出力CSV open失敗: %s err=%d（XAU側は影響なし）",
                  Dxy_Output_File, GetLastError());
      return;
   }
   WriteUtf8Bom(fout);
   WriteUtf8String(fout, "date,dxy_adx56,dxy_di_plus,dxy_di_minus,dxy_di_spread,dxy_di_dir\n");

   //--- メインループ: Agg と同じ JST日回し（古い日 → 今日）---
   datetime now_server = TimeTradeServer();
   datetime now_jst    = ServerToJst(now_server);
   datetime today_jst_midnight = Agg_TruncateToDayJst(now_jst);

   for(int d = Lookback_Days - 1; d >= 0; d--)
   {
      datetime day_jst_midnight = today_jst_midnight - (datetime)(d * 86400);
      Dxy_ProcessDay(fout, day_jst_midnight);
   }

   FileClose(fout);

   Print("==== [Dxy] dxy_env Complete ====");
   PrintFormat("  written = %d / skipped = %d", g_dxy_rows_written, g_dxy_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Dxy_Output_File);
}

//+==================================================================+
//| Dxy_ProcessDay                                                   |
//|   1日分: その日 (JST 00:00〜24:00) の最終「確定」H1バーの         |
//|   ADX/DI+/DI- を1行書く。                                        |
//|     - 当日は iBarShift が進行中バー(shift=0)を返すため shift=1    |
//|       （最終確定バー）へ繰り上げ → 毎時、当日行が更新されていく   |
//|     - 範囲内に確定バー無し（土日・休場・週明け直後）→ skip       |
//|     - CopyBuffer 失敗 / 値<=0 → skip（0値行禁止）                |
//+==================================================================+
void Dxy_ProcessDay(int fout, datetime day_jst_midnight)
{
   datetime range_start_srv = JstToServer(day_jst_midnight);
   datetime range_end_srv   = JstToServer(day_jst_midnight + 86400);

   //--- その日の最終バー（当日は進行中バーが返る）---
   int sh = iBarShift(DXY_Symbol, PERIOD_H1, range_end_srv - 1, false);
   if(sh < 0)
   {
      g_dxy_rows_skipped++;
      return;
   }
   if(sh == 0) sh = 1;   // 進行中バーは使わない → 最終確定バー(shift=1)へ

   //--- 確定バーがその日の範囲内にあるか（無ければ非営業日 or 当日確定バー未発生）---
   datetime t_bar = iTime(DXY_Symbol, PERIOD_H1, sh);
   if(t_bar == 0 || t_bar < range_start_srv || t_bar >= range_end_srv)
   {
      g_dxy_rows_skipped++;
      return;
   }

   //--- ADX/DI 取得（空バッファ・値<=0 は 0値行禁止 → skip）---
   double adx = Agg_GetBufValue(hDxy_ADX, 0, sh);   // 汎用ヘルパ流用（handle/buf/shift）
   double dip = Agg_GetBufValue(hDxy_ADX, 1, sh);
   double din = Agg_GetBufValue(hDxy_ADX, 2, sh);
   if(adx <= 0 || dip <= 0 || din <= 0)
   {
      g_dxy_rows_skipped++;
      if(Verbose)
         PrintFormat("[SKIP] [Dxy] %s 値取得不能 (adx=%.2f dip=%.2f din=%.2f) → 0値行禁止で書かない",
                     FormatJstDate(day_jst_midnight), adx, dip, din);
      return;
   }

   double spread = dip - din;
   string dir    = (spread > 0) ? "USD_UP" : "USD_DN";

   string line = FormatJstDate(day_jst_midnight) + ",";
   line += DoubleToString(adx,    2) + ",";
   line += DoubleToString(dip,    2) + ",";
   line += DoubleToString(din,    2) + ",";
   line += DoubleToString(spread, 2) + ",";   // 符号付き小数2桁
   line += dir;
   WriteUtf8String(fout, line + "\n");

   g_dxy_rows_written++;
}

//+##################################################################+
//|                                                                  |
//|  合成DXY 維持パート（v1.11 追加）                                 |
//|                                                                  |
//|  合成ロジックは Phase 1 Script と同一:                            |
//|    data/dxy/DXY_Synth_Timeseries_v1.mq5                          |
//|    DXY = Synth_Const × Π Comp_k^Weight_k （5項・SEK除外）         |
//|    - log空間で和。負の指数の成分は H/L を入替                     |
//|    - union timeline。欠損は直前Closeで平坦に埋める               |
//|      ただし 48h超 / 週末跨ぎ / 初足前 は埋めない                  |
//|    - 1成分でも埋められない時刻は足を作らない（skip）              |
//|  ソースTF: M5 固定（検証した物差しと同一。VPSのM1は2025-07まで）  |
//|                                                                  |
//|  維持:                                                           |
//|    - ブートストラップ（DXY_SYNTH 無し / 履歴が                    |
//|      Lookback_Days+Synth_Warmup_Days を覆わない / 最終バーが      |
//|      その起点より古い）: 全削除 → チャンク毎 CustomRatesReplace   |
//|    - 差分（通常）: 最終バーの Overlap 分前から最新まで再合成 →    |
//|      CustomRatesUpdate（形成中バーの上書き含む）。                |
//|      直前値埋めの状態を Phase 1 と一致させるため、書込起点より    |
//|      Max_Fill_Hours+1h 前から読み（priming）、書くのは起点以降のみ|
//+##################################################################+
#define SYNTH_NCOMP 5

struct SynthCompRates { MqlRates r[]; };

string   g_syn_sym[SYNTH_NCOMP];
double   g_syn_w[SYNTH_NCOMP];
bool     g_syn_comp_inited = false;
bool     g_syn_ready       = false;   // ブートストラップ要否の判定を通過済み（以降は差分のみ）
int      g_syn_boot_votes  = 0;       // 既存シンボルの読取不能/範囲不足が連続した回数
#define  SYNTH_BOOT_CONFIRM 3

//--- 直前値埋め用の状態（チャンクを跨いで保持・Build毎にリセット）---
bool     g_syn_has[SYNTH_NCOMP];
datetime g_syn_last_t[SYNTH_NCOMP];
double   g_syn_last_c[SYNTH_NCOMP];

//+==================================================================+
//| Synth_IsEnabled: DXY_Symbol が合成シンボルを指す時のみ維持する    |
//+==================================================================+
bool Synth_IsEnabled()
{
   return (DXY_Symbol == Synth_Symbol);
}

//+==================================================================+
//| Synth_InitComponents: 成分銘柄・ウェイト設定 + 気配値登録         |
//+==================================================================+
bool Synth_InitComponents()
{
   g_syn_sym[0] = Comp1_Symbol; g_syn_w[0] = Comp1_Weight;
   g_syn_sym[1] = Comp2_Symbol; g_syn_w[1] = Comp2_Weight;
   g_syn_sym[2] = Comp3_Symbol; g_syn_w[2] = Comp3_Weight;
   g_syn_sym[3] = Comp4_Symbol; g_syn_w[3] = Comp4_Weight;
   g_syn_sym[4] = Comp5_Symbol; g_syn_w[4] = Comp5_Weight;

   for(int k = 0; k < SYNTH_NCOMP; k++)
   {
      if(!SymbolSelect(g_syn_sym[k], true))
      {
         PrintFormat("[ERR] [Synth] 成分銘柄 %s を気配値に登録できない err=%d → 合成不可.",
                     g_syn_sym[k], GetLastError());
         return false;
      }
   }

   string f = StringFormat("[INFO] [Synth] Formula: %s", DoubleToString(Synth_Const, 8));
   for(int k = 0; k < SYNTH_NCOMP; k++)
      f += StringFormat(" x %s^%s", g_syn_sym[k], DoubleToString(g_syn_w[k], 3));
   Print(f + "  (Source TF: M5 fixed)");
   return true;
}

//+==================================================================+
//| Synth_Ensure                                                     |
//|   初回（g_syn_ready=false）: ブートストラップ要否を判定して       |
//|     構築 or 差分。成功したら g_syn_ready=true。                   |
//|   以降: 差分のみ。                                               |
//|   戻り値 false = 今回 DXY_SYNTH を最新化できなかった（DXY skip）   |
//+==================================================================+
bool Synth_Ensure()
{
   if(!g_syn_comp_inited)
   {
      if(!Synth_InitComponents()) return false;
      g_syn_comp_inited = true;
   }

   if(g_syn_ready)
      return Synth_UpdateDiff();

   //--- ブートストラップ要否判定 ---
   datetime needed_from = TimeCurrent()
                        - (datetime)((long)(Lookback_Days + MathMax(0, Synth_Warmup_Days)) * 86400);

   bool is_custom = false;
   bool exists    = SymbolExist(Synth_Symbol, is_custom);
   if(exists && !is_custom)
   {
      PrintFormat("[ERR] [Synth] %s がブローカー銘柄として存在（カスタムでない）→ 合成不可.", Synth_Symbol);
      return false;
   }

   string reason = "";
   datetime last_t = 0;
   if(!exists)
      reason = "symbol not found";
   else
   {
      SymbolSelect(Synth_Symbol, true);
      if(!Synth_GetLastBar(last_t))
         reason = "no bars";
      else if(last_t < needed_from)
         reason = "last bar older than needed range";
      else if(!Synth_CoversFrom(needed_from))
         reason = "history does not reach needed range";

      //--- 既存シンボルの「読めない」は履歴ロード途中の一過性かもしれない。
      //    ブートストラップは全削除を伴うため、連続 SYNTH_BOOT_CONFIRM 回
      //    （＝OnInit + 毎時タイマー）同じ判定が続いた時だけ実行する。
      if(reason == "no bars" || reason == "history does not reach needed range")
      {
         g_syn_boot_votes++;
         if(g_syn_boot_votes < SYNTH_BOOT_CONFIRM)
         {
            PrintFormat("[WARN] [Synth] %s: %s (%d/%d) → 一過性の可能性。今回は構築せずDXY skip.",
                        Synth_Symbol, reason, g_syn_boot_votes, SYNTH_BOOT_CONFIRM);
            return false;
         }
      }
   }
   g_syn_boot_votes = 0;

   bool ok;
   if(reason != "")
   {
      PrintFormat("[INFO] [Synth] BOOTSTRAP: reason=%s  build_from=%s  (Lookback_Days=%d + Warmup=%d)",
                  reason, TimeToString(needed_from, TIME_DATE|TIME_MINUTES),
                  Lookback_Days, Synth_Warmup_Days);
      ok = Synth_Bootstrap(needed_from);
   }
   else
   {
      PrintFormat("[INFO] [Synth] %s exists and covers %s.. (last=%s) → 差分のみ.",
                  Synth_Symbol, TimeToString(needed_from, TIME_DATE),
                  TimeToString(last_t, TIME_DATE|TIME_MINUTES));
      ok = Synth_UpdateDiff();
   }
   if(ok) g_syn_ready = true;
   return ok;
}

//+==================================================================+
//| Synth_GetLastBar: DXY_SYNTH の最終バー時刻（M1系列）              |
//+==================================================================+
bool Synth_GetLastBar(datetime &last_t)
{
   last_t = 0;
   datetime t[];
   for(int attempt = 1; attempt <= 10; attempt++)
   {
      ResetLastError();
      if(CopyTime(Synth_Symbol, PERIOD_M1, 0, 1, t) > 0 && t[0] > 0)
      {
         last_t = t[0];
         return true;
      }
      Sleep(1000);
   }
   return false;
}

//+==================================================================+
//| Synth_CoversFrom: needed_from 付近（+7日以内）に H1 バーがあるか   |
//|   ※ M1 系列は MaxBars に掛かり得るため H1 で判定                 |
//+==================================================================+
bool Synth_CoversFrom(datetime needed_from)
{
   datetime t[];
   for(int attempt = 1; attempt <= 10; attempt++)
   {
      ResetLastError();
      if(CopyTime(Synth_Symbol, PERIOD_H1, needed_from, needed_from + 7 * 86400, t) > 0)
         return true;
      Sleep(1000);
   }
   return false;
}

//+==================================================================+
//| Synth_PrepareSymbol: 無ければ作成（プロパティは Phase 1 と同じ）   |
//+==================================================================+
bool Synth_PrepareSymbol()
{
   bool is_custom = false;
   if(SymbolExist(Synth_Symbol, is_custom))
   {
      if(!is_custom)
      {
         PrintFormat("[ERR] [Synth] %s exists as a broker symbol (not custom).", Synth_Symbol);
         return false;
      }
   }
   else
   {
      ResetLastError();
      if(!CustomSymbolCreate(Synth_Symbol, Synth_Path))
      {
         PrintFormat("[ERR] [Synth] CustomSymbolCreate failed err=%d", GetLastError());
         return false;
      }
      PrintFormat("[INFO] [Synth] Custom symbol created: Custom\\%s\\%s", Synth_Path, Synth_Symbol);

      if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_DIGITS, Synth_Digits))
         PrintFormat("[WARN] [Synth] set DIGITS failed err=%d", GetLastError());
      if(!CustomSymbolSetDouble(Synth_Symbol, SYMBOL_POINT, MathPow(10.0, -Synth_Digits)))
         PrintFormat("[WARN] [Synth] set POINT failed err=%d", GetLastError());
      if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID))
         PrintFormat("[WARN] [Synth] set CHART_MODE failed err=%d", GetLastError());
      if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED))
         PrintFormat("[WARN] [Synth] set TRADE_MODE failed err=%d", GetLastError());
      CustomSymbolSetString(Synth_Symbol, SYMBOL_DESCRIPTION, "Synthetic DXY (ICE ex-SEK, 5 pairs)");
   }
   SymbolSelect(Synth_Symbol, true);
   return true;
}

//+==================================================================+
//| Synth_Bootstrap: 全削除 → build_from から最新までチャンク Replace  |
//+==================================================================+
bool Synth_Bootstrap(datetime build_from)
{
   if(!Synth_PrepareSymbol()) return false;

   ResetLastError();
   int del = CustomRatesDelete(Synth_Symbol, 0, D'3000.01.01 00:00');
   PrintFormat("[INFO] [Synth] CustomRatesDelete(all): %d bars removed (err=%d)", del, GetLastError());
   if(del < 0)
   {
      Print("[ERR] [Synth] CustomRatesDelete failed → ブートストラップ中止（新旧混在を避ける）.");
      return false;
   }

   int written = 0; long skipped = 0;
   datetime first_out = 0, last_out = 0;
   if(!Synth_Build(build_from, build_from, true, written, skipped, first_out, last_out))
      return false;

   PrintFormat("[INFO] [Synth] BOOTSTRAP done: bars=%d skipped(unfillable)=%I64d  %s .. %s",
               written, skipped,
               first_out > 0 ? TimeToString(first_out, TIME_DATE|TIME_MINUTES) : "n/a",
               last_out  > 0 ? TimeToString(last_out,  TIME_DATE|TIME_MINUTES) : "n/a");
   if(written == 0)
   {
      Print("[ERR] [Synth] ブートストラップで合成バー0本.");
      return false;
   }
   return true;
}

//+==================================================================+
//| Synth_UpdateDiff: 最終バーの Overlap 分前から最新までを再合成      |
//|   → CustomRatesUpdate（形成中バーの上書き含む）                   |
//+==================================================================+
bool Synth_UpdateDiff()
{
   datetime last_t = 0;
   if(!Synth_GetLastBar(last_t))
   {
      Print("[ERR] [Synth] DXY_SYNTH 最終バー取得失敗 → 次回ブートストラップ判定へ戻す.");
      g_syn_ready = false;
      return false;
   }

   //--- 成分の最新M5時刻が揃っているか（1本だけ遅れていると平坦埋めが確定してしまう）---
   datetime lat[SYNTH_NCOMP];
   datetime lat_max = 0;
   for(int k = 0; k < SYNTH_NCOMP; k++)
   {
      datetime t[];
      lat[k] = 0;
      ResetLastError();
      if(CopyTime(g_syn_sym[k], PERIOD_M5, 0, 1, t) > 0) lat[k] = t[0];
      if(lat[k] == 0)
      {
         PrintFormat("[ERR] [Synth] 成分 %s の最新M5取得失敗 err=%d → 今回skip.",
                     g_syn_sym[k], GetLastError());
         return false;
      }
      if(lat[k] > lat_max) lat_max = lat[k];
   }
   for(int k = 0; k < SYNTH_NCOMP; k++)
   {
      if((long)(lat_max - lat[k]) > (long)Synth_Comp_Lag_Max_Min * 60)
      {
         PrintFormat("[ERR] [Synth] 成分 %s の最新M5 %s が他(%s)より %d分超遅れ → 今回skip.",
                     g_syn_sym[k], TimeToString(lat[k], TIME_DATE|TIME_MINUTES),
                     TimeToString(lat_max, TIME_DATE|TIME_MINUTES), Synth_Comp_Lag_Max_Min);
         return false;
      }
   }

   datetime write_from = last_t - (datetime)((long)MathMax(0, Synth_Rewrite_Overlap_Min) * 60);
   datetime prime_from = write_from - (datetime)((long)(MathMax(0, Synth_Max_Fill_Hours) + 1) * 3600);

   int written = 0; long skipped = 0;
   datetime first_out = 0, last_out = 0;
   if(!Synth_Build(prime_from, write_from, false, written, skipped, first_out, last_out))
      return false;

   PrintFormat("[INFO] [Synth] diff update: prev_last=%s write_from=%s -> bars=%d skipped=%I64d new_last=%s (comp M5 latest=%s)",
               TimeToString(last_t, TIME_DATE|TIME_MINUTES),
               TimeToString(write_from, TIME_DATE|TIME_MINUTES),
               written, skipped,
               last_out > 0 ? TimeToString(last_out, TIME_DATE|TIME_MINUTES) : "n/a",
               TimeToString(lat_max, TIME_DATE|TIME_MINUTES));
   return true;
}

//+==================================================================+
//| 週末跨ぎ判定（Phase 1 と同一）                                    |
//|   t_last 以後の最初の土曜12:00 を t_now が越えたか                |
//+==================================================================+
bool Synth_CrossesWeekend(datetime t_last, datetime t_now)
{
   MqlDateTime dt;
   TimeToStruct(t_last, dt);
   datetime day0 = t_last - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   int days_to_sat = (6 - dt.day_of_week + 7) % 7;
   datetime sat_noon = day0 + (datetime)(days_to_sat * 86400 + 12 * 3600);
   if(t_last >= sat_noon) sat_noon += 7 * 86400;
   return (t_now >= sat_noon);
}

bool Synth_CanFill(int k, datetime t)
{
   if(!g_syn_has[k]) return false;
   if((long)(t - g_syn_last_t[k]) > (long)Synth_Max_Fill_Hours * 3600) return false;
   if(Synth_CrossesWeekend(g_syn_last_t[k], t)) return false;
   return true;
}

//+==================================================================+
//| Synth_CopyRatesRetry（Phase 1 と同一の待ち方）                    |
//|   戻り値: 本数 / 0 = データ無し / -1 = 履歴ロード中のまま(4401等)  |
//|   ※ ブートストラップでは -1 を 0 扱い（Phase 1 と同一挙動）        |
//+==================================================================+
int Synth_CopyRatesRetry(const string sym, datetime from, datetime to, MqlRates &arr[])
{
   ArraySetAsSeries(arr, false);
   int err = 0;
   for(int attempt = 1; attempt <= 3; attempt++)
   {
      ResetLastError();
      int n = CopyRates(sym, PERIOD_M5, from, to, arr);
      if(n >= 0) return n;
      err = GetLastError();
      if(err != 4401 && err != 4066 && attempt >= 2) return 0;   // 休場等で本当に無い
      Sleep(1000);
   }
   return (err == 4401 || err == 4066) ? -1 : 0;
}

//+==================================================================+
//| Synth_WriteRates: 分割書込                                       |
//|   replace_mode=true : CustomRatesReplace（ブートストラップ）      |
//|   replace_mode=false: CustomRatesUpdate （差分・同時刻は上書き）  |
//+==================================================================+
bool Synth_WriteRates(const MqlRates &arr[], int n, bool replace_mode)
{
   int maxw = MathMax(100, Synth_Max_Rates_Per_Write);
   for(int a = 0; a < n; a += maxw)
   {
      int cnt = MathMin(maxw, n - a);
      MqlRates sub[];
      ArrayResize(sub, cnt);
      for(int j = 0; j < cnt; j++) sub[j] = arr[a + j];

      int r = -1, err = 0;
      for(int attempt = 1; attempt <= 2; attempt++)
      {
         ResetLastError();
         if(replace_mode)
            r = CustomRatesReplace(Synth_Symbol, sub[0].time, sub[cnt - 1].time, sub);
         else
            r = CustomRatesUpdate(Synth_Symbol, sub);
         err = GetLastError();
         if(r >= 0) break;
         Sleep(500);
      }
      if(r < 0)
      {
         PrintFormat("[ERR] [Synth] %s failed: %s..%s n=%d (ret=%d err=%d)",
                     replace_mode ? "CustomRatesReplace" : "CustomRatesUpdate",
                     TimeToString(sub[0].time, TIME_DATE|TIME_MINUTES),
                     TimeToString(sub[cnt - 1].time, TIME_DATE|TIME_MINUTES),
                     cnt, r, err);
         return false;
      }
   }
   return true;
}

//+==================================================================+
//| Synth_Build: 合成M5構築 → 分割書込（Phase 1 BuildAndWrite 移植）   |
//|   prime_from から読み、直前値埋めの状態を作る。                    |
//|   書くのは t >= write_from の足のみ。                             |
//+==================================================================+
bool Synth_Build(datetime prime_from, datetime write_from, bool replace_mode,
                 int &written, long &skipped, datetime &first_out, datetime &last_out)
{
   for(int k = 0; k < SYNTH_NCOMP; k++)
   {
      g_syn_has[k] = false; g_syn_last_t[k] = 0; g_syn_last_c[k] = 0;
   }
   written = 0; skipped = 0; first_out = 0; last_out = 0;

   double lnK = MathLog(Synth_Const);
   datetime end_time = TimeCurrent() + 3600;
   long chunk_sec = (long)MathMax(1, Synth_Chunk_Days) * 86400;

   int chunk_no = 0;
   for(datetime cf = prime_from; cf <= end_time; cf += (datetime)chunk_sec)
   {
      if(IsStopped()) { Print("[WARN] [Synth] stopped."); return false; }
      chunk_no++;
      datetime ct = cf + (datetime)(chunk_sec - 1);   // 両端含む＝重複なし

      SynthCompRates comp[SYNTH_NCOMP];
      int n[SYNTH_NCOMP], p[SYNTH_NCOMP];
      int any = 0;
      for(int k = 0; k < SYNTH_NCOMP; k++)
      {
         n[k] = Synth_CopyRatesRetry(g_syn_sym[k], cf, ct, comp[k].r);
         if(n[k] < 0)
         {
            if(!replace_mode)
            {
               PrintFormat("[ERR] [Synth] %s M5 履歴ロード未完 (%s..) → 今回skip.",
                           g_syn_sym[k], TimeToString(cf, TIME_DATE|TIME_MINUTES));
               return false;
            }
            n[k] = 0;   // ブートストラップは Phase 1 と同一（データ無し扱い）
         }
         p[k] = 0;
         any += n[k];
      }
      if(any == 0) continue;

      MqlRates out[];
      int cap = 0;
      for(int k = 0; k < SYNTH_NCOMP; k++) cap = MathMax(cap, n[k]);
      ArrayResize(out, 0, cap + 1024);
      int on = 0;

      //--- union timeline マージ ---
      while(true)
      {
         datetime t = 0; bool found = false;
         for(int k = 0; k < SYNTH_NCOMP; k++)
            if(p[k] < n[k] && (!found || comp[k].r[p[k]].time < t)) { t = comp[k].r[p[k]].time; found = true; }
         if(!found) break;

         double lnO = lnK, lnH = lnK, lnL = lnK, lnC = lnK;
         long   vol = 0;
         bool   ok  = true;

         for(int k = 0; k < SYNTH_NCOMP; k++)
         {
            double o = 0, h = 0, l = 0, c = 0;
            bool real = false;
            if(p[k] < n[k] && comp[k].r[p[k]].time == t)
            {
               MqlRates b = comp[k].r[p[k]];
               p[k]++;
               if(b.open > 0 && b.high > 0 && b.low > 0 && b.close > 0)
               {
                  o = b.open; h = b.high; l = b.low; c = b.close;
                  vol += b.tick_volume;
                  real = true;
               }
            }
            if(real)
            {
               g_syn_has[k] = true; g_syn_last_t[k] = t; g_syn_last_c[k] = c;
            }
            else if(Synth_CanFill(k, t))
            {
               o = h = l = c = g_syn_last_c[k];   // 直前Closeで平坦に埋める
            }
            else
            {
               ok = false;                        // 週末跨ぎ/48h超/未開始 → この足は作らない
               continue;                          // 他成分の状態更新は続ける
            }
            double w = g_syn_w[k];
            lnO += w * MathLog(o);
            lnC += w * MathLog(c);
            if(w >= 0) { lnH += w * MathLog(h); lnL += w * MathLog(l); }
            else       { lnH += w * MathLog(l); lnL += w * MathLog(h); }   // 負の指数: H/L 入替
         }
         if(t < write_from) continue;             // priming 区間: 状態だけ更新・書かない
         if(!ok) { skipped++; continue; }

         MqlRates s;
         s.time  = t;
         s.open  = NormalizeDouble(MathExp(lnO), Synth_Digits);
         s.close = NormalizeDouble(MathExp(lnC), Synth_Digits);
         s.high  = NormalizeDouble(MathExp(lnH), Synth_Digits);
         s.low   = NormalizeDouble(MathExp(lnL), Synth_Digits);
         s.high  = MathMax(s.high, MathMax(s.open, s.close));
         s.low   = MathMin(s.low,  MathMin(s.open, s.close));
         s.tick_volume = (vol > 0 ? vol : 1);
         s.spread = 0;
         s.real_volume = 0;

         ArrayResize(out, on + 1, cap + 1024);
         out[on++] = s;
      }

      if(on > 0)
      {
         if(first_out == 0) first_out = out[0].time;
         last_out = out[on - 1].time;
         if(!Synth_WriteRates(out, on, replace_mode))
            return false;
         written += on;
      }

      if(replace_mode && Verbose && chunk_no % 10 == 0)
         PrintFormat("[INFO] [Synth] build progress: chunk#%d up to %s, bars=%d",
                     chunk_no, TimeToString(ct, TIME_DATE), written);
   }
   return true;
}

//+==================================================================+
//| Synth_WaitH1Ready                                                |
//|   差分更新後、DXY_SYNTH H1 の同期と iADX の BarsCalculated を待つ  |
//|   （Phase 1 と同じ作法）。H1 先頭バーが合成最終バーの時間帯まで    |
//|   来ていることも条件にする。最後に確認ログを1行出す。              |
//+==================================================================+
bool Synth_WaitH1Ready()
{
   if(hDxy_ADX == INVALID_HANDLE) return false;
   SymbolSelect(Synth_Symbol, true);

   datetime m_last = 0;
   Synth_GetLastBar(m_last);
   datetime expect_head = m_last - (datetime)((long)m_last % 3600);   // 合成最終バーの属するH1

   int bars = 0, calc = 0;
   bool sync = false;
   datetime head = 0;
   bool ready = false;
   int wait_sec = MathMax(1, Synth_H1_Wait_Sec);
   for(int attempt = 1; attempt <= wait_sec; attempt++)
   {
      datetime t[];
      if(CopyTime(Synth_Symbol, PERIOD_H1, 0, 1, t) > 0) head = t[0];   // 生成トリガー兼
      bars = Bars(Synth_Symbol, PERIOD_H1);
      sync = (bool)SeriesInfoInteger(Synth_Symbol, PERIOD_H1, SERIES_SYNCHRONIZED);
      calc = BarsCalculated(hDxy_ADX);
      if(bars > 0 && sync && calc >= bars && head >= expect_head) { ready = true; break; }
      Sleep(1000);
   }

   datetime confirmed = iTime(Synth_Symbol, PERIOD_H1, 1);   // Dxy が使う最終確定バー
   PrintFormat("[INFO] [Dxy] [Synth] H1 check: %s  M5_last=%s  H1_head(forming)=%s  H1_confirmed(shift1)=%s  "
               "bars=%d calc=%d sync=%s",
               ready ? "READY" : "NOT READY",
               TimeToString(m_last, TIME_DATE|TIME_MINUTES),
               TimeToString(head, TIME_DATE|TIME_MINUTES),
               TimeToString(confirmed, TIME_DATE|TIME_MINUTES),
               bars, calc, sync ? "true" : "false");
   return ready;
}

//+##################################################################+
//|                                                                  |
//|  共通ヘルパ（両パートで同一ロジック → 1本に統一）                |
//|                                                                  |
//+##################################################################+

//+==================================================================+
//| JST ⇄ Server 時刻変換                                            |
//+==================================================================+
datetime JstToServer(datetime jst)
{
   datetime utc = jst - (datetime)(JST_Offset_Hours * 3600);
   long offset_sec = 0;
   if(Use_Auto_Server_Offset)
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   else
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   return utc + (datetime)offset_sec;
}

datetime ServerToJst(datetime server_time)
{
   long offset_sec = 0;
   if(Use_Auto_Server_Offset)
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   else
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   datetime utc = server_time - (datetime)offset_sec;
   return utc + (datetime)(JST_Offset_Hours * 3600);
}

//+==================================================================+
//| FormatJstDate / FormatJstDateTime                                |
//|   FormatJstDate: JST midnight datetime → "yyyy-mm-dd"           |
//|     ※ Agg版(引数名 jst_midnight)とMfe版(引数名 jst)はロジック    |
//|        同一のため1本に統一。                                      |
//+==================================================================+
string FormatJstDate(datetime jst)
{
   //--- "yyyy.mm.dd" → "yyyy-mm-dd" ---
   string s = TimeToString(jst, TIME_DATE);
   StringReplace(s, ".", "-");
   return s;
}

string FormatJstDateTime(datetime jst)
{
   //--- "yyyy.mm.dd HH:MM" → "yyyy-mm-dd HH:MM:00" ---
   string s = TimeToString(jst, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "-");
   return s + ":00";
}

//+==================================================================+
//| UTF-8 出力ヘルパ                                                 |
//+==================================================================+
void WriteUtf8Bom(int fh)
{
   uchar bom[3] = {0xEF, 0xBB, 0xBF};
   FileWriteArray(fh, bom, 0, 3);
}

void WriteUtf8String(int fh, const string s)
{
   uchar buf[];
   StringToCharArray(s, buf, 0, -1, CP_UTF8);
   int n = ArraySize(buf);
   if(n > 0 && buf[n-1] == 0) n--;
   if(n > 0) FileWriteArray(fh, buf, 0, n);
}
//+------------------------------------------------------------------+
