//+------------------------------------------------------------------+
//|  ATR_Ratio_Dual_v1.mq5                                           |
//|  ATR比率を2本表示するインジケータ（柔軟設定版）                    |
//|                                                                  |
//|  各ラインで個別に設定可能:                                          |
//|  - TF (時間軸)                                                    |
//|  - Type (Median: ATR_Short/ATR_Median, Pair: ATR_Short/ATR_Long) |
//|  - ATR_Short / ATR_Long の期間                                    |
//|                                                                  |
//|  デフォルト:                                                       |
//|  - Line A: H1 × Median (ATR16 / 8週median)                       |
//|  - Line B: H1 × Pair   (ATR16 / ATR32)                          |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0: Ratio Line A
#property indicator_label1  "Ratio-A"
#property indicator_type1   DRAW_LINE
#property indicator_color1  0x00D4FF   // シアン
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

//--- Plot 1: Ratio Line B
#property indicator_label2  "Ratio-B"
#property indicator_type2   DRAW_LINE
#property indicator_color2  0xF97316   // オレンジ
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

//--- 比率タイプ
enum ENUM_RATIO_TYPE
{
   RATIO_MEDIAN,   // ATR_Short / ATR_Median (Zone判定用)
   RATIO_PAIR      // ATR_Short / ATR_Long   (Pair Phase判定用)
};

//+------------------------------------------------------------------+
input group "=== Line A ==="
input ENUM_TIMEFRAMES  TF_A             = PERIOD_H1;
input ENUM_RATIO_TYPE  RatioType_A      = RATIO_MEDIAN;
input int              ATR_Short_A      = 16;
input int              ATR_Long_A       = 32;
input int              Median_Weeks_A   = 8;

input group "=== Line B ==="
input ENUM_TIMEFRAMES  TF_B             = PERIOD_H1;
input ENUM_RATIO_TYPE  RatioType_B      = RATIO_PAIR;
input int              ATR_Short_B      = 16;
input int              ATR_Long_B       = 32;
input int              Median_Weeks_B   = 8;

input group "=== 表示 ==="
input bool             Show_Levels      = true;
input bool             Show_Label       = true;
input color            Color_A          = 0x00D4FF;
input color            Color_B          = 0xF97316;

input group "=== 横線レベル ==="
input double           Level_LOW        = 0.70;
input double           Level_PAIR_LO    = 0.95;
input double           Level_MID        = 1.00;
input double           Level_PAIR_HI    = 1.05;
input double           Level_HIGH_LO    = 1.30;
input double           Level_HIGH_HI    = 1.40;

//+------------------------------------------------------------------+
double BufA[], BufB[];
int hShort_A=INVALID_HANDLE, hLong_A=INVALID_HANDLE;
int hShort_B=INVALID_HANDLE, hLong_B=INVALID_HANDLE;
string ObjPrefix = "ATRR1_";

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufA, INDICATOR_DATA);
   SetIndexBuffer(1, BufB, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Color_A);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Color_B);

   //--- Line A ハンドル（Long は Pair の場合のみ必要、Median なら未使用）
   hShort_A = iATR(_Symbol, TF_A, ATR_Short_A);
   hLong_A  = iATR(_Symbol, TF_A, ATR_Long_A);
   hShort_B = iATR(_Symbol, TF_B, ATR_Short_B);
   hLong_B  = iATR(_Symbol, TF_B, ATR_Long_B);

   if(hShort_A==INVALID_HANDLE || hLong_A==INVALID_HANDLE ||
      hShort_B==INVALID_HANDLE || hLong_B==INVALID_HANDLE)
   {
      Alert("[ATR_Ratio_Dual] ハンドル生成失敗");
      return INIT_FAILED;
   }

   //--- 横線描画
   if(Show_Levels)
   {
      IndicatorSetInteger(INDICATOR_LEVELS, 6);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, Level_LOW);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, Level_PAIR_LO);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, Level_MID);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 3, Level_PAIR_HI);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 4, Level_HIGH_LO);
      IndicatorSetDouble(INDICATOR_LEVELVALUE, 5, Level_HIGH_HI);
      for(int i = 0; i < 6; i++)
      {
         color c = clrDimGray;
         if(i == 2) c = clrSilver;                  // 1.00
         else if(i == 0 || i == 5) c = clrGray;     // LOW / HIGH 端
         IndicatorSetInteger(INDICATOR_LEVELCOLOR, i, c);
         IndicatorSetInteger(INDICATOR_LEVELSTYLE, i, (i==2) ? STYLE_SOLID : STYLE_DOT);
      }
   }

   string typeA = (RatioType_A==RATIO_MEDIAN) ? "Med" : "Pair";
   string typeB = (RatioType_B==RATIO_MEDIAN) ? "Med" : "Pair";
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ATR Ratio Dual  A:%s[%s,%d]  B:%s[%s,%d]",
                   typeA, TFToString(TF_A), ATR_Short_A,
                   typeB, TFToString(TF_B), ATR_Short_B));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hShort_A); IndicatorRelease(hLong_A);
   IndicatorRelease(hShort_B); IndicatorRelease(hLong_B);
   DeleteLabel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TFあたり「8週相当」のmedianバー数を計算                          |
//+------------------------------------------------------------------+
int MedianBars(ENUM_TIMEFRAMES tf, int weeks)
{
   ENUM_TIMEFRAMES tf_real = (tf == PERIOD_CURRENT) ? _Period : tf;
   int mins = PeriodSeconds(tf_real) / 60;
   if(mins <= 0) return 960;
   int per_week = 5 * 24 * 60;  // 5営業日 × 24h × 60min
   return weeks * per_week / mins;
}

//+------------------------------------------------------------------+
//| 配列の median を計算（idxから bars 個分の median）             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 1ライン分の Ratio を計算してバッファに書く                       |
//+------------------------------------------------------------------+
void CalcRatioLine(int start, int rates_total,
                   const datetime &time[],
                   ENUM_TIMEFRAMES tf, ENUM_RATIO_TYPE rtype,
                   int hShort, int hLong, int median_weeks,
                   double &buf[])
{
   ENUM_TIMEFRAMES tf_real = (tf == PERIOD_CURRENT) ? _Period : tf;
   bool same_tf = (tf_real == _Period);

   if(same_tf)
   {
      //--- 高速パス: 同一TF
      int copy_n = rates_total;
      double atr_s[]; ArraySetAsSeries(atr_s, true);
      if(CopyBuffer(hShort, 0, 0, copy_n, atr_s) <= 0) return;

      double atr_l[]; ArraySetAsSeries(atr_l, true);
      bool need_l = (rtype == RATIO_PAIR);
      if(need_l && CopyBuffer(hLong, 0, 0, copy_n, atr_l) <= 0) return;

      int med_bars = (rtype == RATIO_MEDIAN) ? MedianBars(tf_real, median_weeks) : 0;

      // 配列は SetAsSeries(true) なので i=0 が最新
      // buf は false（時系列昇順）デフォルトなので、書き込み時は rates_total-1-i に書く
      for(int i_series = 0; i_series < copy_n; i_series++)
      {
         int dst = rates_total - 1 - i_series;
         if(dst < start) break;

         double s = atr_s[i_series];
         if(s <= 0) { buf[dst] = EMPTY_VALUE; continue; }

         double v = 0;
         if(rtype == RATIO_PAIR)
         {
            double l = atr_l[i_series];
            v = (l > 0) ? (s / l) : 0;
         }
         else
         {
            double med = CalcMedian(atr_s, i_series, med_bars);
            v = (med > 0) ? (s / med) : 0;
         }
         buf[dst] = (v > 0) ? v : EMPTY_VALUE;
      }
   }
   else
   {
      //--- マルチTF: 必要分だけTF側からまとめて取得し、各バーをマッピング
      int tf_bars = (int)Bars(_Symbol, tf_real);
      if(tf_bars <= 0) return;
      double atr_s_tf[]; ArraySetAsSeries(atr_s_tf, true);
      double atr_l_tf[]; ArraySetAsSeries(atr_l_tf, true);
      if(CopyBuffer(hShort, 0, 0, tf_bars, atr_s_tf) <= 0) return;
      bool need_l = (rtype == RATIO_PAIR);
      if(need_l && CopyBuffer(hLong, 0, 0, tf_bars, atr_l_tf) <= 0) return;

      int med_bars = (rtype == RATIO_MEDIAN) ? MedianBars(tf_real, median_weeks) : 0;

      ArraySetAsSeries(time, false);
      for(int i = start; i < rates_total; i++)
      {
         int shift = iBarShift(_Symbol, tf_real, time[i], false);
         if(shift < 0 || shift >= tf_bars) { buf[i] = EMPTY_VALUE; continue; }
         double s = atr_s_tf[shift];
         if(s <= 0) { buf[i] = EMPTY_VALUE; continue; }

         double v = 0;
         if(rtype == RATIO_PAIR)
         {
            double l = atr_l_tf[shift];
            v = (l > 0) ? (s / l) : 0;
         }
         else
         {
            double med = CalcMedian(atr_s_tf, shift, med_bars);
            v = (med > 0) ? (s / med) : 0;
         }
         buf[i] = (v > 0) ? v : EMPTY_VALUE;
      }
      ArraySetAsSeries(time, true);
   }
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[], const double &high[],
                const double &low[],  const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(rates_total < 2) return 0;

   int start = (prev_calculated <= 1) ? 0 : prev_calculated - 1;

   CalcRatioLine(start, rates_total, time,
                 TF_A, RatioType_A, hShort_A, hLong_A, Median_Weeks_A, BufA);
   CalcRatioLine(start, rates_total, time,
                 TF_B, RatioType_B, hShort_B, hLong_B, Median_Weeks_B, BufB);

   //--- 最新ラベル
   if(Show_Label)
   {
      double va = (rates_total>0 && BufA[rates_total-1]!=EMPTY_VALUE) ? BufA[rates_total-1] : 0;
      double vb = (rates_total>0 && BufB[rates_total-1]!=EMPTY_VALUE) ? BufB[rates_total-1] : 0;
      UpdateLabel(va, vb);
   }
   return rates_total;
}

//+------------------------------------------------------------------+
//| ラベル表示                                                       |
//+------------------------------------------------------------------+
void UpdateLabel(double va, double vb)
{
   string na = ObjPrefix + "LabelA";
   string nb = ObjPrefix + "LabelB";

   string typeA = (RatioType_A==RATIO_MEDIAN) ? "Med" : "Pair";
   string typeB = (RatioType_B==RATIO_MEDIAN) ? "Med" : "Pair";

   //--- A
   if(ObjectFind(0, na) < 0)
   {
      ObjectCreate(0, na, OBJ_LABEL, ChartWindowFind(), 0, 0);
      ObjectSetInteger(0, na, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, na, OBJPROP_XDISTANCE,  10);
      ObjectSetInteger(0, na, OBJPROP_YDISTANCE,  20);
      ObjectSetInteger(0, na, OBJPROP_FONTSIZE,   9);
      ObjectSetString( 0, na, OBJPROP_FONT,       "Courier New");
      ObjectSetInteger(0, na, OBJPROP_ANCHOR,     ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, na, OBJPROP_COLOR, Color_A);
   ObjectSetString(0, na, OBJPROP_TEXT,
      StringFormat("A %s[%s]: %.3f",
                   typeA, TFToString(TF_A), va));

   //--- B
   if(ObjectFind(0, nb) < 0)
   {
      ObjectCreate(0, nb, OBJ_LABEL, ChartWindowFind(), 0, 0);
      ObjectSetInteger(0, nb, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nb, OBJPROP_XDISTANCE,  10);
      ObjectSetInteger(0, nb, OBJPROP_YDISTANCE,  36);
      ObjectSetInteger(0, nb, OBJPROP_FONTSIZE,   9);
      ObjectSetString( 0, nb, OBJPROP_FONT,       "Courier New");
      ObjectSetInteger(0, nb, OBJPROP_ANCHOR,     ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, nb, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, nb, OBJPROP_COLOR, Color_B);
   ObjectSetString(0, nb, OBJPROP_TEXT,
      StringFormat("B %s[%s]: %.3f",
                   typeB, TFToString(TF_B), vb));

   ChartRedraw();
}

void DeleteLabel()
{
   ObjectDelete(0, ObjPrefix + "LabelA");
   ObjectDelete(0, ObjPrefix + "LabelB");
}

//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      case PERIOD_CURRENT: return "CUR";
      default:        return "???";
   }
}
//+------------------------------------------------------------------+
