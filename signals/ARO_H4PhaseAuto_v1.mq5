//+------------------------------------------------------------------+
//|  ARO_H4PhaseAuto_v1.mq5                                          |
//|  H4 Phase Auto v2（5段階版）                                      |
//|                                                                  |
//|  ロジック仕様: data/bt/h4_phase_auto_spec.md (v2 / 5段階)        |
//|  ベース流用: data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5     |
//|              - FindATRCross() 関数                                |
//|              - H4 ATR 計算ロジック                                |
//|                                                                  |
//|  目的:                                                            |
//|   H4 Wave 手動依存（fwd-data-pipeline-weakness）からの脱却。      |
//|   ATR_RATIO + ATR Cross + ATR_DIFF で H4 Phase を自動判定。       |
//|                                                                  |
//|  判定ロジック v2:                                                 |
//|   ratio ≤ 0.97 (凪帯):                                           |
//|     diff < -1.0  → "収束底"  (PF 2.50 N=82, BUY/SELL方向中立で強) |
//|     diff > +1.0  → "凪離脱"  (PF 0.49 N=40, ★フェイク警告)       |
//|     それ以外     → "凪"     (PF 1.20 N=87, 中立)                  |
//|   ratio > 0.97 (拡張帯):                                          |
//|     cross_dir = "BU" → "BU"                                      |
//|     cross_dir = "PD" → "PD"                                      |
//|     cross_dir = "NONE" → "—"  (判定不能)                          |
//|                                                                  |
//|  出力: MT5/MQL5/Files/H4PhaseAuto_weekly.csv (UTF-16 / 10列)     |
//|                                                                  |
//|  Cross_Dir 命名統一: BT世代2の "UP/DOWN/NONE" でなく、            |
//|                      認識ツール思想に従い "BU/PD/NONE" に変換。  |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 期間設定 ==="
input datetime Start_Time      = D'2020.01.01 00:00';
input datetime End_Time        = D'2027.12.31 23:59';

input group "=== H4 ATR パラメータ ==="
input int      H4_ATR_Short    = 8;
input int      H4_ATR_Long     = 46;
input int      Cross_LookBack  = 30;

input group "=== 凪判定閾値（v2: 5段階） ==="
input double   Nagi_Thresh     = 0.97;   // ATR_Ratio 凪帯閾値（≤ なら凪帯）
input double   Nagi_Diff_Thresh = 1.0;   // ATR_Diff 細分閾値（±でこの値超えると収束底/凪離脱）

input group "=== 出力 ==="
input string   OutputFile      = "H4PhaseAuto_weekly.csv";

//+-----[ ハンドル ]------------------------------------------------+
int hATR_S_H4 = INVALID_HANDLE;
int hATR_L_H4 = INVALID_HANDLE;

//+==================================================================+
//|  OnStart                                                         |
//+==================================================================+
void OnStart()
{
   Print("==== ARO_H4PhaseAuto_v1 (v2 5段階) Start ====");
   PrintFormat("Symbol: %s, Chart Period: %s", _Symbol, EnumToString(_Period));
   PrintFormat("Range: %s 〜 %s",
      TimeToString(Start_Time, TIME_DATE|TIME_MINUTES),
      TimeToString(End_Time,   TIME_DATE|TIME_MINUTES));
   PrintFormat("H4 ATR Short=%d, Long=%d, CrossLookBack=%d",
      H4_ATR_Short, H4_ATR_Long, Cross_LookBack);
   PrintFormat("Nagi_Thresh=%.3f, Nagi_Diff_Thresh=%.3f",
      Nagi_Thresh, Nagi_Diff_Thresh);

   //--- ハンドル初期化 ---
   hATR_S_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Long);
   if(hATR_S_H4 == INVALID_HANDLE || hATR_L_H4 == INVALID_HANDLE) {
      PrintFormat("Handle init failed: err=%d", GetLastError());
      return;
   }
   Sleep(2000);  // インジ計算待ち

   //--- CSV オープン（UTF-16 LE BOM 付き：FILE_TXT|FILE_UNICODE）---
   int fh = FileOpen(OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) {
      PrintFormat("CSV open failed: %s err=%d", OutputFile, GetLastError());
      IndicatorRelease(hATR_S_H4);
      IndicatorRelease(hATR_L_H4);
      return;
   }
   WriteHeader(fh);

   //--- H4 データ取得 ---
   int h4_size = (int)Bars(_Symbol, PERIOD_H4);
   PrintFormat("H4 bars total: %d", h4_size);

   datetime times[];
   double   atr_s[], atr_l[];
   ArraySetAsSeries(times, true);
   ArraySetAsSeries(atr_s, true);
   ArraySetAsSeries(atr_l, true);

   if(CopyTime(_Symbol, PERIOD_H4, 0, h4_size, times) <= 0 ||
      CopyBuffer(hATR_S_H4, 0, 0, h4_size, atr_s) <= 0 ||
      CopyBuffer(hATR_L_H4, 0, 0, h4_size, atr_l) <= 0)
   {
      PrintFormat("Data copy failed err=%d", GetLastError());
      FileClose(fh);
      IndicatorRelease(hATR_S_H4);
      IndicatorRelease(hATR_L_H4);
      return;
   }

   //--- 週次サンプリング: ISO週ごとに、その週の最後のH4バー（金曜近辺）を採用 ---
   // 戦略: 古い順に走査し、ISO週が切り替わったタイミングで前週の「最終バー」を確定→出力
   // series=true で times[0]=最新、times[size-1]=最古
   // 古→新の順は i = size-1 → 0 のループになる

   string prev_week = "";
   int    prev_week_last_idx = -1;  // 前週内で最後に評価したH4バーのインデックス
   int    written = 0;

   for(int i = h4_size - 1; i >= 0; i--) {
      if(atr_s[i] <= 0 || atr_l[i] <= 0) continue;
      if(times[i] < Start_Time) continue;
      if(times[i] > End_Time)   break;

      string wk = IsoWeek(times[i]);

      // 週が切り替わったら、前週の最終バーを出力
      if(wk != prev_week) {
         if(prev_week != "" && prev_week_last_idx >= 0) {
            WriteRow(fh, prev_week, times, atr_s, atr_l, prev_week_last_idx, h4_size);
            written++;
         }
         prev_week = wk;
      }
      // 現週の「最終バー」を更新（古→新ループなので、最後に通過する=この週の最終バー）
      prev_week_last_idx = i;
   }
   // ループ終了後、最後の週も出力
   if(prev_week != "" && prev_week_last_idx >= 0) {
      WriteRow(fh, prev_week, times, atr_s, atr_l, prev_week_last_idx, h4_size);
      written++;
   }

   FileClose(fh);
   PrintFormat("==== Complete: %d weeks written ====", written);
   PrintFormat("Output: %s/MQL5/Files/%s",
      TerminalInfoString(TERMINAL_DATA_PATH), OutputFile);

   IndicatorRelease(hATR_S_H4);
   IndicatorRelease(hATR_L_H4);
}

//+==================================================================+
//|  ISO週文字列 "YYYY-Www" を返す                                   |
//+==================================================================+
string IsoWeek(datetime t)
{
   MqlDateTime mdt;
   TimeToStruct(t, mdt);
   // MQL5 標準には ISO 週関数が無いので自前計算
   // ISO 8601: 週は月曜始まり、その年最初の木曜を含む週がW01

   // 当該日が含まれる週の木曜日を求める
   // day_of_week: 0=日, 1=月, ..., 6=土
   int dow = mdt.day_of_week;
   if(dow == 0) dow = 7;  // ISO: 月=1, ..., 日=7
   // 当該日から、その週の木曜までのシフト
   datetime thursday_of_week = t + (4 - dow) * 86400;

   MqlDateTime tdt;
   TimeToStruct(thursday_of_week, tdt);
   int iso_year = tdt.year;

   // その ISO年のW01の月曜日を求める
   // = その年の1月4日が含まれる週の月曜日
   datetime jan4 = StringToTime(StringFormat("%04d.01.04 00:00", iso_year));
   MqlDateTime jdt;
   TimeToStruct(jan4, jdt);
   int jan4_dow = jdt.day_of_week;
   if(jan4_dow == 0) jan4_dow = 7;
   datetime w01_monday = jan4 - (jan4_dow - 1) * 86400;

   // 当該日が含まれる週の月曜日
   datetime week_monday = t - (dow - 1) * 86400;

   int week_no = (int)((week_monday - w01_monday) / (7 * 86400)) + 1;

   return StringFormat("%04d-W%02d", iso_year, week_no);
}

//+==================================================================+
//|  ATR8/46 クロス検索 (BT世代2 FindCrossBack 流用)                |
//|                                                                  |
//|  戻り値: クロスからの経過バー数 (0=最新バー直後にクロス)         |
//|         -1 = LookBack内にクロス無し                              |
//|  dir_out: +1 = ATR_S が ATR_L を上抜け (BU = 拡張上昇開始)       |
//|           -1 = ATR_S が ATR_L を下抜け (PD = 拡張下降開始)       |
//|            0 = クロス無し                                        |
//+==================================================================+
int FindATRCross(const double &s[], const double &l[], int idx, int max_look, int &dir_out)
{
   dir_out = 0;
   int sz = MathMin(ArraySize(s), ArraySize(l));
   for(int k = 0; k <= max_look; k++) {
      int i_now  = idx + k;
      int i_prev = idx + k + 1;
      if(i_prev >= sz) break;
      if(s[i_now]<=0 || l[i_now]<=0 || s[i_prev]<=0 || l[i_prev]<=0) continue;
      bool now_above  = (s[i_now]  > l[i_now]);
      bool prev_above = (s[i_prev] > l[i_prev]);
      if(now_above != prev_above) {
         dir_out = now_above ? 1 : -1;
         return k;
      }
   }
   return -1;
}

//+==================================================================+
//|  Cross_Dir int → 認識ツール用文字列に変換                        |
//|                                                                  |
//|  BT世代2 では "UP/DOWN/NONE" だが、認識ツール思想に従い          |
//|  "BU/PD/NONE" に統一する                                         |
//+==================================================================+
string CrossDirLabel(int cd)
{
   if(cd > 0) return "BU";
   if(cd < 0) return "PD";
   return "NONE";
}

//+==================================================================+
//|  H4 Phase Auto 判定（v2 / 5段階）                                |
//|                                                                  |
//|  入力:                                                            |
//|    ratio    = ATR_Short / ATR_Long                                |
//|    cross    = "BU" / "PD" / "NONE"                                |
//|    diff     = ATR_Short - ATR_Long                                |
//|                                                                  |
//|  戻り値: "BU" / "PD" / "凪" / "収束底" / "凪離脱" / "—"          |
//+==================================================================+
string H4PhaseAuto(double ratio, string cross_dir, double atr_diff)
{
   // 安全処理
   if(ratio <= 0) return "—";

   // 凪帯（ratio ≤ 閾値）を diff で3層に細分
   if(ratio <= Nagi_Thresh) {
      if(atr_diff < -Nagi_Diff_Thresh) return "収束底";   // PF 2.50 (N=82) ボトムアウト前
      if(atr_diff >  Nagi_Diff_Thresh) return "凪離脱";   // PF 0.49 (N=40) フェイク警告
      return "凪";                                         // PF 1.20 (N=87) 中立
   }

   // 拡張帯（ratio > 閾値）
   if(cross_dir == "BU") return "BU";
   if(cross_dir == "PD") return "PD";
   return "—";  // NONE は判定不能
}

//+==================================================================+
//|  CSV ヘッダー書き込み                                            |
//+==================================================================+
void WriteHeader(int fh)
{
   string line =
      "Week,WeekEndTime,H4_BarTime,"
      "H4_ATR_Short,H4_ATR_Long,H4_ATR_Ratio,H4_ATR_Diff,"
      "H4_Cross_Bars,H4_Cross_Dir,H4_Phase_Auto";
   FileWriteString(fh, line + "\r\n");
}

//+==================================================================+
//|  CSV 1行書き込み                                                 |
//|                                                                  |
//|  idx は「その週の最終 H4 バー」のインデックス（series=true 前提）|
//+==================================================================+
void WriteRow(int fh, const string &wk,
              const datetime &times[], const double &atr_s[], const double &atr_l[],
              int idx, int h4_size)
{
   double a_s   = atr_s[idx];
   double a_l   = atr_l[idx];
   double ratio = (a_l > 0) ? a_s / a_l : 0.0;
   double diff  = a_s - a_l;

   int cd = 0;
   int cb = FindATRCross(atr_s, atr_l, idx, Cross_LookBack, cd);
   string cross_label = CrossDirLabel(cd);
   string phase       = H4PhaseAuto(ratio, cross_label, diff);

   // WeekEndTime = 週内最終 H4 バー時刻（実質これがサンプリング基準）
   // H4_BarTime  = 同じく評価したバー時刻（現状は WeekEndTime と同値だが、将来分離余地）
   string week_end = TimeToString(times[idx], TIME_DATE|TIME_MINUTES);
   string bar_time = TimeToString(times[idx], TIME_DATE|TIME_MINUTES);

   string line = "";
   line += wk + ",";
   line += week_end + ",";
   line += bar_time + ",";
   line += DoubleToString(a_s, 4) + ",";
   line += DoubleToString(a_l, 4) + ",";
   line += DoubleToString(ratio, 4) + ",";
   line += DoubleToString(diff, 4) + ",";
   line += IntegerToString(cb) + ",";
   line += cross_label + ",";
   line += phase;
   FileWriteString(fh, line + "\r\n");
}
//+------------------------------------------------------------------+
