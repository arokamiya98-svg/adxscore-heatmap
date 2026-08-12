//+------------------------------------------------------------------+
//|  Econ_Event_Lines_History_v1.mq5                                 |
//|  過去の米経済指標を「ボラTier別の縦線」で表示する分析用インジ    |
//|                                                                  |
//|  位置づけ: フォワード表示版とは別の括り＝過去・全表示・相場分析用 |
//|            「指標＝エントリー」ではなく、発表後の値動きの挙動／    |
//|            ATRバンドとの絡み／数時間の流れを遡って目視するための道具。|
//|  Tier    : EVENT_VOLATILITY_RANKING_v1.md の実測ボラ順            |
//|            S=NFP/CPI/FOMC  A=PPI/小売/GDP/PCE/ADP/PMI  B=ISM      |
//|  データ  : MT5内蔵カレンダー（サーバー時間＝価格と同一系→位置正確）|
//|  色      : 方向中立のゴールド系グラデ（青/赤=DI方向色と非衝突）    |
//|                                                                  |
//|  使い方  : MetaEditorでF7コンパイル → XAUUSDチャートにドラッグ。   |
//|            ATRバンド系インジと重ねて見るのが本来の用途。          |
//+------------------------------------------------------------------+
#property copyright "ARO"
#property version   "1.10"
#property indicator_chart_window
#property indicator_plots 0
// v1.10 (2026-08-12): 分類をイベント名→**EventID**へ（Forward v1.20と同じ恒久対応）。
//   端末のUI言語で名前が変わる（VPS=日本語）ため、名前一致は言語依存で壊れる。
//   IDはMetaQuotes共通。出典: data/bt/Econ_Calendar_US_History.csv の EventID列。

input datetime InpFrom      = D'2024.01.01 00:00'; // 表示開始（重ければ後ろへ）
input bool     InpShowTierS = true;                // NFP/CPI/FOMC
input bool     InpShowTierA = true;                // PPI/小売/GDP/PCE/ADP/PMI
input bool     InpShowTierB = true;                // ISM（実測で弱い＝薄）
input bool     InpShowLabel = true;                // 指標名ラベル
input bool     InpShowValue = false;               // 実際値/予想も出す（サプライズ検証）
input int      InpMaxLines  = 800;                 // 縦線上限（Macの負荷配慮）

const string PFX = "EEL_";

//--- EventID → Tier(3=S/2=A/1=B/0=対象外) と グループ名（Forward版と同一辞書）---
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
   ObjectsDeleteAll(0, PFX);

   MqlCalendarValue values[];
   datetime to = TimeCurrent();                       // 過去のみ（未来＝フォワード版の管轄）
   int n = CalendarValueHistory(values, InpFrom, to, NULL, "USD");
   if(n <= 0)
   {
      PrintFormat("[EEL] カレンダー取得0 / err=%d（このブローカーが未提供の可能性）", GetLastError());
      return;
   }

   int drawn = 0;
   for(int i=0; i<n && drawn<InpMaxLines; i++)
   {
      string grp; int tier = ClassifyTier(values[i].event_id, grp);  // 分類はIDのみで完結（名称参照不要）
      if(tier==0) continue;
      if(tier==3 && !InpShowTierS) continue;
      if(tier==2 && !InpShowTierA) continue;
      if(tier==1 && !InpShowTierB) continue;

      datetime vt = values[i].time;
      string key = PFX + grp + "_" + IntegerToString((long)vt);  // 同グループ同時刻＝同名で1本化
      if(ObjectFind(0, key) >= 0) continue;

      color col; int wid; ENUM_LINE_STYLE sty;
      if(tier==3){ col=clrDarkOrange;   wid=2; sty=STYLE_SOLID; }
      else if(tier==2){ col=clrGoldenrod; wid=1; sty=STYLE_SOLID; }
      else { col=C'110,110,110'; wid=1; sty=STYLE_DOT; }

      if(!ObjectCreate(0, key, OBJ_VLINE, 0, vt, 0)) continue;
      ObjectSetInteger(0, key, OBJPROP_COLOR, col);
      ObjectSetInteger(0, key, OBJPROP_WIDTH, wid);
      ObjectSetInteger(0, key, OBJPROP_STYLE, sty);
      ObjectSetInteger(0, key, OBJPROP_BACK, true);          // ローソク背面
      ObjectSetInteger(0, key, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, key, OBJPROP_HIDDEN, true);

      if(InpShowLabel)
      {
         string lab = grp;
         if(InpShowValue && values[i].HasActualValue())
         {
            string a = DoubleToString(values[i].GetActualValue(), 2);
            string f = values[i].HasForecastValue() ? DoubleToString(values[i].GetForecastValue(), 2) : "-";
            lab = grp + " A:" + a + " F:" + f;      // サプライズ = A vs F
         }
         ObjectSetString(0, key, OBJPROP_TEXT, lab);
      }
      drawn++;
   }
   ChartRedraw();
   PrintFormat("[EEL] 縦線 %d本描画（%s〜現在, USD / TierS/A/B=%s/%s/%s）",
      drawn, TimeToString(InpFrom, TIME_DATE),
      InpShowTierS?"on":"off", InpShowTierA?"on":"off", InpShowTierB?"on":"off");
}

int OnInit(){ BuildLines(); return(INIT_SUCCEEDED); }
void OnDeinit(const int reason){ ObjectsDeleteAll(0, PFX); ChartRedraw(); }
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &vol[], const int &sp[])
{ return(rates_total); }
//+------------------------------------------------------------------+
