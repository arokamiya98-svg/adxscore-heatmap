//+------------------------------------------------------------------+
//|  DXY_Synth_Timeseries_v1.mq5                                     |
//|  合成DXY（ICE式からSEK項を除いた5項）を CustomSymbol に構築し、  |
//|  H1バーごとの ADX(56)+DI± / ATR32/64 時系列CSVを出力する         |
//|                                                                  |
//|  目的: DXY環境札 v3 Phase 1 §3.1 検証用                          |
//|    HFM USDIndex版（DXY_ADX_Timeseries_v1.csv）との突合用データ   |
//|    指示書: data/scriptable/コー_impl_dxy_card_v3_synth.md        |
//|                                                                  |
//|  ベース: DXY_ADX_Timeseries_v1.mq5                               |
//|    - 出力列・UTF-16・ADX56/ATR32/64/Med960/Ratio 規約を踏襲      |
//|    - CalcMedian は gen3 L408 移植のまま（改変禁止）              |
//|                                                                  |
//|  合成式（SEK項なし・再正規化なし）:                              |
//|    DXY = 50.14348112 × EURUSD^-0.576 × USDJPY^0.136              |
//|                      × GBPUSD^-0.119 × USDCAD^0.091              |
//|                      × USDCHF^0.036                              |
//|                                                                  |
//|  処理:                                                           |
//|    1. 成分 M1（不足時 M5）を Chunk_Days ごとに取得               |
//|    2. 時刻突合（union timeline）。欠損は直前Closeで埋める        |
//|       ただし 週末跨ぎ / Max_Fill_Hours 超 は埋めない＝その分skip |
//|    3. 合成 OHLC を log空間で計算（負の指数の成分は H/L 入替）    |
//|    4. DXY_SYNTH を全削除 → チャンク毎に CustomRatesReplace       |
//|    5. DXY_SYNTH H1 で iADX/iATR → CSV                            |
//|                                                                  |
//|  実行: 任意チャートで Script 実行（Exnessセント口座想定・VPS）   |
//|  出力: MQL5/Files/DXY_Synth_Timeseries_v1.csv                    |
//|        (FILE_UNICODE = UTF-16 LE BOM付き)                        |
//|  列  : Time,Close,ADX,DI_Plus,DI_Minus,ATR_S,ATR_L,Med960,Ratio  |
//|        Time はサーバー時刻そのまま（オフセットは突合側で検出）   |
//|  ログ: MQL5/Files/DXY_Synth_Timeseries_v1_log.txt（UTF-16）      |
//|        採用TF・実開始日時・チャンク毎の書込成否を記録            |
//|                                                                  |
//|  シグナル判定・売買ロジックは一切含まない（時系列を吐くだけ）     |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property script_show_inputs
#property strict

#define NCOMP 5

enum ENUM_SRC_TF
{
   SRC_AUTO = 0,   // AUTO（M1優先・不足ならM5）
   SRC_M1   = 1,   // M1 強制
   SRC_M5   = 2    // M5 強制
};

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 期間 ==="
input datetime TS_StartTime     = D'2024.01.01 00:00';  // 出力開始（終端は最新確定バー）
input int      Warmup_Days      = 120;  // 合成の構築開始を前倒し（Med960/ADX56 の助走）

input group "=== 合成DXY ==="
input string   Synth_Symbol     = "DXY_SYNTH";
input string   Synth_Path       = "Synth";      // Custom\Synth に作成
input int      Synth_Digits     = 5;
input double   Synth_Const      = 50.14348112;
input string   Comp1_Symbol     = "EURUSDc";
input double   Comp1_Weight     = -0.576;
input string   Comp2_Symbol     = "USDJPYc";
input double   Comp2_Weight     = 0.136;
input string   Comp3_Symbol     = "GBPUSDc";
input double   Comp3_Weight     = -0.119;
input string   Comp4_Symbol     = "USDCADc";
input double   Comp4_Weight     = 0.091;
input string   Comp5_Symbol     = "USDCHFc";
input double   Comp5_Weight     = 0.036;

input group "=== ソースTF・欠損埋め ==="
input ENUM_SRC_TF Source_TF     = SRC_AUTO;
input int      Probe_Tolerance_Days = 7;    // 構築開始からこの日数以内に初バーがあれば「届いた」判定
input int      Max_Fill_Hours   = 48;       // 直前値埋めの上限（超えたら埋めない）

input group "=== CustomRates 書き込み ==="
input int      Chunk_Days       = 7;        // 取得・書込の単位（日）
input int      Max_Rates_Per_Write = 10000; // 1回の CustomRatesReplace の上限件数

input group "=== 物差し（DXY試行値・2026-07-14） ==="
input int      ADX_Period       = 56;
input int      H1_ATR_Short     = 32;
input int      H1_ATR_Long      = 64;
input int      ATR_Median_Weeks = 8;    // 8週 → 8*5*24=960本

input group "=== 出力 ==="
input string   TS_OutputFile    = "DXY_Synth_Timeseries_v1.csv";
input string   Log_File         = "DXY_Synth_Timeseries_v1_log.txt";
input int      Progress_Every   = 500;

//+-----[ 型・グローバル ]------------------------------------------+
struct CompRates { MqlRates r[]; };

string   g_sym[NCOMP];
double   g_w[NCOMP];

// 直前値埋め用の状態（チャンクを跨いで保持）
bool     g_has[NCOMP];
datetime g_last_t[NCOMP];
double   g_last_c[NCOMP];
long     g_filled[NCOMP];
long     g_real[NCOMP];

int hADX = INVALID_HANDLE;
int hATR_S = INVALID_HANDLE, hATR_L = INVALID_HANDLE;
int g_log = INVALID_HANDLE;

//+==================================================================+
//|  ログ（Print + ログファイル）                                    |
//+==================================================================+
void Log(const string s)
{
   Print(s);
   if(g_log != INVALID_HANDLE) { FileWriteString(g_log, s + "\r\n"); FileFlush(g_log); }
}
void LogFileOnly(const string s)
{
   if(g_log != INVALID_HANDLE) { FileWriteString(g_log, s + "\r\n"); }
}

//+==================================================================+
//|  OnStart                                                         |
//+==================================================================+
void OnStart()
{
   g_log = FileOpen(Log_File, FILE_WRITE|FILE_TXT|FILE_UNICODE);
   if(g_log == INVALID_HANDLE)
      PrintFormat("WARN: log file open failed (err=%d). Print only.", GetLastError());

   Log("==== DXY_Synth_Timeseries_v1 Start ====");
   Log("Run at (server): " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Log("Server: " + AccountInfoString(ACCOUNT_SERVER));
   Log(StringFormat("TerminalMaxBars: %d", (int)TerminalInfoInteger(TERMINAL_MAXBARS)));
   Log(StringFormat("ADX=%d  ATR=%d/%d  MedianWeeks=%d",
       ADX_Period, H1_ATR_Short, H1_ATR_Long, ATR_Median_Weeks));

   g_sym[0]=Comp1_Symbol; g_w[0]=Comp1_Weight;
   g_sym[1]=Comp2_Symbol; g_w[1]=Comp2_Weight;
   g_sym[2]=Comp3_Symbol; g_w[2]=Comp3_Weight;
   g_sym[3]=Comp4_Symbol; g_w[3]=Comp4_Weight;
   g_sym[4]=Comp5_Symbol; g_w[4]=Comp5_Weight;

   string f = StringFormat("Formula: %s", DoubleToString(Synth_Const, 8));
   for(int k = 0; k < NCOMP; k++)
      f += StringFormat(" x %s^%s", g_sym[k], DoubleToString(g_w[k], 3));
   Log(f);

   datetime build_start = TS_StartTime - (datetime)((long)MathMax(0, Warmup_Days) * 86400);
   Log("Output range: " + TimeToString(TS_StartTime, TIME_DATE|TIME_MINUTES) + " - latest confirmed H1 bar");
   Log("Build start (with warmup): " + TimeToString(build_start, TIME_DATE|TIME_MINUTES));

   // === 1. 成分銘柄の存在確認 ===
   for(int k = 0; k < NCOMP; k++) {
      if(!SymbolSelect(g_sym[k], true)) {
         Log(StringFormat("ERROR: component symbol not available: %s (err=%d)", g_sym[k], GetLastError()));
         Finish(); return;
      }
   }

   // === 2. ソースTF決定（M1 → 不足なら M5）===
   ENUM_TIMEFRAMES tf = PERIOD_M1;
   if(!DecideSourceTF(build_start, tf)) { Finish(); return; }

   // === 3. カスタムシンボル準備 ===
   if(!PrepareCustomSymbol()) { Finish(); return; }

   // === 4. 合成 → 分割書き込み ===
   datetime synth_first = 0, synth_last = 0;
   if(!BuildAndWrite(build_start, tf, synth_first, synth_last)) { Finish(); return; }

   // === 5. H1 で指標計算 → CSV ===
   ExportTimeseries();

   Finish();
}

void Finish()
{
   ReleaseHandles();
   Comment("");
   Log("==== DXY_Synth_Timeseries_v1 End ====");
   if(g_log != INVALID_HANDLE) { FileClose(g_log); g_log = INVALID_HANDLE; }
}

//+==================================================================+
//|  ソースTF決定                                                    |
//+==================================================================+
bool ProbeHistory(const string sym, ENUM_TIMEFRAMES tf, datetime from, datetime &first_avail)
{
   first_avail = 0;
   datetime to = from + (datetime)((long)MathMax(1, Probe_Tolerance_Days) * 86400);
   for(int attempt = 1; attempt <= 5; attempt++) {
      datetime t[];
      ResetLastError();
      int n = CopyTime(sym, tf, from, to, t);   // 履歴ダウンロードのトリガーも兼ねる
      if(n > 0) { first_avail = t[0]; return true; }
      Sleep(1500);
   }
   first_avail = (datetime)SeriesInfoInteger(sym, tf, SERIES_FIRSTDATE);
   return false;
}

bool DecideSourceTF(datetime build_start, ENUM_TIMEFRAMES &tf)
{
   if(Source_TF == SRC_M1) { tf = PERIOD_M1; Log("Source TF: M1 (forced by input)"); }
   else if(Source_TF == SRC_M5) { tf = PERIOD_M5; Log("Source TF: M5 (forced by input)"); }
   else {
      bool m1_ok = true;
      for(int k = 0; k < NCOMP; k++) {
         datetime fa;
         bool ok = ProbeHistory(g_sym[k], PERIOD_M1, build_start, fa);
         Log(StringFormat("Probe M1 %s: %s first=%s", g_sym[k], ok ? "OK" : "SHORT",
             fa > 0 ? TimeToString(fa, TIME_DATE|TIME_MINUTES) : "n/a"));
         if(!ok) m1_ok = false;
      }
      tf = m1_ok ? PERIOD_M1 : PERIOD_M5;
      Log(m1_ok ? "Source TF: M1 (AUTO: M1 history reaches build start)"
                : "Source TF: M5 (AUTO: M1 history short -> fallback)");
   }

   // 採用TFでの到達確認（届かなくても続行・実開始日時をログに残す）
   for(int k = 0; k < NCOMP; k++) {
      datetime fa;
      bool ok = ProbeHistory(g_sym[k], tf, build_start, fa);
      Log(StringFormat("Probe %s %s: %s first=%s", EnumToString(tf), g_sym[k], ok ? "OK" : "SHORT",
          fa > 0 ? TimeToString(fa, TIME_DATE|TIME_MINUTES) : "n/a"));
      if(!ok) Log(StringFormat("WARN: %s %s history does not reach build start. Synth starts later.",
                               g_sym[k], EnumToString(tf)));
   }
   return true;
}

//+==================================================================+
//|  カスタムシンボル準備（既存なら再利用・全レート削除）            |
//+==================================================================+
bool PrepareCustomSymbol()
{
   bool is_custom = false;
   if(SymbolExist(Synth_Symbol, is_custom)) {
      if(!is_custom) {
         Log("ERROR: " + Synth_Symbol + " exists as a broker symbol (not custom). Abort.");
         return false;
      }
      Log("Custom symbol exists -> reuse: " + Synth_Symbol);
   } else {
      ResetLastError();
      if(!CustomSymbolCreate(Synth_Symbol, Synth_Path)) {
         Log(StringFormat("ERROR: CustomSymbolCreate failed (err=%d)", GetLastError()));
         return false;
      }
      Log("Custom symbol created: Custom\\" + Synth_Path + "\\" + Synth_Symbol);
   }

   // プロパティ（失敗しても致命ではない＝WARN）
   if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_DIGITS, Synth_Digits))
      Log(StringFormat("WARN: set DIGITS failed (err=%d)", GetLastError()));
   if(!CustomSymbolSetDouble(Synth_Symbol, SYMBOL_POINT, MathPow(10.0, -Synth_Digits)))
      Log(StringFormat("WARN: set POINT failed (err=%d)", GetLastError()));
   if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID))
      Log(StringFormat("WARN: set CHART_MODE failed (err=%d)", GetLastError()));
   if(!CustomSymbolSetInteger(Synth_Symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED))
      Log(StringFormat("WARN: set TRADE_MODE failed (err=%d)", GetLastError()));
   CustomSymbolSetString(Synth_Symbol, SYMBOL_DESCRIPTION, "Synthetic DXY (ICE ex-SEK, 5 pairs)");

   // 期間丸ごと置換: 既存レートを全削除してからチャンク毎に Replace
   ResetLastError();
   int del = CustomRatesDelete(Synth_Symbol, 0, D'3000.01.01 00:00');
   Log(StringFormat("CustomRatesDelete(all): %d bars removed (err=%d)", del, GetLastError()));
   if(del < 0) {
      Log("ERROR: CustomRatesDelete failed. Abort (avoid mixing old/new rates).");
      return false;
   }
   return true;
}

//+==================================================================+
//|  週末跨ぎ判定: t_last 以後の最初の土曜12:00 を t_now が越えたか  |
//|  （サーバー時刻 GMT+0〜+3 のどれでも土曜昼は確実に休場）          |
//+==================================================================+
bool CrossesWeekend(datetime t_last, datetime t_now)
{
   MqlDateTime dt;
   TimeToStruct(t_last, dt);
   datetime day0 = t_last - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   int days_to_sat = (6 - dt.day_of_week + 7) % 7;
   datetime sat_noon = day0 + (datetime)(days_to_sat * 86400 + 12 * 3600);
   if(t_last >= sat_noon) sat_noon += 7 * 86400;
   return (t_now >= sat_noon);
}

bool CanFill(int k, datetime t)
{
   if(!g_has[k]) return false;
   if((long)(t - g_last_t[k]) > (long)Max_Fill_Hours * 3600) return false;
   if(CrossesWeekend(g_last_t[k], t)) return false;
   return true;
}

//+==================================================================+
//|  CopyRates リトライ（範囲指定・履歴ロード待ち）                  |
//+==================================================================+
int CopyRatesRetry(const string sym, ENUM_TIMEFRAMES tf, datetime from, datetime to, MqlRates &arr[])
{
   ArraySetAsSeries(arr, false);
   for(int attempt = 1; attempt <= 3; attempt++) {
      ResetLastError();
      int n = CopyRates(sym, tf, from, to, arr);
      if(n >= 0) return n;
      int err = GetLastError();
      if(err != 4401 && err != 4066 && attempt >= 2) return 0;  // 休場等で本当に無い
      Sleep(1000);
   }
   return 0;
}

//+==================================================================+
//|  CustomRatesReplace 分割書き込み                                 |
//+==================================================================+
bool WriteRates(const MqlRates &arr[], int n, int chunk_no)
{
   int maxw = MathMax(100, Max_Rates_Per_Write);
   for(int a = 0; a < n; a += maxw) {
      int cnt = MathMin(maxw, n - a);
      MqlRates sub[];
      ArrayResize(sub, cnt);
      for(int j = 0; j < cnt; j++) sub[j] = arr[a + j];

      int r = -1, err = 0;
      for(int attempt = 1; attempt <= 2; attempt++) {
         ResetLastError();
         r = CustomRatesReplace(Synth_Symbol, sub[0].time, sub[cnt - 1].time, sub);
         err = GetLastError();
         if(r >= 0) break;
         Sleep(500);
      }
      string msg = StringFormat("  write chunk#%d part@%d: %s..%s n=%d -> %s (ret=%d err=%d)",
                   chunk_no, a,
                   TimeToString(sub[0].time, TIME_DATE|TIME_MINUTES),
                   TimeToString(sub[cnt - 1].time, TIME_DATE|TIME_MINUTES),
                   cnt, r >= 0 ? "OK" : "FAIL", r, err);
      if(r < 0) { Log(msg); return false; }
      LogFileOnly(msg);
   }
   return true;
}

//+==================================================================+
//|  合成M1(M5)構築 → 分割書き込み                                   |
//+==================================================================+
bool BuildAndWrite(datetime build_start, ENUM_TIMEFRAMES tf,
                   datetime &synth_first, datetime &synth_last)
{
   for(int k = 0; k < NCOMP; k++) {
      g_has[k] = false; g_last_t[k] = 0; g_last_c[k] = 0;
      g_filled[k] = 0; g_real[k] = 0;
   }
   long skipped = 0, total_written = 0;
   datetime comp_first[NCOMP];
   for(int k = 0; k < NCOMP; k++) comp_first[k] = 0;

   double lnK = MathLog(Synth_Const);
   double pt  = MathPow(10.0, -Synth_Digits);
   datetime end_time = TimeCurrent() + 3600;
   long chunk_sec = (long)MathMax(1, Chunk_Days) * 86400;

   int chunk_no = 0;
   for(datetime cf = build_start; cf <= end_time; cf += (datetime)chunk_sec) {
      if(IsStopped()) { Log("WARN: script stopped by user."); return false; }
      chunk_no++;
      datetime ct = cf + (datetime)(chunk_sec - 1);   // 両端含む＝重複なし

      // 成分を順次取得（1チャンク分のみ保持）
      CompRates comp[NCOMP];
      int n[NCOMP], p[NCOMP];
      int any = 0;
      for(int k = 0; k < NCOMP; k++) {
         n[k] = CopyRatesRetry(g_sym[k], tf, cf, ct, comp[k].r);
         p[k] = 0;
         any += n[k];
         if(n[k] > 0 && comp_first[k] == 0) comp_first[k] = comp[k].r[0].time;
      }
      if(any == 0) {
         LogFileOnly(StringFormat("  chunk#%d %s: no data (holiday/out of history)",
                     chunk_no, TimeToString(cf, TIME_DATE)));
         continue;
      }

      MqlRates out[];
      int cap = 0;
      for(int k = 0; k < NCOMP; k++) cap = MathMax(cap, n[k]);
      ArrayResize(out, 0, cap + 1024);
      int on = 0;

      // union timeline マージ
      while(true) {
         datetime t = 0; bool found = false;
         for(int k = 0; k < NCOMP; k++)
            if(p[k] < n[k] && (!found || comp[k].r[p[k]].time < t)) { t = comp[k].r[p[k]].time; found = true; }
         if(!found) break;

         double lnO = lnK, lnH = lnK, lnL = lnK, lnC = lnK;
         long   vol = 0;
         bool   ok  = true;

         for(int k = 0; k < NCOMP; k++) {
            double o = 0, h = 0, l = 0, c = 0;
            bool real = false;
            if(p[k] < n[k] && comp[k].r[p[k]].time == t) {
               MqlRates b = comp[k].r[p[k]];
               p[k]++;
               if(b.open > 0 && b.high > 0 && b.low > 0 && b.close > 0) {
                  o = b.open; h = b.high; l = b.low; c = b.close;
                  vol += b.tick_volume;
                  real = true;
               }
            }
            if(real) {
               g_has[k] = true; g_last_t[k] = t; g_last_c[k] = c; g_real[k]++;
            } else if(CanFill(k, t)) {
               o = h = l = c = g_last_c[k];      // 直前Closeで平坦に埋める
               g_filled[k]++;
            } else {
               ok = false;                       // 週末跨ぎ/48h超/未開始 → この足は作らない
               continue;                         // 他成分の状態更新は続ける
            }
            double w = g_w[k];
            lnO += w * MathLog(o);
            lnC += w * MathLog(c);
            if(w >= 0) { lnH += w * MathLog(h); lnL += w * MathLog(l); }
            else       { lnH += w * MathLog(l); lnL += w * MathLog(h); }  // 負の指数: H/L 入替
         }
         if(!ok) { skipped++; continue; }

         MqlRates s;
         s.time  = t;
         s.open  = NormalizeDouble(MathExp(lnO), Synth_Digits);
         s.close = NormalizeDouble(MathExp(lnC), Synth_Digits);
         s.high  = NormalizeDouble(MathExp(lnH), Synth_Digits);
         s.low   = NormalizeDouble(MathExp(lnL), Synth_Digits);
         s.high  = MathMax(s.high, MathMax(s.open, s.close));
         s.low   = MathMin(s.low,  MathMin(s.open, s.close));
         s.tick_volume = (vol > 0 ? vol : 1);
         s.spread = 0;
         s.real_volume = 0;

         ArrayResize(out, on + 1, cap + 1024);
         out[on++] = s;
      }

      if(on > 0) {
         if(synth_first == 0) synth_first = out[0].time;
         synth_last = out[on - 1].time;
         if(!WriteRates(out, on, chunk_no)) {
            Log("ERROR: CustomRatesReplace failed. Abort (CSV not written).");
            return false;
         }
         total_written += on;
      }

      if(chunk_no % 10 == 0) {
         string m = StringFormat("build progress: chunk#%d up to %s, synth bars=%I64d",
                    chunk_no, TimeToString(ct, TIME_DATE), total_written);
         Log(m);
         Comment("DXY_Synth: " + m);
      }
   }

   Log("---- Build summary ----");
   Log(StringFormat("Source TF: %s", EnumToString(tf)));
   for(int k = 0; k < NCOMP; k++)
      Log(StringFormat("  %s: first=%s real=%I64d filled=%I64d", g_sym[k],
          comp_first[k] > 0 ? TimeToString(comp_first[k], TIME_DATE|TIME_MINUTES) : "n/a",
          g_real[k], g_filled[k]));
   Log(StringFormat("Synth bars written: %I64d  skipped(unfillable): %I64d", total_written, skipped));
   Log("Synth actual start: " + (synth_first > 0 ? TimeToString(synth_first, TIME_DATE|TIME_MINUTES) : "n/a"));
   Log("Synth last bar    : " + (synth_last  > 0 ? TimeToString(synth_last,  TIME_DATE|TIME_MINUTES) : "n/a"));
   if(synth_first > TS_StartTime)
      Log("WARN: synth starts AFTER TS_StartTime. Early output rows are missing / Ratio=0.");

   if(total_written == 0) { Log("ERROR: no synthetic bars built. Abort."); return false; }
   return true;
}

//+==================================================================+
//|  H1 系列の生成待ち                                              |
//+==================================================================+
int WaitH1Ready()
{
   SymbolSelect(Synth_Symbol, true);
   int bars = 0;
   for(int attempt = 1; attempt <= 30; attempt++) {
      datetime t[];
      CopyTime(Synth_Symbol, PERIOD_H1, 0, 1, t);   // 生成トリガー
      bars = Bars(Synth_Symbol, PERIOD_H1);
      bool sync = (bool)SeriesInfoInteger(Synth_Symbol, PERIOD_H1, SERIES_SYNCHRONIZED);
      if(bars > 0 && sync) break;
      Sleep(1000);
   }
   return bars;
}

//+==================================================================+
//|  指標計算 → CSV（v1 と同一の列・書式）                           |
//+==================================================================+
void ExportTimeseries()
{
   int h1_size = WaitH1Ready();
   Log(StringFormat("Bars: %s H1=%d", Synth_Symbol, h1_size));
   if(h1_size <= 0) { Log("ERROR: H1 series of synth not available."); return; }

   if(!InitHandles()) return;

   // 指標の計算完了待ち
   for(int attempt = 1; attempt <= 30; attempt++) {
      if(BarsCalculated(hADX) >= h1_size && BarsCalculated(hATR_S) >= h1_size &&
         BarsCalculated(hATR_L) >= h1_size) break;
      Sleep(1000);
   }

   datetime times[];
   double closes[];
   double adx[], dip[], din[];
   double atr_s[], atr_l[];

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(adx, true); ArraySetAsSeries(dip, true); ArraySetAsSeries(din, true);
   ArraySetAsSeries(atr_s, true); ArraySetAsSeries(atr_l, true);

   if(CopyTime(Synth_Symbol, PERIOD_H1, 0, h1_size, times) <= 0) {
      Log(StringFormat("ERROR: CopyTime H1 failed (err=%d)", GetLastError())); return;
   }
   if(CopyClose(Synth_Symbol, PERIOD_H1, 0, h1_size, closes) <= 0) {
      Log(StringFormat("ERROR: CopyClose H1 failed (err=%d)", GetLastError())); return;
   }
   if(!CopyBufRetry(hADX,   0, h1_size, adx,   "ADX main") ||
      !CopyBufRetry(hADX,   1, h1_size, dip,   "DI+")      ||
      !CopyBufRetry(hADX,   2, h1_size, din,   "DI-")      ||
      !CopyBufRetry(hATR_S, 0, h1_size, atr_s, "ATR short")||
      !CopyBufRetry(hATR_L, 0, h1_size, atr_l, "ATR long"))
   {
      Log("ERROR: CopyBuffer failed after retries. Abort.");
      return;
   }

   int eff = MathMin(ArraySize(times), MathMin(ArraySize(closes),
             MathMin(ArraySize(adx), MathMin(ArraySize(atr_s), ArraySize(atr_l)))));
   if(eff < h1_size)
      Log(StringFormat("WARN: copied less than requested. eff=%d/%d", eff, h1_size));

   int median_bars = ATR_Median_Weeks * 5 * 24;   // 8週 → 960

   int start_idx = -1;
   for(int i = eff - 1; i >= 1; i--) {
      if(times[i] >= TS_StartTime) { start_idx = i; break; }
   }
   if(start_idx < 1) { Log("ERROR: no confirmed H1 bars at/after TS_StartTime."); return; }
   Log("H1 data head: " + TimeToString(times[eff-1], TIME_DATE|TIME_MINUTES));
   Log("Output first row: " + TimeToString(times[start_idx], TIME_DATE|TIME_MINUTES));

   if(start_idx + median_bars >= eff)
      Log(StringFormat("WARN: history short of %d-bar median buffer at range head. "
                       "Early rows will output Ratio=0.", median_bars));

   int fh = FileOpen(TS_OutputFile, FILE_WRITE|FILE_TXT|FILE_UNICODE, ',');
   if(fh == INVALID_HANDLE) {
      Log(StringFormat("ERROR: CSV open failed: err=%d", GetLastError())); return;
   }
   FileWriteString(fh, "Time,Close,ADX,DI_Plus,DI_Minus,ATR_S,ATR_L,Med960,Ratio\r\n");

   int total_rows = start_idx;
   int written = 0, zero_ratio = 0;
   int prog_every = MathMax(1, Progress_Every);

   for(int i = start_idx; i >= 1; i--) {
      if(IsStopped()) { Log("WARN: script stopped by user."); break; }

      double med   = CalcMedian(atr_s, i, median_bars);
      double ratio = (atr_s[i] > 0 && med > 0) ? atr_s[i] / med : 0;
      if(ratio <= 0) zero_ratio++;

      string line = TimeToString(times[i], TIME_DATE|TIME_MINUTES) + ",";
      line += DoubleToString(closes[i], Synth_Digits) + ",";
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
         Comment(StringFormat("DXY_Synth_Timeseries: %d / %d (%.1f%%)  %s",
                 written, total_rows, pct, TimeToString(times[i], TIME_DATE)));
         if(written % (prog_every * 4) == 0)
            PrintFormat("progress: %d / %d (%.1f%%)", written, total_rows, pct);
      }
   }

   FileClose(fh);

   Log(StringFormat("Rows written: %d (expected %d)  Ratio=0 rows: %d",
       written, total_rows, zero_ratio));
   Log(StringFormat("Output: %s\\MQL5\\Files\\%s",
       TerminalInfoString(TERMINAL_DATA_PATH), TS_OutputFile));
}

//+==================================================================+
//|  ハンドル初期化・解放                                            |
//+==================================================================+
bool InitHandles()
{
   hADX   = iADX(Synth_Symbol, PERIOD_H1, ADX_Period);
   hATR_S = iATR(Synth_Symbol, PERIOD_H1, H1_ATR_Short);
   hATR_L = iATR(Synth_Symbol, PERIOD_H1, H1_ATR_Long);

   if(hADX==INVALID_HANDLE || hATR_S==INVALID_HANDLE || hATR_L==INVALID_HANDLE)
   {
      Log("ERROR: Handle init failed");
      return false;
   }
   Sleep(2000);
   return true;
}

void ReleaseHandles()
{
   if(hADX   != INVALID_HANDLE) { IndicatorRelease(hADX);   hADX   = INVALID_HANDLE; }
   if(hATR_S != INVALID_HANDLE) { IndicatorRelease(hATR_S); hATR_S = INVALID_HANDLE; }
   if(hATR_L != INVALID_HANDLE) { IndicatorRelease(hATR_L); hATR_L = INVALID_HANDLE; }
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
