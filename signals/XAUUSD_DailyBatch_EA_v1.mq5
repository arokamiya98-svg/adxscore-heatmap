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
//|  作成日: 2026-06-18                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property strict

//+==================================================================+
//| 入力パラメータ                                                    |
//+==================================================================+
input group "=== 共通 ==="
input string  Allowed_Symbol           = "XAUUSD";   // この銘柄以外は起動拒否
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

//+==================================================================+
//| グローバル: 指標ハンドル（Aggregate専用, hAgg_ 接頭辞）           |
//+==================================================================+
int hAgg_ATR_S_H1 = INVALID_HANDLE, hAgg_ATR_L_H1 = INVALID_HANDLE, hAgg_ADX_H1 = INVALID_HANDLE;
int hAgg_ATR_S_H4 = INVALID_HANDLE, hAgg_ATR_L_H4 = INVALID_HANDLE, hAgg_ADX_H4 = INVALID_HANDLE;
int hAgg_ATR_S_D1 = INVALID_HANDLE, hAgg_ATR_L_D1 = INVALID_HANDLE, hAgg_ADX_D1 = INVALID_HANDLE;

//+==================================================================+
//| グローバル: 出力カウンタ                                          |
//+==================================================================+
int g_agg_rows_written = 0;
int g_agg_rows_skipped = 0;   // 営業日でない日（土日・H1足なし）

int g_mfe_rows_written = 0;
int g_mfe_rows_skipped = 0;
int g_mfe_rows_partial = 0;   // 48本フル追跡できなかった行

//+==================================================================+
//| グローバル: EA制御                                                |
//+==================================================================+
bool g_first_run = false;

//+==================================================================+
//| OnInit                                                           |
//+==================================================================+
int OnInit()
{
   Print("==== XAUUSD_DailyBatch_EA v1.00 OnInit ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, Allowed_Symbol);
   PrintFormat("Agg_Output: %s / Mfe_Output: %s", Agg_Output_File, Mfe_Output_File);
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
}

//+==================================================================+
//| OnDeinit                                                         |
//+==================================================================+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Agg_ReleaseHandles();
   PrintFormat("==== XAUUSD_DailyBatch_EA v1.00 OnDeinit (reason=%d) ====", reason);
}

//+==================================================================+
//| HandlesReady                                                     |
//|   9ハンドルすべて BarsCalculated>0 になったら true。              |
//|   旧 OnStart の Sleep(2000) ゲートの代替。                        |
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
