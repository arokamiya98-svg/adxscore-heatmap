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
//|  ■ 通知（v1.10 追加 / v1.20 Push主役化 / v1.30 タッチ＝エッジ検出）|
//|    上/下バンドそれぞれ独立ON/OFF（Alert_Upper / Alert_Lower）。     |
//|    v1.30: 「バンド外に居る状態」でなく「内側→接触の遷移」で発火。   |
//|    ・現在値(tick)がバンドに触れた瞬間に1回だけ通知                  |
//|    ・以降は価格がバンド内側へ ReArm_Dist($)戻るまで再武装しない     |
//|      ＝外側に居座っても毎バー再発火しない（旧版はこれがクロス       |
//|      オーバー的な連打の原因）。境界チャタリングもこれで抑止         |
//|    ・保険で同一バー内は最大1回/側                                   |
//|    ・Ratioゲートで消えているバーは鳴らさない（土俵外は沈黙）        |
//|    ・チャート適用/パラメータ変更直後の再計算では鳴らさない          |
//|    ・主経路=スマホPush通知(SendNotification)。Alert()ポップアップ   |
//|      は既定OFF（VPS無人では開くまで見えない）。Push要件: MT5        |
//|      ツール→オプション→通知タブの MetaQuotes ID＋有効化。発火と     |
//|      Push成否はエキスパートログ(Print)に常時残す。                  |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.30"
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
input double          ReArm_Dist       = 3.0;           // 再武装距離$（内側へ戻る深さ。次のタッチ許可条件）
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
datetime g_lastAlertUpper = 0, g_lastAlertLower = 0;   // 1バー1回の発火記録（保険）
bool     g_upTouched = false, g_dnTouched = false;     // タッチ滞在中フラグ（エッジ検出用）

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

   //--- 通知（現在値のエッジ検出＝内側→接触の遷移だけ拾う）
   if(Alert_Upper || Alert_Lower)
   {
      ArraySetAsSeries(time,  false);
      ArraySetAsSeries(close, false);
      int last = rates_total - 1;
      if(prev_calculated == 0)
      {
         // 適用直後/パラメータ変更直後は鳴らさず、現在の位置関係で初期化
         // （既に外側に居るなら「タッチ滞在中」から開始＝居座り発火を防ぐ）
         g_lastAlertUpper = time[last];
         g_lastAlertLower = time[last];
         bool bandOK = (BufUpper[last] != EMPTY_VALUE && BufLower[last] != EMPTY_VALUE);
         g_upTouched = bandOK && (close[last] >= BufUpper[last]);
         g_dnTouched = bandOK && (close[last] <= BufLower[last]);
      }
      else
         CheckAlerts(time, close, last);
   }

   if(ShowRatioLabel)
      UpdateLabel(rates_total, atrR);

   return rates_total;
}

//+------------------------------------------------------------------+
//| バンドタッチ通知（エッジ検出）                                     |
//|   発火: 非タッチ状態 → 現在値がバンド接触 の遷移の瞬間だけ          |
//|   再武装: バンド内側へ ReArm_Dist($) 戻ったら次のタッチを許可       |
//|   ゲートで消えているバー（EMPTY_VALUE）は判定ごと凍結              |
//+------------------------------------------------------------------+
void CheckAlerts(const datetime &time[], const double &close[], int last)
{
   if(last < 0) return;
   if(BufUpper[last] == EMPTY_VALUE || BufLower[last] == EMPTY_VALUE) return;

   string tf = StringSubstr(EnumToString(_Period), 7);   // "PERIOD_H1" → "H1"
   double px = close[last];                              // 進行中バーの現在値

   if(Alert_Upper)
   {
      if(!g_upTouched && px >= BufUpper[last])
      {
         g_upTouched = true;
         if(time[last] != g_lastAlertUpper)   // 保険: 同一バー内は1回まで
         {
            g_lastAlertUpper = time[last];
            Notify(StringFormat("[ATR-R Keltner] %s %s ▲上バンドタッチ %.1f (band %.1f)",
                                _Symbol, tf, px, BufUpper[last]));
         }
      }
      else if(g_upTouched && px <= BufUpper[last] - ReArm_Dist)
         g_upTouched = false;                 // 内側へ十分戻った → 再武装
   }

   if(Alert_Lower)
   {
      if(!g_dnTouched && px <= BufLower[last])
      {
         g_dnTouched = true;
         if(time[last] != g_lastAlertLower)
         {
            g_lastAlertLower = time[last];
            Notify(StringFormat("[ATR-R Keltner] %s %s ▼下バンドタッチ %.1f (band %.1f)",
                                _Symbol, tf, px, BufLower[last]));
         }
      }
      else if(g_dnTouched && px >= BufLower[last] + ReArm_Dist)
         g_dnTouched = false;
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
