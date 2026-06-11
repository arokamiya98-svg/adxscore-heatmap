//+------------------------------------------------------------------+
//|  XAUUSD_Daily_MFE_MAE_v1.mq5                                     |
//|                                                                  |
//|  非トレード日も含めた全営業日について、JST 14:00 仮想エントリー   |
//|  時点からの 48時間 (H1 × 48本) MFE/MAE を BUY/SELL 両方記録する。 |
//|                                                                  |
//|  研究目的（絶対固定）:                                            |
//|    日次研究カレンダー（マニ実装）のデータソース拡張。              |
//|    「どの市場環境で期待値が発生していたか」を全営業日で見るため、 |
//|    既存 trade_input.csv（実トレード日のみ）を全営業日に拡張する。 |
//|                                                                  |
//|  禁止事項:                                                        |
//|    - 勝率分析 / PF分析 / 月別集計 / 損益集計の目的化              |
//|    - パターン別重み付け、加熱帯ペナルティ等の判断ロジック混入      |
//|    - 「日次変動の捏造」(推定値・補完値の混入)                     |
//|    - 12h/24h/36h セグメント値の「評価ラベル化」                  |
//|      (例: 「12h で MFE 大きい→いい兆候」のようなラベル付け禁止)  |
//|                                                                  |
//|  指示書: data/mani_room/コー_指示書_日次研究データ取得_v0.1.md    |
//|                                                                  |
//|  v1.1 (2026-06-10 PM) 改訂:                                       |
//|    - H1 のみ時間別化: 12h / 24h / 36h セグメント MFE/MAE 追加     |
//|      (48h 維持 + 既存カラム名は完全維持、新規カラム追加のみ)      |
//|    - 後方互換: buy_mfe_usd / buy_mae_usd / sell_mfe_usd /         |
//|      sell_mae_usd は 48h 値として現状維持 (リネームなし)          |
//|    - 新規追加: buy_mfe_12h_usd / buy_mae_12h_usd /                |
//|      sell_mfe_12h_usd / sell_mae_12h_usd (同 24h / 36h)           |
//|    - bar_idx は 48h のみ維持、12h/24h/36h は省略 (コー判断)       |
//|      → 軌跡解像度は十分、bar_idx は到達点識別用                  |
//|                                                                  |
//|  参照ロジック (流用元):                                            |
//|    - Trade_Snapshot_Builder.mq5 v1.1:                            |
//|        JstToServer / ServerToJst (GMT offset 自動算出)            |
//|        TraceMaeMfe48h (48h MFE/MAE 三層追跡の H1 部分)            |
//|        WriteUtf8Bom / WriteUtf8String (UTF-8 BOM 出力)            |
//|                                                                  |
//|  入力: なし (MT5から直接取得)                                      |
//|  出力: MQL5/Files/daily_mfe_mae_48h.csv (UTF-8 BOM)              |
//|                                                                  |
//|  実装メモ (取得項目の根拠):                                        |
//|    date                : マニ側カレンダー結合キー                  |
//|    virtual_entry_jst   : 仮想エントリー時刻 (JST 14:00, あろさん   |
//|                         東京時間メイン戦略の実勢時刻)               |
//|    virtual_entry_price : その時刻 H1 close (事実情報)             |
//|    buy_mfe_usd / buy_mae_usd  : BUY 仮想 48h 振れ幅 (事実情報)    |
//|    sell_mfe_usd / sell_mae_usd: SELL 仮想 48h 振れ幅 (事実情報)   |
//|    buy_mfe_12h_usd / buy_mae_12h_usd : BUY 仮想 12h 振れ幅       |
//|    buy_mfe_24h_usd / buy_mae_24h_usd : BUY 仮想 24h 振れ幅       |
//|    buy_mfe_36h_usd / buy_mae_36h_usd : BUY 仮想 36h 振れ幅       |
//|    sell_mfe_12h_usd / sell_mae_12h_usd 〜 36h : 同 SELL          |
//|    bars_traced         : 実際に追跡できたH1足数 (品質情報, 48h基準)|
//|                                                                  |
//|  作成日: 2026-06-10                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.10"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 出力ファイル ==="
input string  Output_File              = "daily_mfe_mae_48h.csv";

input group "=== 取得期間 ==="
input int     Lookback_Days            = 120;      // 直近何日分を出力するか
input string  Virtual_Entry_Time_JST   = "14:00";  // 仮想エントリー時刻 (JST)

input group "=== タイムゾーン ==="
input int     JST_Offset_Hours         = 9;        // JST = UTC+9 (固定)
input bool    Use_Auto_Server_Offset   = true;     // TimeTradeServer-TimeGMT 自動算出
input int     Manual_Server_Offset_Hours = 2;      // 自動算出失敗時のフォールバック

input group "=== 48h MFE/MAE 追跡 ==="
input int     H1_Trace_Bars_48h        = 48;       // H1 48本 = 48時間相当

input group "=== シンボル制約 ==="
input string  Allowed_Symbol           = "XAUUSD"; // この銘柄以外はスキップ

input group "=== デバッグ ==="
input bool    Verbose                  = true;

//+-----[ 集計カウンタ ]--------------------------------------------+
int g_rows_written = 0;
int g_rows_skipped = 0;
int g_rows_partial = 0;  // 48本フル追跡できなかった行

//+==================================================================+
//| OnStart                                                          |
//+==================================================================+
void OnStart()
{
   Print("==== XAUUSD_Daily_MFE_MAE v1.1 Start ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, Allowed_Symbol);
   PrintFormat("Output: %s", Output_File);
   PrintFormat("Lookback: %d days, Virtual entry: %s JST",
               Lookback_Days, Virtual_Entry_Time_JST);
   PrintFormat("Time-segmented MFE/MAE: 12h / 24h / 36h / 48h (H1 only)");

   //--- シンボル制約チェック ---
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return;
   }

   //--- 仮想エントリー時刻パース (HH:MM) ---
   int entry_hh = 0, entry_mm = 0;
   if(!ParseHHMM(Virtual_Entry_Time_JST, entry_hh, entry_mm))
   {
      PrintFormat("[FATAL] Virtual_Entry_Time_JST のパース失敗: %s (形式: HH:MM)",
                  Virtual_Entry_Time_JST);
      return;
   }

   //--- 出力 CSV オープン (UTF-8 BOM) ---
   int fout = FileOpen(Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 出力CSV open失敗: %s err=%d", Output_File, GetLastError());
      return;
   }
   WriteUtf8Bom(fout);
   WriteHeaderUtf8(fout);

   //--- DST 境界跨ぎ警告 ---
   if(Use_Auto_Server_Offset && Verbose)
   {
      long ofs = (long)(TimeTradeServer() - TimeGMT());
      PrintFormat("[INFO] Current server-GMT offset = %d sec (= %.2f h). "
                  "DST境界を跨ぐ期間内ではズレに注意.",
                  (int)ofs, ofs/3600.0);
   }

   //--- 走査範囲: 今日 - Lookback_Days  〜 今日 ---
   //   JST 基準の日付を1日ずつシフトしながら走査                     ---
   //   起点: 今日 (JST) - Lookback_Days 日前 0:00 JST              ---
   datetime now_server = TimeTradeServer();
   datetime now_jst    = ServerToJst(now_server);
   //--- 今日 (JST) 0:00 ---
   MqlDateTime today_jst_dt;
   TimeToStruct(now_jst, today_jst_dt);
   today_jst_dt.hour = 0;
   today_jst_dt.min  = 0;
   today_jst_dt.sec  = 0;
   datetime today_jst_0000 = StructToTime(today_jst_dt);

   //--- 走査開始日 (JST 0:00) ---
   datetime start_jst_0000 = today_jst_0000 - (datetime)((Lookback_Days - 1) * 86400);

   //--- ループ: 1日ずつ仮想エントリーを試行 ---
   for(int d = 0; d < Lookback_Days; d++)
   {
      datetime day_jst_0000 = start_jst_0000 + (datetime)(d * 86400);

      //--- その日の仮想エントリー時刻 (JST) を組み立てる ---
      MqlDateTime ve_dt;
      TimeToStruct(day_jst_0000, ve_dt);
      ve_dt.hour = entry_hh;
      ve_dt.min  = entry_mm;
      ve_dt.sec  = 0;
      datetime virtual_entry_jst = StructToTime(ve_dt);

      //--- 未来日付なら出力しない (今日 14:00 がまだ来てない場合等) ---
      if(virtual_entry_jst > now_jst)
      {
         if(Verbose) PrintFormat("[SKIP] future entry %s",
                                  FormatJstDateTime(virtual_entry_jst));
         continue;
      }

      ProcessDay(fout, virtual_entry_jst);
   }

   FileClose(fout);

   Print("==== XAUUSD_Daily_MFE_MAE v1.1 Complete ====");
   PrintFormat("  written = %d", g_rows_written);
   PrintFormat("  partial (some bars missing in 48h) = %d", g_rows_partial);
   PrintFormat("  skipped (no bar at 14:00) = %d", g_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Output_File);
}

//+==================================================================+
//| ProcessDay                                                       |
//|   1日分の仮想エントリー → 48h MFE/MAE 計算 → 1行書き出し         |
//|                                                                  |
//|   営業日判定: その時刻のH1足が取得できるか否か                   |
//|     (土日・祝日・年末年始は MT5 が足を持たないので自動スキップ)  |
//+==================================================================+
void ProcessDay(int fout, datetime virtual_entry_jst)
{
   string sym = _Symbol;

   //--- JST → server 時刻 ---
   datetime virtual_entry_server = JstToServer(virtual_entry_jst);

   //--- H1 足の shift を取得 (指定時刻以下の最大バー) ---
   int sh_h1 = iBarShift(sym, PERIOD_H1, virtual_entry_server, false);
   if(sh_h1 < 0)
   {
      if(Verbose) PrintFormat("[SKIP] iBarShift fail @ %s (server=%s)",
                               FormatJstDateTime(virtual_entry_jst),
                               TimeToString(virtual_entry_server, TIME_DATE|TIME_MINUTES));
      g_rows_skipped++;
      return;
   }

   //--- 取得したH1足の時刻 (server) ---
   datetime h1_bar_server = iTime(sym, PERIOD_H1, sh_h1);
   if(h1_bar_server == 0)
   {
      if(Verbose) PrintFormat("[SKIP] iTime fail @ %s",
                               FormatJstDateTime(virtual_entry_jst));
      g_rows_skipped++;
      return;
   }

   //--- 営業日判定 ---
   //   仮想エントリー時刻が属するH1足の時刻が、想定時刻から大きくずれている場合スキップ
   //   (例: 土日に呼ばれた場合、直近の金曜H1足が返ってくるので、それを除外)
   //   許容: 仮想エントリー時刻 - 6時間 〜 仮想エントリー時刻 の範囲
   //   (休場時間帯を考慮し、当日中の足のみ採用)
   long diff_sec = (long)virtual_entry_server - (long)h1_bar_server;
   if(diff_sec < 0 || diff_sec > 6 * 3600)
   {
      if(Verbose) PrintFormat("[SKIP non-trading] %s (last_bar=%s, diff=%dh)",
                               FormatJstDateTime(virtual_entry_jst),
                               TimeToString(h1_bar_server, TIME_DATE|TIME_MINUTES),
                               (int)(diff_sec / 3600));
      g_rows_skipped++;
      return;
   }

   //--- 仮想エントリー価格 (そのH1足の close) ---
   double entry_close = iClose(sym, PERIOD_H1, sh_h1);
   if(entry_close <= 0)
   {
      if(Verbose) PrintFormat("[SKIP] iClose fail @ %s",
                               FormatJstDateTime(virtual_entry_jst));
      g_rows_skipped++;
      return;
   }

   //--- 48h MFE/MAE 追跡 (BUY/SELL 両方) ---
   //   時間別セグメント (12h / 24h / 36h / 48h) も同時に計算するため、
   //   全48本の high/low を一度に取得して4段階に集約する
   //   (BUY 基準で MFE/MAE を算出し、SELL は対称関係で導出)
   double buy_mfe_12=0, buy_mae_12=0;
   double buy_mfe_24=0, buy_mae_24=0;
   double buy_mfe_36=0, buy_mae_36=0;
   double buy_mfe_48=0, buy_mae_48=0;
   int    buy_mfe_idx_48 = -1, buy_mae_idx_48 = -1;
   int    bars_traced = 0;

   bool ok = TraceMaeMfe_Segmented(sh_h1, H1_Trace_Bars_48h, entry_close,
                                    buy_mfe_12, buy_mae_12,
                                    buy_mfe_24, buy_mae_24,
                                    buy_mfe_36, buy_mae_36,
                                    buy_mfe_48, buy_mae_48,
                                    buy_mfe_idx_48, buy_mae_idx_48,
                                    bars_traced);

   //--- SELL 側は BUY 側の符号を入れ替えた対称関係 ---
   //   BUY: favor = high - entry,    adverse = entry - low
   //   SELL: favor = entry - low,    adverse = high - entry
   //   → SELL_MFE は BUY_MAE と同値、SELL_MAE は BUY_MFE と同値    ---
   //   (同じH1足群を見るので、極値は同じ)                            ---
   double sell_mfe_12 = buy_mae_12, sell_mae_12 = buy_mfe_12;
   double sell_mfe_24 = buy_mae_24, sell_mae_24 = buy_mfe_24;
   double sell_mfe_36 = buy_mae_36, sell_mae_36 = buy_mfe_36;
   double sell_mfe_48 = buy_mae_48, sell_mae_48 = buy_mfe_48;
   int    sell_mfe_idx_48 = buy_mae_idx_48;
   int    sell_mae_idx_48 = buy_mfe_idx_48;

   if(!ok)
   {
      if(Verbose) PrintFormat("[SKIP] TraceMaeMfe fail @ %s",
                               FormatJstDateTime(virtual_entry_jst));
      g_rows_skipped++;
      return;
   }

   //--- date 文字列 (JST, YYYY-MM-DD) ---
   string date_str = FormatJstDate(virtual_entry_jst);
   string ve_str   = FormatJstDateTime(virtual_entry_jst);

   //--- 行書き出し ---
   WriteRow(fout, date_str, ve_str, entry_close,
            buy_mfe_48, buy_mae_48,
            sell_mfe_48, sell_mae_48,
            buy_mfe_idx_48, buy_mae_idx_48,
            sell_mfe_idx_48, sell_mae_idx_48,
            bars_traced,
            buy_mfe_12, buy_mae_12, sell_mfe_12, sell_mae_12,
            buy_mfe_24, buy_mae_24, sell_mfe_24, sell_mae_24,
            buy_mfe_36, buy_mae_36, sell_mfe_36, sell_mae_36);

   g_rows_written++;
   if(bars_traced < H1_Trace_Bars_48h) g_rows_partial++;

   if(Verbose && (g_rows_written % 20 == 0))
      PrintFormat("[INFO] processed %d days...", g_rows_written);
}

//+==================================================================+
//| TraceMaeMfe_Segmented                                            |
//|   エントリーバー (entry_shift) より新しい N 本のH1バーを走査して |
//|   BUY側の MFE/MAE を 12h / 24h / 36h / 48h セグメント別に計算。   |
//|   SELL側は対称関係 (符号逆転) で呼び出し側が算出する。            |
//|                                                                  |
//|   セグメント定義:                                                  |
//|     12h = エントリー後 1本目 〜 12本目                            |
//|     24h = エントリー後 1本目 〜 24本目                            |
//|     36h = エントリー後 1本目 〜 36本目                            |
//|     48h = エントリー後 1本目 〜 48本目 (= 全体)                  |
//|   ※累積型 (12h ⊆ 24h ⊆ 36h ⊆ 48h)                              |
//|                                                                  |
//|   bar_idx は 48h セグメントのみ返す。12h/24h/36h は省略           |
//|   (Q3 「bar_idx は 48h 維持で OK」指示通り、軌跡解像度は十分)     |
//|                                                                  |
//|   bars_traced が trace_n 未満の場合 (休場跨ぎ等)、                |
//|     - 取得できた本数までで各セグメント値を確定                    |
//|     - 例: bars_traced=20 なら 12h と 24h は完全、36h と 48h は    |
//|       「実取得20本まで」の値となる (部分値、partial)              |
//|                                                                  |
//|   旧版 TraceMaeMfe48h_DualSide から拡張 (2026-06-10)              |
//+==================================================================+
bool TraceMaeMfe_Segmented(int entry_shift, int trace_n, double entry_price,
                            double &buy_mfe_12, double &buy_mae_12,
                            double &buy_mfe_24, double &buy_mae_24,
                            double &buy_mfe_36, double &buy_mae_36,
                            double &buy_mfe_48, double &buy_mae_48,
                            int    &buy_mfe_idx_48, int &buy_mae_idx_48,
                            int    &bars_traced)
{
   buy_mfe_12=0; buy_mae_12=0;
   buy_mfe_24=0; buy_mae_24=0;
   buy_mfe_36=0; buy_mae_36=0;
   buy_mfe_48=0; buy_mae_48=0;
   buy_mfe_idx_48 = -1; buy_mae_idx_48 = -1;
   bars_traced = 0;

   if(entry_shift < 0) return false;
   if(trace_n <= 0)   return false;

   string sym = _Symbol;

   //--- 走査開始 shift = entry_shift - 1 (エントリーバーの次の新しいバー) ---
   //--- エントリーバー自身はエントリー前の動きを含むので除外する         ---
   int start_shift = entry_shift - 1;
   if(start_shift < 0)
   {
      // エントリーバー自体が現在バー = 直近すぎて追跡開始できない
      return false;
   }

   //--- 取得可能本数を確定 ---
   //   start_shift = entry_shift-1 (新しい側)
   //   end_shift   = entry_shift-trace_n (古い側、ただし 0 が下限)
   int desired_end = entry_shift - trace_n;
   int end_shift   = (desired_end < 0) ? 0 : desired_end;
   int n_bars      = start_shift - end_shift + 1;
   if(n_bars <= 0) return false;

   //--- High/Low を取得 (series=true で end_shift から n_bars 本) ---
   //    series 配列 index:                                             ---
   //      [0]       = start_shift (新しい側、entry の次のバー = idx 1)---
   //      [n_bars-1]= end_shift   (古い側、entry の n_bars 本後)       ---
   //    → entry から数えて何本目 = n_bars - k                          ---
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(sym, PERIOD_H1, end_shift, n_bars, highs) <= 0) return false;
   if(CopyLow (sym, PERIOD_H1, end_shift, n_bars, lows)  <= 0) return false;

   //--- セグメント走査: entry 後 1..12, 1..24, 1..36, 1..48 ---
   //    series index k に対する「entry 後の何本目」 = n_bars - k       ---
   //    → entry 後 1..H 本目を取るには n_bars - k <= H、即ち k >= n_bars - H
   double best_favor_12=-DBL_MAX, worst_adverse_12=-DBL_MAX;
   double best_favor_24=-DBL_MAX, worst_adverse_24=-DBL_MAX;
   double best_favor_36=-DBL_MAX, worst_adverse_36=-DBL_MAX;
   double best_favor_48=-DBL_MAX, worst_adverse_48=-DBL_MAX;
   int    best_idx_48  = -1, worst_idx_48 = -1;

   for(int k = 0; k < n_bars; k++)
   {
      double hi = highs[k];
      double lo = lows[k];
      if(hi <= 0 || lo <= 0) continue;

      //--- BUY 側 ---
      double favor   = hi - entry_price;   // 上が有利
      double adverse = entry_price - lo;   // 下抜けが逆行

      //--- entry 後の何本目 (1..n_bars) ---
      int bar_no = n_bars - k;

      //--- 48h (全体) ---
      if(bar_no <= 48)
      {
         if(favor > best_favor_48)        { best_favor_48 = favor;        best_idx_48 = k; }
         if(adverse > worst_adverse_48)   { worst_adverse_48 = adverse;   worst_idx_48 = k; }
      }
      //--- 36h ---
      if(bar_no <= 36)
      {
         if(favor > best_favor_36)        best_favor_36 = favor;
         if(adverse > worst_adverse_36)   worst_adverse_36 = adverse;
      }
      //--- 24h ---
      if(bar_no <= 24)
      {
         if(favor > best_favor_24)        best_favor_24 = favor;
         if(adverse > worst_adverse_24)   worst_adverse_24 = adverse;
      }
      //--- 12h ---
      if(bar_no <= 12)
      {
         if(favor > best_favor_12)        best_favor_12 = favor;
         if(adverse > worst_adverse_12)   worst_adverse_12 = adverse;
      }
   }

   //--- 48h セグメント (bar_idx 付き) ---
   if(best_idx_48 >= 0)
   {
      buy_mfe_48     = MathMax(0.0, best_favor_48);
      buy_mfe_idx_48 = n_bars - best_idx_48;
   }
   if(worst_idx_48 >= 0)
   {
      buy_mae_48     = MathMax(0.0, worst_adverse_48);
      buy_mae_idx_48 = n_bars - worst_idx_48;
   }

   //--- 12h / 24h / 36h セグメント (bar_idx 省略) ---
   //    sentinel (-DBL_MAX) のままなら 0 のまま、それ以外は max(0, value)
   if(best_favor_12 > -DBL_MAX)    buy_mfe_12 = MathMax(0.0, best_favor_12);
   if(worst_adverse_12 > -DBL_MAX) buy_mae_12 = MathMax(0.0, worst_adverse_12);
   if(best_favor_24 > -DBL_MAX)    buy_mfe_24 = MathMax(0.0, best_favor_24);
   if(worst_adverse_24 > -DBL_MAX) buy_mae_24 = MathMax(0.0, worst_adverse_24);
   if(best_favor_36 > -DBL_MAX)    buy_mfe_36 = MathMax(0.0, best_favor_36);
   if(worst_adverse_36 > -DBL_MAX) buy_mae_36 = MathMax(0.0, worst_adverse_36);

   bars_traced = n_bars;
   return true;
}

//+==================================================================+
//| JstToServer                                                      |
//|   JST (UTC+9) → サーバー時刻                                     |
//|                                                                  |
//|   流用元: Trade_Snapshot_Builder.mq5 v1.1 と同じロジック         |
//+==================================================================+
datetime JstToServer(datetime jst)
{
   //--- JST → UTC ---
   datetime utc = jst - (datetime)(JST_Offset_Hours * 3600);

   long offset_sec = 0;
   if(Use_Auto_Server_Offset)
   {
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   }
   else
   {
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   }

   return utc + (datetime)offset_sec;
}

//+==================================================================+
//| ServerToJst                                                      |
//|   サーバー時刻 → JST (UTC+9)                                     |
//+==================================================================+
datetime ServerToJst(datetime server_time)
{
   long offset_sec = 0;
   if(Use_Auto_Server_Offset)
   {
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   }
   else
   {
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   }

   //--- server → UTC → JST ---
   datetime utc = server_time - (datetime)offset_sec;
   return utc + (datetime)(JST_Offset_Hours * 3600);
}

//+==================================================================+
//| ParseHHMM                                                        |
//|   "HH:MM" → hh, mm                                              |
//+==================================================================+
bool ParseHHMM(const string &s, int &hh, int &mm)
{
   int colon = StringFind(s, ":");
   if(colon < 0) return false;
   string h_str = StringSubstr(s, 0, colon);
   string m_str = StringSubstr(s, colon + 1);
   hh = (int)StringToInteger(h_str);
   mm = (int)StringToInteger(m_str);
   if(hh < 0 || hh > 23) return false;
   if(mm < 0 || mm > 59) return false;
   return true;
}

//+==================================================================+
//| FormatJstDate / FormatJstDateTime                                |
//+==================================================================+
string FormatJstDate(datetime jst)
{
   //--- "yyyy.mm.dd HH:MM" → "yyyy-mm-dd" ---
   string s = TimeToString(jst, TIME_DATE);
   StringReplace(s, ".", "-");
   return s;
}

string FormatJstDateTime(datetime jst)
{
   //--- "yyyy.mm.dd HH:MM" → "yyyy-mm-dd HH:MM:00" ---
   string s = TimeToString(jst, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "-");
   return s + ":00";
}

//+==================================================================+
//| WriteUtf8Bom / WriteUtf8String                                   |
//|   流用元: Trade_Snapshot_Builder.mq5 v1.1                        |
//+==================================================================+
void WriteUtf8Bom(int fh)
{
   uchar bom[3] = {0xEF, 0xBB, 0xBF};
   FileWriteArray(fh, bom, 0, 3);
}

void WriteUtf8String(int fh, const string s)
{
   uchar buf[];
   StringToCharArray(s, buf, 0, -1, CP_UTF8);
   int n = ArraySize(buf);
   if(n > 0 && buf[n-1] == 0) n--;
   if(n > 0) FileWriteArray(fh, buf, 0, n);
}

//+==================================================================+
//| WriteHeaderUtf8                                                  |
//|                                                                  |
//|   出力カラム (v1.1 / 19列):                                        |
//|     [1]  date                  YYYY-MM-DD (JST)                  |
//|     [2]  virtual_entry_jst     YYYY-MM-DD HH:MM:SS (JST)         |
//|     [3]  virtual_entry_price   その時刻の H1 close               |
//|     [4]  buy_mfe_usd           BUY 仮想 48h MFE (USD) ★既存維持 |
//|     [5]  buy_mae_usd           BUY 仮想 48h MAE (USD) ★既存維持 |
//|     [6]  sell_mfe_usd          SELL 仮想 48h MFE (USD) ★既存維持|
//|     [7]  sell_mae_usd          SELL 仮想 48h MAE (USD) ★既存維持|
//|     [8]  buy_mfe_bar_idx       BUY MFE 到達バー (entry 後 1..48)|
//|     [9]  buy_mae_bar_idx       BUY MAE 到達バー                  |
//|     [10] sell_mfe_bar_idx      SELL MFE 到達バー (= buy_mae 同値)|
//|     [11] sell_mae_bar_idx      SELL MAE 到達バー (= buy_mfe 同値)|
//|     [12] bars_traced           実追跡 H1 足数 (48h 基準)         |
//|     [13] buy_mfe_12h_usd       ★新規 BUY 仮想 12h MFE (USD)    |
//|     [14] buy_mae_12h_usd       ★新規 BUY 仮想 12h MAE (USD)    |
//|     [15] sell_mfe_12h_usd      ★新規 SELL 仮想 12h MFE (USD)   |
//|     [16] sell_mae_12h_usd      ★新規 SELL 仮想 12h MAE (USD)   |
//|     [17] buy_mfe_24h_usd 〜 sell_mae_24h_usd (4列)               |
//|     [21] buy_mfe_36h_usd 〜 sell_mae_36h_usd (4列)               |
//|                                                                  |
//|   合計: 12 + 4×3 = 24列                                          |
//|                                                                  |
//|   方針 (Q3): 既存カラム名は不変、新規カラム追加のみ。            |
//|     後方互換維持のため (マニ generate_daily_calendar.py 等)      |
//+==================================================================+
void WriteHeaderUtf8(int fh)
{
   string line =
      // [1-3] 基本
      "date,virtual_entry_jst,virtual_entry_price,"
      // [4-7] 48h MFE/MAE (★既存維持: リネームせず 48h 値として扱う)
      "buy_mfe_usd,buy_mae_usd,sell_mfe_usd,sell_mae_usd,"
      // [8-11] 48h bar_idx (★既存維持)
      "buy_mfe_bar_idx,buy_mae_bar_idx,sell_mfe_bar_idx,sell_mae_bar_idx,"
      // [12] 実追跡本数 (★既存維持)
      "bars_traced,"
      // [13-16] 12h セグメント (★新規)
      "buy_mfe_12h_usd,buy_mae_12h_usd,sell_mfe_12h_usd,sell_mae_12h_usd,"
      // [17-20] 24h セグメント (★新規)
      "buy_mfe_24h_usd,buy_mae_24h_usd,sell_mfe_24h_usd,sell_mae_24h_usd,"
      // [21-24] 36h セグメント (★新規)
      "buy_mfe_36h_usd,buy_mae_36h_usd,sell_mfe_36h_usd,sell_mae_36h_usd";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| WriteRow                                                         |
//|   v1.1 24列出力                                                   |
//+==================================================================+
void WriteRow(int fh,
              const string &date_str, const string &ve_str, double entry_price,
              double buy_mfe_48, double buy_mae_48,
              double sell_mfe_48, double sell_mae_48,
              int buy_mfe_idx, int buy_mae_idx,
              int sell_mfe_idx, int sell_mae_idx,
              int bars_traced,
              double buy_mfe_12, double buy_mae_12, double sell_mfe_12, double sell_mae_12,
              double buy_mfe_24, double buy_mae_24, double sell_mfe_24, double sell_mae_24,
              double buy_mfe_36, double buy_mae_36, double sell_mfe_36, double sell_mae_36)
{
   string line = "";
   //--- [1-3] 基本 ---
   line += date_str + ",";
   line += ve_str + ",";
   line += DoubleToString(entry_price, 3) + ",";
   //--- [4-7] 48h MFE/MAE (既存維持) ---
   line += DoubleToString(buy_mfe_48, 3) + ",";
   line += DoubleToString(buy_mae_48, 3) + ",";
   line += DoubleToString(sell_mfe_48, 3) + ",";
   line += DoubleToString(sell_mae_48, 3) + ",";
   //--- [8-11] 48h bar_idx (既存維持) ---
   line += IntegerToString(buy_mfe_idx) + ",";
   line += IntegerToString(buy_mae_idx) + ",";
   line += IntegerToString(sell_mfe_idx) + ",";
   line += IntegerToString(sell_mae_idx) + ",";
   //--- [12] bars_traced (既存維持) ---
   line += IntegerToString(bars_traced) + ",";
   //--- [13-16] 12h セグメント (新規) ---
   line += DoubleToString(buy_mfe_12, 3) + ",";
   line += DoubleToString(buy_mae_12, 3) + ",";
   line += DoubleToString(sell_mfe_12, 3) + ",";
   line += DoubleToString(sell_mae_12, 3) + ",";
   //--- [17-20] 24h セグメント (新規) ---
   line += DoubleToString(buy_mfe_24, 3) + ",";
   line += DoubleToString(buy_mae_24, 3) + ",";
   line += DoubleToString(sell_mfe_24, 3) + ",";
   line += DoubleToString(sell_mae_24, 3) + ",";
   //--- [21-24] 36h セグメント (新規) ---
   line += DoubleToString(buy_mfe_36, 3) + ",";
   line += DoubleToString(buy_mae_36, 3) + ",";
   line += DoubleToString(sell_mfe_36, 3) + ",";
   line += DoubleToString(sell_mae_36, 3);
   WriteUtf8String(fh, line + "\n");
}
//+------------------------------------------------------------------+
