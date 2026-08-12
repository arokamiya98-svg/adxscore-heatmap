//+------------------------------------------------------------------+
//|  Econ_Event_Lines_Forward_v1.mq5                                 |
//|  これから来る米経済指標を「バーの外（未来側）」に縦線で先出しする |
//|                                                                  |
//|  位置づけ: 過去分析版(History)とは別の括り＝現場用フォワードツール |
//|            右のチャートシフト空間に「来る地形」を先に置き、東京場の |
//|            構え（浅め/持ち越さない/見送り）を組むための認知装置。   |
//|            指標≠エントリー。環境として認知に含めるための道具。     |
//|  Tier    : EVENT_VOLATILITY_RANKING_v1.md の実測ボラ順（全Tier）  |
//|  データ  : MT5内蔵カレンダーの“予定”（未来イベント・予想値付き）  |
//|  更新    : OnTimerで定期再描画。過ぎたイベントは自動で落ちる。     |
//|  注意    : 未来外挿は取引時間ベース→週末跨ぎは数バーずれ得る(許容)。|
//+------------------------------------------------------------------+
#property copyright "ARO"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

input int      InpDaysAhead     = 3;      // 何日先まで先出しするか（元構想=直近3日）
input bool     InpShowTierS      = true;  // NFP/CPI/FOMC
input bool     InpShowTierA      = true;  // PPI/小売/GDP/PCE/ADP/PMI
input bool     InpShowTierB      = true;  // ISM（全部盛り）
input bool     InpShowLabel      = true;  // 指標名ラベル
input bool     InpShowValue      = false; // 予想値/前回値（発表前なので Actual は無い）
input bool     InpForceChartShift= true;  // 右に未来空間を確保（フォワード表示に必須）
input int      InpRefreshMin     = 30;    // 自動更新間隔（分）

const string PFX = "FWDEVT_";

//--- EventName → Tier(3=S/2=A/1=B/0=対象外) と グループ名（History版と同一辞書）---
int ClassifyTier(const string nm, string &grp)
{
   if(nm=="Nonfarm Payrolls"){ grp="NFP"; return 3; }
   if(nm=="CPI" || nm=="CPI m/m" || nm=="CPI y/y"){ grp="CPI"; return 3; }
   if(nm=="Fed Interest Rate Decision"){ grp="FOMC"; return 3; }
   if(nm=="PPI m/m" || nm=="PPI y/y"){ grp="PPI"; return 2; }
   if(nm=="Retail Sales m/m" || nm=="Core Retail Sales m/m"){ grp="RETAIL"; return 2; }
   if(nm=="GDP q/q" || nm=="GDP Price Index q/q" || nm=="GDP Sales q/q"){ grp="GDP"; return 2; }
   if(nm=="Core PCE Price Index m/m" || nm=="PCE Price Index m/m"){ grp="PCE"; return 2; }
   if(nm=="ADP Nonfarm Employment Change"){ grp="ADP"; return 2; }
   if(nm=="S&P Global Manufacturing PMI" || nm=="S&P Global Services PMI" || nm=="S&P Global Composite PMI"){ grp="PMI"; return 2; }
   if(nm=="ISM Non-Manufacturing PMI"){ grp="ISM-Svc"; return 1; }
   if(nm=="ISM Manufacturing PMI"){ grp="ISM-Mfg"; return 1; }
   grp=""; return 0;
}

void BuildLines()
{
   ObjectsDeleteAll(0, PFX);

   MqlCalendarValue values[];
   datetime from = TimeCurrent();                       // 今から（過ぎたイベントは含めない＝自動で落ちる）
   datetime to   = from + (datetime)InpDaysAhead*86400; // N日先まで
   int n = CalendarValueHistory(values, from, to, NULL, "USD");
   if(n <= 0)
   {
      PrintFormat("[FWDEVT] 未来カレンダー取得0 / err=%d（未提供 or 予定なし）", GetLastError());
      return;
   }

   int drawn = 0;
   for(int i=0; i<n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;

      string grp; int tier = ClassifyTier(ev.name, grp);
      if(tier==0) continue;
      if(tier==3 && !InpShowTierS) continue;
      if(tier==2 && !InpShowTierA) continue;
      if(tier==1 && !InpShowTierB) continue;

      datetime vt = values[i].time;
      string key = PFX + grp + "_" + IntegerToString((long)vt);  // 同グループ同時刻＝1本化
      if(ObjectFind(0, key) >= 0) continue;

      color col; int wid; ENUM_LINE_STYLE sty;
      if(tier==3){ col=clrDarkOrange;   wid=2; sty=STYLE_SOLID; }
      else if(tier==2){ col=clrGoldenrod; wid=1; sty=STYLE_SOLID; }
      else { col=C'110,110,110'; wid=1; sty=STYLE_DOT; }

      if(!ObjectCreate(0, key, OBJ_VLINE, 0, vt, 0)) continue;  // 未来時刻にも配置可
      ObjectSetInteger(0, key, OBJPROP_COLOR, col);
      ObjectSetInteger(0, key, OBJPROP_WIDTH, wid);
      ObjectSetInteger(0, key, OBJPROP_STYLE, sty);
      ObjectSetInteger(0, key, OBJPROP_BACK, true);
      ObjectSetInteger(0, key, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, key, OBJPROP_HIDDEN, true);

      if(InpShowLabel)
      {
         string lab = grp + " " + TimeToString(vt, TIME_MINUTES);   // 未来は“いつ”が肝→時刻併記
         if(InpShowValue && values[i].HasForecastValue())
         {
            string f = DoubleToString(values[i].GetForecastValue(), 2);
            string p = values[i].HasPreviousValue() ? DoubleToString(values[i].GetPreviousValue(), 2) : "-";
            lab = grp + " " + TimeToString(vt, TIME_MINUTES) + " F:" + f + " P:" + p;
         }
         ObjectSetString(0, key, OBJPROP_TEXT, lab);
      }
      drawn++;
   }
   ChartRedraw();
   PrintFormat("[FWDEVT] 先出し縦線 %d本（今〜%d日先, USD / S/A/B=%s/%s/%s）",
      drawn, InpDaysAhead, InpShowTierS?"on":"off", InpShowTierA?"on":"off", InpShowTierB?"on":"off");
}

int OnInit()
{
   if(InpForceChartShift) ChartSetInteger(0, CHART_SHIFT, true);  // 右に未来空間を確保
   EventSetTimer(InpRefreshMin*60);
   BuildLines();
   return(INIT_SUCCEEDED);
}
void OnTimer(){ BuildLines(); }                                    // 定期再描画（過ぎた分を落とす）
void OnDeinit(const int reason){ EventKillTimer(); ObjectsDeleteAll(0, PFX); ChartRedraw(); }
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &vol[], const int &sp[])
{ return(rates_total); }
//+------------------------------------------------------------------+
