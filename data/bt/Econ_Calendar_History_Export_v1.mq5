//+------------------------------------------------------------------+
//|  Econ_Calendar_History_Export_v1.mq5                             |
//|  MT5内蔵 経済カレンダーの「米指標(USD)」履歴を CSV 出力する Script |
//|                                                                  |
//|  用途 : ボラティリティイベント実測（TR復元ランキング）の本番ソース |
//|  ねらい: FOMC/CPI/PCE/NFP/PPI/小売/ISM/PMI/GDP/ADP …を網羅取得     |
//|  肝    : 出力 Time = サーバー時間。ATR_Ratio_Timeseries_v1.csv と  |
//|          同一時間軸・同一フォーマット("YYYY.MM.DD HH:MM")なので     |
//|          突き合わせにJST変換もDST補正も一切不要（較正誤差ゼロ）。   |
//|                                                                  |
//|  使い方: MetaEditorで開く→F7コンパイル→任意チャートにドラッグ実行  |
//|          出力先 = MQL5/Files/<InpFileName>                        |
//|          未来日(InpTo=2027)も取れるのでフォワード縦線にも流用可。  |
//+------------------------------------------------------------------+
#property copyright "ARO"
#property version   "1.00"
#property script_show_inputs
#property strict

input datetime InpFrom          = D'2024.01.01 00:00';  // ATR CSVの起点に合わせる
input datetime InpTo            = D'2027.01.01 00:00';   // 未来も取得（フォワード用途）
input string   InpCurrency      = "USD";                // 米ドル指標＝XAU主ドライバに限定
input int      InpMinImportance = 1;                    // 0=全部 1=LOW以上 2=MOD以上 3=HIGHのみ
input string   InpFileName      = "Econ_Calendar_US_History.csv";

string ImpStr(ENUM_CALENDAR_EVENT_IMPORTANCE imp)
{
   switch(imp)
   {
      case CALENDAR_IMPORTANCE_HIGH:     return("HIGH");
      case CALENDAR_IMPORTANCE_MODERATE: return("MODERATE");
      case CALENDAR_IMPORTANCE_LOW:      return("LOW");
      default:                           return("NONE");
   }
}

// CSVフィールドをダブルクォート囲みに（イベント名のカンマ対策・内部"は'へ）
string Q(string s){ StringReplace(s,"\"","'"); return("\""+s+"\""); }

void OnStart()
{
   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, InpFrom, InpTo, NULL, InpCurrency);
   if(n <= 0)
   {
      PrintFormat("[Econ Export] 取得0件 / err=%d — このブローカーが経済カレンダー未提供の可能性。ForexFactory等の外部CSVにフォールバックが必要。", GetLastError());
      return;
   }

   int fh = FileOpen(InpFileName, FILE_WRITE|FILE_TXT|FILE_UNICODE);   // UTF-16（ATR CSVと同系）
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("[Econ Export] FileOpen失敗 err=%d", GetLastError());
      return;
   }

   FileWriteString(fh, "Time,EventName,Importance,Actual,Forecast,Previous,Currency,EventID,Impact,Period\r\n");

   int written = 0;
   for(int i=0; i<n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if((int)ev.importance < InpMinImportance)      continue;   // 重要度フィルタ

      string t   = TimeToString(values[i].time,   TIME_DATE|TIME_MINUTES);
      string per = TimeToString(values[i].period, TIME_DATE|TIME_MINUTES);
      string act = values[i].HasActualValue()   ? DoubleToString(values[i].GetActualValue(),4)   : "";
      string fc  = values[i].HasForecastValue() ? DoubleToString(values[i].GetForecastValue(),4) : "";
      string pv  = values[i].HasPreviousValue() ? DoubleToString(values[i].GetPreviousValue(),4) : "";

      string impact = "NA";
      if(values[i].impact_type == CALENDAR_IMPACT_POSITIVE) impact = "POS";
      else if(values[i].impact_type == CALENDAR_IMPACT_NEGATIVE) impact = "NEG";

      string line = StringFormat("%s,%s,%s,%s,%s,%s,%s,%I64u,%s,%s\r\n",
                       t, Q(ev.name), ImpStr(ev.importance),
                       act, fc, pv, InpCurrency, values[i].event_id, impact, per);
      FileWriteString(fh, line);
      written++;
   }
   FileClose(fh);
   PrintFormat("[Econ Export] 完了: 取得%d件 → 出力%d件  MQL5/Files/%s", n, written, InpFileName);
}
//+------------------------------------------------------------------+
