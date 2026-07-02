//+------------------------------------------------------------------+
//|  ATR_Ratio_Timeseries_v1.mq5                                     |
//|  H1バーごとの H1_Ratio / H4_Ratio 時系列CSV出力 Script           |
//|                                                                  |
//|  目的: 反転×H4収束 共起検証の基盤時系列                          |
//|    (仕様: data/bt/atr_ratio_timeseries_spec.md)                  |
//|                                                                  |
//|  物差し: ATR_WidthSignal_BT_gen3_kc.mq5 と完全一致               |
//|    - H1_Ratio = iATR(H1,16) / CalcMedian(過去960本・上側中央値)  |
//|    - H4_Ratio = iATR(H4,8)  / CalcMedian(過去240本・上側中央値)  |
//|    - CalcMedian は gen3 L408 をそのまま移植（改変禁止）          |
//|    - H4値は H1バー時刻→iBarShift で対応H4バーを参照             |
//|      (同一H4バーに属するH1バー4本は同じH4値になる＝仕様通り)     |
//|                                                                  |
//|  シグナル判定・フィルター・売買ロジックは一切含まない            |
//|  （時系列を吐くだけ。反転点との突合は Mac側 Python で行う）      |
//|                                                                  |
//|  実行: H1 XAUUSD チャートで Script 実行（確定バーのみ出力）      |
//|  出力: MQL5/Files/ATR_Ratio_Timeseries_v1.csv                    |
//|        (FILE_UNICODE = UTF-16 LE BOM付き・gen3と同方式)          |
//|  列  : Time,H1_ATR16,H1_ATR32,H1_Med960,H1_Ratio,                |
//|        H4_ATR8,H4_ATR46,H4_Med240,H4_Ratio                       |
//|                                                                  |
//|  注意: 中央値が計算不能（履歴不足）の行はスキップせず            |
//|        Ratio=0 で出力する（Python側で除外する前提）              |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 期間 ==="
input datetime TS_StartTime     = D'2024.01.01 00:00';  // 出力開始（終端は実行時点の最新確定バー）

input group "=== 物差し（gen3と同一・変更しない）==="
input int      H1_ATR_Short     = 16;
input int      H1_ATR_Long      = 32;
input int      H4_ATR_Short     = 8;
input int      H4_ATR_Long      = 46;
input int      ATR_Median_Weeks = 8;    // 8週 → H1: 8*5*24=960本 / H4: 8*5*6=240本

input group "=== 出力 ==="
input string   TS_OutputFile    = "ATR_Ratio_Timeseries_v1.csv";
input int      Progress_Every   = 500;  // 進捗Comment更新間隔（行）

//+-----[ ハンドル ]------------------------------------------------+
int hATR_S_H1 = INVALID_HANDLE, hATR_L_H1 = INVALID_HANDLE;
int hATR_S_H4 = INVALID_HANDLE, hATR_L_H4 = INVALID_HANDLE;

//+==================================================================+
//|  OnStart                                                         |
//+==================================================================+
void OnStart()
{
   Print("==== ATR_Ratio_Timeseries_v1 Start ====");
   PrintFormat("Symbol: %s, Period(chart): %s", _Symbol, EnumToString(_Period));
   PrintFormat("Range: %s 〜 latest confirmed bar",
      TimeToString(TS_StartTime, TIME_DATE|TIME_MINUTES));

   if(!InitHandles()) return;

   // === バー数取得 ===
   int h1_size = (int)Bars(_Symbol, PERIOD_H1);
   int h4_size = (int)Bars(_Symbol, PERIOD_H4);
   PrintFormat("Bars: H1=%d, H4=%d", h1_size, h4_size);
   if(h1_size <= 0 || h4_size <= 0) {
      Print("ERROR: no bars available. Load history first.");
      ReleaseHandles();
      return;
   }

   // === 配列一括取得（gen3と同方式: series=true / index 0=最新, 大=古い）===
   datetime times[];
   double atr_s_h1[], atr_l_h1[];
   double atr_s_h4[], atr_l_h4[];

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(atr_s_h1, true); ArraySetAsSeries(atr_l_h1, true);
   ArraySetAsSeries(atr_s_h4, true); ArraySetAsSeries(atr_l_h4, true);

   if(CopyTime(_Symbol, PERIOD_H1, 0, h1_size, times) <= 0) {
      PrintFormat("ERROR: CopyTime H1 failed (err=%d)", GetLastError());
      ReleaseHandles();
      return;
   }
   if(!CopyBufRetry(hATR_S_H1, h1_size, atr_s_h1, "H1 ATR16") ||
      !CopyBufRetry(hATR_L_H1, h1_size, atr_l_h1, "H1 ATR32") ||
      !CopyBufRetry(hATR_S_H4, h4_size, atr_s_h4, "H4 ATR8")  ||
      !CopyBufRetry(hATR_L_H4, h4_size, atr_l_h4, "H4 ATR46"))
   {
      Print("ERROR: CopyBuffer failed after retries. Abort.");
      ReleaseHandles();
      return;
   }

   // 実効サイズ（CopyBufferが要求本数未満を返した場合の保険）
   int eff_h1 = MathMin(ArraySize(times),
                MathMin(ArraySize(atr_s_h1), ArraySize(atr_l_h1)));
   int eff_h4 = MathMin(ArraySize(atr_s_h4), ArraySize(atr_l_h4));
   if(eff_h1 < h1_size || eff_h4 < h4_size)
      PrintFormat("WARN: copied less than requested. eff_h1=%d/%d, eff_h4=%d/%d",
                  eff_h1, h1_size, eff_h4, h4_size);

   // === 中央値バー数（gen3と同一の導出式）===
   int median_bars    = ATR_Median_Weeks * 5 * 24;   // 8週 → 960
   int h4_median_bars = ATR_Median_Weeks * 5 * 6;    // 8週 → 240

   // === 出力範囲の先頭インデックス（最古の対象バー）を確定 ===
   // series=true: index大=古い。times[i] >= TS_StartTime を満たす最大 i が先頭。
   int start_idx = -1;
   for(int i = eff_h1 - 1; i >= 1; i--) {
      if(times[i] >= TS_StartTime) { start_idx = i; break; }
   }
   if(start_idx < 1) {
      Print("ERROR: no confirmed H1 bars at/after TS_StartTime.");
      ReleaseHandles();
      return;
   }

   // 履歴バッファ充足チェック（先頭バーで960本中央値が引けるか）
   if(start_idx + median_bars >= eff_h1)
      PrintFormat("WARN: H1 history short of 960-bar buffer at range head "
                  "(start_idx=%d, need >= %d bars total, have %d). "
                  "Early rows will output Ratio=0.",
                  start_idx, start_idx + median_bars + 1, eff_h1);

   // === CSVオープン（UTF-16 LE BOM付き・gen3と同方式）===
   int fh = FileOpen(TS_OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) {
      PrintFormat("ERROR: CSV open failed: err=%d", GetLastError());
      ReleaseHandles();
      return;
   }
   FileWriteString(fh,
      "Time,H1_ATR16,H1_ATR32,H1_Med960,H1_Ratio,"
      "H4_ATR8,H4_ATR46,H4_Med240,H4_Ratio\r\n");

   // === メインループ: 古い → 新しい（i=start_idx → 1、i=0は形成中バーで除外）===
   int total_rows = start_idx;   // i = start_idx..1 で1行ずつ
   int written = 0, zero_h1 = 0, zero_h4 = 0, h4_miss = 0;
   int prog_every = MathMax(1, Progress_Every);   // 0除算ガード

   // H4中央値キャッシュ（H4バーが変わった時のみ再計算）
   int    last_hi     = -999;
   double h4_med_cache = 0;

   for(int i = start_idx; i >= 1; i--) {
      if(IsStopped()) { Print("WARN: script stopped by user."); break; }

      // --- H1側 ---
      double h1_atr16 = atr_s_h1[i];
      double h1_atr32 = atr_l_h1[i];
      double h1_med   = CalcMedian(atr_s_h1, i, median_bars);
      double h1_ratio = (h1_atr16 > 0 && h1_med > 0) ? h1_atr16 / h1_med : 0;
      if(h1_ratio <= 0) zero_h1++;

      // --- H4側（iBarShiftで対応H4バーを引く）---
      double h4_atr8 = 0, h4_atr46 = 0, h4_med = 0, h4_ratio = 0;
      int hi = iBarShift(_Symbol, PERIOD_H4, times[i]);
      if(hi >= 0 && hi < eff_h4) {
         h4_atr8  = atr_s_h4[hi];
         h4_atr46 = atr_l_h4[hi];
         if(hi != last_hi) {   // H4バーが変わった時のみ中央値を再計算
            h4_med_cache = CalcMedian(atr_s_h4, hi, h4_median_bars);
            last_hi      = hi;
         }
         h4_med   = h4_med_cache;
         h4_ratio = (h4_atr8 > 0 && h4_med > 0) ? h4_atr8 / h4_med : 0;
      } else {
         h4_miss++;
      }
      if(h4_ratio <= 0) zero_h4++;

      // --- 行出力（Ratio=0 でもスキップしない）---
      string line = TimeToString(times[i], TIME_DATE|TIME_MINUTES) + ",";
      line += DoubleToString(h1_atr16, 4) + ",";
      line += DoubleToString(h1_atr32, 4) + ",";
      line += DoubleToString(h1_med,   4) + ",";
      line += DoubleToString(h1_ratio, 3) + ",";
      line += DoubleToString(h4_atr8,  4) + ",";
      line += DoubleToString(h4_atr46, 4) + ",";
      line += DoubleToString(h4_med,   4) + ",";
      line += DoubleToString(h4_ratio, 3);
      FileWriteString(fh, line + "\r\n");
      written++;

      // --- 進捗表示 ---
      if(written % prog_every == 0 || written == total_rows) {
         double pct = 100.0 * written / total_rows;
         Comment(StringFormat("ATR_Ratio_Timeseries: %d / %d (%.1f%%)  %s",
                 written, total_rows, pct,
                 TimeToString(times[i], TIME_DATE)));
         if(written % (prog_every * 4) == 0)
            PrintFormat("progress: %d / %d (%.1f%%)", written, total_rows, pct);
      }
   }

   FileClose(fh);
   Comment("");

   Print("==== ATR_Ratio_Timeseries_v1 Complete ====");
   PrintFormat("Rows written: %d (expected %d)", written, total_rows);
   PrintFormat("Ratio=0 rows: H1=%d, H4=%d (H4 bar not found: %d)",
               zero_h1, zero_h4, h4_miss);
   PrintFormat("Output: %s\\MQL5\\Files\\%s",
               TerminalInfoString(TERMINAL_DATA_PATH), TS_OutputFile);

   ReleaseHandles();
}

//+==================================================================+
//|  ハンドル初期化・解放（gen3と同方式）                            |
//+==================================================================+
bool InitHandles()
{
   hATR_S_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Short);
   hATR_L_H1 = iATR(_Symbol, PERIOD_H1, H1_ATR_Long);
   hATR_S_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(_Symbol, PERIOD_H4, H4_ATR_Long);

   if(hATR_S_H1==INVALID_HANDLE || hATR_L_H1==INVALID_HANDLE ||
      hATR_S_H4==INVALID_HANDLE || hATR_L_H4==INVALID_HANDLE)
   {
      Print("ERROR: Handle init failed");
      return false;
   }
   // インジ計算待ち（gen3と同じ）
   Sleep(2000);
   return true;
}

void ReleaseHandles()
{
   IndicatorRelease(hATR_S_H1); IndicatorRelease(hATR_L_H1);
   IndicatorRelease(hATR_S_H4); IndicatorRelease(hATR_L_H4);
}

//+==================================================================+
//|  CopyBuffer リトライ（履歴ロード待ち対策・最大5回）              |
//+==================================================================+
bool CopyBufRetry(int handle, int count, double &arr[], string tag)
{
   for(int attempt = 1; attempt <= 5; attempt++) {
      ResetLastError();
      int got = CopyBuffer(handle, 0, 0, count, arr);
      if(got > 0) return true;
      PrintFormat("CopyBuffer %s failed (attempt %d/5, err=%d), retrying...",
                  tag, attempt, GetLastError());
      Sleep(1000);
   }
   return false;
}

//+==================================================================+
//|  CalcMedian - gen3 (ATR_WidthSignal_BT_gen3_kc.mq5 L408) から    |
//|  そのまま移植。改変禁止。                                        |
//|  series=true 前提: arr[idx..idx+bars-1] = 現在バー含む過去bars本 |
//|  上側中央値 tmp[cnt/2]                                           |
//+==================================================================+
double CalcMedian(const double &arr[], int idx, int bars)
{
   int sz = ArraySize(arr);
   if(idx + bars >= sz) return 0;
   double tmp[];
   ArrayResize(tmp, bars);
   int cnt = 0;
   for(int k = idx; k < idx + bars; k++)
      if(arr[k] > 0) tmp[cnt++] = arr[k];
   if(cnt < 10) return 0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
}
//+------------------------------------------------------------------+
