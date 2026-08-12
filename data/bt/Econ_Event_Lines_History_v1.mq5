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
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

input datetime InpFrom      = D'2024.01.01 00:00'; // 表示開始（重ければ後ろへ）
input bool     InpShowTierS = true;                // NFP/CPI/FOMC
input bool     InpShowTierA = true;                // PPI/小売/GDP/PCE/ADP/PMI
input bool     InpShowTierB = true;                // ISM（実測で弱い＝薄）
input bool     InpShowLabel = true;                // 指標名ラベル
input bool     InpShowValue = false;               // 実際値/予想も出す（サプライズ検証）
input int      InpMaxLines  = 800;                 // 縦線上限（Macの負荷配慮）

const string PFX = "EEL_";

//--- EventName → Tier(3=S/2=A/1=B/0=対象外) と グループ名 ---
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
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;

      string grp; int tier = ClassifyTier(ev.name, grp);
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
