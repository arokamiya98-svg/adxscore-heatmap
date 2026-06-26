//+------------------------------------------------------------------+
//|  ADX_Weekly_Above_EA_v1.mq5                                      |
//|                                                                  |
//|  ②自動集計（週次ヒートマップ＝ADXスコア計算元）の常駐EA化。      |
//|  Script版 ADX_Weekly_Above_v4.mq5（OnStart型）を                |
//|  OnInit/OnTimer/OnDeinit の常駐EAに移植し、VPS上のMT5で          |
//|  XAUUSD H1チャート1枚から ADX_Weekly_Above_v4.csv を毎時無人生成。|
//|  進行中週（今週）は手描きBU/PD空のまま、ADXスコアだけ毎時最新。   |
//|                                                                  |
//|  移植元（ロジックは1ミリも変えずコピペ移植 — 触らず温存・正本）:  |
//|    - ADX_Weekly_Above_v4.mq5 (OnStart / 17列 /                  |
//|        銘柄ループ内で iADX 都度生成・解放 / UTF-16出力)          |
//|        → ADX_Weekly_Above_v4.csv (UTF-16 / FILE_CSV|FILE_UNICODE)|
//|                                                                  |
//|  移植方針（コー_指示書_②自動集計_ADX_Weekly_EA化_v1.md）:        |
//|    - H4Phaseと違い「本体まるごと OnTimer」方式。ADX_Weekly は     |
//|      銘柄ループ内で iADX を都度生成→CopyBuffer(日付範囲)→        |
//|      IndicatorRelease する構造のため、グローバルハンドル化せず、  |
//|      ハンドル管理は移植元のまま無改変にし、旧 OnStart 本体を      |
//|      RunWeeklyAggregate() にリネームして OnTimer から呼ぶ。       |
//|    - HandlesReady() の代わりに DataReady() ゲート（新規）。       |
//|      グローバルハンドルが無いので BarsCalculated は使えない。     |
//|      Bars(H1) > InpH1_Period+100 && Bars(H4) > InpH4_Period+100  |
//|      でゲート＝データ未ロード時にヘッダだけの空CSVを吐く事故を防ぐ|
//|      （空CSVがpushされると Mac heatmap が壊れる）。              |
//|    - 本体内の既存SKIP（if(h1_n_adx<=0) continue 等）はそのまま   |
//|      ＝二重のフェイルセーフ。                                     |
//|    - FileOpen(FILE_WRITE) はフル上書き＝追記事故なし。毎時焼直し。|
//|                                                                  |
//|  地雷（指示書§1）:                                               |
//|    - 出力は UTF-16 のまま（系統B/CのUTF-8 BOMと揃えない）。       |
//|    - 進行中週を出す H1ループ FLUSH機構（移植元187-246）は絶対維持。|
//|      i==h1_n で wk="FLUSH" を立て直前の実週を FileWrite する。    |
//|      これが「週確定を待たず毎時最新」を成立させる本体。           |
//|    - InpSymbols="XAUUSD" は温存するが Allowed_Symbol チェックで   |
//|      実質XAUUSD単一運用。将来複数銘柄に戻す時は OnInit の         |
//|      _Symbol チェックを外す（下記 OnInit のコメント参照）。       |
//|                                                                  |
//|  指示書: data/vps/コー_指示書_②自動集計_ADX_Weekly_EA化_v1.md    |
//|  作成日: 2026-06-26                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 共通 ==="
input string   Allowed_Symbol  = "XAUUSD";          // この銘柄以外は起動拒否（誤アタッチ防止）

input group "=== EA制御（新規）==="
input int      Update_Interval_Min = 60;            // 本間隔（ready後の再生成周期, 分）
input int      First_Run_Delay_Sec = 15;            // 初回タイマー（ready待ちの短間隔, 秒）
input bool     Verbose         = true;

input group "=== 集計対象（移植元から維持）==="
input string   InpSymbols      = "XAUUSD";
input datetime InpStartDate    = D'2023.01.01 00:00';   // 移植元の string リテラル "..." を datetime リテラル D'...' に正規化（値は完全同一・暗黙変換 warning 解消）
input datetime InpEndDate      = D'2027.12.31 23:59';   // 同上（CSV出力・集計ロジックに影響なし）
input int      InpH1_Period    = 32;
input int      InpH4_Period    = 46;
input double   InpThresh_Low   = 20.0;
input double   InpThresh_H4Hi  = 25.0;

input group "=== 出力 ==="
input string   InpFileName     = "ADX_Weekly_Above_v4.csv";

//+-----[ EA制御 ]--------------------------------------------------+
bool g_first_run = false;

//+==================================================================+
//| OnInit                                                           |
//+==================================================================+
int OnInit()
{
   Print("==== ADX_Weekly_Above_EA v1.00 OnInit ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s, Period: %s",
      _Symbol, Allowed_Symbol, EnumToString(_Period));
   PrintFormat("InpSymbols: %s", InpSymbols);
   PrintFormat("H1 ADX周期=%d  H4 ADX周期=%d  H4強閾値=%.1f",
      InpH1_Period, InpH4_Period, InpThresh_H4Hi);
   PrintFormat("Output: %s", InpFileName);

   //--- シンボル制約: XAUUSD以外で起動拒否（XAUUSD H1チャート運用前提）---
   //   ※ 将来複数銘柄集計に戻す時は、この _Symbol チェックを外し、
   //     InpSymbols へカンマ区切りで銘柄を並べる（本体は銘柄ループ温存）。
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s H1 チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return(INIT_FAILED);
   }

   //--- 初回は短く（ready待ち）---
   //   ※ ハンドルはOnInitで作らない（本体内で銘柄ループ都度生成のため）。
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);

   return(INIT_SUCCEEDED);
}

//+==================================================================+
//| OnTimer                                                          |
//+==================================================================+
void OnTimer()
{
   //--- H1/H4バーが十分ロードされるまで持ち越し（系統B/C HandlesReady相当）---
   if(!DataReady())
   {
      if(Verbose) Print("[WAIT] H1/H4 bars not loaded enough yet...");
      return;
   }

   //--- ready初回だけ本間隔へ張り替え ---
   if(g_first_run)
   {
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);
      g_first_run = false;
      if(Verbose)
         PrintFormat("[INFO] data ready. timer → %d min interval.",
                     Update_Interval_Min);
   }

   //--- 旧 OnStart 本体まるごと（FileOpen→銘柄ループ→FileClose）---
   RunWeeklyAggregate();
}

//+==================================================================+
//| OnDeinit                                                         |
//|   ハンドルは本体内で都度 IndicatorRelease 済み → 追加解放不要。   |
//+==================================================================+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("==== ADX_Weekly_Above_EA v1.00 OnDeinit (reason=%d) ====", reason);
}

//+==================================================================+
//| DataReady                                                        |
//|   グローバルハンドルが無いので BarsCalculated は使えない。        |
//|   H1/H4 のバーが ADX周期+余裕(100) 分ロードされたかでゲート。     |
//|   データ未ロード状態で本体を走らせて「ヘッダだけの空CSV」を       |
//|   吐く事故を防ぐ（系統B/C HandlesReady() に相当）。              |
//|   しきい値根拠: ADX(period) の計算に最低 period 本超のバーが要る。|
//|   +100 はウォームアップ余裕（指示書§2 で指定の値）。            |
//+==================================================================+
bool DataReady()
{
   if(Bars(_Symbol, PERIOD_H1) <= InpH1_Period + 100) return false;
   if(Bars(_Symbol, PERIOD_H4) <= InpH4_Period + 100) return false;
   return true;
}

//+##################################################################+
//|                                                                  |
//|  以下、旧 OnStart 本体 → RunWeeklyAggregate() にリネームのみ。    |
//|  集計ロジック・銘柄ループ・FLUSH機構は移植元 25-266 を            |
//|  1ミリも変えず無改変コピペ。                                      |
//|                                                                  |
//+##################################################################+
void RunWeeklyAggregate()
{
   string symbols[];
   int sym_count = StringSplit(InpSymbols, ',', symbols);
   if(sym_count == 0) { Print("ERROR: 銘柄リストが空"); return; }

   int fh = FileOpen(InpFileName, FILE_WRITE | FILE_CSV | FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) { Print("ERROR: ファイルオープン失敗 ", InpFileName); return; }

   FileWrite(fh,
      "Week", "WeekStart", "Symbol",
      "H1_Bars_Above20", "H1_Total_Bars", "H1_Pct_Above20",
      "H1_Range_Pips",   "H1_AvgADX",    "H1_MaxADX",
      "H4_Bars_Above20", "H4_Total_Bars", "H4_Pct_Above20",
      "H4_Bars_Above25", "H4_Pct_Above25",
      "H4_Range_Pips",   "H4_AvgADX",    "H4_MaxADX"
   );

   int total_rows   = 0;
   int error_count  = 0;
   string ok_syms   = "";
   string fail_syms = "";

   for(int si = 0; si < sym_count; si++)
   {
      string sym = symbols[si];
      StringTrimLeft(sym); StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;

      Print("=== 処理開始: ", sym, " ===");
      Print("  H1 ADX周期=", InpH1_Period, "  H4 ADX周期=", InpH4_Period, "  H4強閾値=", InpThresh_H4Hi);

      //--- pip換算係数（銘柄別）
      double pip_factor = GetPipFactor(sym);
      Print(sym, " pip_factor=", pip_factor);

      //----------------------------------------------------------------
      // H1データ取得
      //----------------------------------------------------------------
      int h1_adx_handle = iADX(sym, PERIOD_H1, InpH1_Period);
      if(h1_adx_handle == INVALID_HANDLE)
      {
         Print("SKIP: H1 ADXハンドル作成失敗 [", sym, "] シンボル名を確認してください");
         fail_syms += sym + "(H1ADX) ";
         error_count++;
         continue;
      }

      double h1_adx[], h1_high[], h1_low[];
      datetime h1_time[];
      ArraySetAsSeries(h1_adx, true); ArraySetAsSeries(h1_high, true);
      ArraySetAsSeries(h1_low, true); ArraySetAsSeries(h1_time, true);

      int h1_n_adx  = CopyBuffer(h1_adx_handle, 0, InpStartDate, InpEndDate, h1_adx);
      int h1_n_high = CopyHigh(sym, PERIOD_H1, InpStartDate, InpEndDate, h1_high);
      int h1_n_low  = CopyLow (sym, PERIOD_H1, InpStartDate, InpEndDate, h1_low);
      int h1_n_time = CopyTime(sym, PERIOD_H1, InpStartDate, InpEndDate, h1_time);
      IndicatorRelease(h1_adx_handle);

      if(h1_n_adx <= 0 || h1_n_time <= 0)
      {
         Print("SKIP: H1データなし [", sym, "] adx=", h1_n_adx, " time=", h1_n_time);
         Print("  → チャートを開いてデータをロードしてから再実行してください");
         fail_syms += sym + "(H1data) ";
         error_count++;
         continue;
      }

      int h1_n = MathMin(MathMin(h1_n_adx, h1_n_high), MathMin(h1_n_low, h1_n_time));
      Print(sym, " H1バー数: ", h1_n);

      ArrayReverse(h1_adx); ArrayReverse(h1_high);
      ArrayReverse(h1_low); ArrayReverse(h1_time);

      //----------------------------------------------------------------
      // H4データ取得
      //----------------------------------------------------------------
      int h4_adx_handle = iADX(sym, PERIOD_H4, InpH4_Period);
      if(h4_adx_handle == INVALID_HANDLE)
      {
         Print("SKIP: H4 ADXハンドル作成失敗 [", sym, "]");
         fail_syms += sym + "(H4ADX) ";
         error_count++;
         continue;
      }

      double h4_adx[], h4_high[], h4_low[];
      datetime h4_time[];
      ArraySetAsSeries(h4_adx, true); ArraySetAsSeries(h4_high, true);
      ArraySetAsSeries(h4_low, true); ArraySetAsSeries(h4_time, true);

      int h4_n_adx  = CopyBuffer(h4_adx_handle, 0, InpStartDate, InpEndDate, h4_adx);
      int h4_n_high = CopyHigh(sym, PERIOD_H4, InpStartDate, InpEndDate, h4_high);
      int h4_n_low  = CopyLow (sym, PERIOD_H4, InpStartDate, InpEndDate, h4_low);
      int h4_n_time = CopyTime(sym, PERIOD_H4, InpStartDate, InpEndDate, h4_time);
      IndicatorRelease(h4_adx_handle);

      if(h4_n_adx <= 0 || h4_n_time <= 0)
      {
         Print("SKIP: H4データなし [", sym, "] adx=", h4_n_adx, " time=", h4_n_time);
         fail_syms += sym + "(H4data) ";
         error_count++;
         continue;
      }

      int h4_n = MathMin(MathMin(h4_n_adx, h4_n_high), MathMin(h4_n_low, h4_n_time));
      Print(sym, " H4バー数: ", h4_n);

      ArrayReverse(h4_adx); ArrayReverse(h4_high);
      ArrayReverse(h4_low); ArrayReverse(h4_time);

      //----------------------------------------------------------------
      // H4を週キー別に先に集計
      //----------------------------------------------------------------
      string h4_weeks[];   ArrayResize(h4_weeks,   0);
      int    h4_bars20[];  ArrayResize(h4_bars20,  0);
      int    h4_bars25[];  ArrayResize(h4_bars25,  0);
      int    h4_total[];   ArrayResize(h4_total,   0);
      double h4_sumAdx[];  ArrayResize(h4_sumAdx,  0);
      double h4_maxAdx[];  ArrayResize(h4_maxAdx,  0);
      double h4_rangeHi[]; ArrayResize(h4_rangeHi, 0);
      double h4_rangeLo[]; ArrayResize(h4_rangeLo, 0);

      for(int i = 0; i < h4_n; i++)
      {
         string wk = GetWeekKey(h4_time[i]);
         int idx = FindWeek(h4_weeks, wk);
         if(idx < 0)
         {
            idx = ArraySize(h4_weeks);
            ArrayResize(h4_weeks,   idx+1); h4_weeks[idx]   = wk;
            ArrayResize(h4_bars20,  idx+1); h4_bars20[idx]  = 0;
            ArrayResize(h4_bars25,  idx+1); h4_bars25[idx]  = 0;
            ArrayResize(h4_total,   idx+1); h4_total[idx]   = 0;
            ArrayResize(h4_sumAdx,  idx+1); h4_sumAdx[idx]  = 0;
            ArrayResize(h4_maxAdx,  idx+1); h4_maxAdx[idx]  = 0;
            ArrayResize(h4_rangeHi, idx+1); h4_rangeHi[idx] = -DBL_MAX;
            ArrayResize(h4_rangeLo, idx+1); h4_rangeLo[idx] =  DBL_MAX;
         }
         double adx = h4_adx[i];
         h4_total[idx]++;
         h4_sumAdx[idx] += adx;
         if(adx > h4_maxAdx[idx]) h4_maxAdx[idx] = adx;
         if(adx >= InpThresh_Low)
         {
            h4_bars20[idx]++;
            if(h4_high[i] > h4_rangeHi[idx]) h4_rangeHi[idx] = h4_high[i];
            if(h4_low[i]  < h4_rangeLo[idx]) h4_rangeLo[idx] = h4_low[i];
         }
         if(adx >= InpThresh_H4Hi) h4_bars25[idx]++;
      }

      //----------------------------------------------------------------
      // H1ループで週集計
      //----------------------------------------------------------------
      string cur_week = "";
      datetime cur_week_start = 0;
      int    h1_bars20 = 0, h1_total = 0;
      double h1_sumAdx = 0, h1_maxAdx = 0;
      double h1_rangeHi = -DBL_MAX, h1_rangeLo = DBL_MAX;
      int    rows_this_sym = 0;

      for(int i = 0; i <= h1_n; i++)
      {
         string wk = (i < h1_n) ? GetWeekKey(h1_time[i]) : "FLUSH";

         if(wk != cur_week && cur_week != "")
         {
            int h4idx = FindWeek(h4_weeks, cur_week);
            int    h4b20=0, h4b25=0, h4tot=0;
            double h4avg=0, h4mx=0, h4rPips=0;
            if(h4idx >= 0)
            {
               h4b20  = h4_bars20[h4idx];
               h4b25  = h4_bars25[h4idx];
               h4tot  = h4_total[h4idx];
               h4avg  = h4tot > 0 ? h4_sumAdx[h4idx] / h4tot : 0;
               h4mx   = h4_maxAdx[h4idx];
               double rHi = h4_rangeHi[h4idx];
               double rLo = h4_rangeLo[h4idx];
               h4rPips = (rHi > rLo && rHi != -DBL_MAX) ? (rHi - rLo) / pip_factor : 0;
            }

            double h1pct   = h1_total > 0 ? (double)h1_bars20 / h1_total * 100.0 : 0;
            double h1avg   = h1_total > 0 ? h1_sumAdx / h1_total : 0;
            double h1rPips = (h1_rangeHi > h1_rangeLo && h1_rangeHi != -DBL_MAX)
                             ? (h1_rangeHi - h1_rangeLo) / pip_factor : 0;
            double h4pct20 = h4tot > 0 ? (double)h4b20 / h4tot * 100.0 : 0;
            double h4pct25 = h4tot > 0 ? (double)h4b25 / h4tot * 100.0 : 0;

            FileWrite(fh,
               cur_week,
               TimeToString(cur_week_start, TIME_DATE),
               sym,
               h1_bars20, h1_total, DoubleToString(h1pct, 1),
               DoubleToString(h1rPips, 1), DoubleToString(h1avg, 2), DoubleToString(h1_maxAdx, 2),
               h4b20, h4tot, DoubleToString(h4pct20, 1),
               h4b25, DoubleToString(h4pct25, 1),
               DoubleToString(h4rPips, 1), DoubleToString(h4avg, 2), DoubleToString(h4mx, 2)
            );
            total_rows++;
            rows_this_sym++;

            h1_bars20=0; h1_total=0; h1_sumAdx=0; h1_maxAdx=0;
            h1_rangeHi=-DBL_MAX; h1_rangeLo=DBL_MAX;
         }
         if(i >= h1_n) break;

         cur_week       = wk;
         cur_week_start = GetWeekStart(h1_time[i]);

         double adx = h1_adx[i];
         h1_total++;
         h1_sumAdx += adx;
         if(adx > h1_maxAdx) h1_maxAdx = adx;
         if(adx >= InpThresh_Low)
         {
            h1_bars20++;
            if(h1_high[i] > h1_rangeHi) h1_rangeHi = h1_high[i];
            if(h1_low[i]  < h1_rangeLo) h1_rangeLo = h1_low[i];
         }
      }

      Print(sym, " 完了: ", rows_this_sym, "週分出力");
      ok_syms += sym + " ";
   }

   FileClose(fh);

   Print("========================================");
   Print("=== ADX_Weekly_Above_v4 完了 ===");
   Print("H1 ADX周期=", InpH1_Period, "  H4 ADX周期=", InpH4_Period, "  H4強閾値=", InpThresh_H4Hi);
   Print("総出力行数: ", total_rows);
   Print("成功銘柄: ", ok_syms);
   if(error_count > 0)
   {
      Print("失敗銘柄: ", fail_syms);
      Print("※ 失敗した銘柄はチャートを開いてデータをロード後に再実行してください");
   }
   Print("保存先: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", InpFileName);
   Print("========================================");
}

//+##################################################################+
//|                                                                  |
//|  以下、純粋関数群（移植元 271-341 を 1ミリも変えず無改変コピペ）  |
//|                                                                  |
//+##################################################################+

//+------------------------------------------------------------------+
//| pip換算係数（銘柄別精密設定）                                      |
//+------------------------------------------------------------------+
double GetPipFactor(string sym)
{
   if(StringFind(sym, "XAG") >= 0) return 0.01;
   if(StringFind(sym, "XAU") >= 0) return 0.1;
   if(StringFind(sym, "BTC") >= 0) return 1.0;
   if(StringFind(sym, "ETH") >= 0) return 0.1;
   if(StringFind(sym, "JPY") >= 0) return 0.01;
   return 0.0001;
}

//+------------------------------------------------------------------+
//| 週配列内検索（末尾から探して高速化）                               |
//+------------------------------------------------------------------+
int FindWeek(const string &arr[], string key)
{
   int n = ArraySize(arr);
   for(int i = n-1; i >= MathMax(0, n-10); i--)
      if(arr[i] == key) return i;
   for(int i = 0; i < n; i++)
      if(arr[i] == key) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| 週キー生成（ISO 8601: 2024-W03）                                  |
//+------------------------------------------------------------------+
string GetWeekKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int dow = dt.day_of_week;
   int shift = (dow == 0) ? -6 : 1 - dow;
   datetime monday = t + shift * 86400;
   MqlDateTime mdt;
   TimeToStruct(monday, mdt);

   datetime jan4 = StringToTime(IntegerToString(mdt.year) + ".01.04 00:00");
   MqlDateTime j4; TimeToStruct(jan4, j4);
   int j4shift = (j4.day_of_week == 0) ? -6 : 1 - j4.day_of_week;
   datetime w1mon = jan4 + j4shift * 86400;

   int wnum = (int)((monday - w1mon) / (7*86400)) + 1;
   int yr   = mdt.year;

   if(wnum <= 0)
   {
      yr--;
      datetime pj4 = StringToTime(IntegerToString(yr)+".01.04 00:00");
      MqlDateTime pj; TimeToStruct(pj4, pj);
      int pshift = (pj.day_of_week==0)?-6:1-pj.day_of_week;
      wnum = (int)((monday - (pj4+pshift*86400))/(7*86400))+1;
   }
   else if(wnum >= 53)
   {
      datetime nj4 = StringToTime(IntegerToString(yr+1)+".01.04 00:00");
      if(monday >= nj4 - 7*86400) { yr++; wnum=1; }
   }
   return StringFormat("%04d-W%02d", yr, wnum);
}

//+------------------------------------------------------------------+
//| 週の月曜00:00を返す                                               |
//+------------------------------------------------------------------+
datetime GetWeekStart(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   int shift = (dt.day_of_week==0)?-6:1-dt.day_of_week;
   datetime monday = t + shift*86400;
   MqlDateTime mdt; TimeToStruct(monday, mdt);
   return StringToTime(StringFormat("%04d.%02d.%02d 00:00", mdt.year, mdt.mon, mdt.day));
}
//+------------------------------------------------------------------+
