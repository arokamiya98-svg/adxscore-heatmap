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
#property version   "1.20"
#property indicator_chart_window
#property indicator_plots 0
// v1.10 (2026-08-12): イベント名の表記揺れ対策で分類を部分一致(StringFind)へ。InpDebug追加。
// v1.11 (2026-08-12): CHART_SHIFTはON/OFFのみでシフト幅%(CHART_SHIFT_SIZE)は別物・
//   既定20%=表示バー本数依存のため、表示本数から逆算して明示指定＋ズーム時に追従。
// v1.20 (2026-08-12): ★分類をイベント名→**EventID**へ変更（VPS実測で確定した恒久対応）。
//   VPSはMT5のUIが日本語＝カレンダーAPIが日本語名を返す（"小売売上高前月比"等）。
//   英単語ベースの名前判定は全滅し、"CPI"/"PPI"等の英字略語だけが偶然マッチしていた
//   （＝「TierSしか出ない」の正体）。加えて "クリーブランドFed中央値CPI前月比" が
//   TierS扱いで誤描画されていた。IDはMetaQuotes共通でUI言語に非依存＝両方を同時に解消。
//   ID出典: data/bt/Econ_Calendar_US_History.csv の EventID列。

input int      InpDaysAhead     = 3;      // 何日先まで先出しするか（元構想=直近3日）
input bool     InpShowTierS      = true;  // NFP/CPI/FOMC
input bool     InpShowTierA      = true;  // PPI/小売/GDP/PCE/ADP/PMI
input bool     InpShowTierB      = true;  // ISM（全部盛り）
input bool     InpShowLabel      = true;  // 指標名ラベル
input bool     InpShowValue      = false; // 予想値/前回値（発表前なので Actual は無い）
input bool     InpForceChartShift= true;  // 右に未来空間を確保（フォワード表示に必須）
input int      InpRefreshMin     = 30;    // 自動更新間隔（分）
input bool     InpDebug          = false; // 取得した全イベントの実名をログ出力（診断用）

const string PFX = "FWDEVT_";

// 未来空間の幅を表示バー本数から逆算して明示指定（ズーム状態に依らずN日分を確保）。
void UpdateShiftSize()
{
   if(!InpForceChartShift) return;
   int visible = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   long periodSec = PeriodSeconds();
   if(visible <= 0 || periodSec <= 0) return;

   double barsPerDay = 86400.0 / periodSec;
   double neededBars = InpDaysAhead * barsPerDay;
   double pct = neededBars / visible * 100.0;
   pct = MathMax(10.0, MathMin(50.0, pct));  // CHART_SHIFT_SIZEの許容域
   ChartSetDouble(0, CHART_SHIFT_SIZE, pct);
}

//--- EventID → Tier(3=S/2=A/1=B/0=対象外) と グループ名 ---
//    IDはMetaQuotesカレンダー共通＝端末のUI言語に依存しない。
//    IDは data/bt/Econ_Calendar_US_History.csv（EventID列）から採取。
int ClassifyTier(const ulong id, string &grp)
{
   switch(id)
   {
      // ── Tier S ──
      case 840030016: grp="NFP";  return 3;  // Nonfarm Payrolls
      case 840030005:                        // CPI m/m
      case 840030007:                        // CPI y/y
      case 840030035: grp="CPI";  return 3;  // CPI
      case 840050014: grp="FOMC"; return 3;  // Fed Interest Rate Decision

      // ── Tier A ──
      case 840030001:                        // PPI m/m
      case 840030003: grp="PPI";    return 2;// PPI y/y
      case 840020010:                        // Retail Sales m/m
      case 840020011: grp="RETAIL"; return 2;// Core Retail Sales m/m
      case 840010007: grp="GDP";    return 2;// GDP q/q
      case 840010001:                        // Core PCE Price Index m/m
      case 840010003: grp="PCE";    return 2;// PCE Price Index m/m
      case 840190001: grp="ADP";    return 2;// ADP Nonfarm Employment Change
      case 840500001:                        // S&P Global Manufacturing PMI
      case 840500002:                        // S&P Global Services PMI
      case 840500003: grp="PMI";    return 2;// S&P Global Composite PMI

      // ── Tier B ──
      case 840040001: grp="ISM-Mfg"; return 1;// ISM Manufacturing PMI
      case 840040003: grp="ISM-Svc"; return 1;// ISM Non-Manufacturing PMI
   }
   grp=""; return 0;
}

void BuildLines()
{
   UpdateShiftSize();
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
      bool hasEv = CalendarEventById(values[i].event_id, ev);  // 名前は診断表示用（分類はIDのみで完結）

      string grp; int tier = ClassifyTier(values[i].event_id, grp);
      if(InpDebug)
         PrintFormat("[FWDEVT-DBG] %s | id=%I64u name=\"%s\" | tier=%d grp=%s",
            TimeToString(values[i].time, TIME_DATE|TIME_MINUTES), values[i].event_id,
            hasEv ? ev.name : "(名称取得不可)", tier, grp);
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
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE) UpdateShiftSize();  // ズーム/スクロール直後に幅を追従
}
void OnDeinit(const int reason){ EventKillTimer(); ObjectsDeleteAll(0, PFX); ChartRedraw(); }
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &vol[], const int &sp[])
{ return(rates_total); }
//+------------------------------------------------------------------+
