//+------------------------------------------------------------------+
//|  ATR_Ratio_Keltner_v1.mq5                                       |
//|  ATR Ratio 点灯ケルトナー（収束待ち基準 × Ratioゲート可視化）   |
//|                                                                  |
//|  ■ 目的                                                          |
//|    ケルトナーの幅に「ボトムアウトを待つ収束基準値(既定14)」を当て、|
//|    ATR(16)がその基準まで収束したら価格がバンドに収まる＝収束を     |
//|    空間で見る認識ツール。さらに ATR Ratio で高ボラ時はバンドを     |
//|    丸ごと消す（土俵の足切り）。XAUUSD H1 前提。                    |
//|                                                                  |
//|  ■ 二段構成                                                       |
//|    【バンド本体】中心EMA ± band                                   |
//|        band = FIXED_TARGET: TargetATR × Mult（収束待ち基準を幅に） |
//|             = DYNAMIC_ATR : iATR(Width_ATR_Period) × Mult（今の値幅）|
//|    【表示ゲート】UseRatioGate=true のとき                          |
//|        Ratio = iATR(Ratio_ATR_Period) ÷ 直近Ratio_Median_Bars本中央値|
//|        RatioLower ≤ Ratio ≤ RatioUpper のバーだけ描画（外は消す）  |
//|                                                                  |
//|  ■ Ratio定義の一致（カイBT分析と厳密一致）                         |
//|    中央値計算は ATR_WidthSignal_BT_v3bywavelog_gen2.mq5 の         |
//|    CalcMedian 準拠：ATR>0のみ採用 / 有効10本未満は無効 /           |
//|    要素数が偶数なら上側中央値 tmp[cnt/2]。                          |
//|    既定 Ratio_Median_Bars=960 = 8週×5日×24h。                     |
//|                                                                  |
//|  ■ 単位                                                          |
//|    iATR生値は価格単位（XAUで例 ATR16≈18）。換算しない。            |
//|    TargetATR=14 は $14。Mult=2 で 中心±28。                       |
//|                                                                  |
//|  ■ 負荷（Mac非力・CPUバウンド対策）                                |
//|    描画・中央値計算は最新 DrawBars 本のみ。prev_calculated で       |
//|    増分更新（初回 DrawBars本、以降は最新バーのみ引き直し）。        |
//|                                                                  |
//|  ■ 使い方                                                         |
//|    1) MetaEditor で F7 コンパイル（.ex5不可）                      |
//|    2) H1チャートに適用。960本(=H1で約40日)以上の履歴が要る         |
//|       （足りないとゲート判定不可で最新側も消えることがある）        |
//|                                                                  |
//|  ■ 通知（v1.10 追加 / v1.20 でPush主役化）                         |
//|    上/下バンドそれぞれ独立ON/OFF（Alert_Upper / Alert_Lower）。     |
//|    条件: バー高値≧上バンド ▲ / バー安値≦下バンド ▼（タッチ）。     |
//|    ・発火は1バー1回（同一バー内で連打しない）                       |
//|    ・Ratioゲートで消えているバーは鳴らさない（土俵外は沈黙）        |
//|    ・チャート適用/パラメータ変更直後の再計算では鳴らさない          |
//|    ・v1.20: 主経路=スマホPush通知(SendNotification)。VPS無人運用    |
//|      ではAlert()ポップアップは開くまで見えず無意味なため既定OFF     |
//|      （Alert_Popup=trueで復活可）。Push要件: MT5 ツール→オプション  |
//|      →通知タブで MetaQuotes ID 設定＋通知有効化。発火は履歴として   |
//|      エキスパートログ(Print)にも常時残す。                          |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.20"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Plot 0: Upper Band
#property indicator_label1  "KC Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSteelBlue
#property indicator_width1  1
#property indicator_style1  STYLE_SOLID
//--- Plot 1: Lower Band
#property indicator_label2  "KC Lower"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSteelBlue
#property indicator_width2  1
#property indicator_style2  STYLE_SOLID
//--- Plot 2: Center
#property indicator_label3  "KC Center"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGray
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

//+------------------------------------------------------------------+
//| 幅モード                                                          |
//+------------------------------------------------------------------+
enum ENUM_BAND_MODE
{
   FIXED_TARGET = 0,   // 固定（収束待ち基準 TargetATR × Mult）
   DYNAMIC_ATR  = 1    // 動的（現在ATR × Mult）
};

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== 中心線 ==="
input int             EMA_Period       = 32;            // EMA周期

input group "=== バンド幅 ==="
input ENUM_BAND_MODE  BandWidthMode    = FIXED_TARGET;  // 幅モード
input double          TargetATR        = 14.0;          // 固定モード幅（収束待ち基準）
input int             Width_ATR_Period = 16;            // 動的モードATR周期
input double          Mult             = 2.0;           // 幅倍率

input group "=== Ratioゲート（可視化制御）==="
input bool            UseRatioGate     = true;          // Ratioで表示ON/OFF
input int             Ratio_ATR_Period = 16;            // ゲート判定ATR周期
input int             Ratio_Median_Bars= 960;           // 中央値の窓（8週=8*5*24）
input double          RatioLower       = 0.70;          // 表示下限
input double          RatioUpper       = 1.40;          // 表示上限（高ボラ消し）

input group "=== 通知（バンドタッチ→スマホPush）==="
input bool            Alert_Upper      = true;          // 上バンドタッチで通知 ▲
input bool            Alert_Lower      = true;          // 下バンドタッチで通知 ▼
input bool            Alert_Popup      = false;         // Alert()ポップアップも出す（VPS無人では不要）

input group "=== 表示・負荷 ==="
input int             DrawBars         = 500;           // 描画する最新バー数
input bool            ShowRatioLabel   = true;          // 右上ラベル表示
input color           Color_Upper      = C'90,140,180'; // 上バンド色
input color           Color_Lower      = C'90,140,180'; // 下バンド色
input color           Color_Center     = C'120,120,120';// 中心線色

//+------------------------------------------------------------------+
//| バッファ・グローバル                                               |
//+------------------------------------------------------------------+
double BufUpper[], BufLower[], BufCenter[];
int    hEMA, hATR_Ratio, hATR_Width;
string LabelName = "ARK_INFO";
datetime g_lastAlertUpper = 0, g_lastAlertLower = 0;   // 1バー1回の発火記録

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufUpper,  INDICATOR_DATA);
   SetIndexBuffer(1, BufLower,  INDICATOR_DATA);
   SetIndexBuffer(2, BufCenter, INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Color_Upper);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Color_Lower);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, Color_Center);

   hEMA       = iMA (_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR_Ratio = iATR(_Symbol, PERIOD_CURRENT, Ratio_ATR_Period);
   hATR_Width = iATR(_Symbol, PERIOD_CURRENT, Width_ATR_Period);

   if(hEMA==INVALID_HANDLE || hATR_Ratio==INVALID_HANDLE || hATR_Width==INVALID_HANDLE)
   {
      Alert("[ATR_Ratio_Keltner] ハンドル生成失敗");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ATR-R Keltner [EMA%d %s%.1f x%.1f %s%.2f-%.2f]",
         EMA_Period,
         (BandWidthMode==FIXED_TARGET ? "Tgt" : "ATR"),
         (BandWidthMode==FIXED_TARGET ? TargetATR : (double)Width_ATR_Period),
         Mult,
         (UseRatioGate ? "G" : "off"), RatioLower, RatioUpper));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hEMA       != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATR_Ratio != INVALID_HANDLE) IndicatorRelease(hATR_Ratio);
   if(hATR_Width != INVALID_HANDLE) IndicatorRelease(hATR_Width);
   ObjectDelete(0, LabelName);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 中央値（BT CalcMedian 準拠）                                       |
//|   非series配列（index0=最古）で i から過去 bars 本                |
//|   ・ATR>0のみ採用 ・有効10本未満は無効(0) ・偶数は上側中央値       |
//+------------------------------------------------------------------+
double CalcMedianNon(const double &arr[], int i, int bars)
{
   if(i - bars + 1 < 0) return 0.0;
   double tmp[];
   ArrayResize(tmp, bars);
   int cnt = 0;
   for(int k = i - bars + 1; k <= i; k++)
      if(arr[k] > 0.0) tmp[cnt++] = arr[k];
   if(cnt < 10) return 0.0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
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
   if(rates_total < 50) return 0;

   //--- 計算元バッファ（非series＝index0が最古）
   double ema[], atrR[], atrW[];
   if(CopyBuffer(hEMA,       0, 0, rates_total, ema)  <= 0) return prev_calculated;
   if(CopyBuffer(hATR_Ratio, 0, 0, rates_total, atrR) <= 0) return prev_calculated;
   if(BandWidthMode==DYNAMIC_ATR)
      if(CopyBuffer(hATR_Width, 0, 0, rates_total, atrW) <= 0) return prev_calculated;

   //--- 描画範囲（最新 DrawBars 本。ゲートONなら中央値ぶんの履歴を確保）
   int hist_need = UseRatioGate ? Ratio_Median_Bars : 0;
   int begin = rates_total - DrawBars;
   if(begin < hist_need) begin = hist_need;
   if(begin < 0)         begin = 0;

   //--- 初回は全バッファをEMPTYで初期化（範囲外バーを非表示に）
   if(prev_calculated == 0)
   {
      for(int j=0; j<rates_total; j++)
      { BufUpper[j]=EMPTY_VALUE; BufLower[j]=EMPTY_VALUE; BufCenter[j]=EMPTY_VALUE; }
   }

   int start = (prev_calculated <= 1) ? begin : prev_calculated - 1;
   if(start < begin) start = begin;

   double fixed_band = TargetATR * Mult;

   for(int i=start; i<rates_total; i++)
   {
      double band = (BandWidthMode==FIXED_TARGET) ? fixed_band : atrW[i]*Mult;
      if(band <= 0.0)
      { BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE; BufCenter[i]=EMPTY_VALUE; continue; }

      //--- Ratioゲート：レンジ外/履歴不足は3本ともEMPTYで消す
      if(UseRatioGate)
      {
         double med = CalcMedianNon(atrR, i, Ratio_Median_Bars);
         if(med <= 0.0)
         { BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE; BufCenter[i]=EMPTY_VALUE; continue; }
         double ratio = atrR[i] / med;
         if(ratio < RatioLower || ratio > RatioUpper)
         { BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE; BufCenter[i]=EMPTY_VALUE; continue; }
      }

      double c = ema[i];
      BufUpper[i]  = c + band;
      BufLower[i]  = c - band;
      BufCenter[i] = c;
   }

   //--- アラート（最新バーのみ判定・1バー1回）
   if(Alert_Upper || Alert_Lower)
   {
      ArraySetAsSeries(time, false);
      ArraySetAsSeries(high, false);
      ArraySetAsSeries(low,  false);
      if(prev_calculated == 0)
      {
         // 適用直後/パラメータ変更直後の再計算では鳴らさない
         g_lastAlertUpper = time[rates_total-1];
         g_lastAlertLower = time[rates_total-1];
      }
      else
         CheckAlerts(time, high, low, rates_total-1);
   }

   if(ShowRatioLabel)
      UpdateLabel(rates_total, atrR);

   return rates_total;
}

//+------------------------------------------------------------------+
//| バンドタッチアラート                                               |
//|   ゲートで消えているバー（EMPTY_VALUE）は鳴らさない                |
//+------------------------------------------------------------------+
void CheckAlerts(const datetime &time[], const double &high[],
                 const double &low[], int last)
{
   if(last < 0) return;
   if(BufUpper[last] == EMPTY_VALUE || BufLower[last] == EMPTY_VALUE) return;

   string tf = StringSubstr(EnumToString(_Period), 7);   // "PERIOD_H1" → "H1"

   if(Alert_Upper && time[last] != g_lastAlertUpper && high[last] >= BufUpper[last])
   {
      g_lastAlertUpper = time[last];
      string msg = StringFormat("[ATR-R Keltner] %s %s ▲上バンドタッチ High %.1f >= %.1f",
                                _Symbol, tf, high[last], BufUpper[last]);
      Notify(msg);
   }

   if(Alert_Lower && time[last] != g_lastAlertLower && low[last] <= BufLower[last])
   {
      g_lastAlertLower = time[last];
      string msg = StringFormat("[ATR-R Keltner] %s %s ▼下バンドタッチ Low %.1f <= %.1f",
                                _Symbol, tf, low[last], BufLower[last]);
      Notify(msg);
   }
}

//+------------------------------------------------------------------+
//| 通知の実送信（Push主経路・履歴はエキスパートログに常時残す）       |
//+------------------------------------------------------------------+
void Notify(const string msg)
{
   ResetLastError();
   if(!SendNotification(msg))
      Print(msg, "  ※Push送信失敗 err=", GetLastError(),
            "（ツール→オプション→通知 の MetaQuotes ID/有効化を確認）");
   else
      Print(msg, "  (Push送信OK)");
   if(Alert_Popup) Alert(msg);
}

//+------------------------------------------------------------------+
//| 右上ラベル（現在Ratioとゲート状態 IN/OUT）                         |
//+------------------------------------------------------------------+
void UpdateLabel(int rates_total, const double &atrR[])
{
   int last = rates_total - 1;
   if(last < 0) return;

   double med   = (UseRatioGate) ? CalcMedianNon(atrR, last, Ratio_Median_Bars) : 0.0;
   double ratio = (med > 0.0) ? atrR[last]/med : 0.0;
   bool   shown = (!UseRatioGate) || (med > 0.0 && ratio >= RatioLower && ratio <= RatioUpper);

   if(ObjectFind(0, LabelName) < 0)
   {
      ObjectCreate(0, LabelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, LabelName, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LabelName, OBJPROP_XDISTANCE,  10);
      ObjectSetInteger(0, LabelName, OBJPROP_YDISTANCE,  18);
      ObjectSetInteger(0, LabelName, OBJPROP_FONTSIZE,   9);
      ObjectSetString( 0, LabelName, OBJPROP_FONT,       "Courier New");
      ObjectSetInteger(0, LabelName, OBJPROP_ANCHOR,     ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, LabelName, OBJPROP_SELECTABLE, false);
   }

   string gate = (!UseRatioGate) ? "GATE OFF"
                 : (shown ? StringFormat("IN  R=%.2f", ratio)
                          : StringFormat("OUT R=%.2f", ratio));
   color  lc   = (!UseRatioGate) ? C'150,150,150'
                 : (shown ? C'90,200,150' : C'200,120,120');

   ObjectSetInteger(0, LabelName, OBJPROP_COLOR, lc);
   ObjectSetString(0, LabelName, OBJPROP_TEXT,
      StringFormat("ATR-R Keltner | %s | %s%.1f x%.1f",
         gate,
         (BandWidthMode==FIXED_TARGET ? "Tgt" : "ATR"),
         (BandWidthMode==FIXED_TARGET ? TargetATR : (double)Width_ATR_Period),
         Mult));
   ChartRedraw();
}
//+------------------------------------------------------------------+
