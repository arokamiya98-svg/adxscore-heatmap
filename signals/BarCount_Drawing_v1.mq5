//+------------------------------------------------------------------+
//|  BarCount_Drawing_v1.mq5                                         |
//|  シンプル ローソク足カウント描画ツール                              |
//|                                                                  |
//|  仕様：                                                            |
//|    - チャート上を2点クリック → ラインを引いて本数表示              |
//|    - CSVなどへの保存は一切なし（純粋な表示専用）                   |
//|    - インジ再起動でもラインは保持（テンプレ保存可能）              |
//|    - 上限なし、何本でも引ける                                       |
//|                                                                  |
//|  操作：                                                            |
//|    1点目クリック → 「始点をセットしました」とログ表示              |
//|    2点目クリック → ライン描画 + 本数を中央に表示                   |
//|                                                                  |
//|  リセット：                                                         |
//|    F12キー（or リセットボタン）で1点目をキャンセル                 |
//|    ラインは右クリック→削除で個別削除（普通のtrendline同様）       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| 入力パラメータ（最小限）                                            |
//+------------------------------------------------------------------+
input color   Line_Color  = clrDodgerBlue;
input int     Line_Width  = 2;
input color   Text_Color  = clrWhite;
input int     Text_Size   = 12;
input string  Text_Font   = "Arial Bold";
input bool    Show_OnOff_Button = true;  // ON/OFFボタン表示

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
string LINE_PREFIX = "BCD_LINE_";
string TEXT_PREFIX = "BCD_TXT_";
string BTN_NAME    = "BCD_TOGGLE_BTN";

bool     g_has_first_click = false;
datetime g_first_time      = 0;
double   g_first_price     = 0;
bool     g_enabled         = true;  // ON/OFFトグル

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "BarCount_Drawing_v1");

   // チャートクリック検知
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE,    false);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, false);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);

   // ON/OFFボタン作成
   if(Show_OnOff_Button) CreateToggleButton();

   Print("[BarCount] 起動。チャート上を2点クリックで本数表示。");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // インジ削除時のみボタンを消す（ラインは保持）
   if(reason == REASON_REMOVE)
   {
      ObjectDelete(0, BTN_NAME);
      ChartRedraw();
   }
   // ★重要：ラインとテキストは消さない！再起動で消えないようにする
   // あろさんが手動で右クリック削除する想定
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
   return rates_total;
}

//+------------------------------------------------------------------+
//| ON/OFFボタン作成                                                   |
//+------------------------------------------------------------------+
void CreateToggleButton()
{
   if(ObjectFind(0, BTN_NAME) >= 0) return;

   ObjectCreate(0, BTN_NAME, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_XSIZE,     90);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_YSIZE,     24);
   ObjectSetString (0, BTN_NAME, OBJPROP_TEXT,      "Count: ON");
   ObjectSetInteger(0, BTN_NAME, OBJPROP_BGCOLOR,   clrSeaGreen);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_FONTSIZE,  9);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_SELECTABLE,false);
}

//+------------------------------------------------------------------+
//| ON/OFFボタン状態更新                                               |
//+------------------------------------------------------------------+
void UpdateButton()
{
   if(g_enabled)
   {
      ObjectSetString (0, BTN_NAME, OBJPROP_TEXT,    "Count: ON");
      ObjectSetInteger(0, BTN_NAME, OBJPROP_BGCOLOR, clrSeaGreen);
   }
   else
   {
      ObjectSetString (0, BTN_NAME, OBJPROP_TEXT,    "Count: OFF");
      ObjectSetInteger(0, BTN_NAME, OBJPROP_BGCOLOR, clrGray);
   }
   // ボタン押下状態をリセット
   ObjectSetInteger(0, BTN_NAME, OBJPROP_STATE, false);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| チャートイベント                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- ボタンクリック ---
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_NAME)
   {
      g_enabled = !g_enabled;
      // ボタンON/OFF切替時は1点目もリセット
      g_has_first_click = false;
      UpdateButton();
      Print("[BarCount] ", g_enabled ? "ON" : "OFF");
      return;
   }

   //--- キー入力（F12で1点目キャンセル）---
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 123)  // F12
      {
         if(g_has_first_click)
         {
            g_has_first_click = false;
            Print("[BarCount] 1点目をキャンセル");
         }
      }
      return;
   }

   //--- チャートクリック ---
   if(id == CHARTEVENT_CLICK && g_enabled)
   {
      int sub_window = 0;
      datetime click_time = 0;
      double   click_price = 0;
      if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, sub_window, click_time, click_price))
         return;
      if(sub_window != 0) return;

      // クリックされたバーの時刻に丸める
      int bar_idx = iBarShift(_Symbol, PERIOD_CURRENT, click_time, false);
      if(bar_idx < 0) return;
      datetime bar_time = iTime(_Symbol, PERIOD_CURRENT, bar_idx);

      if(!g_has_first_click)
      {
         // 1点目
         g_first_time      = bar_time;
         g_first_price     = click_price;
         g_has_first_click = true;
         Print("[BarCount] 始点: ", TimeToString(bar_time, TIME_DATE|TIME_MINUTES),
               " (F12で取消)");
      }
      else
      {
         // 2点目 → ライン作成
         datetime t2 = bar_time;
         double   p2 = click_price;

         datetime t1 = g_first_time;
         double   p1 = g_first_price;

         // 時系列順
         if(t1 > t2)
         {
            datetime tmp_t = t1; t1 = t2; t2 = tmp_t;
            double   tmp_p = p1; p1 = p2; p2 = tmp_p;
         }

         CreateLineAndText(t1, p1, t2, p2);
         g_has_first_click = false;
      }
   }

   //--- オブジェクト削除（ラインを消したらテキストも消す）---
   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      if(StringFind(sparam, LINE_PREFIX) == 0)
      {
         string suffix = StringSubstr(sparam, StringLen(LINE_PREFIX));
         string txt_name = TEXT_PREFIX + suffix;
         ObjectDelete(0, txt_name);
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| ライン＋本数テキスト作成                                            |
//+------------------------------------------------------------------+
void CreateLineAndText(datetime t1, double p1, datetime t2, double p2)
{
   // バー本数（始点〜終点を含む）
   int bar1 = iBarShift(_Symbol, PERIOD_CURRENT, t1, false);
   int bar2 = iBarShift(_Symbol, PERIOD_CURRENT, t2, false);
   int bar_count = MathAbs(bar1 - bar2) + 1;

   // ユニークID = 日時ベース（再起動でも重複しない）
   string id_str = StringFormat("%d_%d", (long)t1, (long)t2);
   string line_name = LINE_PREFIX + id_str;
   string text_name = TEXT_PREFIX + id_str;

   // 既に同じIDがあれば削除して上書き
   ObjectDelete(0, line_name);
   ObjectDelete(0, text_name);

   //--- ライン ---
   if(!ObjectCreate(0, line_name, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      Print("[BarCount] ライン作成失敗");
      return;
   }
   ObjectSetInteger(0, line_name, OBJPROP_COLOR,     Line_Color);
   ObjectSetInteger(0, line_name, OBJPROP_WIDTH,     Line_Width);
   ObjectSetInteger(0, line_name, OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0, line_name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, line_name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, line_name, OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0, line_name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, line_name, OBJPROP_HIDDEN,    false);

   //--- 本数テキスト（ライン中央）---
   datetime t_mid = (datetime)((long)t1/2 + (long)t2/2);
   double   p_mid = (p1 + p2) / 2.0;

   if(ObjectCreate(0, text_name, OBJ_TEXT, 0, t_mid, p_mid))
   {
      ObjectSetString (0, text_name, OBJPROP_TEXT,      IntegerToString(bar_count));
      ObjectSetString (0, text_name, OBJPROP_FONT,      Text_Font);
      ObjectSetInteger(0, text_name, OBJPROP_FONTSIZE,  Text_Size);
      ObjectSetInteger(0, text_name, OBJPROP_COLOR,     Text_Color);
      ObjectSetInteger(0, text_name, OBJPROP_ANCHOR,    ANCHOR_CENTER);
      ObjectSetInteger(0, text_name, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, text_name, OBJPROP_BACK,      false);
   }

   ChartRedraw();
   Print("[BarCount] ", bar_count, "本 (", TimeToString(t1, TIME_DATE|TIME_MINUTES),
         " → ", TimeToString(t2, TIME_DATE|TIME_MINUTES), ")");
}

//+------------------------------------------------------------------+
