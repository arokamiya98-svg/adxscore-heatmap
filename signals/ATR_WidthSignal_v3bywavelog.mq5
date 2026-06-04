//+------------------------------------------------------------------+
//|  ATR_WidthSignal_v3.mq5                                          |
//|  値幅が出やすいパターンを可視化するインジケーター v3             |
//|                                                                  |
//|  v3思想:                                                          |
//|  - シグナルは「相場状態を検出するセンサー」                       |
//|  - 発火条件は緩め、フェーズ仕分けは別レイヤー（Phase C）         |
//|  - 買い/売り両対応                                                |
//|  - 全パターン同時発火OK（multi-fire）                            |
//|                                                                  |
//|  検出パターン:                                                   |
//|  A: 大値幅期待   (Gold)   RISING_DECEL × vel3 8〜15 × DI整合     |
//|  B: 押し目高勝率 (Aqua)   RISING_DECEL × vel3 ≥5 × H1/H4逆      |
//|  C: 初動         (Lime)   EXPANDING × H4=LOW × H1=MID/HIGH       |
//|  D: H4ATR節目    (Magenta) H4 ATRクロス直後 × DI整合 ★新規      |
//|  E: ボトムアウト (Orange)  H1 ATR接近 × MA接近 × DI整合 ★新規  |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "3.00"
#property indicator_chart_window
#property indicator_buffers 20
#property indicator_plots   10

//--- PatA BUY: 大値幅期待（ダイヤ◆ 上）
#property indicator_label1  "PatA_BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGold
#property indicator_width1  2
//--- PatA SELL: 大値幅期待（ダイヤ◆ 下）
#property indicator_label2  "PatA_SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrGoldenrod
#property indicator_width2  2

//--- PatB BUY: 押し目（三角▲）
#property indicator_label3  "PatB_BUY"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  2
//--- PatB SELL: 戻り売り（逆三角▽）
#property indicator_label4  "PatB_SELL"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDeepSkyBlue
#property indicator_width4  2

//--- PatC BUY: 初動（丸●）
#property indicator_label5  "PatC_BUY"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLimeGreen
#property indicator_width5  2
//--- PatC SELL: 初動下（丸●）
#property indicator_label6  "PatC_SELL"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrSeaGreen
#property indicator_width6  2

//--- PatD BUY: H4節目（マゼンタ★）
#property indicator_label7  "PatD_BUY"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrMagenta
#property indicator_width7  3
//--- PatD SELL: H4節目（マゼンタ★）
#property indicator_label8  "PatD_SELL"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrMediumVioletRed
#property indicator_width8  3

//--- PatE BUY: ボトムアウト（オレンジ☆）
#property indicator_label9  "PatE_BUY"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrOrange
#property indicator_width9  2
//--- PatE SELL: トップアウト（オレンジ☆）
#property indicator_label10 "PatE_SELL"
#property indicator_type10  DRAW_ARROW
#property indicator_color10 clrDarkOrange
#property indicator_width10 2

//+------------------------------------------------------------------+
//| 入力パラメータ                                                   |
//+------------------------------------------------------------------+
// --- H1 タイミングTF ---
input group "=== H1 パラメータ ==="
input int    H1_ATR_Short      = 16;
input int    H1_ATR_Long       = 32;
input int    H1_ADX_Period     = 32;
input int    H1_MA_Period      = 32;
input int    ATR_Median_Weeks  = 8;

// --- H4 文脈TF ---
input group "=== H4 パラメータ ==="
input int    H4_ATR_Short      = 8;
input int    H4_ATR_Long       = 46;
input int    H4_ADX_Period     = 46;
input int    H4_MA_Period      = 46;

// --- ATRゾーン閾値 ---
input group "=== ATRゾーン ==="
input double ATR_Low_Ratio     = 0.70;
input double ATR_High_Ratio    = 1.40;

// --- ATRペア閾値 ---
input group "=== ATRペア(short/long) ==="
input double ATR_Pair_Expand   = 1.05;  // > これ で EXPAND
input double ATR_Pair_Contract = 0.95;  // < これ で CONTRACT

// --- パターン共通 ---
input group "=== ATRパターン ==="
input int    ATR_Vel_Bars      = 3;
input double ATR_Expand_Thresh = 10.0;
input double ATR_Flat_Thresh   = 3.0;

// --- PatA条件 ---
input group "=== PatA: 大値幅 ==="
input double PatA_Vel3_Min     = 8.0;
input double PatA_Vel3_Max     = 15.0;

// --- PatB条件 ---
input group "=== PatB: 押し目 ==="
input double PatB_Vel3_Min     = 5.0;

// --- PatD条件: H4ATRクロス節目 ---
input group "=== PatD: H4ATR節目 ==="
input int    PatD_CrossBars_Max = 3;   // クロス後N H1バー以内
input double PatD_H1_ADX_Min    = 18.0;
input double PatD_DI_Strength_Min = 5.0; // |DI_spread| MEDIUM下限

// --- PatE条件: ボトムアウト ---
input group "=== PatE: ボトムアウト ==="
input double PatE_Pair_Min     = 0.85;  // ATR pair ratio下限
input double PatE_Pair_Max     = 0.95;  // ATR pair ratio上限
input double PatE_MA_Dist_Max  = 0.5;   // MAからの距離(ATR倍率)
input int    PatE_LookBack     = 3;     // CONTRACTING_SLOW直前バー数

// --- 共通NG（緩和） ---
input group "=== 共通NG（緩め） ==="
input double NG_H1_ADX_Max     = 40.0;
input double NG_ATR_Ratio_Max  = 2.00;

// --- 警告閾値 ---
input group "=== 警告フラグ ==="
input double WARN_H1_ADX       = 35.0;
input double WARN_ATR_Ratio    = 1.70;

// --- 表示 ---
input group "=== 表示 ==="
input double Arrow_ATR_Offset  = 0.8;
input bool   Show_Dashboard    = true;

//+------------------------------------------------------------------+
//| バッファ                                                         |
//+------------------------------------------------------------------+
double PatA_BuyBuf[];
double PatA_SellBuf[];
double PatB_BuyBuf[];
double PatB_SellBuf[];
double PatC_BuyBuf[];
double PatC_SellBuf[];
double PatD_BuyBuf[];
double PatD_SellBuf[];
double PatE_BuyBuf[];
double PatE_SellBuf[];
//--- 計算用ダミー（必要本数合わせ）
double Calc1[], Calc2[], Calc3[], Calc4[], Calc5[];
double Calc6[], Calc7[], Calc8[], Calc9[], Calc10[];

//--- ハンドル
int hATR_S_H1, hATR_L_H1, hADX_H1, hMA_H1;
int hATR_S_H4, hATR_L_H4, hADX_H4, hMA_H4;

//--- ダッシュボードプレフィックス
string DB_PREFIX = "WSv3_";

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,  PatA_BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1,  PatA_SellBuf, INDICATOR_DATA);
   SetIndexBuffer(2,  PatB_BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(3,  PatB_SellBuf, INDICATOR_DATA);
   SetIndexBuffer(4,  PatC_BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(5,  PatC_SellBuf, INDICATOR_DATA);
   SetIndexBuffer(6,  PatD_BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(7,  PatD_SellBuf, INDICATOR_DATA);
   SetIndexBuffer(8,  PatE_BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(9,  PatE_SellBuf, INDICATOR_DATA);
   SetIndexBuffer(10, Calc1,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, Calc2,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, Calc3,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, Calc4,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, Calc5,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, Calc6,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, Calc7,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, Calc8,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(18, Calc9,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(19, Calc10, INDICATOR_CALCULATIONS);

   for(int p=0; p<10; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, 0.0);

   // 矢印コード
   PlotIndexSetInteger(0, PLOT_ARROW, 119);  // ◆ PatA BUY
   PlotIndexSetInteger(1, PLOT_ARROW, 119);  // ◆ PatA SELL
   PlotIndexSetInteger(2, PLOT_ARROW, 233);  // ▲ PatB BUY
   PlotIndexSetInteger(3, PLOT_ARROW, 234);  // ▽ PatB SELL
   PlotIndexSetInteger(4, PLOT_ARROW, 108);  // ● PatC BUY
   PlotIndexSetInteger(5, PLOT_ARROW, 108);  // ● PatC SELL
   PlotIndexSetInteger(6, PLOT_ARROW, 171);  // ★ PatD BUY
   PlotIndexSetInteger(7, PLOT_ARROW, 171);  // ★ PatD SELL
   PlotIndexSetInteger(8, PLOT_ARROW, 167);  // ☆ PatE BUY
   PlotIndexSetInteger(9, PLOT_ARROW, 167);  // ☆ PatE SELL

   ArraySetAsSeries(PatA_BuyBuf,  true);
   ArraySetAsSeries(PatA_SellBuf, true);
   ArraySetAsSeries(PatB_BuyBuf,  true);
   ArraySetAsSeries(PatB_SellBuf, true);
   ArraySetAsSeries(PatC_BuyBuf,  true);
   ArraySetAsSeries(PatC_SellBuf, true);
   ArraySetAsSeries(PatD_BuyBuf,  true);
   ArraySetAsSeries(PatD_SellBuf, true);
   ArraySetAsSeries(PatE_BuyBuf,  true);
   ArraySetAsSeries(PatE_SellBuf, true);

   //--- ハンドル生成
   hATR_S_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Short);
   hATR_L_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Long);
   hADX_H1   = iADX(_Symbol, PERIOD_H1, H1_ADX_Period);
   hMA_H1    = iMA (_Symbol, PERIOD_H1, H1_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR_S_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Long);
   hADX_H4   = iADX(_Symbol, PERIOD_H4, H4_ADX_Period);
   hMA_H4    = iMA (_Symbol, PERIOD_H4, H4_MA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR_S_H1==INVALID_HANDLE || hATR_L_H1==INVALID_HANDLE ||
      hADX_H1==INVALID_HANDLE   || hMA_H1==INVALID_HANDLE   ||
      hATR_S_H4==INVALID_HANDLE || hATR_L_H4==INVALID_HANDLE ||
      hADX_H4==INVALID_HANDLE   || hMA_H4==INVALID_HANDLE)
   {
      Print("[WidthSignalV3] ハンドル生成失敗");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "ATR_WidthSignal_v3");

   if(Show_Dashboard) CreateDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hATR_S_H1);
   IndicatorRelease(hATR_L_H1);
   IndicatorRelease(hADX_H1);
   IndicatorRelease(hMA_H1);
   IndicatorRelease(hATR_S_H4);
   IndicatorRelease(hATR_L_H4);
   IndicatorRelease(hADX_H4);
   IndicatorRelease(hMA_H4);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| ATR動的中央値                                                    |
//+------------------------------------------------------------------+
double CalcATRMedian(const double &atr_arr[], int idx, int median_bars)
{
   int start = idx;
   int end   = idx + median_bars;
   if(end >= ArraySize(atr_arr)) return 0;

   double tmp[];
   ArrayResize(tmp, median_bars);
   int cnt = 0;
   for(int k = start; k < end; k++)
      if(atr_arr[k] > 0) tmp[cnt++] = atr_arr[k];
   if(cnt < 10) return 0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
}

//+------------------------------------------------------------------+
//| ATRクロス検知（短期 vs 長期）                                    |
//| 戻り値: クロス後経過バー数（直近MAX_LOOKまで）。クロスなしは-1   |
//| dir_out: +1=UP(short下→上抜け), -1=DOWN, 0=なし                 |
//+------------------------------------------------------------------+
int FindATRCross(const double &atr_s[], const double &atr_l[],
                 int idx, int max_look, int &dir_out)
{
   dir_out = 0;
   int size = MathMin(ArraySize(atr_s), ArraySize(atr_l));
   if(idx + 1 >= size) return -1;

   for(int k = 0; k <= max_look; k++)
   {
      int i_now = idx + k;
      int i_prev = idx + k + 1;
      if(i_prev >= size) break;
      if(atr_s[i_now] <= 0 || atr_l[i_now] <= 0 ||
         atr_s[i_prev] <= 0 || atr_l[i_prev] <= 0) continue;

      bool now_above  = (atr_s[i_now]  > atr_l[i_now]);
      bool prev_above = (atr_s[i_prev] > atr_l[i_prev]);
      if(now_above != prev_above)
      {
         dir_out = now_above ? 1 : -1;
         return k;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| ATRパターン判定                                                  |
//| 戻り値: "EXPANDING","RISING_ACCEL","RISING_DECEL","FLAT",        |
//|         "CONTRACTING","CONTRACTING_SLOW"                         |
//+------------------------------------------------------------------+
string AtrPattern(double vel3, double accel)
{
   if(MathAbs(vel3) < ATR_Flat_Thresh) return "FLAT";
   if(vel3 > ATR_Expand_Thresh && accel > 0) return "EXPANDING";
   if(vel3 > 0 && accel > 0) return "RISING_ACCEL";
   if(vel3 > 0 && accel <= 0) return "RISING_DECEL";
   if(vel3 < 0 && accel < 0) return "CONTRACTING";
   if(vel3 < 0 && accel >= 0) return "CONTRACTING_SLOW";
   return "FLAT";
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   int median_bars = ATR_Median_Weeks * 5 * 24;
   int min_bars    = median_bars + ATR_Vel_Bars * 2 + 20;
   if(rates_total < min_bars) return 0;

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(time,  true);

   int limit = rates_total - prev_calculated + 1;
   if(prev_calculated == 0) limit = rates_total - min_bars;
   if(limit <= 0) limit = 1;

   int copy_size = limit + median_bars + ATR_Vel_Bars * 2 + 20;

   //--- H1データ取得
   double atr_s_h1[], atr_l_h1[];
   double adx_h1[], dip_h1[], din_h1[], ma_h1[];
   ArraySetAsSeries(atr_s_h1, true);
   ArraySetAsSeries(atr_l_h1, true);
   ArraySetAsSeries(adx_h1,   true);
   ArraySetAsSeries(dip_h1,   true);
   ArraySetAsSeries(din_h1,   true);
   ArraySetAsSeries(ma_h1,    true);

   if(CopyBuffer(hATR_S_H1, 0, 0, copy_size, atr_s_h1) <= 0) return prev_calculated;
   if(CopyBuffer(hATR_L_H1, 0, 0, copy_size, atr_l_h1) <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H1,   0, 0, copy_size, adx_h1)   <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H1,   1, 0, copy_size, dip_h1)   <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H1,   2, 0, copy_size, din_h1)   <= 0) return prev_calculated;
   if(CopyBuffer(hMA_H1,    0, 0, copy_size, ma_h1)    <= 0) return prev_calculated;

   //--- H4データ一括取得
   int h4_copy_size = copy_size / 4 + 30;
   double atr_s_h4[], atr_l_h4[], adx_h4[], dip_h4[], din_h4[], ma_h4[];
   datetime h4_time[];
   ArraySetAsSeries(atr_s_h4, true);
   ArraySetAsSeries(atr_l_h4, true);
   ArraySetAsSeries(adx_h4,   true);
   ArraySetAsSeries(dip_h4,   true);
   ArraySetAsSeries(din_h4,   true);
   ArraySetAsSeries(ma_h4,    true);
   ArraySetAsSeries(h4_time,  true);

   if(CopyBuffer(hATR_S_H4, 0, 0, h4_copy_size, atr_s_h4) <= 0) return prev_calculated;
   if(CopyBuffer(hATR_L_H4, 0, 0, h4_copy_size, atr_l_h4) <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H4,   0, 0, h4_copy_size, adx_h4)   <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H4,   1, 0, h4_copy_size, dip_h4)   <= 0) return prev_calculated;
   if(CopyBuffer(hADX_H4,   2, 0, h4_copy_size, din_h4)   <= 0) return prev_calculated;
   if(CopyBuffer(hMA_H4,    0, 0, h4_copy_size, ma_h4)    <= 0) return prev_calculated;
   if(CopyTime(_Symbol, PERIOD_H4, 0, h4_copy_size, h4_time) <= 0) return prev_calculated;

   //--- メインループ
   for(int i = 0; i < limit; i++)
   {
      PatA_BuyBuf[i]=0;  PatA_SellBuf[i]=0;
      PatB_BuyBuf[i]=0;  PatB_SellBuf[i]=0;
      PatC_BuyBuf[i]=0;  PatC_SellBuf[i]=0;
      PatD_BuyBuf[i]=0;  PatD_SellBuf[i]=0;
      PatE_BuyBuf[i]=0;  PatE_SellBuf[i]=0;

      //--- H1基本値
      double atr_s = atr_s_h1[i];
      double atr_l = atr_l_h1[i];
      double h1adx = adx_h1[i];
      double h1dip = dip_h1[i];
      double h1din = din_h1[i];
      double ma    = ma_h1[i];
      double price = close[i];
      if(atr_s<=0 || atr_l<=0 || h1adx<=0 || ma<=0) continue;

      //--- 共通NG（過熱）
      if(h1adx > NG_H1_ADX_Max) continue;

      //--- H1 ATR中央値・ratio
      double atr_med = CalcATRMedian(atr_s_h1, i, median_bars);
      if(atr_med <= 0) continue;
      double atr_ratio = atr_s / atr_med;
      if(atr_ratio > NG_ATR_Ratio_Max) continue;

      string atr_zone = (atr_ratio < ATR_Low_Ratio)  ? "LOW"  :
                        (atr_ratio > ATR_High_Ratio) ? "HIGH" : "NORMAL";

      //--- H1 ATRペア
      double h1_pair = atr_s / atr_l;
      string h1_pair_phase = (h1_pair > ATR_Pair_Expand)   ? "EXPAND"  :
                             (h1_pair < ATR_Pair_Contract) ? "CONTRACT": "NEUTRAL";

      //--- H1 ATRクロス
      int h1_cross_dir = 0;
      int h1_cross_bars = FindATRCross(atr_s_h1, atr_l_h1, i, 50, h1_cross_dir);

      //--- vel3 & accel（短期ATRベース）
      double vel3 = 0, accel = 0;
      if(i + ATR_Vel_Bars < copy_size && atr_s_h1[i+ATR_Vel_Bars] > 0)
         vel3 = (atr_s - atr_s_h1[i+ATR_Vel_Bars]) / atr_s_h1[i+ATR_Vel_Bars] * 100.0;

      double vel3_prev = 0;
      if(i + ATR_Vel_Bars*2 < copy_size)
      {
         double ap  = atr_s_h1[i + ATR_Vel_Bars];
         double ap2 = atr_s_h1[i + ATR_Vel_Bars*2];
         if(ap2 > 0) vel3_prev = (ap - ap2) / ap2 * 100.0;
      }
      accel = vel3 - vel3_prev;

      string h1_pat = AtrPattern(vel3, accel);

      //--- H1パターン直前N本のCONTRACTING_SLOW判定（PatE用）
      bool had_contract_slow = false;
      for(int b = 1; b <= PatE_LookBack; b++)
      {
         if(i+b+ATR_Vel_Bars*2 >= copy_size) break;
         double va = atr_s_h1[i+b];
         double va_s = atr_s_h1[i+b+ATR_Vel_Bars];
         if(va_s <= 0) continue;
         double v_b = (va - va_s) / va_s * 100.0;
         double va_s2 = atr_s_h1[i+b+ATR_Vel_Bars*2];
         double v_b_prev = (va_s2 > 0) ? (va_s - va_s2) / va_s2 * 100.0 : 0;
         double a_b = v_b - v_b_prev;
         string pat_b = AtrPattern(v_b, a_b);
         if(pat_b == "CONTRACTING_SLOW") { had_contract_slow = true; break; }
      }

      //--- ADX zone & DI方向
      string h1_adz = (h1adx < 20) ? "LOW" : (h1adx < 30) ? "MID" : "HIGH";
      double h1_di_spread = h1dip - h1din;
      bool h1_up = (h1dip > h1din);

      //--- MA位置（ATR(Long)で正規化）
      double ma_dist = (price - ma) / atr_l;
      string ma_pos = "NEAR";
      if(ma_dist < -1.5) ma_pos = "BELOW_FAR";
      else if(ma_dist < -0.5) ma_pos = "BELOW_NEAR";
      else if(ma_dist > 1.5) ma_pos = "ABOVE_FAR";
      else if(ma_dist > 0.5) ma_pos = "ABOVE_NEAR";

      //--- H4 該当バー探索
      datetime h1_t = time[i];
      int hi_idx = -1;
      for(int hi = 0; hi < h4_copy_size - 1; hi++)
      {
         if(h4_time[hi] <= h1_t) { hi_idx = hi; break; }
      }
      if(hi_idx < 0) continue;

      double h4_as = atr_s_h4[hi_idx];
      double h4_al = atr_l_h4[hi_idx];
      double h4adx = adx_h4[hi_idx];
      double h4dip = dip_h4[hi_idx];
      double h4din = din_h4[hi_idx];
      if(h4_as<=0 || h4_al<=0 || h4adx<=0) continue;

      double h4_pair = h4_as / h4_al;
      string h4_pair_phase = (h4_pair > ATR_Pair_Expand)   ? "EXPAND"  :
                             (h4_pair < ATR_Pair_Contract) ? "CONTRACT": "NEUTRAL";

      //--- H4 ATRクロス（H4配列上で検索）
      int h4_cross_dir = 0;
      int h4_cross_bars = FindATRCross(atr_s_h4, atr_l_h4, hi_idx, 20, h4_cross_dir);
      //--- H1バー換算（H4クロス〜現在H1まで何本経過したか概算）
      int h4_cross_bars_in_h1 = -1;
      if(h4_cross_bars >= 0 && hi_idx + h4_cross_bars < h4_copy_size)
      {
         datetime cross_t = h4_time[hi_idx + h4_cross_bars];
         //--- 現在H1時刻 - クロスH4時刻 を H1バー数換算
         long diff_sec = (long)(h1_t - cross_t);
         h4_cross_bars_in_h1 = (int)(diff_sec / 3600);
      }

      string h4_adz = (h4adx < 20) ? "LOW" : (h4adx < 30) ? "MID" : "HIGH";
      double h4_di_spread = h4dip - h4din;
      double h4_di_strength = MathAbs(h4_di_spread);
      bool h4_up = (h4dip > h4din);

      double offset = atr_s * Arrow_ATR_Offset;

      //==================================================================
      // PatA: 大値幅期待  RISING_DECEL × vel3 8〜15 × H4/H1整合
      //==================================================================
      bool patA_base = (atr_zone=="NORMAL" && h1_pat=="RISING_DECEL" &&
                        vel3 >= PatA_Vel3_Min && vel3 <= PatA_Vel3_Max);
      if(patA_base && h4_up && h1_up)
         PatA_BuyBuf[i] = low[i] - offset * 1.5;
      if(patA_base && !h4_up && !h1_up)
         PatA_SellBuf[i] = high[i] + offset * 1.5;

      //==================================================================
      // PatB: 押し目高勝率  RISING_DECEL × vel3≥5 × H1がH4と逆
      //==================================================================
      bool patB_base = (atr_zone=="NORMAL" && h1_pat=="RISING_DECEL" &&
                        vel3 >= PatB_Vel3_Min);
      if(patB_base && h4_up && !h1_up)
         PatB_BuyBuf[i] = low[i] - offset;       // H4上目線、H1押し目 → 買い
      if(patB_base && !h4_up && h1_up)
         PatB_SellBuf[i] = high[i] + offset;     // H4下目線、H1戻り → 売り

      //==================================================================
      // PatC: 初動  EXPANDING × ratio>1 × H4=LOW × H1=MID/HIGH
      //==================================================================
      bool patC_base = (atr_zone=="NORMAL" && h1_pat=="EXPANDING" &&
                        atr_ratio > 1.0 &&
                        h4_adz=="LOW" && (h1_adz=="MID" || h1_adz=="HIGH"));
      if(patC_base && h4_up && h1_up)
         PatC_BuyBuf[i] = low[i] - offset * 0.6;
      if(patC_base && !h4_up && !h1_up)
         PatC_SellBuf[i] = high[i] + offset * 0.6;

      //==================================================================
      // PatD: H4 ATRクロス節目  ★新規
      //  H4クロス後3本以内(H4)≒12時間(H1) × DI整合 × MEDIUM以上
      //  × H1 zone LOW/NORMAL × pattern RISING系/EXPANDING × H1_ADX>18
      //==================================================================
      bool h4_cross_recent = (h4_cross_bars >= 0 && h4_cross_bars <= PatD_CrossBars_Max);
      bool patD_h1_pat_ok = (h1_pat=="RISING_ACCEL" || h1_pat=="RISING_DECEL" ||
                             h1_pat=="EXPANDING");
      bool patD_base = (h4_cross_recent &&
                        (atr_zone=="LOW" || atr_zone=="NORMAL") &&
                        patD_h1_pat_ok &&
                        h1adx > PatD_H1_ADX_Min &&
                        h4_di_strength >= PatD_DI_Strength_Min);
      // BUY: クロスUP × H4 DI=UP
      if(patD_base && h4_cross_dir > 0 && h4_up)
         PatD_BuyBuf[i] = low[i] - offset * 2.0;
      // SELL: クロスDOWN × H4 DI=DOWN
      if(patD_base && h4_cross_dir < 0 && !h4_up)
         PatD_SellBuf[i] = high[i] + offset * 2.0;

      //==================================================================
      // PatE: ボトムアウト＋MA接近  ★新規
      //  H1 ATR pair 0.85〜0.95 × 直前CONTRACTING_SLOW × 今 RISING/EXPAND
      //  × MA NEAR × H4 DI_spread整合 × MEDIUM以上 × H1 ADX LOW/MID
      //==================================================================
      bool h1_pair_bottom = (h1_pair >= PatE_Pair_Min && h1_pair <= PatE_Pair_Max);
      bool h1_pat_turn   = (h1_pat=="RISING_ACCEL" || h1_pat=="EXPANDING");
      bool ma_close      = (MathAbs(ma_dist) < PatE_MA_Dist_Max);
      bool patE_base = (h1_pair_bottom && had_contract_slow && h1_pat_turn &&
                        ma_close &&
                        (h1_adz=="LOW" || h1_adz=="MID") &&
                        h4_di_strength >= PatD_DI_Strength_Min);
      // BUY: H4_DI_spread正
      if(patE_base && h4_di_spread > 0)
         PatE_BuyBuf[i] = low[i] - offset * 1.2;
      // SELL: H4_DI_spread負
      if(patE_base && h4_di_spread < 0)
         PatE_SellBuf[i] = high[i] + offset * 1.2;

      //==================================================================
      // 最新バー: ダッシュボード更新
      //==================================================================
      if(i == 0 && Show_Dashboard)
      {
         //--- 警告フラグ
         string warn = "";
         if(h1adx > WARN_H1_ADX)    warn += "過熱注意 ";
         if(atr_ratio > WARN_ATR_Ratio) warn += "ボラ過剰 ";

         //--- アクティブシグナル列挙
         string sigs = "";
         if(PatA_BuyBuf[0]>0)  sigs += "◆A_BUY ";
         if(PatA_SellBuf[0]>0) sigs += "◆A_SELL ";
         if(PatB_BuyBuf[0]>0)  sigs += "▲B_BUY ";
         if(PatB_SellBuf[0]>0) sigs += "▽B_SELL ";
         if(PatC_BuyBuf[0]>0)  sigs += "●C_BUY ";
         if(PatC_SellBuf[0]>0) sigs += "●C_SELL ";
         if(PatD_BuyBuf[0]>0)  sigs += "★D_BUY ";
         if(PatD_SellBuf[0]>0) sigs += "★D_SELL ";
         if(PatE_BuyBuf[0]>0)  sigs += "☆E_BUY ";
         if(PatE_SellBuf[0]>0) sigs += "☆E_SELL ";
         if(sigs == "") sigs = "---";

         UpdateDashboard(
            atr_s, atr_l, atr_med, atr_ratio, atr_zone,
            h1_pair, h1_pair_phase, h1_cross_bars, h1_cross_dir,
            h1_pat, vel3, accel,
            h1adx, h1_adz, h1_di_spread, h1_up,
            ma, ma_dist, ma_pos,
            h4_as, h4_al, h4_pair, h4_pair_phase,
            h4_cross_bars, h4_cross_dir,
            h4adx, h4_adz, h4_di_spread, h4_di_strength, h4_up,
            sigs, warn
         );
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| ダッシュボード                                                   |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   string objs[] = {
      "WSv3_title",
      "WSv3_h1_atr","WSv3_h1_pair","WSv3_h1_pat","WSv3_h1_adx","WSv3_h1_ma",
      "WSv3_sep1",
      "WSv3_h4_atr","WSv3_h4_pair","WSv3_h4_adx","WSv3_h4_ma",
      "WSv3_sep2",
      "WSv3_signal","WSv3_warn"
   };
   int y = 30;
   for(int i=0; i<ArraySize(objs); i++)
   {
      ObjectCreate(0, objs[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objs[i], OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objs[i], OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, objs[i], OBJPROP_YDISTANCE, y + i*16);
      ObjectSetInteger(0, objs[i], OBJPROP_FONTSIZE,  9);
      ObjectSetString(0,  objs[i], OBJPROP_FONT,      "Courier New");
      ObjectSetInteger(0, objs[i], OBJPROP_COLOR,     clrGray);
      ObjectSetString(0,  objs[i], OBJPROP_TEXT,      "---");
   }
   SetLabel("WSv3_title", "─── ATR Width Signal v3 ───", clrSilver);
}

void DeleteDashboard()
{
   string objs[] = {
      "WSv3_title",
      "WSv3_h1_atr","WSv3_h1_pair","WSv3_h1_pat","WSv3_h1_adx","WSv3_h1_ma",
      "WSv3_sep1",
      "WSv3_h4_atr","WSv3_h4_pair","WSv3_h4_adx","WSv3_h4_ma",
      "WSv3_sep2",
      "WSv3_signal","WSv3_warn"
   };
   for(int i=0; i<ArraySize(objs); i++) ObjectDelete(0, objs[i]);
}

void UpdateDashboard(
   double atr_s, double atr_l, double atr_med, double atr_ratio, string atr_zone,
   double h1_pair, string h1_pair_phase, int h1_cross_bars, int h1_cross_dir,
   string h1_pat, double vel3, double accel,
   double h1adx, string h1_adz, double h1_di_spread, bool h1_up,
   double ma, double ma_dist, string ma_pos,
   double h4_as, double h4_al, double h4_pair, string h4_pair_phase,
   int h4_cross_bars, int h4_cross_dir,
   double h4adx, string h4_adz, double h4_di_spread, double h4_di_strength, bool h4_up,
   string sigs, string warn)
{
   color zone_col = (atr_zone=="NORMAL") ? clrLimeGreen :
                    (atr_zone=="HIGH")   ? clrOrange    : clrDodgerBlue;

   SetLabel("WSv3_h1_atr",
      StringFormat("H1 ATR16=%.2f ATR32=%.2f Med=%.2f Ratio=%.2f [%s]",
         atr_s, atr_l, atr_med, atr_ratio, atr_zone),
      zone_col);

   string h1_cross_str = (h1_cross_bars >= 0) ?
      StringFormat("%dbar %s", h1_cross_bars, (h1_cross_dir>0?"UP":"DN")) : "---";
   SetLabel("WSv3_h1_pair",
      StringFormat("H1 pair=%.3f [%s]  cross=%s",
         h1_pair, h1_pair_phase, h1_cross_str),
      clrSilver);

   color pat_col = (h1_pat=="RISING_DECEL")?clrGold :
                   (h1_pat=="EXPANDING")?clrLimeGreen :
                   (h1_pat=="RISING_ACCEL")?clrAqua :
                   (h1_pat=="CONTRACTING_SLOW")?clrOrange :
                   (h1_pat=="CONTRACTING")?clrCrimson : clrDimGray;
   SetLabel("WSv3_h1_pat",
      StringFormat("H1 pat=%-16s vel3=%+5.1f%% accel=%+5.1f",
         h1_pat, vel3, accel),
      pat_col);

   SetLabel("WSv3_h1_adx",
      StringFormat("H1 ADX=%5.1f [%s] DI_sp=%+6.2f %s",
         h1adx, h1_adz, h1_di_spread, h1_up?"UP":"DN"),
      h1_up?clrAqua:clrOrange);

   SetLabel("WSv3_h1_ma",
      StringFormat("H1 MA=%.2f dist=%+.2fATR [%s]",
         ma, ma_dist, ma_pos),
      clrLightGray);

   SetLabel("WSv3_sep1", "──────────────────────────", clrDimGray);

   SetLabel("WSv3_h4_atr",
      StringFormat("H4 ATR8=%.2f ATR46=%.2f", h4_as, h4_al),
      clrSilver);

   string h4_cross_str = (h4_cross_bars >= 0) ?
      StringFormat("%dbar %s", h4_cross_bars, (h4_cross_dir>0?"UP":"DN")) : "---";
   color h4_pair_col = (h4_cross_bars >= 0 && h4_cross_bars <= PatD_CrossBars_Max) ?
      clrMagenta : clrSilver;
   SetLabel("WSv3_h4_pair",
      StringFormat("H4 pair=%.3f [%s] cross=%s",
         h4_pair, h4_pair_phase, h4_cross_str),
      h4_pair_col);

   string h4_str = (h4_di_strength >= 15) ? "STRONG" :
                   (h4_di_strength >= 5)  ? "MEDIUM" : "WEAK";
   SetLabel("WSv3_h4_adx",
      StringFormat("H4 ADX=%5.1f [%s] DI_sp=%+6.2f [%s] %s",
         h4adx, h4_adz, h4_di_spread, h4_str, h4_up?"UP":"DN"),
      h4_up?clrAqua:clrOrange);

   SetLabel("WSv3_h4_ma", "H4 MA46 (参考)", clrDimGray);

   SetLabel("WSv3_sep2", "──────────────────────────", clrDimGray);

   color sig_col = (StringLen(sigs)>3) ? clrYellow : clrDimGray;
   SetLabel("WSv3_signal",
      StringFormat("Signal: %s", sigs), sig_col);

   color warn_col = (StringLen(warn)>0) ? clrRed : clrDimGray;
   SetLabel("WSv3_warn",
      StringFormat("Warn: %s", (warn==""?"---":warn)), warn_col);
}

void SetLabel(string name, string text, color col)
{
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}
//+------------------------------------------------------------------+
