//+------------------------------------------------------------------+
//|  ATR_Velocity_Rhythm_v2_NoBG.mq5                                 |
//|  ATR velocity × ADX立ち上がり × H4ADX リアルタイムインジケーター  |
//|  ※ メインチャート背景色変更なし版                                  |
//|                                                                  |
//|  サブウィンドウ構成（v2改良）:                                      |
//|  ・Plot0: vel_3 カラーヒストグラム（パターン別6色）                 |
//|  ・Plot1: H1 ADX値ライン（ゾーン別カラー）                          |
//|  ・Plot2: H1 ADX velocity 点線（紫）                               |
//|  ・Plot3: H4 ADX値ライン（水色細線）← DIスプレッドから変更          |
//|  ・Plot4: スウィートスポット / PatD前兆ドット                       |
//|  ・メインチャート: ATRゾーン背景色 + パターン情報ラベル              |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "2.00"
#property indicator_separate_window
#property indicator_minimum  -55
#property indicator_maximum   65

#property indicator_buffers  10
#property indicator_plots     5

//--- Plot 0: vel_3 カラーヒストグラム（パターン6色）
#property indicator_label1  "vel_3"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  0x00D4FF,0xA78BFA,0x34D399,0x94A3B8,0xF87171,0xFF9580,0xFFFFFF
//                          RISING_DECEL, EXPANDING, RISING_ACCEL, FLAT, CONTRACTING, CONT_SLOW, UNKNOWN
#property indicator_width1  3
#property indicator_style1  STYLE_SOLID

//--- Plot 1: H1 ADX値ライン（ゾーン別カラー）
#property indicator_label2  "H1 ADX"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  0x94A3B8,0xF0B429,0xF97316
//                          LOW=グレー, MID=ゴールド, HIGH=オレンジ
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

//--- Plot 2: H1 ADX velocity（立ち上がり速度）
#property indicator_label3  "ADX vel"
#property indicator_type3   DRAW_LINE
#property indicator_color3  0xA78BFA   // 紫
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

//--- Plot 3: H4 ADX値ライン（スケール調整済み）
#property indicator_label4  "H4 ADX"
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_color4  0x38BDF8,0x0EA5E9,0xF97316
//                          H4_LOW=薄水色, H4_MID=青, H4_HIGH=オレンジ
#property indicator_width4  1
#property indicator_style4  STYLE_SOLID

//--- Plot 4: シグナルドット（★PatD前兆 / ◆PatA）
#property indicator_label5  "Signal"
#property indicator_type5   DRAW_COLOR_ARROW
#property indicator_color5  0xFF00FF,0xFFD700,0x00D4FF
//                          PatD=マゼンタ, PatA=ゴールド, Sweet=シアン
#property indicator_width5  2

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== ATR設定 ==="
input int    ATR_Period        = 14;
input int    ATR_Median_Weeks  = 8;
input double ATR_Low_Ratio     = 0.70;
input double ATR_High_Ratio    = 1.40;

input group "=== Velocity設定 ==="
input int    Vel_Short         = 3;
input double Expand_Thresh     = 10.0;
input double Flat_Thresh       = 3.0;

input group "=== ADX設定 ==="
input int    H1_ADX_Period     = 28;
input int    H4_ADX_Period     = 30;
input int    ADX_Vel_Bars      = 3;
input double ADX_Entry_Level   = 20.0;
input double ADX_Caution_Level = 30.0;

input group "=== H4 ADX表示 ==="
input double H4_ADX_Scale     = 0.7;    // H4ADXをサブウィンドウに収めるスケール係数
//  ※ H4ADX値 × Scale でプロット（例: H4ADX=25 × 0.7 = 17.5 → H1ADXと並べて見やすい）

input group "=== アラート設定 ==="
input bool   Alert_SweetSpot  = true;
input bool   Alert_PatD       = true;
input bool   Alert_ADX_Cross  = true;
input bool   Alert_OnBar      = true;

input group "=== 表示設定 ==="
input bool   Show_ZoneBG      = true;
input bool   Show_PatternLabel= true;
input bool   Show_ADX_Lines   = true;
input color  Color_LOW_BG     = 0x0D2818;
input color  Color_NORMAL_BG  = 0x071828;
input color  Color_HIGH_BG    = 0x1F0D00;

//+------------------------------------------------------------------+
//| カラーインデックス定数                                              |
//+------------------------------------------------------------------+
// vel_3 ヒストグラム色
#define COL_VEL_RD      0   // RISING_DECEL  シアン
#define COL_VEL_EXP     1   // EXPANDING     紫
#define COL_VEL_RA      2   // RISING_ACCEL  グリーン
#define COL_VEL_FLAT    3   // FLAT          グレー
#define COL_VEL_CONT    4   // CONTRACTING   赤
#define COL_VEL_CS      5   // CONT_SLOW     サーモン
#define COL_VEL_UNK     6   // その他

// H1 ADX ライン色
#define COL_ADX_LOW     0   // グレー
#define COL_ADX_MID     1   // ゴールド ★
#define COL_ADX_HIGH    2   // オレンジ

// H4 ADX ライン色
#define COL_H4_LOW      0   // 薄水色
#define COL_H4_MID      1   // 青
#define COL_H4_HIGH     2   // オレンジ

// シグナルドット色
#define COL_SIG_PATD    0   // マゼンタ（爆発前夜）
#define COL_SIG_PATA    1   // ゴールド（長期化サイン）
#define COL_SIG_SWEET   2   // シアン（スウィートスポット）

//+------------------------------------------------------------------+
//| バッファ宣言                                                       |
//+------------------------------------------------------------------+
double BufVel[];        // vel_3値
double BufVelColor[];   // vel_3カラーインデックス
double BufADX[];        // H1 ADX値
double BufADXColor[];   // H1 ADXカラーインデックス
double BufADXVel[];     // H1 ADX velocity
double BufH4ADX[];      // H4 ADX値（スケール済み）
double BufH4Color[];    // H4 ADXカラーインデックス
double BufSig[];        // シグナルドット
double BufSigColor[];   // シグナルカラーインデックス
double BufZone[];       // 内部: ゾーン（計算用）

int hATR_H1, hADX_H1, hADX_H4;
int MedianBars;
datetime LastAlertSweet = 0, LastAlertD = 0, LastAlertCross = 0;
string ObjPrefix = "AVR2_";

//+------------------------------------------------------------------+
int OnInit()
{
   //--- バッファ割り当て
   SetIndexBuffer(0, BufVel,      INDICATOR_DATA);
   SetIndexBuffer(1, BufVelColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufADX,      INDICATOR_DATA);
   SetIndexBuffer(3, BufADXColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, BufADXVel,   INDICATOR_DATA);
   SetIndexBuffer(5, BufH4ADX,    INDICATOR_DATA);
   SetIndexBuffer(6, BufH4Color,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(7, BufSig,      INDICATOR_DATA);
   SetIndexBuffer(8, BufSigColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(9, BufZone,     INDICATOR_CALCULATIONS);

   //--- 空値
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 矢印コード（シグナルドット）
   PlotIndexSetInteger(4, PLOT_ARROW, 171);  // ★

   //--- ハンドル生成
   hATR_H1 = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   hADX_H1 = iADX(_Symbol, PERIOD_CURRENT, H1_ADX_Period);
   hADX_H4 = iADX(_Symbol, PERIOD_H4,      H4_ADX_Period);

   if(hATR_H1==INVALID_HANDLE || hADX_H1==INVALID_HANDLE || hADX_H4==INVALID_HANDLE)
   {
      Alert("ATR_Velocity_Rhythm v2: ハンドル生成失敗");
      return INIT_FAILED;
   }

   MedianBars = ATR_Median_Weeks * 5 * 24;

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ATR Vel Rhythm v2 [ATR%d H1ADX%d H4ADX%d]",
                   ATR_Period, H1_ADX_Period, H4_ADX_Period));

   //--- 水平線（ADX基準）
   if(Show_ADX_Lines)
   {
      DrawHLine(ObjPrefix+"L20",  ADX_Entry_Level,   0x3B82F6, STYLE_DOT,  1, "ADX 20");
      DrawHLine(ObjPrefix+"L30",  ADX_Caution_Level, 0xF97316, STYLE_DOT,  1, "ADX 30");
      DrawHLine(ObjPrefix+"L0",   0.0,               0x374151, STYLE_SOLID,1, "");
      // H4の目安線（スケール済み）
      DrawHLine(ObjPrefix+"H4L20", 20.0 * H4_ADX_Scale, 0x164E63, STYLE_DOT, 1,
                StringFormat("H4 ADX20 (×%.1f)", H4_ADX_Scale));
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, ObjPrefix);
   // 背景色は変更していないため復元不要
   // ChartSetInteger(0, CHART_COLOR_BACKGROUND, 0x1A1A2E); // ← 無効化
   // ラベル削除
   ObjectDelete(0, ObjPrefix+"ZoneText");
   ObjectDelete(0, ObjPrefix+"PatLabel");
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
   int skip = MedianBars + Vel_Short * 2 + ADX_Vel_Bars + 10;
   if(rates_total < skip + 5) return 0;

   //--- データ一括取得（古い順 = series:false）
   double atr_arr[], adx_m[], adx_p[], adx_n[];
   ArraySetAsSeries(atr_arr, false);
   ArraySetAsSeries(adx_m,   false);
   ArraySetAsSeries(adx_p,   false);
   ArraySetAsSeries(adx_n,   false);

   if(CopyBuffer(hATR_H1, 0, 0, rates_total, atr_arr) <= 0) return 0;
   if(CopyBuffer(hADX_H1, 0, 0, rates_total, adx_m)   <= 0) return 0;
   if(CopyBuffer(hADX_H1, 1, 0, rates_total, adx_p)   <= 0) return 0;
   if(CopyBuffer(hADX_H1, 2, 0, rates_total, adx_n)   <= 0) return 0;

   int start = (prev_calculated <= skip) ? skip : prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
   {
      //--- 初期化
      BufVel[i]    = 0.0;
      BufADX[i]    = EMPTY_VALUE;
      BufADXVel[i] = EMPTY_VALUE;
      BufH4ADX[i]  = EMPTY_VALUE;
      BufSig[i]    = EMPTY_VALUE;
      BufVelColor[i]  = COL_VEL_UNK;
      BufADXColor[i]  = COL_ADX_LOW;
      BufH4Color[i]   = COL_H4_LOW;
      BufSigColor[i]  = COL_SIG_SWEET;

      double atr    = atr_arr[i];
      double h1_adx = adx_m[i];
      double h1_dip = adx_p[i];
      double h1_din = adx_n[i];
      if(atr <= 0 || h1_adx <= 0) continue;

      //------------------------------------------------------
      // ATR動的中央値・ゾーン
      //------------------------------------------------------
      double atr_med = CalcATRMedian(atr_arr, i, MedianBars);
      if(atr_med <= 0) continue;
      double vs = atr / atr_med;

      int zone = (vs < ATR_Low_Ratio) ? 0 : (vs > ATR_High_Ratio) ? 2 : 1;
      BufZone[i] = zone;

      //------------------------------------------------------
      // ATR velocity & accel
      //------------------------------------------------------
      double atr_s = (i >= Vel_Short && atr_arr[i-Vel_Short] > 0) ?
                      atr_arr[i-Vel_Short] : atr;
      double vel3  = (atr_s > 0) ? (atr - atr_s) / atr_s * 100.0 : 0;

      double vel3_prev = 0;
      if(i >= Vel_Short * 2)
      {
         double a1 = atr_arr[i - Vel_Short];
         double a2 = atr_arr[i - Vel_Short * 2];
         if(a2 > 0) vel3_prev = (a1 - a2) / a2 * 100.0;
      }
      double accel = vel3 - vel3_prev;

      //------------------------------------------------------
      // パターン分類 → vel_3ヒストグラムカラー
      //------------------------------------------------------
      int pat;
      if(MathAbs(vel3) < Flat_Thresh)
         pat = 3;  // FLAT
      else if(vel3 > Expand_Thresh && accel > 0)
         pat = 1;  // EXPANDING
      else if(vel3 > 0 && accel > 0)
         pat = 2;  // RISING_ACCEL
      else if(vel3 > 0 && accel <= 0)
         pat = 0;  // RISING_DECEL
      else if(vel3 < 0 && accel < 0)
         pat = 4;  // CONTRACTING
      else
         pat = 5;  // CONTRACTING_SLOW

      BufVel[i]      = vel3;
      BufVelColor[i] = pat;  // 0-5がそのままカラーインデックス

      //------------------------------------------------------
      // H1 ADX → ゾーン別カラー
      //------------------------------------------------------
      int adz = (h1_adx < 20) ? 0 : (h1_adx < 30) ? 1 : 2;
      BufADX[i]      = h1_adx;
      BufADXColor[i] = adz;

      // ADX velocity
      double adx_prev = (i >= ADX_Vel_Bars) ? adx_m[i - ADX_Vel_Bars] : h1_adx;
      double adx_vel  = (adx_prev > 0) ? (h1_adx - adx_prev) / adx_prev * 100.0 : 0;
      BufADXVel[i] = adx_vel;

      //------------------------------------------------------
      // H4 ADX取得
      //------------------------------------------------------
      double h4_adx = 0, h4_dip = 0, h4_din = 0, h4_adx_prev = 0;
      datetime bar_time[1];
      // 現在バーの時刻からH4バーのインデックスを取得
      if(CopyTime(_Symbol, PERIOD_CURRENT, i, 1, bar_time) == 1)
      {
         int h4_idx = iBarShift(_Symbol, PERIOD_H4, bar_time[0], false);
         if(h4_idx >= 0)
         {
            double b0[1], b1[1], b2[1], bp[1];
            ArraySetAsSeries(b0,true); ArraySetAsSeries(b1,true);
            ArraySetAsSeries(b2,true); ArraySetAsSeries(bp,true);
            if(CopyBuffer(hADX_H4, 0, h4_idx, 1, b0) > 0) h4_adx  = b0[0];
            if(CopyBuffer(hADX_H4, 1, h4_idx, 1, b1) > 0) h4_dip  = b1[0];
            if(CopyBuffer(hADX_H4, 2, h4_idx, 1, b2) > 0) h4_din  = b2[0];
            int ph4 = h4_idx + 3;
            if(CopyBuffer(hADX_H4, 0, ph4, 1, bp) > 0)    h4_adx_prev = bp[0];
         }
      }

      if(h4_adx > 0)
      {
         // スケール調整してプロット（H1ADXと視覚的に並べやすく）
         BufH4ADX[i]  = h4_adx * H4_ADX_Scale;
         int h4z = (h4_adx < 20) ? 0 : (h4_adx < 30) ? 1 : 2;
         BufH4Color[i] = h4z;
      }

      //------------------------------------------------------
      // H4 ADX velocity（目覚め判定用）
      //------------------------------------------------------
      double h4_vel = (h4_adx_prev > 0) ?
                      (h4_adx - h4_adx_prev) / h4_adx_prev * 100.0 : 0;
      bool h4_up    = (h4_dip > h4_din);
      bool h1_up    = (h1_dip > h1_din);
      double spread = h1_dip - h1_din;

      //------------------------------------------------------
      // シグナルドット判定（優先度順）
      //------------------------------------------------------
      // PatD: 爆発前夜（H4目覚め × EXPANDING × NORMAL）
      bool isPatD = (h4_adx > 0) && (h4_adx < 20) && (h4_vel > 6) &&
                    h4_up && (zone == 1) &&
                    (pat == 1 || (pat == 2 && vel3 > 3)) &&  // EXPANDING or RISING_ACCEL
                    (h1_adx >= 18);

      // PatA: 長期化サイン（RISING_DECEL × vel3 8-15% × H4ADXじわ上昇 × NORMAL × H1 MID × UP）
      bool isPatA = (pat == 0) &&
                    (vel3 >= 8.0) && (vel3 <= 15.0) &&
                    (h4_vel > 3.0) && h4_up &&
                    (zone == 1) && h1_up &&
                    (h1_adx >= 20) && (h1_adx < 36);

      // スウィートスポット（RISING_DECEL × NORMAL × ADX MID × H1UP）
      bool isSweet = (pat == 0) && (zone == 1) &&
                     (h1_adx >= ADX_Entry_Level) && (h1_adx < ADX_Caution_Level + 5) &&
                     h1_up && (spread > 2.0);

      if(isPatA)
      {
         BufSig[i]      = h1_adx + 4.0;
         BufSigColor[i] = COL_SIG_PATA;
      }
      else if(isPatD)
      {
         BufSig[i]      = h1_adx + 6.0;
         BufSigColor[i] = COL_SIG_PATD;
      }
      else if(isSweet)
      {
         BufSig[i]      = h1_adx + 2.0;
         BufSigColor[i] = COL_SIG_SWEET;
      }

      //------------------------------------------------------
      // 最新バーのみ: 背景色・ラベル・アラート
      //------------------------------------------------------
      if(i == rates_total - 1)
      {
         if(Show_ZoneBG) DrawZoneBG(zone);
         if(Show_PatternLabel)
            UpdatePatternLabel(zone, pat, h1_adx, adz, vel3, accel,
                               h4_adx, h4_vel, h4_up, h1_up,
                               isPatA, isPatD, isSweet, vs, time[i]);

         // アラート
         if(Alert_SweetSpot && isPatA)
         {
            datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
            if(bt != LastAlertSweet)
            {
               LastAlertSweet = bt;
               Alert(StringFormat(
                  "[AVR2] ◆ PatA 長期化サイン %s\n"
                  "vel3=%.1f%% | ADX=%.1f | H4ADX=%.1f(+%.1f%%)",
                  _Symbol, vel3, h1_adx, h4_adx, h4_vel));
            }
         }
         if(Alert_PatD && isPatD)
         {
            datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
            if(bt != LastAlertD)
            {
               LastAlertD = bt;
               Alert(StringFormat(
                  "[AVR2] ★ PatD 爆発前夜 %s\n"
                  "H4ADX=%.1f(+%.1f%%) | vel3=%.1f%% | H1ADX=%.1f\n"
                  "→ PatA出現まで中央値3本",
                  _Symbol, h4_adx, h4_vel, vel3, h1_adx));
            }
         }
         if(Alert_ADX_Cross && i >= 1)
         {
            if(adx_m[i-1] < ADX_Entry_Level && h1_adx >= ADX_Entry_Level)
            {
               datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
               if(bt != LastAlertCross)
               {
                  LastAlertCross = bt;
                  string dir = h1_up ? "UP ↑" : "DOWN ↓";
                  Alert(StringFormat(
                     "[AVR2] ADX20クロス %s\n"
                     "ゾーン:%s | DI:%s | vel3:%.1f%% | Pat:%s",
                     _Symbol, ZoneName(zone), dir, vel3, PatternName(pat)));
               }
            }
         }
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| ATR動的中央値計算                                                  |
//+------------------------------------------------------------------+
double CalcATRMedian(const double &atr[], int idx, int bars)
{
   int start = idx - bars;
   if(start < 0) start = 0;
   int cnt = idx - start;
   if(cnt < 10) return 0;
   double tmp[];
   ArrayResize(tmp, cnt);
   int n = 0;
   for(int k = start; k < idx; k++)
      if(atr[k] > 0) tmp[n++] = atr[k];
   if(n < 5) return 0;
   ArrayResize(tmp, n);
   ArraySort(tmp);
   return tmp[n / 2];
}

//+------------------------------------------------------------------+
//| 水平線描画                                                         |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr,
               ENUM_LINE_STYLE style, int width, string tip)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, ChartWindowFind(), 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   if(tip != "") ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

//+------------------------------------------------------------------+
//| ゾーン背景色（メインチャート）※背景色変更は無効化                   |
//+------------------------------------------------------------------+
void DrawZoneBG(int zone)
{
   // 背景色変更は無効化（チャートの元の背景色を維持）
   // ChartSetInteger(0, CHART_COLOR_BACKGROUND, bg); // ← 無効化

   string on = ObjPrefix + "ZoneText";
   if(ObjectFind(0, on) < 0)
      ObjectCreate(0, on, OBJ_LABEL, 0, 0, 0);

   color zc; string zt;
   switch(zone)
   {
      case 0: zc=0x4ADE80; zt="◼ LOW";    break;
      case 2: zc=0xF97316; zt="◼ HIGH";   break;
      default:zc=0x00D4FF; zt="◼ NORMAL"; break;
   }
   ObjectSetInteger(0, on, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, on, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, on, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, on, OBJPROP_COLOR,     zc);
   ObjectSetInteger(0, on, OBJPROP_FONTSIZE,  11);
   ObjectSetString( 0, on, OBJPROP_FONT,      "Arial Bold");
   ObjectSetString( 0, on, OBJPROP_TEXT,      zt);
   ObjectSetInteger(0, on, OBJPROP_SELECTABLE,false);
}

//+------------------------------------------------------------------+
//| パターン情報ラベル（メインチャート右上）                             |
//+------------------------------------------------------------------+
void UpdatePatternLabel(int zone, int pat,
                        double h1_adx, int adz,
                        double vel3, double accel,
                        double h4_adx, double h4_vel,
                        bool h4_up, bool h1_up,
                        bool isPatA, bool isPatD, bool isSweet,
                        double vs, datetime t)
{
   string on = ObjPrefix + "PatLabel";
   if(ObjectFind(0, on) < 0)
      ObjectCreate(0, on, OBJ_LABEL, 0, 0, 0);

   string adz_str = (adz==0)?"LOW":(adz==1)?"MID★":"HIGH";
   string h4z_str = (h4_adx<20)?"LOW":(h4_adx<30)?"MID":"HIGH";
   string h4v_str = (h4_adx<20 && h4_vel>6) ? " ★目覚め!" : "";
   string dir_h1  = h1_up ? "UP ↑" : "DOWN ↓";
   string dir_h4  = h4_up ? "UP ↑" : "DOWN ↓";

   string sigline = isPatA ? "◆ PatA 長期化サイン" :
                    isPatD ? "★ PatD 爆発前夜" :
                    isSweet? "● SweetSpot"     : "";

   string txt = StringFormat(
      "%s%s\n"
      "──────────────\n"
      "Pat  : %s\n"
      "vel_3: %+.1f%%  accel: %+.1f\n"
      "H1ADX: %.1f [%s]  %s\n"
      "──────────────\n"
      "H4ADX: %.1f [%s]%s\n"
      "H4vel: %+.1f%%  DI: %s\n"
      "Zone : %s (vs %.2f)",
      sigline, (sigline!="") ? "\n" : "",
      PatternName(pat),
      vel3, accel,
      h1_adx, adz_str, dir_h1,
      h4_adx, h4z_str, h4v_str,
      h4_vel, dir_h4,
      ZoneName(zone), vs
   );

   color lc = isPatA ? 0xFFD700 :
              isPatD ? 0xFF00FF :
              isSweet? 0x00D4FF :
              (pat==0 && zone==1) ? 0x5EEAD4 :
              (pat==1)            ? 0xA78BFA :
              (pat==4)            ? 0xF87171 : 0x94A3B8;

   ObjectSetInteger(0, on, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, on, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, on, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, on, OBJPROP_COLOR,     lc);
   ObjectSetInteger(0, on, OBJPROP_FONTSIZE,  9);
   ObjectSetString( 0, on, OBJPROP_FONT,      "Courier New");
   ObjectSetString( 0, on, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, on, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, on, OBJPROP_SELECTABLE,false);
}

//+------------------------------------------------------------------+
string ZoneName(int zone)
{
   switch(zone){ case 0: return "LOW"; case 2: return "HIGH"; default: return "NORMAL"; }
}

string PatternName(int pat)
{
   switch(pat)
   {
      case 0: return "RISING_DECEL ★";
      case 1: return "EXPANDING";
      case 2: return "RISING_ACCEL";
      case 3: return "FLAT";
      case 4: return "CONTRACTING";
      case 5: return "CONTRACTING_SLOW";
      default:return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
