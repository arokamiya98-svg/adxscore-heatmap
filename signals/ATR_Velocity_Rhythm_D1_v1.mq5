//+------------------------------------------------------------------+
//|  ATR_Velocity_Rhythm_D1_v1.mq5                                   |
//|  日足版 ATR velocity × ADX × H4ADX リアルタイムインジケーター      |
//|                                                                  |
//|  H1版(v2)の構造をD1スケールに移植：                                |
//|    メインTF : D1 → ATR(18), ADX(42)                              |
//|    下位参照 : H4 → ADX(30) （D1の内部リズム確認）                  |
//|    Vel窓   : 8 （H1版の3より長い、日足リズム用）                   |
//|                                                                  |
//|  注意：D1チャートに乗せる前提。PERIOD_CURRENT = D1。               |
//|  H1チャートに乗せても動くが、ATR/ADXがそのTFで再計算される。       |
//|                                                                  |
//|  Output : サブウィンドウ                                          |
//|    Plot0: D1 vel_8 カラーヒストグラム（パターン6色）                |
//|    Plot1: D1 ADX(42) 値ライン（ゾーン別カラー）                    |
//|    Plot2: D1 ADX velocity 点線                                   |
//|    Plot3: H4 ADX(30) 値ライン（スケール調整）                      |
//|    Plot4: シグナルドット                                          |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property indicator_separate_window
#property indicator_minimum  -55
#property indicator_maximum   65

#property indicator_buffers  10
#property indicator_plots     5

//--- Plot 0: vel_N カラーヒストグラム（パターン6色）
#property indicator_label1  "vel_N"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  0x00D4FF,0xA78BFA,0x34D399,0x94A3B8,0xF87171,0xFF9580,0xFFFFFF
//                          RISING_DECEL, EXPANDING, RISING_ACCEL, FLAT, CONTRACTING, CONT_SLOW, UNKNOWN
#property indicator_width1  3
#property indicator_style1  STYLE_SOLID

//--- Plot 1: メインTF ADX値ライン（ゾーン別カラー）
#property indicator_label2  "Main ADX"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  0x94A3B8,0xF0B429,0xF97316
//                          LOW=グレー, MID=ゴールド, HIGH=オレンジ
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

//--- Plot 2: メインTF ADX velocity
#property indicator_label3  "ADX vel"
#property indicator_type3   DRAW_LINE
#property indicator_color3  0xA78BFA
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

//--- Plot 3: 下位TF (H4) ADX値ライン
#property indicator_label4  "Sub ADX (H4)"
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_color4  0x38BDF8,0x0EA5E9,0xF97316
//                          LOW=薄水色, MID=青, HIGH=オレンジ
#property indicator_width4  1
#property indicator_style4  STYLE_SOLID

//--- Plot 4: シグナルドット
#property indicator_label5  "Signal"
#property indicator_type5   DRAW_COLOR_ARROW
#property indicator_color5  0xFF00FF,0xFFD700,0x00D4FF
//                          PatD=マゼンタ, PatA=ゴールド, Sweet=シアン
#property indicator_width5  2

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== ATR設定（D1スケール） ==="
input int    ATR_Period         = 18;     // D1 ATR周期（あろさん指定）
input int    ATR_Median_Window  = 200;    // 動的中央値の窓（D1バー数、約8〜10ヶ月）
input double ATR_Low_Ratio      = 0.70;
input double ATR_High_Ratio     = 1.40;

input group "=== Velocity設定（D1スケール） ==="
input int    Vel_Window         = 8;      // vel計算窓（あろさん指定：vel8）
input double Expand_Thresh      = 10.0;   // ボラ急拡張閾値（%）
input double Flat_Thresh        = 3.0;    // FLAT閾値（%）

input group "=== ADX設定 ==="
input int    Main_ADX_Period    = 42;     // メインTF ADX周期（あろさん指定: D1=42）
input int    Sub_ADX_Period     = 30;     // 下位TF ADX周期（あろさん指定: H4=30）
input ENUM_TIMEFRAMES Sub_TF    = PERIOD_H4;  // 下位TF（D1版ならH4）
input int    ADX_Vel_Bars       = 3;
input double ADX_Entry_Level    = 20.0;
input double ADX_Caution_Level  = 30.0;

input group "=== 下位ADX表示 ==="
input double Sub_ADX_Scale      = 0.7;    // 下位ADXのプロットスケール係数

input group "=== アラート設定 ==="
input bool   Alert_SweetSpot    = true;
input bool   Alert_PatD         = true;
input bool   Alert_ADX_Cross    = true;
input bool   Alert_OnBar        = true;

input group "=== 表示設定 ==="
input bool   Show_ZoneBG        = true;
input bool   Show_PatternLabel  = true;
input bool   Show_ADX_Lines     = true;
input color  Color_LOW_BG       = 0x0D2818;
input color  Color_NORMAL_BG    = 0x071828;
input color  Color_HIGH_BG      = 0x1F0D00;

//+------------------------------------------------------------------+
//| カラーインデックス定数（H1版と共通）                                |
//+------------------------------------------------------------------+
#define COL_VEL_RD      0
#define COL_VEL_EXP     1
#define COL_VEL_RA      2
#define COL_VEL_FLAT    3
#define COL_VEL_CONT    4
#define COL_VEL_CS      5
#define COL_VEL_UNK     6

#define COL_ADX_LOW     0
#define COL_ADX_MID     1
#define COL_ADX_HIGH    2

#define COL_SUB_LOW     0
#define COL_SUB_MID     1
#define COL_SUB_HIGH    2

#define COL_SIG_PATD    0
#define COL_SIG_PATA    1
#define COL_SIG_SWEET   2

//+------------------------------------------------------------------+
//| バッファ宣言                                                       |
//+------------------------------------------------------------------+
double BufVel[];         // vel_N値
double BufVelColor[];    // vel_Nカラーインデックス
double BufADX[];         // メインTF ADX値
double BufADXColor[];    // メインTF ADXカラー
double BufADXVel[];      // メインTF ADX velocity
double BufSubADX[];      // 下位TF ADX値（スケール済み）
double BufSubColor[];    // 下位TF ADXカラー
double BufSig[];         // シグナルドット
double BufSigColor[];    // シグナルカラー
double BufZone[];        // 内部: ゾーン

int hATR_Main, hADX_Main, hADX_Sub;
datetime LastAlertSweet = 0, LastAlertD = 0, LastAlertCross = 0;
string ObjPrefix = "AVR_D1_";

//+------------------------------------------------------------------+
int OnInit()
{
   //--- バッファ割り当て
   SetIndexBuffer(0, BufVel,       INDICATOR_DATA);
   SetIndexBuffer(1, BufVelColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufADX,       INDICATOR_DATA);
   SetIndexBuffer(3, BufADXColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, BufADXVel,    INDICATOR_DATA);
   SetIndexBuffer(5, BufSubADX,    INDICATOR_DATA);
   SetIndexBuffer(6, BufSubColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(7, BufSig,       INDICATOR_DATA);
   SetIndexBuffer(8, BufSigColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(9, BufZone,      INDICATOR_CALCULATIONS);

   //--- 空値
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 矢印コード
   PlotIndexSetInteger(4, PLOT_ARROW, 171);

   //--- ハンドル生成（メインTF = チャートの現TF、下位TFは固定）
   hATR_Main = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   hADX_Main = iADX(_Symbol, PERIOD_CURRENT, Main_ADX_Period);
   hADX_Sub  = iADX(_Symbol, Sub_TF,         Sub_ADX_Period);

   if(hATR_Main==INVALID_HANDLE || hADX_Main==INVALID_HANDLE || hADX_Sub==INVALID_HANDLE)
   {
      Alert("ATR_Velocity_Rhythm_D1: ハンドル生成失敗");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ATR Vel Rhythm D1 [ATR%d Vel%d Main_ADX%d Sub_ADX%d(%s)]",
                   ATR_Period, Vel_Window, Main_ADX_Period, Sub_ADX_Period,
                   EnumToString(Sub_TF)));

   //--- 水平線
   if(Show_ADX_Lines)
   {
      DrawHLine(ObjPrefix+"L20",  ADX_Entry_Level,   0x3B82F6, STYLE_DOT,  1, "ADX 20");
      DrawHLine(ObjPrefix+"L30",  ADX_Caution_Level, 0xF97316, STYLE_DOT,  1, "ADX 30");
      DrawHLine(ObjPrefix+"L0",   0.0,               0x374151, STYLE_SOLID,1, "");
      DrawHLine(ObjPrefix+"SubL20", 20.0 * Sub_ADX_Scale, 0x164E63, STYLE_DOT, 1,
                StringFormat("Sub ADX20 (×%.1f)", Sub_ADX_Scale));
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, 0x1A1A2E);
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
                const int &spread_arr[])
{
   int skip = ATR_Median_Window + Vel_Window * 2 + ADX_Vel_Bars + 10;
   if(rates_total < skip + 5) return 0;

   //--- データ一括取得（古い順 = series:false）
   double atr_arr[], adx_m[], adx_p[], adx_n[];
   ArraySetAsSeries(atr_arr, false);
   ArraySetAsSeries(adx_m,   false);
   ArraySetAsSeries(adx_p,   false);
   ArraySetAsSeries(adx_n,   false);

   if(CopyBuffer(hATR_Main, 0, 0, rates_total, atr_arr) <= 0) return 0;
   if(CopyBuffer(hADX_Main, 0, 0, rates_total, adx_m)   <= 0) return 0;
   if(CopyBuffer(hADX_Main, 1, 0, rates_total, adx_p)   <= 0) return 0;
   if(CopyBuffer(hADX_Main, 2, 0, rates_total, adx_n)   <= 0) return 0;

   int start = (prev_calculated <= skip) ? skip : prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
   {
      //--- 初期化
      BufVel[i]      = 0.0;
      BufADX[i]      = EMPTY_VALUE;
      BufADXVel[i]   = EMPTY_VALUE;
      BufSubADX[i]   = EMPTY_VALUE;
      BufSig[i]      = EMPTY_VALUE;
      BufVelColor[i] = COL_VEL_UNK;
      BufADXColor[i] = COL_ADX_LOW;
      BufSubColor[i] = COL_SUB_LOW;
      BufSigColor[i] = COL_SIG_SWEET;

      double atr     = atr_arr[i];
      double main_adx = adx_m[i];
      double main_dip = adx_p[i];
      double main_din = adx_n[i];
      if(atr <= 0 || main_adx <= 0) continue;

      //------------------------------------------------------
      // ATR動的中央値・ゾーン
      //------------------------------------------------------
      double atr_med = CalcATRMedian(atr_arr, i, ATR_Median_Window);
      if(atr_med <= 0) continue;
      double vs = atr / atr_med;

      int zone = (vs < ATR_Low_Ratio) ? 0 : (vs > ATR_High_Ratio) ? 2 : 1;
      BufZone[i] = zone;

      //------------------------------------------------------
      // ATR velocity & accel（Vel_Window使用）
      //------------------------------------------------------
      double atr_s = (i >= Vel_Window && atr_arr[i-Vel_Window] > 0) ?
                      atr_arr[i-Vel_Window] : atr;
      double velN  = (atr_s > 0) ? (atr - atr_s) / atr_s * 100.0 : 0;

      double velN_prev = 0;
      if(i >= Vel_Window * 2)
      {
         double a1 = atr_arr[i - Vel_Window];
         double a2 = atr_arr[i - Vel_Window * 2];
         if(a2 > 0) velN_prev = (a1 - a2) / a2 * 100.0;
      }
      double accel = velN - velN_prev;

      //------------------------------------------------------
      // パターン分類
      //------------------------------------------------------
      int pat;
      if(MathAbs(velN) < Flat_Thresh)
         pat = 3;  // FLAT
      else if(velN > Expand_Thresh && accel > 0)
         pat = 1;  // EXPANDING
      else if(velN > 0 && accel > 0)
         pat = 2;  // RISING_ACCEL
      else if(velN > 0 && accel <= 0)
         pat = 0;  // RISING_DECEL
      else if(velN < 0 && accel < 0)
         pat = 4;  // CONTRACTING
      else
         pat = 5;  // CONTRACTING_SLOW

      BufVel[i]      = velN;
      BufVelColor[i] = pat;

      //------------------------------------------------------
      // メインTF ADX
      //------------------------------------------------------
      int adz = (main_adx < 20) ? 0 : (main_adx < 30) ? 1 : 2;
      BufADX[i]      = main_adx;
      BufADXColor[i] = adz;

      double adx_prev = (i >= ADX_Vel_Bars) ? adx_m[i - ADX_Vel_Bars] : main_adx;
      double adx_vel  = (adx_prev > 0) ? (main_adx - adx_prev) / adx_prev * 100.0 : 0;
      BufADXVel[i] = adx_vel;

      //------------------------------------------------------
      // 下位TF (Sub_TF) ADX取得
      //------------------------------------------------------
      double sub_adx = 0, sub_dip = 0, sub_din = 0, sub_adx_prev = 0;
      datetime bar_time[1];
      if(CopyTime(_Symbol, PERIOD_CURRENT, i, 1, bar_time) == 1)
      {
         int sub_idx = iBarShift(_Symbol, Sub_TF, bar_time[0], false);
         if(sub_idx >= 0)
         {
            double b0[1], b1[1], b2[1], bp[1];
            ArraySetAsSeries(b0,true); ArraySetAsSeries(b1,true);
            ArraySetAsSeries(b2,true); ArraySetAsSeries(bp,true);
            if(CopyBuffer(hADX_Sub, 0, sub_idx, 1, b0) > 0) sub_adx  = b0[0];
            if(CopyBuffer(hADX_Sub, 1, sub_idx, 1, b1) > 0) sub_dip  = b1[0];
            if(CopyBuffer(hADX_Sub, 2, sub_idx, 1, b2) > 0) sub_din  = b2[0];
            int p_sub = sub_idx + 3;
            if(CopyBuffer(hADX_Sub, 0, p_sub, 1, bp) > 0)   sub_adx_prev = bp[0];
         }
      }

      if(sub_adx > 0)
      {
         BufSubADX[i]  = sub_adx * Sub_ADX_Scale;
         int sz = (sub_adx < 20) ? 0 : (sub_adx < 30) ? 1 : 2;
         BufSubColor[i] = sz;
      }

      //------------------------------------------------------
      // 下位TF ADX velocity
      //------------------------------------------------------
      double sub_vel = (sub_adx_prev > 0) ?
                      (sub_adx - sub_adx_prev) / sub_adx_prev * 100.0 : 0;
      bool sub_up   = (sub_dip > sub_din);
      bool main_up  = (main_dip > main_din);
      double main_spread = main_dip - main_din;

      //------------------------------------------------------
      // シグナルドット判定（H1版と同じロジック、TF名だけ違う）
      //------------------------------------------------------
      bool isPatD = (sub_adx > 0) && (sub_adx < 20) && (sub_vel > 6) &&
                    sub_up && (zone == 1) &&
                    (pat == 1 || (pat == 2 && velN > 3)) &&
                    (main_adx >= 18);

      bool isPatA = (pat == 0) &&
                    (velN >= 8.0) && (velN <= 15.0) &&
                    (sub_vel > 3.0) && sub_up &&
                    (zone == 1) && main_up &&
                    (main_adx >= 20) && (main_adx < 36);

      bool isSweet = (pat == 0) && (zone == 1) &&
                     (main_adx >= ADX_Entry_Level) && (main_adx < ADX_Caution_Level + 5) &&
                     main_up && (main_spread > 2.0);

      if(isPatA)
      {
         BufSig[i]      = main_adx + 4.0;
         BufSigColor[i] = COL_SIG_PATA;
      }
      else if(isPatD)
      {
         BufSig[i]      = main_adx + 6.0;
         BufSigColor[i] = COL_SIG_PATD;
      }
      else if(isSweet)
      {
         BufSig[i]      = main_adx + 2.0;
         BufSigColor[i] = COL_SIG_SWEET;
      }

      //------------------------------------------------------
      // 最新バーのみ: 背景色・ラベル・アラート
      //------------------------------------------------------
      if(i == rates_total - 1)
      {
         if(Show_ZoneBG) DrawZoneBG(zone);
         if(Show_PatternLabel)
            UpdatePatternLabel(zone, pat, main_adx, adz, velN, accel,
                               sub_adx, sub_vel, sub_up, main_up,
                               isPatA, isPatD, isSweet, vs, time[i]);

         if(Alert_SweetSpot && isPatA)
         {
            datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
            if(bt != LastAlertSweet)
            {
               LastAlertSweet = bt;
               Alert(StringFormat(
                  "[AVR_D1] ◆ PatA 長期化サイン %s\n"
                  "vel=%.1f%% | ADX=%.1f | SubADX=%.1f(+%.1f%%)",
                  _Symbol, velN, main_adx, sub_adx, sub_vel));
            }
         }
         if(Alert_PatD && isPatD)
         {
            datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
            if(bt != LastAlertD)
            {
               LastAlertD = bt;
               Alert(StringFormat(
                  "[AVR_D1] ★ PatD 爆発前夜 %s\n"
                  "SubADX=%.1f(+%.1f%%) | vel=%.1f%% | MainADX=%.1f",
                  _Symbol, sub_adx, sub_vel, velN, main_adx));
            }
         }
         if(Alert_ADX_Cross && i >= 1)
         {
            if(adx_m[i-1] < ADX_Entry_Level && main_adx >= ADX_Entry_Level)
            {
               datetime bt = Alert_OnBar ? time[i] : TimeCurrent();
               if(bt != LastAlertCross)
               {
                  LastAlertCross = bt;
                  string dir = main_up ? "UP ↑" : "DOWN ↓";
                  Alert(StringFormat(
                     "[AVR_D1] ADX20クロス %s\n"
                     "Zone:%s | DI:%s | vel:%.1f%% | Pat:%s",
                     _Symbol, ZoneName(zone), dir, velN, PatternName(pat)));
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
//| ゾーン背景色                                                       |
//+------------------------------------------------------------------+
void DrawZoneBG(int zone)
{
   color bg;
   switch(zone)
   {
      case 0: bg = Color_LOW_BG;    break;
      case 2: bg = Color_HIGH_BG;   break;
      default:bg = Color_NORMAL_BG; break;
   }
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, bg);

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
//| パターン情報ラベル                                                  |
//+------------------------------------------------------------------+
void UpdatePatternLabel(int zone, int pat,
                        double main_adx, int adz,
                        double velN, double accel,
                        double sub_adx, double sub_vel,
                        bool sub_up, bool main_up,
                        bool isPatA, bool isPatD, bool isSweet,
                        double vs, datetime t)
{
   string on = ObjPrefix + "PatLabel";
   if(ObjectFind(0, on) < 0)
      ObjectCreate(0, on, OBJ_LABEL, 0, 0, 0);

   string adz_str = (adz==0)?"LOW":(adz==1)?"MID★":"HIGH";
   string sub_str = (sub_adx<20)?"LOW":(sub_adx<30)?"MID":"HIGH";
   string sub_wake = (sub_adx<20 && sub_vel>6) ? " ★目覚め!" : "";
   string dir_main = main_up ? "UP ↑" : "DOWN ↓";
   string dir_sub  = sub_up ? "UP ↑" : "DOWN ↓";

   string sigline = isPatA ? "◆ PatA 長期化サイン" :
                    isPatD ? "★ PatD 爆発前夜" :
                    isSweet? "● SweetSpot"     : "";

   string main_tf_str = EnumToString((ENUM_TIMEFRAMES)_Period);
   string sub_tf_str  = EnumToString(Sub_TF);

   string txt = StringFormat(
      "%s%s"
      "[D1版 ATR%d Vel%d]\n"
      "──────────────\n"
      "Pat   : %s\n"
      "vel_%d: %+.1f%%  accel: %+.1f\n"
      "%s ADX(%d): %.1f [%s]  %s\n"
      "──────────────\n"
      "%s ADX(%d): %.1f [%s]%s\n"
      "Sub vel: %+.1f%%  DI: %s\n"
      "Zone : %s (vs %.2f)",
      sigline, (sigline!="") ? "\n" : "",
      ATR_Period, Vel_Window,
      PatternName(pat),
      Vel_Window, velN, accel,
      main_tf_str, Main_ADX_Period, main_adx, adz_str, dir_main,
      sub_tf_str, Sub_ADX_Period, sub_adx, sub_str, sub_wake,
      sub_vel, dir_sub,
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
