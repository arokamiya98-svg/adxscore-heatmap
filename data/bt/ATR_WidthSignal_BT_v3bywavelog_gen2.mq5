//+------------------------------------------------------------------+
//|  ATR_WidthSignal_BT_v3bywavelog_gen2.mq5                         |
//|  BT世代2: H4_ADX周期比較 + DI動態詳細記録 + フィルターラベル付け  |
//|                                                                  |
//|  ベース: ATR_WidthSignal_BT_v3bywavelog.mq5 (世代1, 71列)        |
//|  追加: 13列 DI動態 (vel3, vel8, slope x H1/H4 x +/-)             |
//|        5列 フィルターラベル (TRUE/FALSE)                         |
//|  合計: 89列                                                       |
//|                                                                  |
//|  目的:                                                            |
//|   1. H4_ADX周期(30 vs 46) の発火パターン差を統計検証             |
//|   2. DI動態の詳細記録 (新仮説検証の材料)                          |
//|   3. フィルター候補のラベル付け (除外せず、TRUE/FALSE記録のみ)    |
//|                                                                  |
//|  実行: H4_ADX_Period=30 で1回, =46 でもう1回 BT走らせる想定      |
//|  出力: MT5/MQL5/Files/ATR_WidthSignal_BT_h4adx<Period>.csv       |
//|                                                                  |
//|  原則: 結果フィッティング禁止 - フィルターはラベル付けのみ        |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "2.00"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== BT 設定 ==="
input datetime BT_StartTime    = D'2024.01.01 00:00';
input datetime BT_EndTime      = D'2026.06.02 23:59';
// 出力ファイル名は H4_ADX_Period の値で動的に生成するため、
// 下記の BT_OutputFile は base 互換のため残すのみで実際は使わない
input string   BT_OutputFile_Unused = "ADXSCORE_bt\\ATR_WidthSignal_BT_NEW.csv";

input group "=== H1 パラメータ ==="
input int    H1_ATR_Short      = 16;
input int    H1_ATR_Long       = 32;
input int    H1_ADX_Period     = 32;
input int    H1_MA_Period      = 32;
input int    ATR_Median_Weeks  = 8;

input group "=== H4 パラメータ ==="
input int    H4_ATR_Short      = 8;
input int    H4_ATR_Long       = 46;
input int    H4_ADX_Period     = 46;   // ★★★ 30 と 46 を切り替えて2回BTを走らせる
input int    H4_MA_Period      = 46;

input group "=== D1 パラメータ ==="
input int    D1_ATR_Short      = 22;
input int    D1_ATR_Long       = 42;
input int    D1_ADX_Period     = 22;

input group "=== ATRゾーン ==="
input double ATR_Low_Ratio     = 0.70;
input double ATR_High_Ratio    = 1.40;

input group "=== ATRペア閾値 ==="
input double ATR_Pair_Expand   = 1.05;
input double ATR_Pair_Contract = 0.95;

input group "=== ATRパターン ==="
input int    ATR_Vel_Bars      = 3;
input double ATR_Expand_Thresh = 10.0;
input double ATR_Flat_Thresh   = 3.0;

input group "=== PatA: 大値幅 ==="
input double PatA_Vel3_Min     = 8.0;
input double PatA_Vel3_Max     = 15.0;

input group "=== PatB: 押し目 ==="
input double PatB_Vel3_Min     = 5.0;

input group "=== PatD: H4ATR節目 ==="
input int    PatD_CrossBars_Max = 3;
input double PatD_H1_ADX_Min    = 18.0;
input double PatD_DI_Strength_Min = 5.0;

input group "=== PatE: ボトムアウト ==="
input double PatE_Pair_Min     = 0.85;
input double PatE_Pair_Max     = 0.95;
input double PatE_MA_Dist_Max  = 0.5;
input int    PatE_LookBack     = 3;

input group "=== NGフィルター（継承）==="
input double NG_H1_ADX_Max     = 40.0;
input double NG_ATR_Ratio_Max  = 2.00;

input group "=== SL/TP ==="
input int    ATR_Avg_Period    = 32;
input double SL_ATR_Mult       = 2.0;
input double RR_Ratio          = 1.6;
input double Lot               = 0.01;

//+-----[ ハンドル ]------------------------------------------------+
int hATR_S_H1=INVALID_HANDLE, hATR_L_H1=INVALID_HANDLE;
int hADX_H1=INVALID_HANDLE,   hMA_H1=INVALID_HANDLE;
int hATR_S_H4=INVALID_HANDLE, hATR_L_H4=INVALID_HANDLE;
int hADX_H4=INVALID_HANDLE,   hMA_H4=INVALID_HANDLE;
int hATR_S_D1=INVALID_HANDLE, hATR_L_D1=INVALID_HANDLE;
int hADX_D1=INVALID_HANDLE;

//+-----[ グローバル ]----------------------------------------------+
int FileHandle = INVALID_HANDLE;
int TradeNo    = 0;
string OutputFile = "";  // OnStart 内で StringFormat 生成

//+-----[ 環境構造体 ]---------------------------------------------+
struct EnvSnapshot {
   datetime open_time;
   double   entry_price;

   // H1
   double atr_s_h1, atr_l_h1, atr_med_h1;
   double atr_ratio_median_h1, atr_pair_h1;
   string atr_zone_h1, pair_phase_h1, atr_pattern_h1;
   double vel3, atr_accel;
   double adx_h1, di_plus_h1, di_minus_h1, di_spread_h1;
   string di_dir_h1;
   double ma_h1, ma_dist_h1;
   string ma_pos_h1;
   bool   had_contract_slow_h1;

   // H4
   double atr_s_h4, atr_l_h4, atr_med_h4;
   double atr_ratio_median_h4, atr_pair_h4;
   string atr_zone_h4, pair_phase_h4, atr_pattern_h4;
   double vel3_h4, atr_accel_h4;
   double adx_h4, di_plus_h4, di_minus_h4, di_spread_h4;
   string di_dir_h4;
   int    cross_bars_h4, cross_bars_h1conv, cross_dir_h4_int;
   string cross_dir_h4;
   double ma_h4, ma_dist_h4;
   string ma_pos_h4;

   // D1
   double atr_s_d1, atr_l_d1;
   double atr_pair_d1;
   string pair_phase_d1, atr_pattern_d1;
   double adx_d1, di_plus_d1, di_minus_d1, di_spread_d1;
   string di_dir_d1;
   int    d1_cross_dir_int;
   string d1_atr_cross_dir;

   // 時間
   int weekday, hour;

   // SL基準
   double atr_avg32;

   // ★★★ 世代2追加: DI動態 13列 ★★★
   // H1 DI+
   double h1_di_plus_vel3;
   double h1_di_plus_vel8;
   double h1_di_plus_slope;
   // H1 DI-
   double h1_di_minus_vel3;
   double h1_di_minus_vel8;
   double h1_di_minus_slope;
   // H4 DI+
   double h4_di_plus_vel3;
   double h4_di_plus_vel8;
   double h4_di_plus_slope;
   // H4 DI-
   double h4_di_minus_vel3;
   double h4_di_minus_vel8;
   double h4_di_minus_slope;
};

struct TradeResult {
   string   pattern;
   string   direction;
   double   sl, tp;
   double   sl_pips, tp_pips;
   datetime close_time;
   double   close_price;
   string   result;
   double   profit_usd, profit_pips;
   double   mfe, mae;
   int      duration_bars;
};

//+==================================================================+
//|  OnStart                                                         |
//+==================================================================+
void OnStart()
{
   Print("==== ATR_WidthSignal_BT_v3bywavelog_gen2 Start ====");
   PrintFormat("Symbol: %s, Period(chart): %s", _Symbol, EnumToString(_Period));
   PrintFormat("H4_ADX_Period: %d  (★比較対象: 30 vs 46)", H4_ADX_Period);
   PrintFormat("BT Range: %s 〜 %s",
      TimeToString(BT_StartTime, TIME_DATE|TIME_MINUTES),
      TimeToString(BT_EndTime,   TIME_DATE|TIME_MINUTES));

   if(!InitHandles()) return;

   // ★ 出力ファイル名を H4_ADX_Period 動的生成
   OutputFile = StringFormat("ATR_WidthSignal_BT_h4adx%d.csv", H4_ADX_Period);
   PrintFormat("Output filename: %s", OutputFile);

   // CSV オープン（UTF-16 LE BOM 付き）
   FileHandle = FileOpen(OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(FileHandle == INVALID_HANDLE) {
      PrintFormat("CSV open failed: err=%d", GetLastError());
      ReleaseHandles();
      return;
   }
   WriteCsvHeader();

   // === H1 OHLC & 環境配列を一括取得 ===
   int h1_size = (int)Bars(_Symbol, PERIOD_H1);
   int h4_size = (int)Bars(_Symbol, PERIOD_H4);
   int d1_size = (int)Bars(_Symbol, PERIOD_D1);
   PrintFormat("Bars: H1=%d, H4=%d, D1=%d", h1_size, h4_size, d1_size);

   datetime times[];
   double close_h1[], high_h1[], low_h1[];
   double atr_s_h1[], atr_l_h1[], adx_h1[], dip_h1[], din_h1[], ma_h1[];
   double atr_s_h4[], atr_l_h4[], adx_h4[], dip_h4[], din_h4[], ma_h4[];
   double atr_s_d1[], atr_l_d1[], adx_d1[], dip_d1[], din_d1[];
   datetime time_h4[], time_d1[];

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(close_h1, true);
   ArraySetAsSeries(high_h1, true);
   ArraySetAsSeries(low_h1, true);
   ArraySetAsSeries(atr_s_h1, true); ArraySetAsSeries(atr_l_h1, true);
   ArraySetAsSeries(adx_h1, true);   ArraySetAsSeries(dip_h1, true);
   ArraySetAsSeries(din_h1, true);   ArraySetAsSeries(ma_h1, true);
   ArraySetAsSeries(atr_s_h4, true); ArraySetAsSeries(atr_l_h4, true);
   ArraySetAsSeries(adx_h4, true);   ArraySetAsSeries(dip_h4, true);
   ArraySetAsSeries(din_h4, true);   ArraySetAsSeries(ma_h4, true);
   ArraySetAsSeries(atr_s_d1, true); ArraySetAsSeries(atr_l_d1, true);
   ArraySetAsSeries(adx_d1, true);   ArraySetAsSeries(dip_d1, true);
   ArraySetAsSeries(din_d1, true);
   ArraySetAsSeries(time_h4, true);
   ArraySetAsSeries(time_d1, true);

   if(CopyTime(_Symbol, PERIOD_H1, 0, h1_size, times) <= 0 ||
      CopyClose(_Symbol, PERIOD_H1, 0, h1_size, close_h1) <= 0 ||
      CopyHigh(_Symbol, PERIOD_H1, 0, h1_size, high_h1) <= 0 ||
      CopyLow(_Symbol, PERIOD_H1, 0, h1_size, low_h1) <= 0 ||
      CopyBuffer(hATR_S_H1, 0, 0, h1_size, atr_s_h1) <= 0 ||
      CopyBuffer(hATR_L_H1, 0, 0, h1_size, atr_l_h1) <= 0 ||
      CopyBuffer(hADX_H1,   0, 0, h1_size, adx_h1)   <= 0 ||
      CopyBuffer(hADX_H1,   1, 0, h1_size, dip_h1)   <= 0 ||
      CopyBuffer(hADX_H1,   2, 0, h1_size, din_h1)   <= 0 ||
      CopyBuffer(hMA_H1,    0, 0, h1_size, ma_h1)    <= 0)
   { Print("H1 copy failed"); FileClose(FileHandle); ReleaseHandles(); return; }

   if(CopyTime(_Symbol, PERIOD_H4, 0, h4_size, time_h4) <= 0 ||
      CopyBuffer(hATR_S_H4, 0, 0, h4_size, atr_s_h4) <= 0 ||
      CopyBuffer(hATR_L_H4, 0, 0, h4_size, atr_l_h4) <= 0 ||
      CopyBuffer(hADX_H4,   0, 0, h4_size, adx_h4)   <= 0 ||
      CopyBuffer(hADX_H4,   1, 0, h4_size, dip_h4)   <= 0 ||
      CopyBuffer(hADX_H4,   2, 0, h4_size, din_h4)   <= 0 ||
      CopyBuffer(hMA_H4,    0, 0, h4_size, ma_h4)    <= 0)
   { Print("H4 copy failed"); FileClose(FileHandle); ReleaseHandles(); return; }

   if(CopyTime(_Symbol, PERIOD_D1, 0, d1_size, time_d1) <= 0 ||
      CopyBuffer(hATR_S_D1, 0, 0, d1_size, atr_s_d1) <= 0 ||
      CopyBuffer(hATR_L_D1, 0, 0, d1_size, atr_l_d1) <= 0 ||
      CopyBuffer(hADX_D1,   0, 0, d1_size, adx_d1)   <= 0 ||
      CopyBuffer(hADX_D1,   1, 0, d1_size, dip_d1)   <= 0 ||
      CopyBuffer(hADX_D1,   2, 0, d1_size, din_d1)   <= 0)
   { Print("D1 copy failed"); FileClose(FileHandle); ReleaseHandles(); return; }

   int median_bars   = ATR_Median_Weeks * 5 * 24;
   int h4_median_bars= ATR_Median_Weeks * 5 * 6;
   int min_history   = median_bars + ATR_Vel_Bars * 2 + 50;

   int scanned = 0, fired = 0, skipped_ng = 0;

   // i = h1_size-1 (古い) → i = 1 (最新-1)
   for(int i = h1_size - 1; i >= 1; i--) {
      if(i + min_history >= h1_size) continue;
      if(times[i] < BT_StartTime) continue;
      if(times[i] > BT_EndTime)   continue;

      scanned++;

      EnvSnapshot env;
      if(!BuildEnv(i, times, close_h1,
                   atr_s_h1, atr_l_h1, adx_h1, dip_h1, din_h1, ma_h1,
                   atr_s_h4, atr_l_h4, adx_h4, dip_h4, din_h4, ma_h4, time_h4,
                   atr_s_d1, atr_l_d1, adx_d1, dip_d1, din_d1, time_d1,
                   median_bars, h4_median_bars, h4_size, d1_size, env))
         continue;

      // NGフィルター（シグナル本体継承）
      if(env.adx_h1 > NG_H1_ADX_Max) { skipped_ng++; continue; }
      if(env.atr_ratio_median_h1 > NG_ATR_Ratio_Max) { skipped_ng++; continue; }

      // パターン発火判定
      bool fires_arr[10];
      DetectFires(env, fires_arr);

      string patterns[10] = {"PatA","PatA","PatB","PatB","PatC","PatC","PatD","PatD","PatE","PatE"};
      string dirs[10]     = {"BUY","SELL","BUY","SELL","BUY","SELL","BUY","SELL","BUY","SELL"};

      for(int p = 0; p < 10; p++) {
         if(!fires_arr[p]) continue;
         TradeResult res;
         res.pattern   = patterns[p];
         res.direction = dirs[p];
         if(!TraceTrade(i, env, res, high_h1, low_h1, close_h1, times, h1_size))
            continue;
         TradeNo++;
         WriteCsvRow(env, res);
         fired++;
      }
   }

   FileClose(FileHandle);
   Print("==== BT Complete ====");
   PrintFormat("Scanned: %d, Skipped(NG): %d, Trades: %d", scanned, skipped_ng, fired);
   PrintFormat("Output: %s/MQL5/Files/%s", TerminalInfoString(TERMINAL_DATA_PATH), OutputFile);

   ReleaseHandles();
}

//+==================================================================+
//|  ハンドル初期化・解放                                           |
//+==================================================================+
bool InitHandles()
{
   hATR_S_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Short);
   hATR_L_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Long);
   hADX_H1   = iADX(_Symbol, PERIOD_H1, H1_ADX_Period);
   hMA_H1    = iMA (_Symbol, PERIOD_H1, H1_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR_S_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Long);
   hADX_H4   = iADX(_Symbol, PERIOD_H4, H4_ADX_Period);
   hMA_H4    = iMA (_Symbol, PERIOD_H4, H4_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR_S_D1 = iATR(_Symbol, PERIOD_D1, D1_ATR_Short);
   hATR_L_D1 = iATR(_Symbol, PERIOD_D1, D1_ATR_Long);
   hADX_D1   = iADX(_Symbol, PERIOD_D1, D1_ADX_Period);

   if(hATR_S_H1==INVALID_HANDLE || hATR_L_H1==INVALID_HANDLE ||
      hADX_H1==INVALID_HANDLE   || hMA_H1==INVALID_HANDLE   ||
      hATR_S_H4==INVALID_HANDLE || hATR_L_H4==INVALID_HANDLE ||
      hADX_H4==INVALID_HANDLE   || hMA_H4==INVALID_HANDLE   ||
      hATR_S_D1==INVALID_HANDLE || hATR_L_D1==INVALID_HANDLE ||
      hADX_D1==INVALID_HANDLE)
   {
      Print("Handle init failed");
      return false;
   }
   // インジ計算待ち
   Sleep(2000);
   return true;
}

void ReleaseHandles()
{
   IndicatorRelease(hATR_S_H1); IndicatorRelease(hATR_L_H1);
   IndicatorRelease(hADX_H1);   IndicatorRelease(hMA_H1);
   IndicatorRelease(hATR_S_H4); IndicatorRelease(hATR_L_H4);
   IndicatorRelease(hADX_H4);   IndicatorRelease(hMA_H4);
   IndicatorRelease(hATR_S_D1); IndicatorRelease(hATR_L_D1);
   IndicatorRelease(hADX_D1);
}

//+==================================================================+
//|  ユーティリティ                                                 |
//+==================================================================+
double CalcMedian(const double &arr[], int idx, int bars)
{
   int sz = ArraySize(arr);
   if(idx + bars >= sz) return 0;
   double tmp[];
   ArrayResize(tmp, bars);
   int cnt = 0;
   for(int k = idx; k < idx + bars; k++)
      if(arr[k] > 0) tmp[cnt++] = arr[k];
   if(cnt < 10) return 0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
}

int FindCrossBack(const double &s[], const double &l[], int idx, int max_look, int &dir_out)
{
   dir_out = 0;
   int sz = MathMin(ArraySize(s), ArraySize(l));
   for(int k = 0; k <= max_look; k++) {
      int i_now  = idx + k;
      int i_prev = idx + k + 1;
      if(i_prev >= sz) break;
      if(s[i_now]<=0 || l[i_now]<=0 || s[i_prev]<=0 || l[i_prev]<=0) continue;
      bool now_above  = (s[i_now]  > l[i_now]);
      bool prev_above = (s[i_prev] > l[i_prev]);
      if(now_above != prev_above) {
         dir_out = now_above ? 1 : -1;
         return k;
      }
   }
   return -1;
}

string AtrPattern(double v3, double accel)
{
   if(MathAbs(v3) < ATR_Flat_Thresh) return "FLAT";
   if(v3 > ATR_Expand_Thresh && accel > 0) return "EXPANDING";
   if(v3 > 0 && accel > 0)  return "RISING_ACCEL";
   if(v3 > 0 && accel <= 0) return "RISING_DECEL";
   if(v3 < 0 && accel < 0)  return "CONTRACTING";
   if(v3 < 0 && accel >= 0) return "CONTRACTING_SLOW";
   return "FLAT";
}

int FindBarIndexAtOrBefore(const datetime &arr[], datetime t, int size)
{
   for(int k = 0; k < size; k++) {
      if(arr[k] <= t) return k;
   }
   return -1;
}

string MaPosLabel(double dist)
{
   if(dist < -1.5) return "BELOW_FAR";
   if(dist < -0.5) return "BELOW_NEAR";
   if(dist >  1.5) return "ABOVE_FAR";
   if(dist >  0.5) return "ABOVE_NEAR";
   return "NEAR";
}

string ZoneLabel(double ratio)
{
   if(ratio <= 0) return "NA";
   if(ratio < ATR_Low_Ratio)  return "LOW";
   if(ratio > ATR_High_Ratio) return "HIGH";
   return "NORMAL";
}

string PairPhaseLabel(double pair)
{
   if(pair > ATR_Pair_Expand)   return "EXPAND";
   if(pair < ATR_Pair_Contract) return "CONTRACT";
   return "NEUTRAL";
}

//+==================================================================+
//|  ★世代2追加: DI動態計算ユーティリティ                          |
//|                                                                  |
//|  series=true 前提:                                                |
//|    idx     = 最新                                                 |
//|    idx+n   = n本前                                                |
//+==================================================================+
double VelN(const double &arr[], int idx, int n)
{
   if(idx + n >= ArraySize(arr)) return 0;
   double prev = arr[idx + n];
   if(prev <= 0) return 0;
   return (arr[idx] - prev) / prev * 100.0;
}

// 8バー線形回帰の傾き
// 過去→最新で y が増加 → slope 正
// 過去→最新で y が減少 → slope 負
double Slope8(const double &arr[], int idx)
{
   int n = 8;
   if(idx + n >= ArraySize(arr)) return 0;
   double sx=0, sy=0, sxy=0, sxx=0;
   for(int k=0; k<n; k++) {
      double x = (double)(n-1-k);   // 時系列順: 過去→最新で x が増える
      double y = arr[idx+k];        // series=true: idx+k は k本前
      sx += x; sy += y; sxy += x*y; sxx += x*x;
   }
   double denom = n*sxx - sx*sx;
   if(denom == 0) return 0;
   return (n*sxy - sx*sy) / denom;
}

//+==================================================================+
//|  環境構築                                                       |
//+==================================================================+
bool BuildEnv(int i, const datetime &times[], const double &close_h1[],
              const double &atr_s_h1[], const double &atr_l_h1[],
              const double &adx_h1[],   const double &dip_h1[],
              const double &din_h1[],   const double &ma_h1[],
              const double &atr_s_h4[], const double &atr_l_h4[],
              const double &adx_h4[],   const double &dip_h4[],
              const double &din_h4[],   const double &ma_h4[],
              const datetime &time_h4[],
              const double &atr_s_d1[], const double &atr_l_d1[],
              const double &adx_d1[],   const double &dip_d1[],
              const double &din_d1[],   const datetime &time_d1[],
              int median_bars, int h4_median_bars, int h4_size, int d1_size,
              EnvSnapshot &env)
{
   if(atr_s_h1[i]<=0 || atr_l_h1[i]<=0 || adx_h1[i]<=0 || ma_h1[i]<=0) return false;

   env.open_time   = times[i];
   env.entry_price = close_h1[i];

   // === H1 ===
   env.atr_s_h1 = atr_s_h1[i];
   env.atr_l_h1 = atr_l_h1[i];

   env.atr_med_h1 = CalcMedian(atr_s_h1, i, median_bars);
   if(env.atr_med_h1 <= 0) return false;
   env.atr_ratio_median_h1 = env.atr_s_h1 / env.atr_med_h1;
   env.atr_pair_h1         = env.atr_s_h1 / env.atr_l_h1;

   env.atr_zone_h1   = ZoneLabel(env.atr_ratio_median_h1);
   env.pair_phase_h1 = PairPhaseLabel(env.atr_pair_h1);

   int vb = ATR_Vel_Bars;
   if(i + vb*2 >= ArraySize(atr_s_h1)) return false;

   double v3 = 0, va = 0;
   if(atr_s_h1[i+vb] > 0)
      v3 = (env.atr_s_h1 - atr_s_h1[i+vb]) / atr_s_h1[i+vb] * 100.0;
   double v3_prev = 0;
   if(atr_s_h1[i+vb*2] > 0)
      v3_prev = (atr_s_h1[i+vb] - atr_s_h1[i+vb*2]) / atr_s_h1[i+vb*2] * 100.0;
   va = v3 - v3_prev;
   env.vel3        = v3;
   env.atr_accel   = va;
   env.atr_pattern_h1 = AtrPattern(v3, va);

   // PatE LookBack: 直前N本のCONTRACTING_SLOW判定
   env.had_contract_slow_h1 = false;
   for(int b = 1; b <= PatE_LookBack; b++) {
      if(i+b+vb*2 >= ArraySize(atr_s_h1)) break;
      double va_b = atr_s_h1[i+b];
      double va_s = atr_s_h1[i+b+vb];
      if(va_s <= 0) continue;
      double v_b = (va_b - va_s) / va_s * 100.0;
      double va_s2 = atr_s_h1[i+b+vb*2];
      double v_b_prev = (va_s2 > 0) ? (va_s - va_s2) / va_s2 * 100.0 : 0;
      double a_b = v_b - v_b_prev;
      if(AtrPattern(v_b, a_b) == "CONTRACTING_SLOW") { env.had_contract_slow_h1 = true; break; }
   }

   env.adx_h1       = adx_h1[i];
   env.di_plus_h1   = dip_h1[i];
   env.di_minus_h1  = din_h1[i];
   env.di_spread_h1 = env.di_plus_h1 - env.di_minus_h1;
   env.di_dir_h1    = (env.di_plus_h1 > env.di_minus_h1) ? "UP" : "DN";

   env.ma_h1      = ma_h1[i];
   env.ma_dist_h1 = (env.entry_price - env.ma_h1) / env.atr_l_h1;
   env.ma_pos_h1  = MaPosLabel(env.ma_dist_h1);

   // ATR_Avg32（SL基準）
   double sum = 0; int cnt = 0;
   for(int k = 0; k < ATR_Avg_Period; k++) {
      if(i + k >= ArraySize(atr_s_h1)) break;
      if(atr_s_h1[i+k] > 0) { sum += atr_s_h1[i+k]; cnt++; }
   }
   env.atr_avg32 = (cnt > 0) ? sum / cnt : env.atr_s_h1;

   // === ★世代2追加: H1 DI動態 ===
   env.h1_di_plus_vel3   = VelN(dip_h1, i, 3);
   env.h1_di_plus_vel8   = VelN(dip_h1, i, 8);
   env.h1_di_plus_slope  = Slope8(dip_h1, i);
   env.h1_di_minus_vel3  = VelN(din_h1, i, 3);
   env.h1_di_minus_vel8  = VelN(din_h1, i, 8);
   env.h1_di_minus_slope = Slope8(din_h1, i);

   // === H4 ===
   int hi = FindBarIndexAtOrBefore(time_h4, env.open_time, h4_size);
   if(hi < 0) return false;
   if(atr_s_h4[hi]<=0 || atr_l_h4[hi]<=0 || adx_h4[hi]<=0 || ma_h4[hi]<=0) return false;

   env.atr_s_h4 = atr_s_h4[hi];
   env.atr_l_h4 = atr_l_h4[hi];

   env.atr_med_h4 = CalcMedian(atr_s_h4, hi, h4_median_bars);
   env.atr_ratio_median_h4 = (env.atr_med_h4 > 0) ? env.atr_s_h4 / env.atr_med_h4 : 0;
   env.atr_pair_h4         = env.atr_s_h4 / env.atr_l_h4;

   env.atr_zone_h4   = ZoneLabel(env.atr_ratio_median_h4);
   env.pair_phase_h4 = PairPhaseLabel(env.atr_pair_h4);

   if(hi + vb*2 < h4_size && atr_s_h4[hi+vb] > 0 && atr_s_h4[hi+vb*2] > 0) {
      double v3_h4 = (env.atr_s_h4 - atr_s_h4[hi+vb]) / atr_s_h4[hi+vb] * 100.0;
      double v3_h4_prev = (atr_s_h4[hi+vb] - atr_s_h4[hi+vb*2]) / atr_s_h4[hi+vb*2] * 100.0;
      env.vel3_h4       = v3_h4;
      env.atr_accel_h4  = v3_h4 - v3_h4_prev;
      env.atr_pattern_h4 = AtrPattern(v3_h4, env.atr_accel_h4);
   } else {
      env.vel3_h4 = 0; env.atr_accel_h4 = 0; env.atr_pattern_h4 = "FLAT";
   }

   env.adx_h4       = adx_h4[hi];
   env.di_plus_h4   = dip_h4[hi];
   env.di_minus_h4  = din_h4[hi];
   env.di_spread_h4 = env.di_plus_h4 - env.di_minus_h4;
   env.di_dir_h4    = (env.di_plus_h4 > env.di_minus_h4) ? "UP" : "DN";

   env.ma_h4      = ma_h4[hi];
   env.ma_dist_h4 = (env.entry_price - env.ma_h4) / env.atr_l_h4;
   env.ma_pos_h4  = MaPosLabel(env.ma_dist_h4);

   int cd = 0;
   int cb = FindCrossBack(atr_s_h4, atr_l_h4, hi, 20, cd);
   env.cross_bars_h4    = cb;
   env.cross_dir_h4_int = cd;
   env.cross_dir_h4     = (cd > 0) ? "UP" : (cd < 0) ? "DOWN" : "NONE";
   if(cb >= 0 && hi + cb < h4_size) {
      datetime cross_t = time_h4[hi + cb];
      long diff_sec = (long)(env.open_time - cross_t);
      env.cross_bars_h1conv = (int)(diff_sec / 3600);
   } else {
      env.cross_bars_h1conv = -1;
   }

   // === ★世代2追加: H4 DI動態 ===
   env.h4_di_plus_vel3   = VelN(dip_h4, hi, 3);
   env.h4_di_plus_vel8   = VelN(dip_h4, hi, 8);
   env.h4_di_plus_slope  = Slope8(dip_h4, hi);
   env.h4_di_minus_vel3  = VelN(din_h4, hi, 3);
   env.h4_di_minus_vel8  = VelN(din_h4, hi, 8);
   env.h4_di_minus_slope = Slope8(din_h4, hi);

   // === D1 ===
   int di = FindBarIndexAtOrBefore(time_d1, env.open_time, d1_size);
   if(di < 0) return false;
   if(atr_s_d1[di]<=0 || atr_l_d1[di]<=0 || adx_d1[di]<=0) return false;

   env.atr_s_d1    = atr_s_d1[di];
   env.atr_l_d1    = atr_l_d1[di];
   env.atr_pair_d1 = env.atr_s_d1 / env.atr_l_d1;
   env.pair_phase_d1 = PairPhaseLabel(env.atr_pair_d1);

   if(di + vb*2 < d1_size && atr_s_d1[di+vb] > 0 && atr_s_d1[di+vb*2] > 0) {
      double v3_d1 = (env.atr_s_d1 - atr_s_d1[di+vb]) / atr_s_d1[di+vb] * 100.0;
      double v3_d1_prev = (atr_s_d1[di+vb] - atr_s_d1[di+vb*2]) / atr_s_d1[di+vb*2] * 100.0;
      env.atr_pattern_d1 = AtrPattern(v3_d1, v3_d1 - v3_d1_prev);
   } else {
      env.atr_pattern_d1 = "FLAT";
   }

   env.adx_d1       = adx_d1[di];
   env.di_plus_d1   = dip_d1[di];
   env.di_minus_d1  = din_d1[di];
   env.di_spread_d1 = env.di_plus_d1 - env.di_minus_d1;
   env.di_dir_d1    = (env.di_plus_d1 > env.di_minus_d1) ? "UP" : "DN";

   int dcd = 0;
   int dcb = FindCrossBack(atr_s_d1, atr_l_d1, di, 30, dcd);
   env.d1_cross_dir_int = dcd;
   env.d1_atr_cross_dir = (dcd > 0) ? "BU" : (dcd < 0) ? "PD" : "NONE";

   // 時間
   MqlDateTime mdt;
   TimeToStruct(env.open_time, mdt);
   env.weekday = mdt.day_of_week;
   env.hour    = mdt.hour;

   return true;
}

//+==================================================================+
//|  発火判定                                                       |
//+==================================================================+
void DetectFires(const EnvSnapshot &env, bool &fires[])
{
   for(int p = 0; p < 10; p++) fires[p] = false;

   bool h1_up = (env.di_dir_h1 == "UP");
   bool h4_up = (env.di_dir_h4 == "UP");
   string z   = env.atr_zone_h1;
   string adz = (env.adx_h1 < 20) ? "LOW" : (env.adx_h1 < 30) ? "MID" : "HIGH";
   string adz4= (env.adx_h4 < 20) ? "LOW" : (env.adx_h4 < 30) ? "MID" : "HIGH";
   double h4_di_strength = MathAbs(env.di_spread_h4);

   //--- PatA
   bool patA_base = (z == "NORMAL" && env.atr_pattern_h1 == "RISING_DECEL" &&
                     env.vel3 >= PatA_Vel3_Min && env.vel3 <= PatA_Vel3_Max);
   if(patA_base && h4_up && h1_up)    fires[0] = true;
   if(patA_base && !h4_up && !h1_up)  fires[1] = true;

   //--- PatB
   bool patB_base = (z == "NORMAL" && env.atr_pattern_h1 == "RISING_DECEL" &&
                     env.vel3 >= PatB_Vel3_Min);
   if(patB_base && h4_up && !h1_up)   fires[2] = true;
   if(patB_base && !h4_up && h1_up)   fires[3] = true;

   //--- PatC
   bool patC_base = (z == "NORMAL" && env.atr_pattern_h1 == "EXPANDING" &&
                     env.atr_ratio_median_h1 > 1.0 &&
                     adz4 == "LOW" && (adz == "MID" || adz == "HIGH"));
   if(patC_base && h4_up && h1_up)    fires[4] = true;
   if(patC_base && !h4_up && !h1_up)  fires[5] = true;

   //--- PatD
   bool h4_cross_recent = (env.cross_bars_h4 >= 0 && env.cross_bars_h4 <= PatD_CrossBars_Max);
   bool patD_pat_ok = (env.atr_pattern_h1 == "RISING_ACCEL" ||
                       env.atr_pattern_h1 == "RISING_DECEL" ||
                       env.atr_pattern_h1 == "EXPANDING");
   bool patD_base = (h4_cross_recent && (z == "LOW" || z == "NORMAL") &&
                     patD_pat_ok && env.adx_h1 > PatD_H1_ADX_Min &&
                     h4_di_strength >= PatD_DI_Strength_Min);
   if(patD_base && env.cross_dir_h4_int > 0 && h4_up)   fires[6] = true;
   if(patD_base && env.cross_dir_h4_int < 0 && !h4_up)  fires[7] = true;

   //--- PatE
   bool h1_pair_bottom = (env.atr_pair_h1 >= PatE_Pair_Min && env.atr_pair_h1 <= PatE_Pair_Max);
   bool h1_pat_turn    = (env.atr_pattern_h1 == "RISING_ACCEL" || env.atr_pattern_h1 == "EXPANDING");
   bool ma_close       = (MathAbs(env.ma_dist_h1) < PatE_MA_Dist_Max);
   bool patE_base = (h1_pair_bottom && env.had_contract_slow_h1 && h1_pat_turn && ma_close &&
                     (adz == "LOW" || adz == "MID") &&
                     h4_di_strength >= PatD_DI_Strength_Min);
   if(patE_base && env.di_spread_h4 > 0) fires[8] = true;
   if(patE_base && env.di_spread_h4 < 0) fires[9] = true;
}

//+==================================================================+
//|  仮想エントリー追跡                                             |
//+==================================================================+
bool TraceTrade(int entry_idx, const EnvSnapshot &env, TradeResult &res,
                const double &high_h1[], const double &low_h1[],
                const double &close_h1[], const datetime &times[], int h1_size)
{
   double sl_dist = env.atr_avg32 * SL_ATR_Mult;
   double tp_dist = sl_dist * RR_Ratio;
   if(sl_dist <= 0) return false;

   bool is_buy = (res.direction == "BUY");
   res.sl = is_buy ? env.entry_price - sl_dist : env.entry_price + sl_dist;
   res.tp = is_buy ? env.entry_price + tp_dist : env.entry_price - tp_dist;
   res.sl_pips = sl_dist * 100.0;
   res.tp_pips = tp_dist * 100.0;

   res.result = "";
   res.mfe = 0;
   res.mae = 0;

   // i は ArraySetAsSeries(true) で大きい=古い、小さい=未来
   // 追跡は entry_idx → entry_idx-1 → ... → 1 と進む（未来方向）
   for(int j = entry_idx - 1; j >= 1; j--) {
      if(j >= h1_size) continue;
      double hi = high_h1[j];
      double lo = low_h1[j];

      // MFE/MAE 更新
      double mfe_pips, mae_pips;
      if(is_buy) {
         mfe_pips = (hi - env.entry_price) * 100.0;
         mae_pips = (env.entry_price - lo) * 100.0;
      } else {
         mfe_pips = (env.entry_price - lo) * 100.0;
         mae_pips = (hi - env.entry_price) * 100.0;
      }
      if(mfe_pips > res.mfe) res.mfe = mfe_pips;
      if(mae_pips > res.mae) res.mae = mae_pips;

      bool sl_hit, tp_hit;
      if(is_buy) {
         sl_hit = (lo <= res.sl);
         tp_hit = (hi >= res.tp);
      } else {
         sl_hit = (hi >= res.sl);
         tp_hit = (lo <= res.tp);
      }

      if(sl_hit && tp_hit) { // 同一バー両方該当 → SL優先（保守）
         res.result = "LOSS";
         res.close_time   = times[j];
         res.close_price  = res.sl;
         res.duration_bars= entry_idx - j;
         break;
      }
      if(sl_hit) {
         res.result = "LOSS";
         res.close_time   = times[j];
         res.close_price  = res.sl;
         res.duration_bars= entry_idx - j;
         break;
      }
      if(tp_hit) {
         res.result = "WIN";
         res.close_time   = times[j];
         res.close_price  = res.tp;
         res.duration_bars= entry_idx - j;
         break;
      }
   }

   // 未決済（BT終端まで未到達）→ 記録しない
   if(res.result == "") return false;

   // Profit
   double diff = is_buy ? (res.close_price - env.entry_price) : (env.entry_price - res.close_price);
   res.profit_pips = diff * 100.0;
   // USD: Lot=0.01 のXAUUSD → 1pip = 0.01 USD/pip per 0.01lot 概算（環境差あり、参考値）
   res.profit_usd  = res.profit_pips * Lot * 1.0;

   return true;
}

//+==================================================================+
//|  ★世代2追加: フィルター判定関数                                  |
//|                                                                  |
//|  全フィルター: 該当=TRUE, 非該当=FALSE (文字列で書く)            |
//|                                                                  |
//|  MID-L / MID-H:                                                  |
//|    H1_ATR_Ratio_Median <= 1.0 → MID-L                            |
//|    H1_ATR_Ratio_Median >  1.0 → MID-H                            |
//|    (NORMAL帯 0.70-1.40 内での内分。Zone判定とは独立)             |
//+==================================================================+
string FlagCrossNoneSell(const EnvSnapshot &env, const string &direction)
{
   return (env.d1_atr_cross_dir == "NONE" && direction == "SELL") ? "TRUE" : "FALSE";
}

string FlagPatDSell(const string &pattern, const string &direction)
{
   return (pattern == "PatD" && direction == "SELL") ? "TRUE" : "FALSE";
}

string FlagPatCMidH(const EnvSnapshot &env, const string &pattern)
{
   bool cond = (pattern == "PatC" && env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0);
   return cond ? "TRUE" : "FALSE";
}

string FlagUpNoneMidH(const EnvSnapshot &env)
{
   bool cond = (env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "NONE" &&
                env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0);
   return cond ? "TRUE" : "FALSE";
}

string FlagDiSpreadTight(const EnvSnapshot &env)
{
   return (MathAbs(env.di_spread_h4) < 1.0) ? "TRUE" : "FALSE";
}

//+==================================================================+
//|  CSV 書き込み                                                   |
//|                                                                  |
//|  ヘッダー: 71列 (世代1継承) + 13列 (DI動態) + 5列 (フィルタ)     |
//|         = 合計 89列                                              |
//+==================================================================+
void WriteCsvHeader()
{
   string line =
      // === 既存71列 (世代1継承 - 順序変更禁止) ===
      "TradeNo,OpenTime,CloseTime,Pattern,Direction,"
      "EntryPrice,SL,TP,SL_Pips,TP_Pips,Lot,ATR_Avg32,"
      "H1_ATR_Short,H1_ATR_Long,H1_ATR_Median,"
      "H1_ATR_Ratio_Median,H1_ATR_Pair,"
      "H1_ATR_Zone,H1_Pair_Phase,H1_ATR_Pattern,"
      "H1_Vel3,H1_ATR_Accel,"
      "H1_ADX,H1_DI_Plus,H1_DI_Minus,H1_DI_Spread,H1_DI_Dir,"
      "H1_MA,H1_MA_Dist,H1_MA_Pos,"
      "H1_Had_Contract_Slow,"
      "H4_ATR_Short,H4_ATR_Long,H4_ATR_Median,"
      "H4_ATR_Ratio_Median,H4_ATR_Pair,"
      "H4_ATR_Zone,H4_Pair_Phase,H4_ATR_Pattern,"
      "H4_Vel3,H4_ATR_Accel,"
      "H4_ADX,H4_DI_Plus,H4_DI_Minus,H4_DI_Spread,H4_DI_Dir,"
      "H4_Cross_Bars_H4,H4_Cross_Bars_H1conv,H4_Cross_Dir,"
      "H4_MA,H4_MA_Dist,H4_MA_Pos,"
      "D1_ATR_Short,D1_ATR_Long,D1_ATR_Pair,"
      "D1_Pair_Phase,D1_ATR_Pattern,"
      "D1_ADX,D1_DI_Plus,D1_DI_Minus,D1_DI_Spread,D1_DI_Dir,"
      "D1_ATR_Cross_Dir,"
      "Weekday,Hour,"
      "Result,Profit_USD,Profit_Pips,MFE,MAE,DurationBars,"
      // === ★世代2追加: H1 DI動態 6列 ===
      "H1_DI_Plus_Vel3,H1_DI_Plus_Vel8,H1_DI_Plus_Slope,"
      "H1_DI_Minus_Vel3,H1_DI_Minus_Vel8,H1_DI_Minus_Slope,"
      // === ★世代2追加: H4 DI動態 6列 ===
      "H4_DI_Plus_Vel3,H4_DI_Plus_Vel8,H4_DI_Plus_Slope,"
      "H4_DI_Minus_Vel3,H4_DI_Minus_Vel8,H4_DI_Minus_Slope,"
      // === ★世代2追加: フィルターラベル 5列 ===
      "Filter_Cross_None_Sell,Filter_PatD_Sell,Filter_PatC_MidH,"
      "Filter_UpNoneMidH,Filter_DI_Spread_Tight";
   FileWriteString(FileHandle, line + "\r\n");
}

void WriteCsvRow(const EnvSnapshot &env, const TradeResult &res)
{
   string line = "";
   // === 既存71列 (世代1継承 - 順序変更禁止) ===
   line += IntegerToString(TradeNo) + ",";
   line += TimeToString(env.open_time, TIME_DATE|TIME_MINUTES) + ",";
   line += TimeToString(res.close_time, TIME_DATE|TIME_MINUTES) + ",";
   line += res.pattern + ",";
   line += res.direction + ",";
   line += DoubleToString(env.entry_price, 3) + ",";
   line += DoubleToString(res.sl, 3) + ",";
   line += DoubleToString(res.tp, 3) + ",";
   line += DoubleToString(res.sl_pips, 1) + ",";
   line += DoubleToString(res.tp_pips, 1) + ",";
   line += DoubleToString(Lot, 2) + ",";
   line += DoubleToString(env.atr_avg32, 4) + ",";
   // H1
   line += DoubleToString(env.atr_s_h1, 4) + ",";
   line += DoubleToString(env.atr_l_h1, 4) + ",";
   line += DoubleToString(env.atr_med_h1, 4) + ",";
   line += DoubleToString(env.atr_ratio_median_h1, 3) + ",";
   line += DoubleToString(env.atr_pair_h1, 3) + ",";
   line += env.atr_zone_h1 + ",";
   line += env.pair_phase_h1 + ",";
   line += env.atr_pattern_h1 + ",";
   line += DoubleToString(env.vel3, 2) + ",";
   line += DoubleToString(env.atr_accel, 2) + ",";
   line += DoubleToString(env.adx_h1, 2) + ",";
   line += DoubleToString(env.di_plus_h1, 2) + ",";
   line += DoubleToString(env.di_minus_h1, 2) + ",";
   line += DoubleToString(env.di_spread_h1, 2) + ",";
   line += env.di_dir_h1 + ",";
   line += DoubleToString(env.ma_h1, 3) + ",";
   line += DoubleToString(env.ma_dist_h1, 3) + ",";
   line += env.ma_pos_h1 + ",";
   line += (env.had_contract_slow_h1 ? "true" : "false");
   line += ",";
   // H4
   line += DoubleToString(env.atr_s_h4, 4) + ",";
   line += DoubleToString(env.atr_l_h4, 4) + ",";
   line += DoubleToString(env.atr_med_h4, 4) + ",";
   line += DoubleToString(env.atr_ratio_median_h4, 3) + ",";
   line += DoubleToString(env.atr_pair_h4, 3) + ",";
   line += env.atr_zone_h4 + ",";
   line += env.pair_phase_h4 + ",";
   line += env.atr_pattern_h4 + ",";
   line += DoubleToString(env.vel3_h4, 2) + ",";
   line += DoubleToString(env.atr_accel_h4, 2) + ",";
   line += DoubleToString(env.adx_h4, 2) + ",";
   line += DoubleToString(env.di_plus_h4, 2) + ",";
   line += DoubleToString(env.di_minus_h4, 2) + ",";
   line += DoubleToString(env.di_spread_h4, 2) + ",";
   line += env.di_dir_h4 + ",";
   line += IntegerToString(env.cross_bars_h4) + ",";
   line += IntegerToString(env.cross_bars_h1conv) + ",";
   line += env.cross_dir_h4 + ",";
   line += DoubleToString(env.ma_h4, 3) + ",";
   line += DoubleToString(env.ma_dist_h4, 3) + ",";
   line += env.ma_pos_h4 + ",";
   // D1
   line += DoubleToString(env.atr_s_d1, 4) + ",";
   line += DoubleToString(env.atr_l_d1, 4) + ",";
   line += DoubleToString(env.atr_pair_d1, 3) + ",";
   line += env.pair_phase_d1 + ",";
   line += env.atr_pattern_d1 + ",";
   line += DoubleToString(env.adx_d1, 2) + ",";
   line += DoubleToString(env.di_plus_d1, 2) + ",";
   line += DoubleToString(env.di_minus_d1, 2) + ",";
   line += DoubleToString(env.di_spread_d1, 2) + ",";
   line += env.di_dir_d1 + ",";
   line += env.d1_atr_cross_dir + ",";
   // 時間
   line += IntegerToString(env.weekday) + ",";
   line += IntegerToString(env.hour) + ",";
   // 結果
   line += res.result + ",";
   line += DoubleToString(res.profit_usd, 2) + ",";
   line += DoubleToString(res.profit_pips, 1) + ",";
   line += DoubleToString(res.mfe, 1) + ",";
   line += DoubleToString(res.mae, 1) + ",";
   line += IntegerToString(res.duration_bars) + ",";
   // === ★世代2追加: H1 DI動態 6列 ===
   line += DoubleToString(env.h1_di_plus_vel3,   3) + ",";
   line += DoubleToString(env.h1_di_plus_vel8,   3) + ",";
   line += DoubleToString(env.h1_di_plus_slope,  4) + ",";
   line += DoubleToString(env.h1_di_minus_vel3,  3) + ",";
   line += DoubleToString(env.h1_di_minus_vel8,  3) + ",";
   line += DoubleToString(env.h1_di_minus_slope, 4) + ",";
   // === ★世代2追加: H4 DI動態 6列 ===
   line += DoubleToString(env.h4_di_plus_vel3,   3) + ",";
   line += DoubleToString(env.h4_di_plus_vel8,   3) + ",";
   line += DoubleToString(env.h4_di_plus_slope,  4) + ",";
   line += DoubleToString(env.h4_di_minus_vel3,  3) + ",";
   line += DoubleToString(env.h4_di_minus_vel8,  3) + ",";
   line += DoubleToString(env.h4_di_minus_slope, 4) + ",";
   // === ★世代2追加: フィルターラベル 5列 (最後の列はカンマなし) ===
   line += FlagCrossNoneSell(env, res.direction) + ",";
   line += FlagPatDSell(res.pattern, res.direction) + ",";
   line += FlagPatCMidH(env, res.pattern) + ",";
   line += FlagUpNoneMidH(env) + ",";
   line += FlagDiSpreadTight(env);
   FileWriteString(FileHandle, line + "\r\n");
}
//+------------------------------------------------------------------+
