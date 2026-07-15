//+------------------------------------------------------------------+
//|  DXY_ADX_Timeseries_v1.mq5                                       |
//|  DXY(USDIndex) H1バーごとの ADX(56)+DI± / ATR32/64 時系列CSV     |
//|                                                                  |
//|  目的: DXYレジーム × XAUUSD既存シグナル のクロス解析基盤          |
//|    - ADX(56): 手描き波分析(2026-07-14)の大波BU=56に基づく試行値   |
//|    - ATR32/64: 中波反周期の本命候補（手描き波 BU31/サイクル91）    |
//|                                                                  |
//|  ベース: ATR_Ratio_Timeseries_v1.mq5（使い回し基盤・同方式）      |
//|    - CalcMedian は gen3 L408 移植のまま（改変禁止）               |
//|    - 中央値: 過去 8週=960本 の上側中央値                          |
//|                                                                  |
//|  シグナル判定・売買ロジックは一切含まない（時系列を吐くだけ）      |
//|                                                                  |
//|  実行: USDIndex チャートで Script 実行（TFは任意・確定バーのみ）  |
//|  出力: MQL5/Files/DXY_ADX_Timeseries_v1.csv                      |
//|        (FILE_UNICODE = UTF-16 LE BOM付き)                        |
//|  列  : Time,Close,ADX,DI_Plus,DI_Minus,ATR_S,ATR_L,Med960,Ratio  |
//|                                                                  |
//|  注意: 中央値が計算不能（履歴不足）の行は Ratio=0 で出力          |
//|        （Python側で除外する前提）                                 |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 期間 ==="
input datetime TS_StartTime     = D'2024.01.01 00:00';  // 出力開始（終端は最新確定バー）

input group "=== 物差し（DXY試行値・2026-07-14） ==="
input int      ADX_Period       = 56;
input int      H1_ATR_Short     = 32;
input int      H1_ATR_Long      = 64;
input int      ATR_Median_Weeks = 8;    // 8週 → 8*5*24=960本

input group "=== 出力 ==="
input string   TS_OutputFile    = "DXY_ADX_Timeseries_v1.csv";
input int      Progress_Every   = 500;

//+-----[ ハンドル ]------------------------------------------------+
int hADX = INVALID_HANDLE;
int hATR_S = INVALID_HANDLE, hATR_L = INVALID_HANDLE;

//+==================================================================+
//|  OnStart                                                         |
//+==================================================================+
void OnStart()
{
   Print("==== DXY_ADX_Timeseries_v1 Start ====");
   PrintFormat("Symbol: %s, Period(chart): %s", _Symbol, EnumToString(_Period));
   PrintFormat("ADX=%d  ATR=%d/%d  MedianWeeks=%d",
               ADX_Period, H1_ATR_Short, H1_ATR_Long, ATR_Median_Weeks);
   PrintFormat("Range: %s 〜 latest confirmed bar",
      TimeToString(TS_StartTime, TIME_DATE|TIME_MINUTES));

   if(!InitHandles()) return;

   // === バー数取得 ===
   int h1_size = (int)Bars(_Symbol, PERIOD_H1);
   PrintFormat("Bars: H1=%d", h1_size);
   if(h1_size <= 0) {
      Print("ERROR: no bars available. Load history first.");
      ReleaseHandles();
      return;
   }

   // === 配列一括取得（series=true / index 0=最新, 大=古い）===
   datetime times[];
   double closes[];
   double adx[], dip[], din[];
   double atr_s[], atr_l[];

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(adx, true); ArraySetAsSeries(dip, true); ArraySetAsSeries(din, true);
   ArraySetAsSeries(atr_s, true); ArraySetAsSeries(atr_l, true);

   if(CopyTime(_Symbol, PERIOD_H1, 0, h1_size, times) <= 0) {
      PrintFormat("ERROR: CopyTime H1 failed (err=%d)", GetLastError());
      ReleaseHandles();
      return;
   }
   if(CopyClose(_Symbol, PERIOD_H1, 0, h1_size, closes) <= 0) {
      PrintFormat("ERROR: CopyClose H1 failed (err=%d)", GetLastError());
      ReleaseHandles();
      return;
   }
   if(!CopyBufRetry(hADX,   0, h1_size, adx,   "ADX main") ||
      !CopyBufRetry(hADX,   1, h1_size, dip,   "DI+")      ||
      !CopyBufRetry(hADX,   2, h1_size, din,   "DI-")      ||
      !CopyBufRetry(hATR_S, 0, h1_size, atr_s, "ATR short")||
      !CopyBufRetry(hATR_L, 0, h1_size, atr_l, "ATR long"))
   {
      Print("ERROR: CopyBuffer failed after retries. Abort.");
      ReleaseHandles();
      return;
   }

   int eff = MathMin(ArraySize(times), MathMin(ArraySize(closes),
             MathMin(ArraySize(adx), MathMin(ArraySize(atr_s), ArraySize(atr_l)))));
   if(eff < h1_size)
      PrintFormat("WARN: copied less than requested. eff=%d/%d", eff, h1_size);

   int median_bars = ATR_Median_Weeks * 5 * 24;   // 8週 → 960

   // === 出力範囲の先頭インデックス（最古の対象バー）===
   int start_idx = -1;
   for(int i = eff - 1; i >= 1; i--) {
      if(times[i] >= TS_StartTime) { start_idx = i; break; }
   }
   if(start_idx < 1) {
      Print("ERROR: no confirmed H1 bars at/after TS_StartTime.");
      ReleaseHandles();
      return;
   }
   PrintFormat("実データ先頭: %s（履歴がStartTimeより浅い場合はここから）",
               TimeToString(times[eff-1], TIME_DATE|TIME_MINUTES));

   if(start_idx + median_bars >= eff)
      PrintFormat("WARN: history short of %d-bar median buffer at range head. "
                  "Early rows will output Ratio=0.", median_bars);

   // === CSVオープン（UTF-16 LE BOM付き）===
   int fh = FileOpen(TS_OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) {
      PrintFormat("ERROR: CSV open failed: err=%d", GetLastError());
      ReleaseHandles();
      return;
   }
   FileWriteString(fh, "Time,Close,ADX,DI_Plus,DI_Minus,ATR_S,ATR_L,Med960,Ratio\r\n");

   // === メインループ: 古い → 新しい（i=0 は形成中バーで除外）===
   int total_rows = start_idx;
   int written = 0, zero_ratio = 0;
   int prog_every = MathMax(1, Progress_Every);

   for(int i = start_idx; i >= 1; i--) {
      if(IsStopped()) { Print("WARN: script stopped by user."); break; }

      double med   = CalcMedian(atr_s, i, median_bars);
      double ratio = (atr_s[i] > 0 && med > 0) ? atr_s[i] / med : 0;
      if(ratio <= 0) zero_ratio++;

      string line = TimeToString(times[i], TIME_DATE|TIME_MINUTES) + ",";
      line += DoubleToString(closes[i], _Digits) + ",";
      line += DoubleToString(adx[i],   2) + ",";
      line += DoubleToString(dip[i],   2) + ",";
      line += DoubleToString(din[i],   2) + ",";
      line += DoubleToString(atr_s[i], 4) + ",";
      line += DoubleToString(atr_l[i], 4) + ",";
      line += DoubleToString(med,      4) + ",";
      line += DoubleToString(ratio,    3);
      FileWriteString(fh, line + "\r\n");
      written++;

      if(written % prog_every == 0 || written == total_rows) {
         double pct = 100.0 * written / total_rows;
         Comment(StringFormat("DXY_ADX_Timeseries: %d / %d (%.1f%%)  %s",
                 written, total_rows, pct, TimeToString(times[i], TIME_DATE)));
         if(written % (prog_every * 4) == 0)
            PrintFormat("progress: %d / %d (%.1f%%)", written, total_rows, pct);
      }
   }

   FileClose(fh);
   Comment("");

   Print("==== DXY_ADX_Timeseries_v1 Complete ====");
   PrintFormat("Rows written: %d (expected %d)  Ratio=0 rows: %d",
               written, total_rows, zero_ratio);
   PrintFormat("Output: %s\\MQL5\\Files\\%s",
               TerminalInfoString(TERMINAL_DATA_PATH), TS_OutputFile);

   ReleaseHandles();
}

//+==================================================================+
//|  ハンドル初期化・解放                                            |
//+==================================================================+
bool InitHandles()
{
   hADX   = iADX(_Symbol, PERIOD_H1, ADX_Period);
   hATR_S = iATR(_Symbol, PERIOD_H1, H1_ATR_Short);
   hATR_L = iATR(_Symbol, PERIOD_H1, H1_ATR_Long);

   if(hADX==INVALID_HANDLE || hATR_S==INVALID_HANDLE || hATR_L==INVALID_HANDLE)
   {
      Print("ERROR: Handle init failed");
      return false;
   }
   Sleep(2000);
   return true;
}

void ReleaseHandles()
{
   IndicatorRelease(hADX);
   IndicatorRelease(hATR_S); IndicatorRelease(hATR_L);
}

//+==================================================================+
//|  CopyBuffer リトライ（履歴ロード待ち対策・最大5回）              |
//+==================================================================+
bool CopyBufRetry(int handle, int buffer, int count, double &arr[], string tag)
{
   for(int attempt = 1; attempt <= 5; attempt++) {
      ResetLastError();
      int got = CopyBuffer(handle, buffer, 0, count, arr);
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
