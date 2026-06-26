//+------------------------------------------------------------------+
//|  ARO_H4PhaseAuto_EA_v1.mq5                                       |
//|                                                                  |
//|  ②自動集計（週次ヒートマップ上流）の H4 Phase Auto を常駐EA化。  |
//|  Script版（OnStart型）を OnInit/OnTimer/OnDeinit の常駐EAに移植し、|
//|  VPS上のMT5でXAUUSD H4チャート1枚から H4PhaseAuto_weekly.csv を   |
//|  毎時無人生成する。進行中週（今週）は手描きBU/PD空のまま、        |
//|  H4Phaseラベルだけ毎時最新に更新される。                          |
//|                                                                  |
//|  移植元（ロジックは1ミリも変えずコピペ移植 — 触らず温存）:        |
//|    - ARO_H4PhaseAuto_v1.mq5 (OnStart / 10列 /                    |
//|        iATR 2ハンドル・既にグローバル / UTF-16出力)              |
//|        → H4PhaseAuto_weekly.csv (UTF-16 / FILE_TXT|FILE_UNICODE) |
//|                                                                  |
//|  移植方針（コー_指示書_②自動集計_H4PhaseAuto_EA化_v1.md）:       |
//|    - OnStart → OnInit / OnTimer / OnDeinit / GenerateCsv へ分解   |
//|    - Sleep(2000) は移植せず HandlesReady()（2ハンドル            |
//|      BarsCalculated>0 ゲート）で代替                              |
//|    - ハンドルは元から グローバル（hATR_S_H4/hATR_L_H4）。         |
//|      InitHandles() で生成、解放は OnDeinit の ReleaseHandles()のみ|
//|    - GenerateCsv 内の FATAL return 直前 IndicatorRelease は削除   |
//|      （ハンドル常駐維持。その回は CSV を書かず return＝次回再試行）|
//|    - 判定関数（IsoWeek/FindATRCross/CrossDirLabel/H4PhaseAuto/    |
//|      WriteHeader/WriteRow）は無改変コピペ                         |
//|                                                                  |
//|  地雷（指示書§1）:                                               |
//|    - 出力は UTF-16 のまま（系統B/CのUTF-8 BOMと揃えない）。       |
//|      間違えると Mac側 process_wavelog.py のデコードが壊れる。     |
//|    - 進行中週を出す機構（ループ後の最終週書き出し）は絶対維持。   |
//|      これが「週確定を待たず毎時最新」を成立させる本体。           |
//|                                                                  |
//|  認識ツール思想厳守: 点数化禁止・ラベル                           |
//|    （BU/PD/凪/収束底/凪離脱/—）のまま。                           |
//|                                                                  |
//|  指示書: data/vps/コー_指示書_②自動集計_H4PhaseAuto_EA化_v1.md    |
//|  作成日: 2026-06-26                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 共通 ==="
input string   Allowed_Symbol  = "XAUUSD";          // この銘柄以外は起動拒否

input group "=== EA制御（新規）==="
input int      Update_Interval_Min = 60;            // 本間隔（ready後の再生成周期, 分）
input int      First_Run_Delay_Sec = 15;            // 初回タイマー（ready待ちの短間隔, 秒）
input bool     Verbose         = true;

input group "=== 期間設定（移植元から維持）==="
input datetime Start_Time      = D'2020.01.01 00:00';
input datetime End_Time        = D'2027.12.31 23:59';

input group "=== H4 ATR パラメータ（移植元から維持）==="
input int      H4_ATR_Short    = 8;
input int      H4_ATR_Long     = 46;
input int      Cross_LookBack  = 30;

input group "=== 凪判定閾値（v2: 5段階・移植元から維持）==="
input double   Nagi_Thresh     = 0.97;   // ATR_Ratio 凪帯閾値（≤ なら凪帯）
input double   Nagi_Diff_Thresh = 1.0;   // ATR_Diff 細分閾値（±でこの値超えると収束底/凪離脱）

input group "=== 出力 ==="
input string   OutputFile      = "H4PhaseAuto_weekly.csv";

//+-----[ ハンドル（移植元と同じくグローバル）]---------------------+
int hATR_S_H4 = INVALID_HANDLE;
int hATR_L_H4 = INVALID_HANDLE;

//+-----[ EA制御 ]--------------------------------------------------+
bool g_first_run = false;

//+==================================================================+
//| OnInit                                                           |
//+==================================================================+
int OnInit()
{
   Print("==== ARO_H4PhaseAuto_EA v1.00 (v2 5段階) OnInit ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s, Period: %s",
      _Symbol, Allowed_Symbol, EnumToString(_Period));
   PrintFormat("Range: %s 〜 %s",
      TimeToString(Start_Time, TIME_DATE|TIME_MINUTES),
      TimeToString(End_Time,   TIME_DATE|TIME_MINUTES));
   PrintFormat("H4 ATR Short=%d, Long=%d, CrossLookBack=%d",
      H4_ATR_Short, H4_ATR_Long, Cross_LookBack);
   PrintFormat("Nagi_Thresh=%.3f, Nagi_Diff_Thresh=%.3f",
      Nagi_Thresh, Nagi_Diff_Thresh);
   PrintFormat("Output: %s", OutputFile);

   //--- シンボル制約: XAUUSD以外で起動拒否（誤アタッチ防止）---
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return(INIT_FAILED);
   }

   //--- ハンドル初期化（iATR 2本・移植元71-76を切り出し）---
   if(!InitHandles())
   {
      Print("[FATAL] 指標ハンドル初期化に失敗。終了。");
      return(INIT_FAILED);
   }

   //--- 初回は短く（ready待ち）---
   g_first_run = true;
   EventSetTimer(First_Run_Delay_Sec);

   return(INIT_SUCCEEDED);
}

//+==================================================================+
//| OnTimer                                                          |
//+==================================================================+
void OnTimer()
{
   //--- 2ハンドルの計算完了まで持ち越し（旧 Sleep(2000) の代替）---
   if(!HandlesReady())
   {
      if(Verbose) Print("[WAIT] indicator handles not ready yet...");
      return;
   }

   //--- ready初回だけ本間隔へ張り替え ---
   if(g_first_run)
   {
      EventKillTimer();
      EventSetTimer(Update_Interval_Min * 60);
      g_first_run = false;
      if(Verbose)
         PrintFormat("[INFO] handles ready. timer → %d min interval.",
                     Update_Interval_Min);
   }

   //--- 週次CSVを再生成・上書き ---
   GenerateCsv();
}

//+==================================================================+
//| OnDeinit                                                         |
//+==================================================================+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseHandles();
   PrintFormat("==== ARO_H4PhaseAuto_EA v1.00 OnDeinit (reason=%d) ====", reason);
}

//+==================================================================+
//| InitHandles                                                      |
//|   移植元 OnStart 71-76 のハンドル生成を切り出し。                 |
//+==================================================================+
bool InitHandles()
{
   hATR_S_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Long);
   if(hATR_S_H4 == INVALID_HANDLE || hATR_L_H4 == INVALID_HANDLE) {
      PrintFormat("Handle init failed: err=%d", GetLastError());
      return false;
   }
   return true;
}

//+==================================================================+
//| ReleaseHandles                                                   |
//|   移植元 OnStart 末尾 148-149 の解放。OnDeinit からのみ（常駐維持）|
//+==================================================================+
void ReleaseHandles()
{
   if(hATR_S_H4 != INVALID_HANDLE) IndicatorRelease(hATR_S_H4);
   if(hATR_L_H4 != INVALID_HANDLE) IndicatorRelease(hATR_L_H4);
}

//+==================================================================+
//| HandlesReady                                                     |
//|   2ハンドルすべて !=INVALID_HANDLE かつ BarsCalculated>0 で true。 |
//|   旧 OnStart の Sleep(2000) ゲートの代替。                        |
//+==================================================================+
bool HandlesReady()
{
   if(hATR_S_H4 == INVALID_HANDLE || hATR_L_H4 == INVALID_HANDLE) return false;
   if(BarsCalculated(hATR_S_H4) <= 0) return false;
   if(BarsCalculated(hATR_L_H4) <= 0) return false;
   return true;
}

//+==================================================================+
//| GenerateCsv                                                      |
//|   旧 OnStart のCSV生成部（移植元79-146 / FileOpen→週次ループ→     |
//|   FileClose）。ロジックは無改変。                                  |
//|   ※ シンボル制約・ハンドル初期化・Sleep は OnInit/HandlesReady   |
//|      側へ移したため、ここではCSV生成のみを行う。                  |
//|   ※ FATAL時の return は「その回スキップ」（CSVを書かず return、   |
//|      EAは生かして次回 OnTimer で再試行）。FATAL return 直前の      |
//|      IndicatorRelease（移植元83-84・105-106）は削除＝常駐維持。   |
//+==================================================================+
void GenerateCsv()
{
   //--- CSV オープン（UTF-16 LE BOM 付き：FILE_TXT|FILE_UNICODE）---
   int fh = FileOpen(OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) {
      PrintFormat("CSV open failed: %s err=%d", OutputFile, GetLastError());
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
   // ループ終了後、最後の週も出力（★進行中週＝今週の暫定値が最終行に出る。毎時更新の肝。絶対維持）
   if(prev_week != "" && prev_week_last_idx >= 0) {
      WriteRow(fh, prev_week, times, atr_s, atr_l, prev_week_last_idx, h4_size);
      written++;
   }

   FileClose(fh);
   PrintFormat("==== Complete: %d weeks written ====", written);
   PrintFormat("Output: %s/MQL5/Files/%s",
      TerminalInfoString(TERMINAL_DATA_PATH), OutputFile);
}

//+##################################################################+
//|                                                                  |
//|  以下、判定関数群（移植元 155-307 を 1ミリも変えず無改変コピペ）  |
//|                                                                  |
//+##################################################################+

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
