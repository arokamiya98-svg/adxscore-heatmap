//+------------------------------------------------------------------+
//|  XAUUSD_Daily_Aggregate_v1.mq5                                   |
//|  XAUUSD H1/H4/D1 の各指標を「JST日単位」で集計し、                |
//|  daily_aggregate.csv (UTF-8 BOM, 1行=1営業日) として出力する。    |
//|                                                                  |
//|  目的（マニ研究用）:                                              |
//|    日次の市場環境（ADX/DI/ATR）を「max/close/mean」3軸で記録し、  |
//|    トレードしなかった日も含めて環境推移を追跡できるようにする。   |
//|    → C1 (Trade_Snapshot_Builder) の date キーと結合して           |
//|       「同じ環境でトレードした日 vs しなかった日」の比較を可能に。|
//|                                                                  |
//|  指示書: data/mani_room/コー_指示書_XAUUSD_Daily_Aggregate.md     |
//|                                                                  |
//|  設計方針（Q1-Q4 確定）:                                          |
//|    Q1: D1足の取り方 = JST 23:00 server時刻の iBarShift            |
//|        → その時点で確定している最新 D1値（broker server時間吸収）|
//|    Q2: H4/H1 の「1日」= JST 00:00 〜 翌 00:00 で区切る             |
//|        → JST 14:00 仮想エントリー (C1) と整合                     |
//|    Q3: close = JST 24:00 直前の足の確定値                          |
//|        max   = その日の H4/H1 足の最大値                          |
//|        mean  = その日の H4/H1 足の平均値                          |
//|        DI系  = close のみ                                          |
//|    Q4: 営業日判定 = JST 14:00 の H1足が存在する日のみ出力          |
//|                                                                  |
//|  入力: なし（チャート稼働シンボル = XAUUSD 必須）                 |
//|  出力: MQL5/Files/daily_aggregate.csv (UTF-8 BOM)                |
//|                                                                  |
//|  作成日: 2026-06-09                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 入出力ファイル ==="
input string  Output_File         = "daily_aggregate.csv";

input group "=== 集計期間 ==="
input int     Lookback_Days       = 120;     // 直近 N 日分を出力

input group "=== タイムゾーン ==="
input int     JST_Offset_Hours    = 9;       // JST = UTC+9（固定）
input bool    Use_Auto_Server_Offset = true; // TimeTradeServer() - TimeGMT() で自動算出
input int     Manual_Server_Offset_Hours = 2; // 自動算出失敗時のフォールバック

input group "=== H1 指標周期 (CLAUDE.md 確定値) ==="
input int     H1_ATR_Short        = 16;
input int     H1_ATR_Long         = 32;
input int     H1_ADX_Period       = 32;

input group "=== H4 指標周期 ==="
input int     H4_ATR_Short        = 8;
input int     H4_ATR_Long         = 46;
input int     H4_ADX_Period       = 46;

input group "=== D1 指標周期 ==="
input int     D1_ATR_Short        = 22;
input int     D1_ATR_Long         = 42;
input int     D1_ADX_Period       = 22;

input group "=== DI 方向判定 ==="
input double  DI_Spread_Flat_Thresh = 1.0;   // |spread| < これ なら FLAT 扱い

input group "=== シンボル制約 ==="
input string  Allowed_Symbol      = "XAUUSD";

input group "=== デバッグ ==="
input bool    Verbose             = true;

//+-----[ 指標ハンドル ]--------------------------------------------+
int hATR_S_H1 = INVALID_HANDLE, hATR_L_H1 = INVALID_HANDLE, hADX_H1 = INVALID_HANDLE;
int hATR_S_H4 = INVALID_HANDLE, hATR_L_H4 = INVALID_HANDLE, hADX_H4 = INVALID_HANDLE;
int hATR_S_D1 = INVALID_HANDLE, hATR_L_D1 = INVALID_HANDLE, hADX_D1 = INVALID_HANDLE;

//+-----[ 出力カウンタ ]--------------------------------------------+
int g_rows_written = 0;
int g_rows_skipped = 0;  // 営業日でない日（土日・H1足なし）

//+==================================================================+
//| OnStart                                                          |
//+==================================================================+
void OnStart()
{
   Print("==== XAUUSD_Daily_Aggregate v1.0 Start ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, Allowed_Symbol);
   PrintFormat("Output: %s", Output_File);
   PrintFormat("Lookback_Days: %d", Lookback_Days);

   //--- シンボル制約 ---
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return;
   }

   //--- ハンドル初期化 ---
   if(!InitHandles())
   {
      Print("[FATAL] 指標ハンドル初期化に失敗。終了。");
      return;
   }
   Sleep(2000);  // インジ計算待ち

   //--- 出力 CSV オープン (UTF-8 BOM) ---
   int fout = FileOpen(Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 出力CSV open失敗: %s err=%d", Output_File, GetLastError());
      ReleaseHandles();
      return;
   }
   WriteUtf8Bom(fout);
   WriteHeaderUtf8(fout);

   //--- DST 警告 ---
   if(Use_Auto_Server_Offset && Verbose)
   {
      long ofs = (long)(TimeTradeServer() - TimeGMT());
      PrintFormat("[INFO] Current server-GMT offset = %d sec (= %.2f h).",
                  (int)ofs, ofs/3600.0);
   }

   //--- メインループ: 今日(JST) から Lookback_Days 日前まで遡って処理 ---
   //   today_jst_midnight = 今日の JST 00:00 (UTC基準の datetime表現)
   datetime now_server = TimeTradeServer();
   datetime now_jst    = ServerToJst(now_server);
   // JST 00:00 へ truncate
   datetime today_jst_midnight = TruncateToDayJst(now_jst);

   // 古い日から処理（CSVを古い順に並べる）
   for(int d = Lookback_Days - 1; d >= 0; d--)
   {
      datetime day_jst_midnight = today_jst_midnight - (datetime)(d * 86400);
      ProcessDay(fout, day_jst_midnight);
   }

   FileClose(fout);
   ReleaseHandles();

   Print("==== XAUUSD_Daily_Aggregate v1.0 Complete ====");
   PrintFormat("  written = %d", g_rows_written);
   PrintFormat("  skipped (no business day) = %d", g_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Output_File);
}

//+==================================================================+
//| InitHandles                                                      |
//+==================================================================+
bool InitHandles()
{
   string sym = _Symbol;
   hATR_S_H1 = iATR(sym, PERIOD_H1, H1_ATR_Short);
   hATR_L_H1 = iATR(sym, PERIOD_H1, H1_ATR_Long);
   hADX_H1   = iADX(sym, PERIOD_H1, H1_ADX_Period);
   hATR_S_H4 = iATR(sym, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(sym, PERIOD_H4, H4_ATR_Long);
   hADX_H4   = iADX(sym, PERIOD_H4, H4_ADX_Period);
   hATR_S_D1 = iATR(sym, PERIOD_D1, D1_ATR_Short);
   hATR_L_D1 = iATR(sym, PERIOD_D1, D1_ATR_Long);
   hADX_D1   = iADX(sym, PERIOD_D1, D1_ADX_Period);

   if(hATR_S_H1==INVALID_HANDLE || hATR_L_H1==INVALID_HANDLE || hADX_H1==INVALID_HANDLE ||
      hATR_S_H4==INVALID_HANDLE || hATR_L_H4==INVALID_HANDLE || hADX_H4==INVALID_HANDLE ||
      hATR_S_D1==INVALID_HANDLE || hATR_L_D1==INVALID_HANDLE || hADX_D1==INVALID_HANDLE)
   {
      PrintFormat("[ERR] ハンドル初期化失敗 err=%d", GetLastError());
      return false;
   }
   return true;
}

void ReleaseHandles()
{
   if(hATR_S_H1 != INVALID_HANDLE) IndicatorRelease(hATR_S_H1);
   if(hATR_L_H1 != INVALID_HANDLE) IndicatorRelease(hATR_L_H1);
   if(hADX_H1   != INVALID_HANDLE) IndicatorRelease(hADX_H1);
   if(hATR_S_H4 != INVALID_HANDLE) IndicatorRelease(hATR_S_H4);
   if(hATR_L_H4 != INVALID_HANDLE) IndicatorRelease(hATR_L_H4);
   if(hADX_H4   != INVALID_HANDLE) IndicatorRelease(hADX_H4);
   if(hATR_S_D1 != INVALID_HANDLE) IndicatorRelease(hATR_S_D1);
   if(hATR_L_D1 != INVALID_HANDLE) IndicatorRelease(hATR_L_D1);
   if(hADX_D1   != INVALID_HANDLE) IndicatorRelease(hADX_D1);
}

//+==================================================================+
//| ProcessDay                                                       |
//|   1営業日分の集計を行う。                                         |
//|   入力: day_jst_midnight = その日の JST 00:00                    |
//|                                                                  |
//|   処理:                                                            |
//|     1. JST 14:00 の H1足存在チェック → 無ければ skip (土日等)    |
//|     2. JST 23:00 server時刻で D1足取得（その時点確定の D1値）    |
//|     3. JST 00:00〜24:00 範囲の H4/H1 足を走査して max/close/mean |
//|     4. 1行書き出し                                                |
//+==================================================================+
void ProcessDay(int fout, datetime day_jst_midnight)
{
   //--- 営業日判定: JST 14:00 server時刻に H1足があるか? ---
   datetime jst_1400 = day_jst_midnight + (datetime)(14 * 3600);
   datetime srv_1400 = JstToServer(jst_1400);
   int sh_h1_1400 = iBarShift(_Symbol, PERIOD_H1, srv_1400, true);  // exact=true で厳密一致
   if(sh_h1_1400 < 0)
   {
      // exact=false で再試行 → 直前バーの開始時刻と1時間以内ならOK
      sh_h1_1400 = iBarShift(_Symbol, PERIOD_H1, srv_1400, false);
      if(sh_h1_1400 < 0)
      {
         g_rows_skipped++;
         if(Verbose)
            PrintFormat("[SKIP] %s (no H1 bar at JST 14:00)",
                        FormatJstDate(day_jst_midnight));
         return;
      }
      datetime bar_t = iTime(_Symbol, PERIOD_H1, sh_h1_1400);
      // 1時間以上前のバーなら、その日の14時にバーが無いと判断
      if(srv_1400 - bar_t >= 3600)
      {
         g_rows_skipped++;
         if(Verbose)
            PrintFormat("[SKIP] %s (no H1 bar at JST 14:00, nearest=%s)",
                        FormatJstDate(day_jst_midnight),
                        TimeToString(bar_t, TIME_DATE|TIME_MINUTES));
         return;
      }
   }

   string date_str = FormatJstDate(day_jst_midnight);  // "yyyy-mm-dd"

   //--- D1値取得: JST 23:00 server時刻で iBarShift ---
   //   その時点で確定している直前 D1足を取る (exact=false)
   datetime jst_2300 = day_jst_midnight + (datetime)(23 * 3600);
   datetime srv_2300 = JstToServer(jst_2300);
   int sh_d1 = iBarShift(_Symbol, PERIOD_D1, srv_2300, false);
   if(sh_d1 < 0)
   {
      g_rows_skipped++;
      if(Verbose) PrintFormat("[SKIP] %s D1 bar not found", date_str);
      return;
   }

   double d1_atr22 = GetBufValue(hATR_S_D1, 0, sh_d1);
   double d1_atr42 = GetBufValue(hATR_L_D1, 0, sh_d1);
   double d1_adx22 = GetBufValue(hADX_D1,   0, sh_d1);
   double d1_dip   = GetBufValue(hADX_D1,   1, sh_d1);
   double d1_din   = GetBufValue(hADX_D1,   2, sh_d1);
   double d1_ratio = (d1_atr42 > 0) ? d1_atr22 / d1_atr42 : 0;
   double d1_spread = d1_dip - d1_din;
   string d1_di_dir = ClassifyDiDir(d1_spread);

   //--- H4/H1集計: JST 00:00 〜 翌 00:00 の範囲 ---
   //   range_start_srv (含む) ≤ bar_time < range_end_srv (含まない)
   datetime range_start_srv = JstToServer(day_jst_midnight);
   datetime range_end_srv   = JstToServer(day_jst_midnight + 86400);

   //--- H4 集計 ---
   double h4_adx46_max = 0, h4_adx46_close = 0, h4_adx46_mean = 0;
   double h4_dip_close = 0, h4_din_close = 0;
   double h4_atr8_close = 0, h4_atr46_close = 0;
   AggregateH4(range_start_srv, range_end_srv,
               h4_adx46_max, h4_adx46_close, h4_adx46_mean,
               h4_dip_close, h4_din_close,
               h4_atr8_close, h4_atr46_close);
   double h4_di_spread = h4_dip_close - h4_din_close;
   string h4_di_dir = ClassifyDiDir(h4_di_spread);
   double h4_atr_ratio = (h4_atr46_close > 0) ? h4_atr8_close / h4_atr46_close : 0;

   //--- H1 集計 ---
   double h1_adx32_max = 0, h1_adx32_close = 0, h1_adx32_mean = 0;
   double h1_dip_close = 0, h1_din_close = 0;
   double h1_atr16_close = 0, h1_atr32_close = 0;
   AggregateH1(range_start_srv, range_end_srv,
               h1_adx32_max, h1_adx32_close, h1_adx32_mean,
               h1_dip_close, h1_din_close,
               h1_atr16_close, h1_atr32_close);
   double h1_di_spread = h1_dip_close - h1_din_close;
   string h1_di_dir = ClassifyDiDir(h1_di_spread);
   double h1_atr_ratio = (h1_atr32_close > 0) ? h1_atr16_close / h1_atr32_close : 0;

   //--- 行書き出し ---
   WriteRow(fout, date_str,
            d1_adx22, d1_dip, d1_din, d1_spread, d1_di_dir,
            d1_atr22, d1_atr42, d1_ratio,
            h4_adx46_max, h4_adx46_close, h4_adx46_mean,
            h4_dip_close, h4_din_close, h4_di_spread, h4_di_dir,
            h4_atr8_close, h4_atr46_close, h4_atr_ratio,
            h1_adx32_max, h1_adx32_close, h1_adx32_mean,
            h1_dip_close, h1_din_close, h1_di_spread, h1_di_dir,
            h1_atr16_close, h1_atr32_close, h1_atr_ratio);

   g_rows_written++;
   if(Verbose && (g_rows_written % 20 == 0))
      PrintFormat("[INFO] processed %d days...", g_rows_written);
}

//+==================================================================+
//| AggregateH4 / AggregateH1                                        |
//|   指定 server時刻範囲 [start, end) 内の H4/H1 足を走査して       |
//|   max/close/mean を集計する。                                     |
//|                                                                  |
//|   close = 範囲内最終足（範囲内で最も新しい確定足）の値           |
//|   max   = 範囲内全足の最大値                                      |
//|   mean  = 範囲内全足の単純平均                                    |
//|   DI系  = close のみ（範囲内最終足の DI値）                       |
//|   ATR   = close のみ（範囲内最終足の ATR値）                      |
//+==================================================================+
void AggregateH4(datetime range_start_srv, datetime range_end_srv,
                 double &adx46_max, double &adx46_close, double &adx46_mean,
                 double &dip_close, double &din_close,
                 double &atr8_close, double &atr46_close)
{
   adx46_max = 0; adx46_close = 0; adx46_mean = 0;
   dip_close = 0; din_close = 0;
   atr8_close = 0; atr46_close = 0;

   AggregateRange(PERIOD_H4, hADX_H4, hATR_S_H4, hATR_L_H4,
                  range_start_srv, range_end_srv,
                  adx46_max, adx46_close, adx46_mean,
                  dip_close, din_close,
                  atr8_close, atr46_close);
}

void AggregateH1(datetime range_start_srv, datetime range_end_srv,
                 double &adx32_max, double &adx32_close, double &adx32_mean,
                 double &dip_close, double &din_close,
                 double &atr16_close, double &atr32_close)
{
   adx32_max = 0; adx32_close = 0; adx32_mean = 0;
   dip_close = 0; din_close = 0;
   atr16_close = 0; atr32_close = 0;

   AggregateRange(PERIOD_H1, hADX_H1, hATR_S_H1, hATR_L_H1,
                  range_start_srv, range_end_srv,
                  adx32_max, adx32_close, adx32_mean,
                  dip_close, din_close,
                  atr16_close, atr32_close);
}

//+==================================================================+
//| AggregateRange                                                   |
//|   汎用ヘルパ: tf の足を range_start_srv ≤ bar_time < range_end_srv|
//|   の範囲で走査して max/close/mean を計算。                        |
//|                                                                  |
//|   走査方針:                                                       |
//|     range_end_srv の直前足を iBarShift(range_end_srv-1, false)で  |
//|     探し、そこから古い側へ range_start_srv 直前まで遡る。         |
//|     最新側の足 = close 値（DI/ATR の close もこの足から取る）     |
//+==================================================================+
void AggregateRange(ENUM_TIMEFRAMES tf,
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

      double adx_val = GetBufValue(hADX, 0, sh);
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
   adx_close   = GetBufValue(hADX,    0, sh_close);
   dip_close   = GetBufValue(hADX,    1, sh_close);
   din_close   = GetBufValue(hADX,    2, sh_close);
   atr_s_close = GetBufValue(hATR_S,  0, sh_close);
   atr_l_close = GetBufValue(hATR_L,  0, sh_close);
}

//+==================================================================+
//| ClassifyDiDir                                                    |
//|   DI+ - DI- = spread → BULL / BEAR / FLAT                       |
//+==================================================================+
string ClassifyDiDir(double spread)
{
   if(MathAbs(spread) < DI_Spread_Flat_Thresh) return "FLAT";
   if(spread > 0) return "BULL";
   return "BEAR";
}

//+==================================================================+
//| GetBufValue                                                      |
//+==================================================================+
double GetBufValue(int handle, int buf, int shift)
{
   if(handle == INVALID_HANDLE) return 0;
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buf, shift, 1, tmp) <= 0) return 0;
   return tmp[0];
}

//+==================================================================+
//| JST ⇄ Server 時刻変換 (C1 から流用)                              |
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
//| TruncateToDayJst                                                 |
//|   JST の datetime を 00:00 に切り下げる                           |
//+==================================================================+
datetime TruncateToDayJst(datetime jst)
{
   MqlDateTime t;
   TimeToStruct(jst, t);
   t.hour = 0;
   t.min  = 0;
   t.sec  = 0;
   return StructToTime(t);
}

//+==================================================================+
//| FormatJstDate                                                    |
//|   JST midnight datetime → "yyyy-mm-dd"                          |
//+==================================================================+
string FormatJstDate(datetime jst_midnight)
{
   string s = TimeToString(jst_midnight, TIME_DATE);
   StringReplace(s, ".", "-");
   return s;
}

//+==================================================================+
//| UTF-8 出力ヘルパ (C1 から流用)                                   |
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

//+==================================================================+
//| WriteHeaderUtf8                                                  |
//|   28列:                                                           |
//|     [1]    date                                                   |
//|     [2-9]  D1 (8列: adx22,dip,din,spread,dir,atr22,atr42,ratio)   |
//|     [10-19] H4 (10列: adx46×3, dip_close, din_close, spread, dir, |
//|                       atr8_close, atr46_close, ratio_close)       |
//|     [20-29] H1 (10列: adx32×3, dip_close, din_close, spread, dir, |
//|                       atr16_close, atr32_close, ratio_close)      |
//|   合計: 1 + 8 + 10 + 10 = 29列                                    |
//+==================================================================+
void WriteHeaderUtf8(int fh)
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
//| WriteRow                                                         |
//+==================================================================+
void WriteRow(int fh, const string &date_str,
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
//+------------------------------------------------------------------+
