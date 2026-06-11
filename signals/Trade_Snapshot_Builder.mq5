//+------------------------------------------------------------------+
//|  Trade_Snapshot_Builder.mq5                                      |
//|  あろさんトレードCSVを「日時+価格のインデックス」として使い、     |
//|  各エントリー時点の市場環境スナップショットと、エントリーから    |
//|  固定48時間 × H1/H4/D1 三層の MAE/MFE を後付け取得して           |
//|  trades_enriched.csv として出力する。                            |
//|                                                                  |
//|  研究目的（絶対固定）:                                            |
//|    「どの市場環境で期待値が発生しているか」の構造発見。           |
//|    勝率分析・PF分析・月別集計・損益集計は目的外。                 |
//|                                                                  |
//|  指示書: data/mani_room/コー_指示書_Trade_Snapshot_Builder.md     |
//|                                                                  |
//|  v1.1 (2026-06-08 PM) 改訂:                                       |
//|    - MAE/MFE を「決済期間中」→「固定48時間 × H1/H4/D1 三層」に  |
//|      全面改訂                                                     |
//|    - メタデータ列 bar_time × 4 追加                              |
//|    - 削除: mae_pips, mfe_pips, mae_bar_idx, mfe_bar_idx,         |
//|             bars_held, mae_mfe_ok                                |
//|    - 追加: h1/h4/d1_mfe_usd_48h, *_mfe_bar_idx_48h,              |
//|             *_mae_usd_48h, *_mae_bar_idx_48h, *_bars_traced_48h, |
//|             entry_bar_time, h1_bar_time, h4_bar_time, d1_bar_time|
//|                                                                  |
//|  v1.2 (2026-06-10) 改訂:                                          |
//|    - H1 のみ時間別化: 12h / 24h / 36h セグメント MFE/MAE 追加     |
//|      (48h 維持 + 既存カラム名は完全維持、新規カラム追加のみ)      |
//|    - 後方互換: h1_mfe_usd_48h / h1_mae_usd_48h 等は不変           |
//|    - 新規追加: h1_mfe_usd_12h / h1_mae_usd_12h /                  |
//|      h1_mfe_usd_24h / h1_mae_usd_24h /                            |
//|      h1_mfe_usd_36h / h1_mae_usd_36h (4×3 = 12列)                |
//|    - H4 / D1 は無変更 (4時間足/日足で 12h 以下は解像度不足)      |
//|    - bar_idx は 48h のみ維持、12h/24h/36h は省略 (コー判断)       |
//|    - 番人観点: データ拡張のみ、判断ロジック混入禁止               |
//|                                                                  |
//|  v1.3 (2026-06-10 PM) 改訂 (指示書 v0.2 対応):                    |
//|    - H4 時間別化追加: 12h / 24h / 36h セグメント MFE/MAE          |
//|      (H4 trace_n=12 → 12h=3本/24h=6本/36h=9本/48h=12本)         |
//|    - D1 24h セグメント追加 (D1 trace_n=2 → 24h=1本/48h=2本)      |
//|    - 既存カラム名は完全維持、新規カラム追加のみ                  |
//|    - 新規追加 (H4): h4_mfe_usd_12h/24h/36h, h4_mae_usd_12h/24h/36h|
//|    - 新規追加 (D1): d1_mfe_usd_24h, d1_mae_usd_24h               |
//|    - H4 trace_n が 12 未満の場合、各セグメントは部分値となる    |
//|    - bar_idx は 48h のみ維持 (H4/D1 とも)                        |
//|                                                                  |
//|  v1.31 (2026-06-10 緊急修正): MQL5 64引数制限への対応            |
//|    - 原因: v1.3 で WriteRow 引数が 64→73 個に増加 → MQL5 仕様の |
//|      最大64引数を超過 → 21 compile errors                       |
//|    - 修正: 構造体 TradeSnapshotRow (72フィールド) を導入し、    |
//|      WriteRow(int fh, const TradeSnapshotRow &row) に集約        |
//|    - 出力カラム/値計算ロジックは完全不変 (リグレッションなし)  |
//|    - 副次バグ修正: d1_ok=false 時の WriteRow 末尾カンマ不足を    |
//|      ",,," から ","," " に変更 (D1 24h 2列分のため)             |
//|    - WriteHeaderUtf8 / WriteEmptyRow は 1引数 / 3引数で不変      |
//|                                                                  |
//|  v1.32 (2026-06-11 緊急修正): 研究目的整合 — 未来情報混入の解消 |
//|    - 問題: v1.31 までスナップショット (ATR/ADX/DI/Pattern/Cross/ |
//|      Phase) を iBarShift(exact=false) の結果 = エントリー時刻が  |
//|      「属する」バーの shift から取得していた。                   |
//|      MT5 の Indicator buffer はバー終値時点の値なので、           |
//|      これは「エントリーから最大 1 バー後 (= H1 最大 60 分、     |
//|      H4 最大 4 時間、D1 最大 1 日先)」の値を取得していた。      |
//|      → エントリー時点では知り得ない未来情報の混入                |
//|      → 研究目的「日時+価格を index にエントリー時点の市場環境を  |
//|         後付け取得」に違反                                       |
//|    - 修正: iBarShift 結果を sh_h1_bar / sh_h4_bar / sh_d1_bar    |
//|      にリネームし、スナップショット取得用には sh_h1 = sh_*_bar+1 |
//|      = 直前確定バー (= エントリー時点で既に確定していた値) を    |
//|      使用する。                                                  |
//|    - 影響範囲:                                                    |
//|      [変更] H1/H4/D1 の ATR/ADX/DI/Ratio/Pattern/Median/Zone/    |
//|             Cross/Phase の取得 shift → 全て sh_*_bar+1 へ        |
//|      [不変] bar_time メタデータ (entry/h1/h4/d1_bar_time_jst)    |
//|             → エントリーバー時刻 (sh_*_bar) で記録 (仕様維持)    |
//|      [不変] TraceMaeMfe_Segmented 呼び出し                        |
//|             → 内部で entry_shift-1 起点で追跡するため、引数には  |
//|               sh_*_bar (エントリーバー shift) を渡し続ける        |
//|             → これによりエントリー後の追跡対象バーは不変         |
//|    - CSV ヘッダ / 列数 / 順序: 完全不変 (72列)                  |
//|    - 既存 ATR/ADX/DI/Pattern/Phase 値は変わる(設計上正しい値へ)|
//|    - 番人観点: エントリーロジック混入なし、事実情報の取得位置   |
//|      補正のみ                                                    |
//|                                                                  |
//|  禁止事項:                                                        |
//|    - 12h/24h/36h セグメント値の「評価ラベル化」                  |
//|      (例: 「12h で MFE 大きい→いい兆候」のようなラベル付け禁止)  |
//|                                                                  |
//|  参照ロジック:                                                    |
//|    - ATR_WidthSignal_v4.mq5 : H1 Pattern (RISING_DECEL等) 判定   |
//|                              ATR Zone (LOW/NORMAL/HIGH) 判定     |
//|                              FindATRCross による BU/PD/NONE 判定 |
//|    - ARO_H4PhaseAuto_v1.mq5 : H4 Phase 5段階自動判定             |
//|                              (BU/PD/凪/収束底/凪離脱/—)         |
//|                                                                  |
//|  入力 (中間CSV):                                                  |
//|    MQL5/Files/trade_input.csv (UTF-8, 1行=1トレード)             |
//|    カラム: trade_id,entry_jst,exit_jst,direction,entry_price     |
//|      entry_jst, exit_jst : yyyy-mm-dd HH:MM (JST)                |
//|      exit_jst が空欄ならオープン中 (MAE/MFE は決済情報不使用なので|
//|                                    通常通り 48h 追跡実施)        |
//|      direction : BUY / SELL                                      |
//|                                                                  |
//|  出力:                                                            |
//|    MQL5/Files/trades_enriched.csv (UTF-8 BOM)                    |
//|    trade_id + スナップショット項目（指示書 §2 全項目）            |
//|                                                                  |
//|  作成日: 2026-06-08                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.32"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 入出力ファイル ==="
input string  Input_File          = "trade_input.csv";
input string  Output_File         = "trades_enriched.csv";

input group "=== タイムゾーン ==="
input int     JST_Offset_Hours    = 9;       // JST = UTC+9（固定）
input bool    Use_Auto_Server_Offset = true; // TimeGMTOffset() / TimeDaylightSavings() で自動算出
input int     Manual_Server_Offset_Hours = 2; // 自動算出失敗時のフォールバック（例: HFM冬時間=2）

input group "=== H1 指標周期 (CLAUDE.md 確定値) ==="
input int     H1_ATR_Short        = 16;
input int     H1_ATR_Long         = 32;
input int     H1_ADX_Period       = 32;
input int     H1_ATR_Median_Weeks = 8;       // ATR ratio 中央値ウィンドウ

input group "=== H4 指標周期 ==="
input int     H4_ATR_Short        = 8;
input int     H4_ATR_Long         = 46;
input int     H4_ADX_Period       = 46;

input group "=== D1 指標周期 ==="
input int     D1_ATR_Short        = 22;
input int     D1_ATR_Long         = 42;
input int     D1_ADX_Period       = 22;

input group "=== ATR Zone 閾値 (H1) ==="
input double  ATR_Zone_Low_Ratio  = 0.70;
input double  ATR_Zone_High_Ratio = 1.40;

input group "=== ATR Pair 閾値 ==="
input double  ATR_Pair_Expand     = 1.05;
input double  ATR_Pair_Contract   = 0.95;

input group "=== H1 Pattern 判定 (v4 同等) ==="
input int     ATR_Vel_Bars        = 3;
input double  ATR_Expand_Thresh   = 10.0;
input double  ATR_Flat_Thresh     = 3.0;

input group "=== H4 Phase Auto v2 ==="
input int     H4_Cross_LookBack   = 30;
input double  Nagi_Thresh         = 0.97;    // ratio ≤ ならば凪帯
input double  Nagi_Diff_Thresh    = 1.0;     // diff ±これで収束底/凪離脱

input group "=== D1 ATR Cross 判定 ==="
input int     D1_Cross_LookBack   = 30;

input group "=== 48h MAE/MFE 三層追跡 ==="
input int     H1_Trace_Bars_48h   = 48;      // H1: 48本 = 48時間相当
input int     H4_Trace_Bars_48h   = 12;      // H4: 12本 = 48時間相当
input int     D1_Trace_Bars_48h   = 2;       // D1: 2本

input group "=== シンボル制約 ==="
input string  Allowed_Symbol      = "XAUUSD"; // この銘柄以外はスキップ

input group "=== デバッグ ==="
input bool    Verbose             = true;

//+==================================================================+
//| TradeSnapshotRow                                                 |
//|   v1.31: MQL5 64引数制限を回避するための CSV 1行分のフィールド  |
//|   集約構造体。WriteRow() の引数を 73 → 1 (この構造体への参照)に |
//|   集約する。                                                      |
//|                                                                  |
//|   フィールド数: 72 (出力カラム数と一致 / WriteHeaderUtf8と整合) |
//|   - 既存 v1.3 の WriteRow 引数並びをそのまま 1:1 で持つ          |
//|   - 値の生成・代入は ProcessTradeRow 内で実施                    |
//+==================================================================+
struct TradeSnapshotRow
{
   //--- [1-7] 基本 ---
   string   trade_id;
   string   entry_jst;
   string   exit_jst;
   string   direction;
   double   entry_price;
   datetime entry_server;
   datetime exit_server;
   //--- [8-11] メタデータ (bar_time × 4, JST 表記) ---
   string   entry_bar_time_jst;
   string   h1_bar_time_jst;
   string   h4_bar_time_jst;
   string   d1_bar_time_jst;
   //--- [12-21] H1 スナップショット ---
   double   h1_atr16;
   double   h1_atr32;
   double   h1_ratio;
   double   h1_atr_median;
   double   h1_atr_ratio_median;
   string   h1_atr_zone;
   double   h1_adx32;
   double   h1_dip;
   double   h1_din;
   string   h1_pattern;
   //--- [22-31] H4 スナップショット ---
   double   h4_atr8;
   double   h4_atr46;
   double   h4_ratio;
   double   h4_diff;
   double   h4_adx46;
   double   h4_dip;
   double   h4_din;
   int      h4_cross_bars;
   string   h4_cross_dir;
   string   h4_phase_auto;
   //--- [32-39] D1 スナップショット ---
   double   d1_atr22;
   double   d1_atr42;
   double   d1_ratio;
   double   d1_adx22;
   double   d1_dip;
   double   d1_din;
   int      d1_cross_bars;
   string   d1_phase;
   //--- [40] has_exit ---
   bool     has_exit;
   //--- [41-46] H1 48h MAE/MFE ---
   bool     h1_ok;
   double   h1_mfe_usd;
   int      h1_mfe_idx;
   double   h1_mae_usd;
   int      h1_mae_idx;
   int      h1_bars_traced;
   //--- [47-52] H4 48h MAE/MFE ---
   bool     h4_ok;
   double   h4_mfe_usd;
   int      h4_mfe_idx;
   double   h4_mae_usd;
   int      h4_mae_idx;
   int      h4_bars_traced;
   //--- [53-58] D1 48h MAE/MFE ---
   bool     d1_ok;
   double   d1_mfe_usd;
   int      d1_mfe_idx;
   double   d1_mae_usd;
   int      d1_mae_idx;
   int      d1_bars_traced;
   //--- [59-64] H1 12h/24h/36h MFE/MAE (v1.2) ---
   double   h1_mfe_12;
   double   h1_mae_12;
   double   h1_mfe_24;
   double   h1_mae_24;
   double   h1_mfe_36;
   double   h1_mae_36;
   //--- [65-70] H4 12h/24h/36h MFE/MAE (v1.3) ---
   double   h4_mfe_12;
   double   h4_mae_12;
   double   h4_mfe_24;
   double   h4_mae_24;
   double   h4_mfe_36;
   double   h4_mae_36;
   //--- [71-72] D1 24h MFE/MAE (v1.3) ---
   double   d1_mfe_24;
   double   d1_mae_24;
};

//+-----[ 指標ハンドル ]--------------------------------------------+
int hATR_S_H1 = INVALID_HANDLE, hATR_L_H1 = INVALID_HANDLE, hADX_H1 = INVALID_HANDLE;
int hATR_S_H4 = INVALID_HANDLE, hATR_L_H4 = INVALID_HANDLE, hADX_H4 = INVALID_HANDLE;
int hATR_S_D1 = INVALID_HANDLE, hATR_L_D1 = INVALID_HANDLE, hADX_D1 = INVALID_HANDLE;

//+-----[ 出力行カウンタ ]------------------------------------------+
int g_rows_written  = 0;
int g_rows_skipped  = 0;
int g_rows_partial  = 0;   // 48h 追跡が一部でも不完全だった行

//+==================================================================+
//| OnStart                                                          |
//+==================================================================+
void OnStart()
{
   Print("==== Trade_Snapshot_Builder v1.31 Start ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, Allowed_Symbol);
   PrintFormat("Input: %s", Input_File);
   PrintFormat("Output: %s", Output_File);
   PrintFormat("48h trace bars: H1=%d, H4=%d, D1=%d",
               H1_Trace_Bars_48h, H4_Trace_Bars_48h, D1_Trace_Bars_48h);
   PrintFormat("Time-segmented MFE/MAE: H1=12/24/36/48h, H4=12/24/36/48h, D1=24/48h");

   //--- シンボル制約チェック (チャートのシンボルが Allowed_Symbol と一致する必要) ---
   if(_Symbol != Allowed_Symbol)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ Allowed_Symbol %s. "
                  "%s チャートで起動してください.",
                  _Symbol, Allowed_Symbol, Allowed_Symbol);
      return;
   }

   //--- 指標ハンドル初期化 ---
   if(!InitHandles())
   {
      Print("[FATAL] 指標ハンドル初期化に失敗。終了。");
      return;
   }
   Sleep(2000);  // インジ計算待ち

   //--- 入力 CSV オープン (UTF-8 / ASCII 範囲のみ含む前提) ---
   //   FILE_CSV モードで開く。FileReadString が delimiter ',' でフィールド  ---
   //   分割するために FILE_CSV が必須（FILE_TXT だと行全体を1フィールド扱い）---
   //   FILE_ANSI で ASCII 範囲文字をバイト単位で読み取り、BOM は ReadTradeRow ---
   //   内で 0xFEFF 検知でサニタイズ。                                       ---
   int fin = FileOpen(Input_File, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(fin == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 入力CSV open失敗: %s err=%d", Input_File, GetLastError());
      ReleaseHandles();
      return;
   }

   //--- 出力 CSV オープン (UTF-8 BOM) ---
   int fout = FileOpen(Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 出力CSV open失敗: %s err=%d", Output_File, GetLastError());
      FileClose(fin);
      ReleaseHandles();
      return;
   }
   WriteUtf8Bom(fout);
   WriteHeaderUtf8(fout);

   //--- DST 境界跨ぎ警告 ---
   //   JstToServer は実行時の TimeTradeServer-TimeGMT 差を使うので、
   //   入力トレードの時期と実行時で DST が異なるとズレが生じる。
   if(Use_Auto_Server_Offset && Verbose)
   {
      long ofs = (long)(TimeTradeServer() - TimeGMT());
      PrintFormat("[INFO] Current server-GMT offset = %d sec (= %.2f h). "
                  "DST境界を跨ぐトレード時刻ではズレに注意.",
                  (int)ofs, ofs/3600.0);
   }

   //--- ヘッダ読み飛ばし（5フィールド分） ---
   ReadTradeRow(fin);  // 戻り値は捨てる

   //--- メインループ: 1行ずつ処理 ---
   int line_no = 1;  // ヘッダ後の最初の行が2
   while(!FileIsEnding(fin))
   {
      string fields[];
      int n = ReadTradeRow(fin, fields);
      line_no++;
      if(n <= 0) continue;
      if(n < 5 || StringLen(fields[0]) == 0)
      {
         if(Verbose) PrintFormat("[SKIP line %d] field count=%d (need 5)", line_no, n);
         g_rows_skipped++;
         continue;
      }
      ProcessTradeRow(fout, fields, line_no);
   }

   FileClose(fin);
   FileClose(fout);
   ReleaseHandles();

   Print("==== Trade_Snapshot_Builder v1.31 Complete ====");
   PrintFormat("  written = %d", g_rows_written);
   PrintFormat("  partial(some bars missing in 48h trace) = %d", g_rows_partial);
   PrintFormat("  skipped = %d", g_rows_skipped);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Output_File);
}

//+==================================================================+
//| InitHandles                                                      |
//+==================================================================+
bool InitHandles()
{
   string sym = _Symbol;
   hATR_S_H1 = iATR(sym, PERIOD_H1, H1_ATR_Short);
   hATR_L_H1 = iATR(sym, PERIOD_H1, H1_ATR_Long);
   hADX_H1   = iADX(sym, PERIOD_H1, H1_ADX_Period);
   hATR_S_H4 = iATR(sym, PERIOD_H4, H4_ATR_Short);
   hATR_L_H4 = iATR(sym, PERIOD_H4, H4_ATR_Long);
   hADX_H4   = iADX(sym, PERIOD_H4, H4_ADX_Period);
   hATR_S_D1 = iATR(sym, PERIOD_D1, D1_ATR_Short);
   hATR_L_D1 = iATR(sym, PERIOD_D1, D1_ATR_Long);
   hADX_D1   = iADX(sym, PERIOD_D1, D1_ADX_Period);

   if(hATR_S_H1==INVALID_HANDLE || hATR_L_H1==INVALID_HANDLE || hADX_H1==INVALID_HANDLE ||
      hATR_S_H4==INVALID_HANDLE || hATR_L_H4==INVALID_HANDLE || hADX_H4==INVALID_HANDLE ||
      hATR_S_D1==INVALID_HANDLE || hATR_L_D1==INVALID_HANDLE || hADX_D1==INVALID_HANDLE)
   {
      PrintFormat("[ERR] ハンドル初期化失敗 err=%d", GetLastError());
      return false;
   }
   return true;
}

void ReleaseHandles()
{
   if(hATR_S_H1 != INVALID_HANDLE) IndicatorRelease(hATR_S_H1);
   if(hATR_L_H1 != INVALID_HANDLE) IndicatorRelease(hATR_L_H1);
   if(hADX_H1   != INVALID_HANDLE) IndicatorRelease(hADX_H1);
   if(hATR_S_H4 != INVALID_HANDLE) IndicatorRelease(hATR_S_H4);
   if(hATR_L_H4 != INVALID_HANDLE) IndicatorRelease(hATR_L_H4);
   if(hADX_H4   != INVALID_HANDLE) IndicatorRelease(hADX_H4);
   if(hATR_S_D1 != INVALID_HANDLE) IndicatorRelease(hATR_S_D1);
   if(hATR_L_D1 != INVALID_HANDLE) IndicatorRelease(hATR_L_D1);
   if(hADX_D1   != INVALID_HANDLE) IndicatorRelease(hADX_D1);
}

//+==================================================================+
//| ReadTradeRow                                                     |
//|   1行=1トレード前提で5フィールドを順に読む。                    |
//|   FILE_TXT + ',' デリミタなので、FileReadString 1回 = 1フィールド|
//|   FileIsLineEnding で行末判定。                                  |
//|                                                                  |
//|   戻り値: 読めたフィールド数 (0 なら何も読めず)                 |
//+==================================================================+
int ReadTradeRow(int fh, string &out_fields[])
{
   ArrayResize(out_fields, 0);
   if(FileIsEnding(fh)) return 0;

   int max_fields = 16;  // 中間CSV想定だが余裕を持って
   ArrayResize(out_fields, max_fields);
   int n = 0;
   bool got_anything = false;
   while(n < max_fields)
   {
      if(FileIsEnding(fh)) break;
      string f = FileReadString(fh);
      // FileReadString は ',' or 改行のどちらかで止まる。
      // EOF だと空文字を返すこともある。
      out_fields[n] = f;
      n++;
      got_anything = true;
      if(FileIsLineEnding(fh)) break;
   }
   ArrayResize(out_fields, n);

   // BOM が trade_id 先頭に付いている場合のサニタイズ（ヘッダ行で起きやすい）
   if(n > 0 && StringLen(out_fields[0]) > 0)
   {
      ushort c0 = StringGetCharacter(out_fields[0], 0);
      if(c0 == 0xFEFF)
         out_fields[0] = StringSubstr(out_fields[0], 1);
   }

   if(!got_anything) return 0;
   return n;
}

//+==================================================================+
//| 単純な1フィールド読み（ヘッダ行スキップ用）                      |
//+==================================================================+
int ReadTradeRow(int fh)
{
   string dummy[];
   return ReadTradeRow(fh, dummy);
}

//+==================================================================+
//| ProcessTradeRow                                                  |
//|   1トレード行を処理。CSVカラムは:                                |
//|     trade_id, entry_jst, exit_jst, direction, entry_price        |
//+==================================================================+
void ProcessTradeRow(int fout, const string &fields[], int line_no)
{
   string trade_id       = Trim(fields[0]);
   string entry_jst_str  = Trim(fields[1]);
   string exit_jst_str   = Trim(fields[2]);
   string direction      = StringToUpperCopy(Trim(fields[3]));
   string entry_price_str= Trim(fields[4]);

   //--- オプション6列目: server_offset_hours (空欄 or 数値)        ---
   //   中間CSVでDST境界を厳密にハンドリングしたい場合、Python側で  ---
   //   各トレードの正しいサーバーオフセット時間を計算して付与する。---
   long manual_offset_sec = -999999;  // sentinel
   if(ArraySize(fields) >= 6)
   {
      string ofs_str = Trim(fields[5]);
      if(StringLen(ofs_str) > 0)
      {
         double ofs_h = StringToDouble(ofs_str);
         manual_offset_sec = (long)(ofs_h * 3600);
      }
   }

   if(StringLen(trade_id) == 0)
   {
      if(Verbose) PrintFormat("[SKIP line %d] empty trade_id", line_no);
      g_rows_skipped++;
      return;
   }

   double entry_price = StringToDouble(entry_price_str);

   //--- JST → server 時刻に変換 ---
   datetime entry_jst = ParseJstString(entry_jst_str);
   if(entry_jst == 0)
   {
      PrintFormat("[SKIP line %d] entry_jst parse fail: %s", line_no, entry_jst_str);
      WriteEmptyRow(fout, trade_id, "parse_fail_entry_jst");
      g_rows_skipped++;
      return;
   }
   datetime entry_server = JstToServer(entry_jst, manual_offset_sec);

   bool has_exit = (StringLen(exit_jst_str) > 0);
   datetime exit_server = 0;
   if(has_exit)
   {
      datetime exit_jst = ParseJstString(exit_jst_str);
      if(exit_jst == 0)
      {
         if(Verbose) PrintFormat("[WARN line %d] exit_jst parse fail: %s -> treat as open",
                                 line_no, exit_jst_str);
         has_exit = false;
      }
      else
      {
         exit_server = JstToServer(exit_jst, manual_offset_sec);
      }
   }

   //--- エントリー時刻が属するバーの shift を取得 (メタデータ / 追跡用) ---
   //   iBarShift(symbol, period, time, exact=false)
   //     exact=false の挙動: 指定時刻が属するバー (= 指定時刻 ≧ open_time,
   //                        指定時刻 < open_time + period) の shift を返す。
   //     注意: 「直前確定バー」ではなく「指定時刻が属するバー」。
   //   この shift は:
   //     - bar_time メタデータ (entry/h1/h4/d1_bar_time_jst) として記録
   //     - TraceMaeMfe_Segmented の引数 (内部で -1 して追跡開始)
   //   に使う。
   string sym = _Symbol;
   int sh_h1_bar = iBarShift(sym, PERIOD_H1, entry_server, false);
   int sh_h4_bar = iBarShift(sym, PERIOD_H4, entry_server, false);
   int sh_d1_bar = iBarShift(sym, PERIOD_D1, entry_server, false);

   if(sh_h1_bar < 0 || sh_h4_bar < 0 || sh_d1_bar < 0)
   {
      PrintFormat("[SKIP line %d] iBarShift fail h1=%d h4=%d d1=%d (entry_server=%s)",
                  line_no, sh_h1_bar, sh_h4_bar, sh_d1_bar,
                  TimeToString(entry_server, TIME_DATE|TIME_MINUTES));
      WriteEmptyRow(fout, trade_id, "ibarshift_fail");
      g_rows_skipped++;
      return;
   }

   //--- v1.32: スナップショット取得用 shift = 直前確定バー (sh_*_bar + 1) ---
   //   理由: Indicator buffer (ATR/ADX/DI) はバー終値時点で確定する。
   //         エントリーバー自身の buffer 値はバー終値 (= エントリーから
   //         最大 1 バー後) の値であり、エントリー時点では未確定。
   //         「直前確定バー」(= エントリーバーの 1 本古い側) の値こそが、
   //         エントリー判断時に利用可能だった値である。
   //   研究目的: 「エントリー時点の市場環境を後付け取得」を満たす。
   int sh_h1 = sh_h1_bar + 1;
   int sh_h4 = sh_h4_bar + 1;
   int sh_d1 = sh_d1_bar + 1;

   //--- 取得元バー時刻 (server) を取得 — bar_time メタデータは        ---
   //--- エントリーバー (sh_*_bar) の open_time を維持 (仕様不変)      ---
   datetime entry_bar_server = iTime(sym, PERIOD_H1, sh_h1_bar);
   datetime h1_bar_server    = entry_bar_server;
   datetime h4_bar_server    = iTime(sym, PERIOD_H4, sh_h4_bar);
   datetime d1_bar_server    = iTime(sym, PERIOD_D1, sh_d1_bar);

   //--- メタデータ: JST 表記 (yyyy-mm-dd HH:MM) に変換 ---
   string entry_bar_time_jst = FormatJstBarTime(entry_bar_server, manual_offset_sec);
   string h1_bar_time_jst    = FormatJstBarTime(h1_bar_server,    manual_offset_sec);
   string h4_bar_time_jst    = FormatJstBarTime(h4_bar_server,    manual_offset_sec);
   string d1_bar_time_jst    = FormatJstBarTime(d1_bar_server,    manual_offset_sec);

   //--- H1 スナップショット ---
   double h1_atr16  = GetBufValue(hATR_S_H1, 0, sh_h1);
   double h1_atr32  = GetBufValue(hATR_L_H1, 0, sh_h1);
   double h1_adx32  = GetBufValue(hADX_H1,   0, sh_h1);
   double h1_dip    = GetBufValue(hADX_H1,   1, sh_h1);
   double h1_din    = GetBufValue(hADX_H1,   2, sh_h1);
   double h1_ratio  = (h1_atr32 > 0) ? h1_atr16 / h1_atr32 : 0;

   //--- H1 ATR ratio (中央値ベース): v4 と同じ median ウィンドウ ---
   //   ATR_Median_Weeks * 5 * 24 本の中央値で正規化
   int median_bars = H1_ATR_Median_Weeks * 5 * 24;
   double h1_atr_median = CalcAtrMedian(hATR_S_H1, sh_h1, median_bars);
   double h1_atr_ratio_median = (h1_atr_median > 0) ? h1_atr16 / h1_atr_median : 0;
   string h1_atr_zone = ClassifyAtrZone(h1_atr_ratio_median);

   //--- H1 Pattern (v4 と同じロジック) ---
   string h1_pattern = ComputeH1Pattern(sh_h1);

   //--- H4 スナップショット ---
   double h4_atr8   = GetBufValue(hATR_S_H4, 0, sh_h4);
   double h4_atr46  = GetBufValue(hATR_L_H4, 0, sh_h4);
   double h4_adx46  = GetBufValue(hADX_H4,   0, sh_h4);
   double h4_dip    = GetBufValue(hADX_H4,   1, sh_h4);
   double h4_din    = GetBufValue(hADX_H4,   2, sh_h4);
   double h4_ratio  = (h4_atr46 > 0) ? h4_atr8 / h4_atr46 : 0;
   double h4_diff   = h4_atr8 - h4_atr46;

   //--- H4 Phase Auto v2 ---
   int h4_cross_dir = 0;
   int h4_cross_bars = FindCrossFromHandles(hATR_S_H4, hATR_L_H4, PERIOD_H4,
                                             sh_h4, H4_Cross_LookBack, h4_cross_dir);
   string h4_cross_label = CrossDirLabel(h4_cross_dir);
   string h4_phase_auto = ComputeH4PhaseAuto(h4_ratio, h4_cross_label, h4_diff);

   //--- D1 スナップショット ---
   double d1_atr22  = GetBufValue(hATR_S_D1, 0, sh_d1);
   double d1_atr42  = GetBufValue(hATR_L_D1, 0, sh_d1);
   double d1_adx22  = GetBufValue(hADX_D1,   0, sh_d1);
   double d1_dip    = GetBufValue(hADX_D1,   1, sh_d1);
   double d1_din    = GetBufValue(hADX_D1,   2, sh_d1);
   double d1_ratio  = (d1_atr42 > 0) ? d1_atr22 / d1_atr42 : 0;

   //--- D1 Phase (ATR22/42 クロス方向ベース、v4 mq5 と同等) ---
   int d1_cross_dir = 0;
   int d1_cross_bars = FindCrossFromHandles(hATR_S_D1, hATR_L_D1, PERIOD_D1,
                                             sh_d1, D1_Cross_LookBack, d1_cross_dir);
   string d1_phase = CrossDirLabel(d1_cross_dir);  // BU / PD / NONE

   //--- 三層 (H1/H4/D1) 時間別 MFE/MAE 追跡 (決済情報独立) ----------+
   //   エントリーバーの「次のバー」から N 本走査する。               |
   //   エントリーバー自身はエントリー前の動きを含むので除外する。     |
   //                                                                  |
   //   v1.3: 全TFで時間別セグメント取得                                |
   //     H1 trace_n=48: 12h=12本/24h=24本/36h=36本/48h=48本           |
   //     H4 trace_n=12: 12h= 3本/24h= 6本/36h= 9本/48h=12本           |
   //     D1 trace_n= 2: 24h= 1本/48h= 2本 (12h/36h は意味なし)        |
   //                                                                  |
   //   汎用関数 TraceMaeMfe_Segmented を全TFで使用。                 |
   //   D1 の 12h/36h は計算するが CSV には出力しない (列定義に従う)。|
   double h1_mfe_12=0, h1_mae_12=0, h1_mfe_24=0, h1_mae_24=0;
   double h1_mfe_36=0, h1_mae_36=0, h1_mfe_48=0, h1_mae_48=0;
   int    h1_mfe_idx_48 = -1, h1_mae_idx_48 = -1, h1_bars_traced = 0;
   double h4_mfe_12=0, h4_mae_12=0, h4_mfe_24=0, h4_mae_24=0;
   double h4_mfe_36=0, h4_mae_36=0, h4_mfe_48=0, h4_mae_48=0;
   int    h4_mfe_idx_48 = -1, h4_mae_idx_48 = -1, h4_bars_traced = 0;
   double d1_mfe_12_dummy=0, d1_mae_12_dummy=0, d1_mfe_24=0, d1_mae_24=0;
   double d1_mfe_36_dummy=0, d1_mae_36_dummy=0, d1_mfe_48=0, d1_mae_48=0;
   int    d1_mfe_idx_48 = -1, d1_mae_idx_48 = -1, d1_bars_traced = 0;

   //--- H1: 12/24/36/48 本セグメント ---
   //    v1.32 注: 追跡用の entry_shift は sh_h1 (=直前確定バー) ではなく
   //    sh_h1_bar (=エントリーバー自身) を渡す。
   //    TraceMaeMfe_Segmented は内部で entry_shift-1 起点で追跡するため、
   //    sh_h1_bar を渡すことでエントリー後の最初のバーから走査が始まり、
   //    追跡対象バーが v1.31 から不変になる (= 仕様維持)。
   bool h1_ok = TraceMaeMfe_Segmented(PERIOD_H1, sh_h1_bar, H1_Trace_Bars_48h,
                                       entry_price, direction,
                                       12, 24, 36, 48,
                                       h1_mfe_12, h1_mae_12,
                                       h1_mfe_24, h1_mae_24,
                                       h1_mfe_36, h1_mae_36,
                                       h1_mfe_48, h1_mae_48,
                                       h1_mfe_idx_48, h1_mae_idx_48,
                                       h1_bars_traced);

   //--- H4: 3/6/9/12 本セグメント (= 12h/24h/36h/48h) ---
   bool h4_ok = TraceMaeMfe_Segmented(PERIOD_H4, sh_h4_bar, H4_Trace_Bars_48h,
                                       entry_price, direction,
                                       3, 6, 9, 12,
                                       h4_mfe_12, h4_mae_12,
                                       h4_mfe_24, h4_mae_24,
                                       h4_mfe_36, h4_mae_36,
                                       h4_mfe_48, h4_mae_48,
                                       h4_mfe_idx_48, h4_mae_idx_48,
                                       h4_bars_traced);

   //--- D1: 24h=1本/48h=2本 のみ。12h/36h は計算可だが CSV 非出力 ---
   //   汎用関数の都合上 seg1/seg3 にダミー本数 (1/2) を渡し、結果は捨てる
   bool d1_ok = TraceMaeMfe_Segmented(PERIOD_D1, sh_d1_bar, D1_Trace_Bars_48h,
                                       entry_price, direction,
                                       1, 1, 2, 2,
                                       d1_mfe_12_dummy, d1_mae_12_dummy,
                                       d1_mfe_24, d1_mae_24,
                                       d1_mfe_36_dummy, d1_mae_36_dummy,
                                       d1_mfe_48, d1_mae_48,
                                       d1_mfe_idx_48, d1_mae_idx_48,
                                       d1_bars_traced);

   bool partial = (h1_bars_traced < H1_Trace_Bars_48h)
               || (h4_bars_traced < H4_Trace_Bars_48h)
               || (d1_bars_traced < D1_Trace_Bars_48h);

   //--- 行データ書き込み (v1.31: 構造体経由) ---
   //   MQL5 の関数引数最大 64 個制限を回避するため、ローカル変数を一旦      |
   //   TradeSnapshotRow に詰めてから WriteRow に参照渡しする。                |
   TradeSnapshotRow row;
   //--- [1-7] 基本 ---
   row.trade_id            = trade_id;
   row.entry_jst           = entry_jst_str;
   row.exit_jst            = exit_jst_str;
   row.direction           = direction;
   row.entry_price         = entry_price;
   row.entry_server        = entry_server;
   row.exit_server         = exit_server;
   //--- [8-11] メタデータ ---
   row.entry_bar_time_jst  = entry_bar_time_jst;
   row.h1_bar_time_jst     = h1_bar_time_jst;
   row.h4_bar_time_jst     = h4_bar_time_jst;
   row.d1_bar_time_jst     = d1_bar_time_jst;
   //--- [12-21] H1 スナップショット ---
   row.h1_atr16            = h1_atr16;
   row.h1_atr32            = h1_atr32;
   row.h1_ratio            = h1_ratio;
   row.h1_atr_median       = h1_atr_median;
   row.h1_atr_ratio_median = h1_atr_ratio_median;
   row.h1_atr_zone         = h1_atr_zone;
   row.h1_adx32            = h1_adx32;
   row.h1_dip              = h1_dip;
   row.h1_din              = h1_din;
   row.h1_pattern          = h1_pattern;
   //--- [22-31] H4 スナップショット ---
   row.h4_atr8             = h4_atr8;
   row.h4_atr46            = h4_atr46;
   row.h4_ratio            = h4_ratio;
   row.h4_diff             = h4_diff;
   row.h4_adx46            = h4_adx46;
   row.h4_dip              = h4_dip;
   row.h4_din              = h4_din;
   row.h4_cross_bars       = h4_cross_bars;
   row.h4_cross_dir        = h4_cross_label;
   row.h4_phase_auto       = h4_phase_auto;
   //--- [32-39] D1 スナップショット ---
   row.d1_atr22            = d1_atr22;
   row.d1_atr42            = d1_atr42;
   row.d1_ratio            = d1_ratio;
   row.d1_adx22            = d1_adx22;
   row.d1_dip              = d1_dip;
   row.d1_din              = d1_din;
   row.d1_cross_bars       = d1_cross_bars;
   row.d1_phase            = d1_phase;
   //--- [40] has_exit ---
   row.has_exit            = has_exit;
   //--- [41-46] H1 48h MAE/MFE ---
   row.h1_ok               = h1_ok;
   row.h1_mfe_usd          = h1_mfe_48;
   row.h1_mfe_idx          = h1_mfe_idx_48;
   row.h1_mae_usd          = h1_mae_48;
   row.h1_mae_idx          = h1_mae_idx_48;
   row.h1_bars_traced      = h1_bars_traced;
   //--- [47-52] H4 48h MAE/MFE ---
   row.h4_ok               = h4_ok;
   row.h4_mfe_usd          = h4_mfe_48;
   row.h4_mfe_idx          = h4_mfe_idx_48;
   row.h4_mae_usd          = h4_mae_48;
   row.h4_mae_idx          = h4_mae_idx_48;
   row.h4_bars_traced      = h4_bars_traced;
   //--- [53-58] D1 48h MAE/MFE ---
   row.d1_ok               = d1_ok;
   row.d1_mfe_usd          = d1_mfe_48;
   row.d1_mfe_idx          = d1_mfe_idx_48;
   row.d1_mae_usd          = d1_mae_48;
   row.d1_mae_idx          = d1_mae_idx_48;
   row.d1_bars_traced      = d1_bars_traced;
   //--- [59-64] H1 12h/24h/36h MFE/MAE ---
   row.h1_mfe_12           = h1_mfe_12;
   row.h1_mae_12           = h1_mae_12;
   row.h1_mfe_24           = h1_mfe_24;
   row.h1_mae_24           = h1_mae_24;
   row.h1_mfe_36           = h1_mfe_36;
   row.h1_mae_36           = h1_mae_36;
   //--- [65-70] H4 12h/24h/36h MFE/MAE ---
   row.h4_mfe_12           = h4_mfe_12;
   row.h4_mae_12           = h4_mae_12;
   row.h4_mfe_24           = h4_mfe_24;
   row.h4_mae_24           = h4_mae_24;
   row.h4_mfe_36           = h4_mfe_36;
   row.h4_mae_36           = h4_mae_36;
   //--- [71-72] D1 24h MFE/MAE ---
   row.d1_mfe_24           = d1_mfe_24;
   row.d1_mae_24           = d1_mae_24;

   WriteRow(fout, row);

   g_rows_written++;
   if(partial) g_rows_partial++;

   if(Verbose && (g_rows_written % 5 == 0))
      PrintFormat("[INFO] processed %d rows...", g_rows_written);
}

//+==================================================================+
//| ParseJstString                                                   |
//|   "yyyy-mm-dd HH:MM" or "yyyy/mm/dd HH:MM" → datetime (JST)     |
//+==================================================================+
datetime ParseJstString(const string &s)
{
   string t = s;
   StringReplace(t, "/", ".");
   StringReplace(t, "-", ".");
   // datetime variable: StringToTime expects "yyyy.mm.dd HH:MM"
   datetime dt = StringToTime(t);
   return dt;
}

//+==================================================================+
//| JstToServer                                                      |
//|   JST (UTC+9) → サーバー時刻に変換                              |
//|                                                                  |
//|   server_time = JST - 9h + server_offset                         |
//|                                                                  |
//|   server_offset の取得手順:                                       |
//|     1. 引数 manual_offset_sec が有効値なら最優先（中間CSVで指定）|
//|     2. Use_Auto_Server_Offset = true なら                        |
//|         TimeTradeServer() - TimeGMT() を使う                     |
//|         (注: 実行時の DST 状態に依存、過去日 DST 跨ぎは要注意)   |
//|     3. それ以外は Manual_Server_Offset_Hours を使う              |
//+==================================================================+
datetime JstToServer(datetime jst, long manual_offset_sec = -999999)
{
   // JST → UTC
   datetime utc = jst - (datetime)(JST_Offset_Hours * 3600);

   long offset_sec = 0;
   if(manual_offset_sec != -999999)
   {
      offset_sec = manual_offset_sec;
   }
   else if(Use_Auto_Server_Offset)
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
//|                                                                  |
//|   jst = server_time - server_offset + 9h                         |
//|                                                                  |
//|   オフセット解決ルールは JstToServer と同一（同じ manual_offset_secを|
//|   渡せば対称に往復可能）                                          |
//+==================================================================+
datetime ServerToJst(datetime server_time, long manual_offset_sec = -999999)
{
   long offset_sec = 0;
   if(manual_offset_sec != -999999)
   {
      offset_sec = manual_offset_sec;
   }
   else if(Use_Auto_Server_Offset)
   {
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   }
   else
   {
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   }

   // server → UTC → JST
   datetime utc = server_time - (datetime)offset_sec;
   return utc + (datetime)(JST_Offset_Hours * 3600);
}

//+==================================================================+
//| FormatJstBarTime                                                 |
//|   サーバー時刻のバー時刻を JST "yyyy-mm-dd HH:MM" に変換         |
//+==================================================================+
string FormatJstBarTime(datetime server_time, long manual_offset_sec = -999999)
{
   if(server_time == 0) return "";
   datetime jst = ServerToJst(server_time, manual_offset_sec);
   // TimeToString は "yyyy.mm.dd HH:MM" を返すので '-' に置換
   string s = TimeToString(jst, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "-");
   return s;
}

//+==================================================================+
//| GetBufValue                                                      |
//|   ハンドルから指定 buffer/shift の値を1つ取得                    |
//+==================================================================+
double GetBufValue(int handle, int buf, int shift)
{
   if(handle == INVALID_HANDLE) return 0;
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buf, shift, 1, tmp) <= 0) return 0;
   return tmp[0];
}

//+==================================================================+
//| CalcAtrMedian                                                    |
//|   v4 mq5 と同じく、shift から median_bars 本の中央値             |
//+==================================================================+
double CalcAtrMedian(int handle, int shift, int median_bars)
{
   if(handle == INVALID_HANDLE) return 0;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, 0, shift, median_bars, arr) <= 0) return 0;

   int cnt = 0;
   double tmp[];
   ArrayResize(tmp, median_bars);
   for(int k = 0; k < median_bars; k++)
      if(arr[k] > 0) tmp[cnt++] = arr[k];
   if(cnt < 10) return 0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
}

//+==================================================================+
//| ClassifyAtrZone                                                  |
//|   ratio (atr_short / atr_median) → LOW / NORMAL / HIGH          |
//+==================================================================+
string ClassifyAtrZone(double ratio)
{
   if(ratio <= 0) return "NA";
   if(ratio < ATR_Zone_Low_Ratio)  return "LOW";
   if(ratio > ATR_Zone_High_Ratio) return "HIGH";
   return "NORMAL";
}

//+==================================================================+
//| FindCrossFromHandles                                             |
//|   指定 shift から過去 max_look 本まで遡って ATR_S vs ATR_L クロス|
//|   を検索。dir_out = +1 (UP/BU) / -1 (DOWN/PD) / 0 (なし)         |
//|   戻り値: クロス経過バー数 (0=直前確定にクロス)、-1=なし         |
//+==================================================================+
int FindCrossFromHandles(int hS, int hL, ENUM_TIMEFRAMES tf,
                          int shift, int max_look, int &dir_out)
{
   dir_out = 0;
   if(hS == INVALID_HANDLE || hL == INVALID_HANDLE) return -1;

   int copy_size = max_look + 2;
   double s[], l[];
   ArraySetAsSeries(s, true);
   ArraySetAsSeries(l, true);
   if(CopyBuffer(hS, 0, shift, copy_size, s) <= 0) return -1;
   if(CopyBuffer(hL, 0, shift, copy_size, l) <= 0) return -1;

   for(int k = 0; k <= max_look; k++)
   {
      int i_now  = k;
      int i_prev = k + 1;
      if(i_prev >= ArraySize(s)) break;
      if(s[i_now]<=0 || l[i_now]<=0 || s[i_prev]<=0 || l[i_prev]<=0) continue;
      bool now_above  = (s[i_now]  > l[i_now]);
      bool prev_above = (s[i_prev] > l[i_prev]);
      if(now_above != prev_above)
      {
         dir_out = now_above ? 1 : -1;
         return k;
      }
   }
   return -1;
}

string CrossDirLabel(int cd)
{
   if(cd > 0) return "BU";
   if(cd < 0) return "PD";
   return "NONE";
}

//+==================================================================+
//| ComputeH1Pattern                                                 |
//|   v4 mq5 の AtrPattern と同じロジック。                          |
//|   vel3 = (atr[shift] - atr[shift+vel_bars]) / atr[shift+vel_bars]|
//|   accel = vel3 - vel3_prev                                       |
//+==================================================================+
string ComputeH1Pattern(int shift)
{
   int need = ATR_Vel_Bars * 2 + 2;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hATR_S_H1, 0, shift, need, arr) <= 0) return "NA";
   if(ArraySize(arr) < need) return "NA";
   if(arr[0] <= 0 || arr[ATR_Vel_Bars] <= 0 || arr[ATR_Vel_Bars*2] <= 0)
      return "NA";

   double vel3 = (arr[0] - arr[ATR_Vel_Bars]) / arr[ATR_Vel_Bars] * 100.0;
   double vel3_prev = (arr[ATR_Vel_Bars] - arr[ATR_Vel_Bars*2]) / arr[ATR_Vel_Bars*2] * 100.0;
   double accel = vel3 - vel3_prev;

   return AtrPattern(vel3, accel);
}

string AtrPattern(double vel3, double accel)
{
   if(MathAbs(vel3) < ATR_Flat_Thresh)     return "FLAT";
   if(vel3 > ATR_Expand_Thresh && accel>0) return "EXPANDING";
   if(vel3 > 0 && accel > 0)               return "RISING_ACCEL";
   if(vel3 > 0 && accel <= 0)              return "RISING_DECEL";
   if(vel3 < 0 && accel < 0)               return "CONTRACTING";
   if(vel3 < 0 && accel >= 0)              return "CONTRACTING_SLOW";
   return "FLAT";
}

//+==================================================================+
//| ComputeH4PhaseAuto                                               |
//|   ARO_H4PhaseAuto_v1.mq5 と同じロジック (5段階)                  |
//+==================================================================+
string ComputeH4PhaseAuto(double ratio, string cross_dir, double atr_diff)
{
   if(ratio <= 0) return "NA";

   if(ratio <= Nagi_Thresh)
   {
      if(atr_diff < -Nagi_Diff_Thresh) return "収束底";
      if(atr_diff >  Nagi_Diff_Thresh) return "凪離脱";
      return "凪";
   }
   if(cross_dir == "BU") return "BU";
   if(cross_dir == "PD") return "PD";
   return "—";
}

//+==================================================================+
//| TraceMaeMfe_Segmented                                            |
//|   エントリーバー (entry_shift) より新しい N 本のバーを走査して   |
//|   時間別セグメント (seg1/seg2/seg3/seg_full) ごとに MFE/MAE を   |
//|   計算する（決済情報を一切使わない）。                            |
//|                                                                  |
//|   入力:                                                            |
//|     tf            : 走査する時間軸 (H1/H4/D1)                    |
//|     entry_shift   : エントリー時刻が属するバーの shift           |
//|     trace_n       : 走査するバー本数 (H1=48 / H4=12 / D1=2)      |
//|     entry_price   : エントリー価格                               |
//|     direction     : BUY / SELL / 買い / 売り                     |
//|     seg1, seg2, seg3, seg_full : 各セグメントのバー本数 (上限)   |
//|       例 H1: 12, 24, 36, 48 (= 12h/24h/36h/48h)                  |
//|       例 H4:  3,  6,  9, 12 (= 12h/24h/36h/48h)                  |
//|       例 D1:  1,  1,  2,  2 (D1 は 24h/48h のみ意味)             |
//|       ※累積型 (seg1 ⊆ seg2 ⊆ seg3 ⊆ seg_full)                 |
//|                                                                  |
//|   出力:                                                            |
//|     mfe_s1/mae_s1 : seg1 本以内の累積最大 MFE/MAE                |
//|     mfe_s2/mae_s2 : seg2 本以内の累積最大 MFE/MAE                |
//|     mfe_s3/mae_s3 : seg3 本以内の累積最大 MFE/MAE                |
//|     mfe_sf/mae_sf : seg_full 本以内 (= 全体) の累積最大 MFE/MAE  |
//|     mfe_bar_idx_full : MFE 到達バー番号 (entry 後 1..seg_full)   |
//|     mae_bar_idx_full : MAE 到達バー番号 (entry 後 1..seg_full)   |
//|       ※ seg1/2/3 の bar_idx は出力しない (指示書方針)            |
//|     bars_traced   : 実際に走査できた本数 (0..trace_n)            |
//|                                                                  |
//|   走査範囲:                                                        |
//|     shift = entry_shift - 1 (エントリー後の最初のバー)           |
//|     〜 shift = entry_shift - trace_n (エントリー後 N 本目)       |
//|     ※エントリー前を含むエントリーバー自身は除外する             |
//|                                                                  |
//|   不完全ケース:                                                    |
//|     entry_shift < trace_n の場合（直近トレード）→ 取得可能本数  |
//|     のみ走査し、bars_traced に実本数を記録                       |
//|     各セグメントは「実取得バー本数 ∩ seg N」の範囲で計算         |
//|                                                                  |
//|   戻り値: true = 1本以上走査できた / false = 走査ゼロ            |
//+==================================================================+
bool TraceMaeMfe_Segmented(ENUM_TIMEFRAMES tf, int entry_shift, int trace_n,
                           double entry_price, const string &direction,
                           int seg1, int seg2, int seg3, int seg_full,
                           double &mfe_s1, double &mae_s1,
                           double &mfe_s2, double &mae_s2,
                           double &mfe_s3, double &mae_s3,
                           double &mfe_sf, double &mae_sf,
                           int &mfe_bar_idx_full, int &mae_bar_idx_full,
                           int &bars_traced)
{
   mfe_s1 = 0; mae_s1 = 0;
   mfe_s2 = 0; mae_s2 = 0;
   mfe_s3 = 0; mae_s3 = 0;
   mfe_sf = 0; mae_sf = 0;
   mfe_bar_idx_full = -1; mae_bar_idx_full = -1;
   bars_traced = 0;

   bool is_buy  = (direction == "BUY"  || direction == "買い");
   bool is_sell = (direction == "SELL" || direction == "売り");
   if(!is_buy && !is_sell) return false;
   if(entry_shift < 0) return false;
   if(trace_n <= 0) return false;

   string sym = _Symbol;

   //--- 走査開始 shift = entry_shift - 1（エントリーバーの次の新しいバー）
   //--- ただし、まだ未確定の現在バー shift=0 まで含むので注意         ---
   //    現在バー含めて構わない（直近トレードでも形成中バーの動きを記録）---
   int start_shift = entry_shift - 1;
   if(start_shift < 0)
   {
      // エントリーバー自体が現在バー = 直近すぎて追跡開始できない
      return false;
   }

   //--- 取得可能本数を確定 ---
   //   start_shift = entry_shift-1（新しい側）
   //   end_shift   = entry_shift-trace_n（古い側、ただし 0 が下限）
   int desired_end = entry_shift - trace_n;
   int end_shift   = (desired_end < 0) ? 0 : desired_end;
   int n_bars      = start_shift - end_shift + 1;
   if(n_bars <= 0) return false;

   //--- High/Low を取得（series=true 前提で end_shift から n_bars 本）---
   //    series 配列 index:                                              ---
   //      [0]       = start_shift（新しい側、entry の次のバー = idx 1）---
   //      [n-1]     = end_shift  （古い側、entry の N 本後 = idx N）   ---
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(sym, tf, end_shift, n_bars, highs) <= 0) return false;
   if(CopyLow (sym, tf, end_shift, n_bars, lows)  <= 0) return false;

   //--- セグメント別の最大値追跡 (sentinel = -DBL_MAX) ---
   double best_favor_s1=-DBL_MAX, worst_adverse_s1=-DBL_MAX;
   double best_favor_s2=-DBL_MAX, worst_adverse_s2=-DBL_MAX;
   double best_favor_s3=-DBL_MAX, worst_adverse_s3=-DBL_MAX;
   double best_favor_sf=-DBL_MAX, worst_adverse_sf=-DBL_MAX;
   int    best_idx_sf  = -1, worst_idx_sf = -1;

   for(int k = 0; k < n_bars; k++)
   {
      double hi = highs[k];
      double lo = lows[k];
      if(hi <= 0 || lo <= 0) continue;

      double adverse, favor;
      if(is_buy)
      {
         adverse = entry_price - lo;   // 下抜けが逆行
         favor   = hi - entry_price;   // 上が有利
      }
      else
      {
         adverse = hi - entry_price;   // 上抜けが逆行
         favor   = entry_price - lo;   // 下が有利
      }

      //--- エントリー後の何本目 (1..n_bars) ---
      //   series index k は新しい側起点。
      //   start_shift = entry_shift-1 から数えると k=0 が entry 後 1本目。
      //   entry から数えて何本目 = n_bars - k
      int bar_no = n_bars - k;

      //--- seg_full (= 全体、bar_idx 付き) ---
      if(bar_no <= seg_full)
      {
         if(favor > best_favor_sf)       { best_favor_sf = favor;       best_idx_sf  = k; }
         if(adverse > worst_adverse_sf)  { worst_adverse_sf = adverse;  worst_idx_sf = k; }
      }
      //--- seg3 (bar_idx 省略) ---
      if(bar_no <= seg3)
      {
         if(favor > best_favor_s3)       best_favor_s3 = favor;
         if(adverse > worst_adverse_s3)  worst_adverse_s3 = adverse;
      }
      //--- seg2 ---
      if(bar_no <= seg2)
      {
         if(favor > best_favor_s2)       best_favor_s2 = favor;
         if(adverse > worst_adverse_s2)  worst_adverse_s2 = adverse;
      }
      //--- seg1 ---
      if(bar_no <= seg1)
      {
         if(favor > best_favor_s1)       best_favor_s1 = favor;
         if(adverse > worst_adverse_s1)  worst_adverse_s1 = adverse;
      }
   }

   //--- seg_full (bar_idx 付き) ---
   if(best_idx_sf >= 0)
   {
      mfe_sf           = MathMax(0.0, best_favor_sf);
      mfe_bar_idx_full = n_bars - best_idx_sf;
   }
   if(worst_idx_sf >= 0)
   {
      mae_sf           = MathMax(0.0, worst_adverse_sf);
      mae_bar_idx_full = n_bars - worst_idx_sf;
   }

   //--- seg1/seg2/seg3 (bar_idx なし、sentinel チェック付き) ---
   if(best_favor_s1    > -DBL_MAX) mfe_s1 = MathMax(0.0, best_favor_s1);
   if(worst_adverse_s1 > -DBL_MAX) mae_s1 = MathMax(0.0, worst_adverse_s1);
   if(best_favor_s2    > -DBL_MAX) mfe_s2 = MathMax(0.0, best_favor_s2);
   if(worst_adverse_s2 > -DBL_MAX) mae_s2 = MathMax(0.0, worst_adverse_s2);
   if(best_favor_s3    > -DBL_MAX) mfe_s3 = MathMax(0.0, best_favor_s3);
   if(worst_adverse_s3 > -DBL_MAX) mae_s3 = MathMax(0.0, worst_adverse_s3);

   bars_traced = n_bars;
   return true;
}

//+==================================================================+
//| WriteUtf8Bom                                                     |
//+==================================================================+
void WriteUtf8Bom(int fh)
{
   uchar bom[3] = {0xEF, 0xBB, 0xBF};
   FileWriteArray(fh, bom, 0, 3);
}

//+==================================================================+
//| WriteUtf8String                                                  |
//|   UTF-8 でバイナリ書き込み                                       |
//+==================================================================+
void WriteUtf8String(int fh, const string s)
{
   // 引数は値渡し（const string s）にすることで、呼び出し側で
   // `line + "\n"` のような一時 string (rvalue) も渡せるようにする。
   // MQL5 は参照引数 (const string &) に rvalue を渡せない制約があるため。
   uchar buf[];
   StringToCharArray(s, buf, 0, -1, CP_UTF8);
   // StringToCharArray は末尾に '\0' を付ける場合があるので除外
   int n = ArraySize(buf);
   if(n > 0 && buf[n-1] == 0) n--;
   if(n > 0) FileWriteArray(fh, buf, 0, n);
}

//+==================================================================+
//| WriteHeaderUtf8                                                  |
//|   v1.3 ヘッダ: 72列                                              |
//|                                                                  |
//|   構成:                                                            |
//|     [1-7]   基本 (trade_id, JST/server時刻, direction, price)    |
//|     [8-11]  メタデータ (entry_bar_time × 4)                       |
//|     [12-21] H1 スナップショット (10列)                            |
//|     [22-31] H4 スナップショット (10列)                            |
//|     [32-39] D1 スナップショット (8列)                             |
//|     [40]    has_exit                                             |
//|     [41-46] H1 48h MAE/MFE (6列: ok, mfe_usd, mfe_idx,          |
//|             mae_usd, mae_idx, bars_traced)                       |
//|     [47-52] H4 48h MAE/MFE (6列)                                 |
//|     [53-58] D1 48h MAE/MFE (6列)                                 |
//|     [59-64] H1 12h/24h/36h MFE/MAE (★v1.2 追加, 6列)            |
//|     [65-70] H4 12h/24h/36h MFE/MAE (★v1.3 新規, 6列)            |
//|     [71-72] D1 24h MFE/MAE (★v1.3 新規, 2列)                     |
//|                                                                  |
//|   合計: 7 + 4 + 10 + 10 + 8 + 1 + 6 + 6 + 6 + 6 + 6 + 2 = 72列  |
//|                                                                  |
//|   方針: 既存カラム名は完全維持。新規は末尾に追加。               |
//|   後方互換: マニ generate_daily_calendar.py 等の既存読込は不変。 |
//+==================================================================+
void WriteHeaderUtf8(int fh)
{
   string line =
      // [1-7] 基本
      "trade_id,entry_jst,exit_jst,direction,entry_price,"
      "entry_server_time,exit_server_time,"
      // [8-11] メタデータ (bar_time × 4, JST表記)
      "entry_bar_time,h1_bar_time,h4_bar_time,d1_bar_time,"
      // [12-21] H1 スナップショット
      "h1_atr16,h1_atr32,h1_atr_ratio,h1_atr_median,h1_atr_ratio_median,h1_atr_zone,"
      "h1_adx32,h1_di_plus,h1_di_minus,h1_pattern,"
      // [22-31] H4 スナップショット (10列)
      "h4_atr8,h4_atr46,h4_atr_ratio,h4_atr_diff,"
      "h4_adx46,h4_di_plus,h4_di_minus,"
      "h4_cross_bars,h4_cross_dir,h4_phase_auto,"
      // [32-39] D1 スナップショット (8列)
      "d1_atr22,d1_atr42,d1_atr_ratio,"
      "d1_adx22,d1_di_plus,d1_di_minus,"
      "d1_cross_bars,d1_phase,"
      // [40] has_exit (決済情報の有無フラグ、MAE/MFE 計算には不使用)
      "has_exit,"
      // [41-46] H1 48h MAE/MFE
      "h1_trace_ok,"
      "h1_mfe_usd_48h,h1_mfe_bar_idx_48h,h1_mae_usd_48h,h1_mae_bar_idx_48h,h1_bars_traced_48h,"
      // [47-52] H4 48h MAE/MFE
      "h4_trace_ok,"
      "h4_mfe_usd_48h,h4_mfe_bar_idx_48h,h4_mae_usd_48h,h4_mae_bar_idx_48h,h4_bars_traced_48h,"
      // [53-58] D1 48h MAE/MFE
      "d1_trace_ok,"
      "d1_mfe_usd_48h,d1_mfe_bar_idx_48h,d1_mae_usd_48h,d1_mae_bar_idx_48h,d1_bars_traced_48h,"
      // [59-64] H1 12h/24h/36h MFE/MAE (★v1.2 既存)
      "h1_mfe_usd_12h,h1_mae_usd_12h,"
      "h1_mfe_usd_24h,h1_mae_usd_24h,"
      "h1_mfe_usd_36h,h1_mae_usd_36h,"
      // [65-70] H4 12h/24h/36h MFE/MAE (★v1.3 新規)
      "h4_mfe_usd_12h,h4_mae_usd_12h,"
      "h4_mfe_usd_24h,h4_mae_usd_24h,"
      "h4_mfe_usd_36h,h4_mae_usd_36h,"
      // [71-72] D1 24h MFE/MAE (★v1.3 新規)
      "d1_mfe_usd_24h,d1_mae_usd_24h";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| WriteRow                                                         |
//|   v1.31 72列出力 (MQL5 64引数制限 → 構造体引数に変更)            |
//|                                                                  |
//|   末尾追加列の取扱い:                                              |
//|     - H1 12h/24h/36h は row.h1_ok の真偽に従う (失敗時は空)      |
//|     - H4 12h/24h/36h は row.h4_ok の真偽に従う                   |
//|     - D1 24h        は row.d1_ok の真偽に従う                    |
//+==================================================================+
void WriteRow(int fh, const TradeSnapshotRow &row)
{
   string line = "";
   //--- [1-7] 基本 ---
   line += row.trade_id + ",";
   line += row.entry_jst + ",";
   line += row.exit_jst + ",";
   line += row.direction + ",";
   line += DoubleToString(row.entry_price, 3) + ",";
   line += TimeToString(row.entry_server, TIME_DATE|TIME_MINUTES) + ",";
   line += (row.exit_server > 0 ? TimeToString(row.exit_server, TIME_DATE|TIME_MINUTES) : "") + ",";
   //--- [8-11] メタデータ (bar_time × 4, JST 表記) ---
   line += row.entry_bar_time_jst + ",";
   line += row.h1_bar_time_jst + ",";
   line += row.h4_bar_time_jst + ",";
   line += row.d1_bar_time_jst + ",";
   //--- [12-21] H1 スナップショット ---
   line += DoubleToString(row.h1_atr16, 4) + ",";
   line += DoubleToString(row.h1_atr32, 4) + ",";
   line += DoubleToString(row.h1_ratio, 4) + ",";
   line += DoubleToString(row.h1_atr_median, 4) + ",";
   line += DoubleToString(row.h1_atr_ratio_median, 4) + ",";
   line += row.h1_atr_zone + ",";
   line += DoubleToString(row.h1_adx32, 2) + ",";
   line += DoubleToString(row.h1_dip, 2) + ",";
   line += DoubleToString(row.h1_din, 2) + ",";
   line += row.h1_pattern + ",";
   //--- [22-31] H4 スナップショット ---
   line += DoubleToString(row.h4_atr8, 4) + ",";
   line += DoubleToString(row.h4_atr46, 4) + ",";
   line += DoubleToString(row.h4_ratio, 4) + ",";
   line += DoubleToString(row.h4_diff, 4) + ",";
   line += DoubleToString(row.h4_adx46, 2) + ",";
   line += DoubleToString(row.h4_dip, 2) + ",";
   line += DoubleToString(row.h4_din, 2) + ",";
   line += IntegerToString(row.h4_cross_bars) + ",";
   line += row.h4_cross_dir + ",";
   line += row.h4_phase_auto + ",";
   //--- [32-39] D1 スナップショット ---
   line += DoubleToString(row.d1_atr22, 4) + ",";
   line += DoubleToString(row.d1_atr42, 4) + ",";
   line += DoubleToString(row.d1_ratio, 4) + ",";
   line += DoubleToString(row.d1_adx22, 2) + ",";
   line += DoubleToString(row.d1_dip, 2) + ",";
   line += DoubleToString(row.d1_din, 2) + ",";
   line += IntegerToString(row.d1_cross_bars) + ",";
   line += row.d1_phase + ",";
   //--- [40] has_exit ---
   line += (row.has_exit ? "1" : "0") + ",";
   //--- [41-46] H1 48h MAE/MFE ---
   line += (row.h1_ok ? "1" : "0") + ",";
   if(row.h1_ok)
   {
      line += DoubleToString(row.h1_mfe_usd, 3) + ",";
      line += IntegerToString(row.h1_mfe_idx) + ",";
      line += DoubleToString(row.h1_mae_usd, 3) + ",";
      line += IntegerToString(row.h1_mae_idx) + ",";
      line += IntegerToString(row.h1_bars_traced) + ",";
   }
   else
   {
      line += ",,,,,";
   }
   //--- [47-52] H4 48h MAE/MFE ---
   line += (row.h4_ok ? "1" : "0") + ",";
   if(row.h4_ok)
   {
      line += DoubleToString(row.h4_mfe_usd, 3) + ",";
      line += IntegerToString(row.h4_mfe_idx) + ",";
      line += DoubleToString(row.h4_mae_usd, 3) + ",";
      line += IntegerToString(row.h4_mae_idx) + ",";
      line += IntegerToString(row.h4_bars_traced) + ",";
   }
   else
   {
      line += ",,,,,";
   }
   //--- [53-58] D1 48h MAE/MFE ---
   line += (row.d1_ok ? "1" : "0") + ",";
   if(row.d1_ok)
   {
      line += DoubleToString(row.d1_mfe_usd, 3) + ",";
      line += IntegerToString(row.d1_mfe_idx) + ",";
      line += DoubleToString(row.d1_mae_usd, 3) + ",";
      line += IntegerToString(row.d1_mae_idx) + ",";
      line += IntegerToString(row.d1_bars_traced) + ",";
   }
   else
   {
      line += ",,,,,";
   }
   //--- [59-64] H1 12h/24h/36h MFE/MAE (v1.2 既存) ---
   if(row.h1_ok)
   {
      line += DoubleToString(row.h1_mfe_12, 3) + ",";
      line += DoubleToString(row.h1_mae_12, 3) + ",";
      line += DoubleToString(row.h1_mfe_24, 3) + ",";
      line += DoubleToString(row.h1_mae_24, 3) + ",";
      line += DoubleToString(row.h1_mfe_36, 3) + ",";
      line += DoubleToString(row.h1_mae_36, 3) + ",";
   }
   else
   {
      line += ",,,,,,";
   }
   //--- [65-70] H4 12h/24h/36h MFE/MAE (v1.3 新規) ---
   if(row.h4_ok)
   {
      line += DoubleToString(row.h4_mfe_12, 3) + ",";
      line += DoubleToString(row.h4_mae_12, 3) + ",";
      line += DoubleToString(row.h4_mfe_24, 3) + ",";
      line += DoubleToString(row.h4_mae_24, 3) + ",";
      line += DoubleToString(row.h4_mfe_36, 3) + ",";
      line += DoubleToString(row.h4_mae_36, 3) + ",";
   }
   else
   {
      line += ",,,,,,";
   }
   //--- [71-72] D1 24h MFE/MAE (v1.3 新規) ---
   //   v1.31 修正: ok=false 時のカンマが 1 個しかなく 71列出力となるバグを    |
   //   ","," " (区切り1 + 末尾フィールド空) に修正。最終列のため末尾カンマ無し。|
   if(row.d1_ok)
   {
      line += DoubleToString(row.d1_mfe_24, 3) + ",";
      line += DoubleToString(row.d1_mae_24, 3);
   }
   else
   {
      line += ",";   // 24h MFE 空 + カンマ + 24h MAE 空 (末尾フィールドなので)
   }

   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| WriteEmptyRow                                                    |
//|   スナップショット取得失敗時の最小限の行（trade_id + 空欄）     |
//|   reason は Print のみで CSV には残さない（列整合維持のため）   |
//|   ヘッダの列数: 72列 (v1.3)                                       |
//+==================================================================+
void WriteEmptyRow(int fh, const string &trade_id, const string &reason)
{
   PrintFormat("[ROW_EMPTY] trade_id=%s reason=%s", trade_id, reason);
   string line = trade_id;
   // 残り71列分のカンマを追加（72列ヘッダ - 1 = 71個のカンマ）
   for(int i = 0; i < 71; i++) line += ",";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| Trim / StringToUpperCopy                                         |
//+==================================================================+
string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string StringToUpperCopy(string s)
{
   StringToUpper(s);
   return s;
}
//+------------------------------------------------------------------+
