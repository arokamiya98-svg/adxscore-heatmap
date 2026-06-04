//+------------------------------------------------------------------+
//|  ATR_Dual_v1.mq5                                                 |
//|  ATR 2本表示インジケーター（時間軸切り替え対応）                    |
//|                                                                  |
//|  サブウィンドウ構成:                                               |
//|  ・Plot0: ATR Line A（短期 / メイン用途）                          |
//|  ・Plot1: ATR Line B（長期 / 比較用途）                            |
//|                                                                  |
//|  機能:                                                            |
//|  ・ATR期間 A / B を個別に設定可能                                   |
//|  ・時間軸 A / B を個別にドロップダウンで選択可能                     |
//|  ・同一時間軸 or 異なる時間軸での比較に対応                          |
//|  ・チャート右上にリアルタイム数値ラベルを表示                         |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0: ATR Line A
#property indicator_label1  "ATR-A"
#property indicator_type1   DRAW_LINE
#property indicator_color1  0x00D4FF   // シアン
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

//--- Plot 1: ATR Line B
#property indicator_label2  "ATR-B"
#property indicator_type2   DRAW_LINE
#property indicator_color2  0xF97316   // オレンジ
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== ATR Line A ==="
input int                ATR_Period_A   = 14;
input ENUM_TIMEFRAMES    TF_A           = PERIOD_CURRENT; // 時間軸 A

input group "=== ATR Line B ==="
input int                ATR_Period_B   = 50;
input ENUM_TIMEFRAMES    TF_B           = PERIOD_H4;      // 時間軸 B

input group "=== 表示設定 ==="
input bool               Show_Label     = true;           // 右上ラベル表示
input color              Color_A        = 0x00D4FF;       // Line A カラー
input color              Color_B        = 0xF97316;       // Line B カラー

//+------------------------------------------------------------------+
//| バッファ                                                           |
//+------------------------------------------------------------------+
double BufA[], BufB[];

int hATR_A, hATR_B;
string ObjPrefix = "ATRD1_";

//+------------------------------------------------------------------+
int OnInit()
{
   //--- バッファ割り当て
   SetIndexBuffer(0, BufA, INDICATOR_DATA);
   SetIndexBuffer(1, BufB, INDICATOR_DATA);

   //--- 空値設定
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- カラーをパラメータから適用
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Color_A);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Color_B);

   //--- ATRハンドル生成
   hATR_A = iATR(_Symbol, TF_A, ATR_Period_A);
   hATR_B = iATR(_Symbol, TF_B, ATR_Period_B);

   if(hATR_A == INVALID_HANDLE || hATR_B == INVALID_HANDLE)
   {
      Alert("[ATR_Dual_v1] ハンドル生成失敗");
      return INIT_FAILED;
   }

   //--- ショートネーム
   string tf_a_str = TFToString(TF_A);
   string tf_b_str = TFToString(TF_B);
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ATR Dual  A:%d[%s]  B:%d[%s]",
                   ATR_Period_A, tf_a_str, ATR_Period_B, tf_b_str));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hATR_A);
   IndicatorRelease(hATR_B);
   DeleteLabel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| メイン計算                                                         |
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

   //--- 更新開始バー
   int start = (prev_calculated <= 1) ? 0 : prev_calculated - 1;

   //--------------------------------------------------------------
   // Line A: 現在チャート足と同期（TF_A が PERIOD_CURRENT 等の場合）
   // Line B: TF_B の ATR を現在チャート足にマッピング
   //--------------------------------------------------------------

   //--- ATR-A: チャート時間軸と同期している場合は直接コピー
   if(TF_A == PERIOD_CURRENT || TF_A == _Period)
   {
      // 直接コピー（高速パス）
      double tmp[];
      ArraySetAsSeries(tmp, false);
      int copied = CopyBuffer(hATR_A, 0, 0, rates_total, tmp);
      if(copied <= 0) return prev_calculated;
      for(int i = start; i < rates_total && i < copied; i++)
         BufA[i] = (tmp[i] > 0) ? tmp[i] : EMPTY_VALUE;
   }
   else
   {
      // 異なる時間軸: バーごとにiBarShiftでマッピング
      ArraySetAsSeries(time, false);
      for(int i = start; i < rates_total; i++)
      {
         int shift = iBarShift(_Symbol, TF_A, time[i], false);
         if(shift < 0) { BufA[i] = EMPTY_VALUE; continue; }
         double v[1];
         if(CopyBuffer(hATR_A, 0, shift, 1, v) > 0 && v[0] > 0)
            BufA[i] = v[0];
         else
            BufA[i] = EMPTY_VALUE;
      }
      ArraySetAsSeries(time, true);
   }

   //--- ATR-B: TF_B を現在チャートにマッピング
   if(TF_B == PERIOD_CURRENT || TF_B == _Period)
   {
      double tmp[];
      ArraySetAsSeries(tmp, false);
      int copied = CopyBuffer(hATR_B, 0, 0, rates_total, tmp);
      if(copied <= 0) return prev_calculated;
      for(int i = start; i < rates_total && i < copied; i++)
         BufB[i] = (tmp[i] > 0) ? tmp[i] : EMPTY_VALUE;
   }
   else
   {
      ArraySetAsSeries(time, false);
      for(int i = start; i < rates_total; i++)
      {
         int shift = iBarShift(_Symbol, TF_B, time[i], false);
         if(shift < 0) { BufB[i] = EMPTY_VALUE; continue; }
         double v[1];
         if(CopyBuffer(hATR_B, 0, shift, 1, v) > 0 && v[0] > 0)
            BufB[i] = v[0];
         else
            BufB[i] = EMPTY_VALUE;
      }
      ArraySetAsSeries(time, true);
   }

   //--- ラベル更新（最新バーのみ）
   if(Show_Label)
   {
      double atr_a = (BufA[rates_total-1] != EMPTY_VALUE) ? BufA[rates_total-1] : 0;
      double atr_b = (BufB[rates_total-1] != EMPTY_VALUE) ? BufB[rates_total-1] : 0;
      UpdateLabel(atr_a, atr_b);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| ラベル描画                                                         |
//+------------------------------------------------------------------+
void UpdateLabel(double atr_a, double atr_b)
{
   string na = ObjPrefix + "LabelA";
   string nb = ObjPrefix + "LabelB";

   //--- Line A ラベル
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
      StringFormat("ATR-A(%d)[%s]: %.4f",
                   ATR_Period_A, TFToString(TF_A), atr_a));

   //--- Line B ラベル
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
      StringFormat("ATR-B(%d)[%s]: %.4f",
                   ATR_Period_B, TFToString(TF_B), atr_b));

   ChartRedraw();
}

void DeleteLabel()
{
   ObjectDelete(0, ObjPrefix + "LabelA");
   ObjectDelete(0, ObjPrefix + "LabelB");
}

//+------------------------------------------------------------------+
//| 時間軸名称変換                                                     |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:       return "M1";
      case PERIOD_M5:       return "M5";
      case PERIOD_M15:      return "M15";
      case PERIOD_M30:      return "M30";
      case PERIOD_H1:       return "H1";
      case PERIOD_H4:       return "H4";
      case PERIOD_D1:       return "D1";
      case PERIOD_W1:       return "W1";
      case PERIOD_MN1:      return "MN";
      case PERIOD_CURRENT:  return "CUR";
      default:              return "???";
   }
}
//+------------------------------------------------------------------+
