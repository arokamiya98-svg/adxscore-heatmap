//+------------------------------------------------------------------+
//|  Account_History_Snapshot_v1.mq5                                 |
//|  ログイン中口座の取引履歴（HistorySelect）を指定期間ぶん読み、   |
//|  1ポジション=1行で「当時のロット/リスク/SL設計」と               |
//|  「エントリー時点の市場環境スナップショット（現行確定周期）」を  |
//|  合わせて CSV 出力する過去分析用 Script。                         |
//|                                                                  |
//|  研究目的（絶対固定）:                                            |
//|    過去口座（例: 2025年 1万→300万期）のロット配分と               |
//|    ATR基準へのアプローチを「今の物差し」で測り直し、             |
//|    現行戦略と重ね合わせる構造分析。                               |
//|    ※勝率向上ツールではない。月別損益ランキング等の集計は目的外。|
//|                                                                  |
//|  物差しの出自（列名・ロジックとも完全互換）:                      |
//|    signals/Trade_Snapshot_Builder.mq5 v1.32                       |
//|      - H1/H4/D1 スナップショット（直前確定バー sh+1 取得）        |
//|      - ATR median 8週=960本 / Zone 0.70/1.40                      |
//|      - H1 Pattern (v4同等) / H4 Phase Auto v2 / D1 Cross          |
//|      - 48h 固定 H1 MFE/MAE（エントリーバーの次から48本）          |
//|                                                                  |
//|  本スクリプト固有の追加:                                          |
//|    - 入力 = MT5 口座履歴（trade_input.csv 不要）                  |
//|    - volume / entries / exits（積み増し・分割決済の回数）         |
//|    - balance_at_entry / balance_after（全履歴からbalance再構成）  |
//|    - risk_usd / risk_pct / lot_per_1k / result_r                  |
//|    - sl_dist_atr / tp_dist_atr（SL/TPをH1 ATR16換算）             |
//|    - in-trade MFE/MAE（保有期間中、M5優先→H1フォールバック）     |
//|    - AccountFlow.csv（入出金・クレジットの別建て記録）            |
//|                                                                  |
//|  個人情報の線引き（あろさん確定 2026-06-19 準拠）:                |
//|    口座番号（ACCOUNT_LOGIN）はファイル名にもCSV内にも出力しない。|
//|    出力ファイル名は固定 + 任意タグ（input）。                     |
//|                                                                  |
//|  使い方:                                                          |
//|    1. 対象口座にログイン（investor パスワードでも履歴閲覧可）     |
//|    2. 対象期間の H1/H4/D1（できれば M5）チャートを開き、          |
//|       過去へスクロールして履歴データをダウンロードしておく        |
//|    3. 任意チャートで本 Script を実行（チャートのシンボル不問。    |
//|       指標ハンドルは deal のシンボルごとに生成する）              |
//|    4. MQL5/Files/ に出力された 2 つの CSV を回収                  |
//|                                                                  |
//|  地雷・制約（SPEC_account_history_snapshot_v1.md に詳細）:        |
//|    - JST⇔server 変換は実行時オフセット。過去の DST 跨ぎは        |
//|      最大1時間ズレの可能性（バー単位の環境取得には概ね無害）      |
//|    - balance 再構成は「MT5から見える全履歴」前提。ブローカーが    |
//|      古い履歴を切っていると開始残高がズレる（警告Print で検知）   |
//|    - sl_price/tp_price はエントリー deal 記録時点の値（=初期設計）|
//|      0 = SL/TP未設定（それ自体が当時のアプローチ情報）            |
//|    - CREDIT/BONUS は balance に算入しない（equity側のため）       |
//|                                                                  |
//|  作成日: 2026-07-13                                               |
//|  作成: おぱ（Trade_Snapshot_Builder v1.32 をベースに）            |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.0"
#property script_show_inputs
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 対象期間 (JSTで指定) ==="
input datetime Period_From_JST     = D'2025.01.01 00:00';  // この日時以降のエントリー
input datetime Period_To_JST       = D'2026.01.01 00:00';  // この日時より前のエントリー

input group "=== 出力ファイル ==="
input string  Output_Tag           = "2025";  // ファイル名サフィックス（空欄可）

input group "=== タイムゾーン ==="
input int     JST_Offset_Hours     = 9;       // JST = UTC+9（固定）
input bool    Use_Auto_Server_Offset = true;  // TimeTradeServer()-TimeGMT() で自動算出
input int     Manual_Server_Offset_Hours = 2; // 自動算出失敗時のフォールバック

input group "=== H1 指標周期 (CLAUDE.md 確定値) ==="
input int     H1_ATR_Short         = 16;
input int     H1_ATR_Long          = 32;
input int     H1_ADX_Period        = 32;
input int     H1_ATR_Median_Weeks  = 8;       // ATR ratio 中央値ウィンドウ

input group "=== H4 指標周期 ==="
input int     H4_ATR_Short         = 8;
input int     H4_ATR_Long          = 46;
input int     H4_ADX_Period        = 46;

input group "=== D1 指標周期 ==="
input int     D1_ATR_Short         = 22;
input int     D1_ATR_Long          = 42;
input int     D1_ADX_Period        = 22;

input group "=== ATR Zone 閾値 (H1) ==="
input double  ATR_Zone_Low_Ratio   = 0.70;
input double  ATR_Zone_High_Ratio  = 1.40;

input group "=== H1 Pattern 判定 (v4 同等) ==="
input int     ATR_Vel_Bars         = 3;
input double  ATR_Expand_Thresh    = 10.0;
input double  ATR_Flat_Thresh      = 3.0;

input group "=== H4 Phase Auto v2 ==="
input int     H4_Cross_LookBack    = 30;
input double  Nagi_Thresh          = 0.97;
input double  Nagi_Diff_Thresh     = 1.0;

input group "=== D1 ATR Cross 判定 ==="
input int     D1_Cross_LookBack    = 30;

input group "=== 48h MAE/MFE (H1) ==="
input int     H1_Trace_Bars_48h    = 48;

input group "=== in-trade MFE/MAE ==="
input bool    Intrade_Use_M5       = true;    // M5優先（データ無ければH1へ）

input group "=== デバッグ ==="
input bool    Verbose              = true;

//+==================================================================+
//| PosAgg : deal を position_id 単位に集約する作業構造体            |
//+==================================================================+
struct PosAgg
{
   long     position_id;
   string   symbol;
   string   direction;        // BUY / SELL（最初の IN deal の売買）
   double   vol_in;           // IN volume 合計
   double   vol_out;          // OUT volume 合計
   int      entries;          // IN deal 数（>1 = 積み増し/ナンピン）
   int      exits;            // OUT deal 数（>1 = 分割決済）
   datetime entry_server;     // 最初の IN 時刻
   datetime exit_server;      // 最後の OUT 時刻（0 = オープン中）
   double   entry_price;      // IN 加重平均
   double   exit_price;       // OUT 加重平均
   double   sl_price;         // 最初の IN deal 記録時点の SL（0=未設定）
   double   tp_price;         // 同 TP
   double   profit;           // OUT の DEAL_PROFIT 累積
   double   swap;             // swap 累積
   double   commission;       // IN/OUT commission + fee 累積
   double   balance_at_entry; // 最初の IN 直前の再構成 balance
   double   balance_after;    // 最後の OUT 反映後の再構成 balance
   long     magic;            // 最初の IN deal の magic
   string   comment;          // 最初の IN deal の comment
};

//+==================================================================+
//| SymHandles : シンボル別 指標ハンドルキャッシュ                    |
//+==================================================================+
struct SymHandles
{
   string sym;
   int hATR_S_H1; int hATR_L_H1; int hADX_H1;
   int hATR_S_H4; int hATR_L_H4; int hADX_H4;
   int hATR_S_D1; int hATR_L_D1; int hADX_D1;
   bool ok;
};

//+==================================================================+
//| AccountRow : CSV 1行分（69列）                                    |
//+==================================================================+
struct AccountRow
{
   //--- [1-9] 基本 ---
   long     position_id;
   string   symbol;
   string   direction;
   double   volume;
   int      entries;
   int      exits;
   string   entry_jst;
   string   exit_jst;
   double   duration_h;
   //--- [10-18] 価格・SL/TP設計 ---
   double   entry_price;
   double   exit_price;
   double   sl_price;
   double   tp_price;
   double   sl_dist;
   double   tp_dist;
   double   rr_planned;
   double   sl_dist_atr;
   double   tp_dist_atr;
   //--- [19-22] 損益 ---
   double   profit;
   double   swap;
   double   commission;
   double   net_profit;
   //--- [23-28] 資金・リスク ---
   double   balance_at_entry;
   double   balance_after;
   double   risk_usd;      // <0 = SLなしで計算不能（空欄出力）
   double   risk_pct;
   double   lot_per_1k;
   double   result_r;      // risk_usd が無い場合は空欄出力
   //--- [29-30] 発注メタ ---
   long     magic;
   string   comment;
   //--- [31-40] H1 スナップショット ---
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
   //--- [41-50] H4 スナップショット ---
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
   //--- [51-58] D1 スナップショット ---
   double   d1_atr22;
   double   d1_atr42;
   double   d1_ratio;
   double   d1_adx22;
   double   d1_dip;
   double   d1_din;
   int      d1_cross_bars;
   string   d1_phase;
   //--- [59-64] H1 48h MAE/MFE ---
   bool     h1_ok;
   double   h1_mfe_usd;
   int      h1_mfe_idx;
   double   h1_mae_usd;
   int      h1_mae_idx;
   int      h1_bars_traced;
   //--- [65-69] in-trade MFE/MAE ---
   bool     it_ok;
   string   it_tf;         // M5 / H1 / NA
   double   it_mfe_usd;
   double   it_mae_usd;
   int      it_bars;
   //--- 環境スナップショットが取れたか（列には出さない・空欄制御用）---
   bool     env_ok;
};

//+-----[ グローバル ]----------------------------------------------+
SymHandles g_handles[];
PosAgg     g_pos[];
int        g_rows_written = 0;
int        g_rows_env_fail = 0;

//+==================================================================+
//| OnStart                                                          |
//+==================================================================+
void OnStart()
{
   Print("==== Account_History_Snapshot_v1 Start ====");
   PrintFormat("Server: %s / Currency: %s",
               AccountInfoString(ACCOUNT_SERVER), AccountInfoString(ACCOUNT_CURRENCY));
   PrintFormat("Period (JST): %s ~ %s",
               TimeToString(Period_From_JST, TIME_DATE|TIME_MINUTES),
               TimeToString(Period_To_JST,   TIME_DATE|TIME_MINUTES));

   datetime from_server = JstToServer(Period_From_JST);
   datetime to_server   = JstToServer(Period_To_JST);

   //--- 全履歴選択（balance 再構成のため期間外も含めて全部）---
   if(!HistorySelect(0, TimeCurrent()))
   {
      Print("[FATAL] HistorySelect 失敗");
      return;
   }
   int total = HistoryDealsTotal();
   PrintFormat("[INFO] total deals in history = %d", total);
   if(total == 0)
   {
      Print("[FATAL] 履歴が空。口座を間違えていないか確認。");
      return;
   }

   //--- 出力ファイル名（口座番号は含めない）---
   string tag = (StringLen(Output_Tag) > 0) ? "_" + Output_Tag : "";
   string out_main = "AccountHistory_Enriched" + tag + ".csv";
   string out_flow = "AccountFlow" + tag + ".csv";

   int fflow = FileOpen(out_flow, FILE_WRITE|FILE_BIN, ',');
   if(fflow == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] flow CSV open失敗: %s err=%d", out_flow, GetLastError());
      return;
   }
   WriteUtf8Bom(fflow);
   WriteUtf8String(fflow, "time_jst,type,amount,balance_after,comment\n");

   //--- Pass 1: deal 全走査 → balance 再構成 + position 集約 + flow 書き出し ---
   BuildPositions(fflow, from_server, to_server);
   FileClose(fflow);
   PrintFormat("[INFO] aggregated positions = %d", ArraySize(g_pos));

   //--- Pass 2: 期間内ポジションへ環境エンリッチ + 書き出し ---
   int fout = FileOpen(out_main, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 出力CSV open失敗: %s err=%d", out_main, GetLastError());
      ReleaseAllHandles();
      return;
   }
   WriteUtf8Bom(fout);
   WriteHeaderUtf8(fout);

   int in_period = 0;
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(g_pos[i].entry_server < from_server || g_pos[i].entry_server >= to_server)
         continue;
      in_period++;
      EnrichAndWrite(fout, g_pos[i]);
      if(Verbose && (in_period % 20 == 0))
         PrintFormat("[INFO] processed %d positions...", in_period);
   }

   FileClose(fout);
   ReleaseAllHandles();

   Print("==== Account_History_Snapshot_v1 Complete ====");
   PrintFormat("  positions in period = %d / written = %d / env_fail = %d",
               in_period, g_rows_written, g_rows_env_fail);
   PrintFormat("  Output: %s/MQL5/Files/%s", TerminalInfoString(TERMINAL_DATA_PATH), out_main);
   PrintFormat("  Flow  : %s/MQL5/Files/%s", TerminalInfoString(TERMINAL_DATA_PATH), out_flow);
}

//+==================================================================+
//| BuildPositions                                                   |
//|   deal を実行時刻順（HistorySelect の並び）に全走査。            |
//|   - balance 再構成: CREDIT/BONUS 以外の全 deal で                |
//|       balance += profit + swap + commission + fee                |
//|   - 入出金等の non-trade deal → flow CSV へ                      |
//|   - IN/OUT deal → position_id 単位に g_pos[] へ集約              |
//+==================================================================+
void BuildPositions(int fflow, datetime from_server, datetime to_server)
{
   double balance = 0.0;
   bool   first_deal_checked = false;
   int    total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long   dtype   = HistoryDealGetInteger(ticket, DEAL_TYPE);
      long   dentry  = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      datetime dtime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double profit  = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap    = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double comm    = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double fee     = HistoryDealGetDouble(ticket, DEAL_FEE);

      bool is_trade  = (dtype == DEAL_TYPE_BUY || dtype == DEAL_TYPE_SELL);
      bool is_credit = (dtype == DEAL_TYPE_CREDIT || dtype == DEAL_TYPE_BONUS);

      //--- 最初の deal が入金でなければ「履歴切れ」の疑いを警告 ---
      if(!first_deal_checked)
      {
         first_deal_checked = true;
         if(dtype != DEAL_TYPE_BALANCE)
            Print("[WARN] 最初の deal が入金ではない。ブローカー側で古い履歴が"
                  "切られている可能性 → balance 再構成がズレるので要確認。");
      }

      //--- non-trade deal（入出金/クレジット/補正など）---
      if(!is_trade)
      {
         string ftype;
         if(dtype == DEAL_TYPE_BALANCE) ftype = (profit >= 0) ? "DEPOSIT" : "WITHDRAWAL";
         else if(dtype == DEAL_TYPE_CREDIT) ftype = "CREDIT";
         else if(dtype == DEAL_TYPE_BONUS)  ftype = "BONUS";
         else ftype = "OTHER_" + IntegerToString((int)dtype);

         if(!is_credit)
            balance += profit + swap + comm + fee;

         string fcomment = SanitizeCsv(HistoryDealGetString(ticket, DEAL_COMMENT));
         string line = FormatJstBarTime(dtime) + "," + ftype + ","
                     + DoubleToString(profit, 2) + ","
                     + (is_credit ? "" : DoubleToString(balance, 2)) + ","
                     + fcomment;
         WriteUtf8String(fflow, line + "\n");
         continue;
      }

      //--- trade deal → position 集約 ---
      long pid = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      int idx = FindPos(pid);

      if(dentry == DEAL_ENTRY_IN || dentry == DEAL_ENTRY_INOUT)
      {
         // INOUT（ドテン）は「反転後の新規部分」を新エントリーとして扱う
         if(idx < 0)
         {
            idx = ArraySize(g_pos);
            ArrayResize(g_pos, idx + 1);
            PosAgg p;
            p.position_id      = pid;
            p.symbol           = HistoryDealGetString(ticket, DEAL_SYMBOL);
            p.direction        = (dtype == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            p.vol_in           = 0; p.vol_out = 0;
            p.entries          = 0; p.exits   = 0;
            p.entry_server     = dtime;
            p.exit_server      = 0;
            p.entry_price      = 0; p.exit_price = 0;
            p.sl_price         = HistoryDealGetDouble(ticket, DEAL_SL);
            p.tp_price         = HistoryDealGetDouble(ticket, DEAL_TP);
            p.profit           = 0; p.swap = 0; p.commission = 0;
            p.balance_at_entry = balance;   // IN 反映前 = エントリー直前残高
            p.balance_after    = balance;
            p.magic            = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            p.comment          = SanitizeCsv(HistoryDealGetString(ticket, DEAL_COMMENT));
            g_pos[idx] = p;
         }
         double v  = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double pr = HistoryDealGetDouble(ticket, DEAL_PRICE);
         // 加重平均建値
         double tot_v = g_pos[idx].vol_in + v;
         if(tot_v > 0)
            g_pos[idx].entry_price = (g_pos[idx].entry_price * g_pos[idx].vol_in + pr * v) / tot_v;
         g_pos[idx].vol_in = tot_v;
         g_pos[idx].entries++;
         g_pos[idx].commission += comm + fee;
         g_pos[idx].swap       += swap;
      }
      else  // DEAL_ENTRY_OUT / DEAL_ENTRY_OUT_BY
      {
         if(idx < 0)
         {
            // 対応する IN が履歴に無い（履歴切れで OUT だけ残った等）→ スキップ
            if(Verbose)
               PrintFormat("[WARN] OUT deal without IN: pos_id=%I64d time=%s → skip",
                           pid, TimeToString(dtime, TIME_DATE|TIME_MINUTES));
         }
         else
         {
            double v  = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double pr = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double tot_v = g_pos[idx].vol_out + v;
            if(tot_v > 0)
               g_pos[idx].exit_price = (g_pos[idx].exit_price * g_pos[idx].vol_out + pr * v) / tot_v;
            g_pos[idx].vol_out = tot_v;
            g_pos[idx].exits++;
            g_pos[idx].exit_server = dtime;
            g_pos[idx].profit     += profit;
            g_pos[idx].swap       += swap;
            g_pos[idx].commission += comm + fee;
         }
      }

      //--- balance 反映（trade deal は profit+swap+comm+fee）---
      balance += profit + swap + comm + fee;
      if(idx >= 0) g_pos[idx].balance_after = balance;
   }

   PrintFormat("[INFO] balance 再構成 最終値 = %.2f （口座の現残高と照合して）", balance);
}

//+==================================================================+
//| FindPos : position_id → g_pos index（後ろから線形探索）          |
//|   IN の直後に OUT が来ることが多いので後方から探すと速い          |
//+==================================================================+
int FindPos(long pid)
{
   for(int i = ArraySize(g_pos) - 1; i >= 0; i--)
      if(g_pos[i].position_id == pid) return i;
   return -1;
}

//+==================================================================+
//| EnrichAndWrite                                                   |
//|   1ポジションに環境スナップショット + MFE/MAE を付けて書き出す。 |
//+==================================================================+
void EnrichAndWrite(int fout, const PosAgg &p)
{
   AccountRow row;
   bool has_exit = (p.exit_server > 0);

   //--- 基本 ---
   row.position_id = p.position_id;
   row.symbol      = p.symbol;
   row.direction   = p.direction;
   row.volume      = p.vol_in;
   row.entries     = p.entries;
   row.exits       = p.exits;
   row.entry_jst   = FormatJstBarTime(p.entry_server);
   row.exit_jst    = has_exit ? FormatJstBarTime(p.exit_server) : "";
   row.duration_h  = has_exit ? (double)(p.exit_server - p.entry_server) / 3600.0 : 0;

   //--- 価格・SL/TP設計 ---
   row.entry_price = p.entry_price;
   row.exit_price  = has_exit ? p.exit_price : 0;
   row.sl_price    = p.sl_price;
   row.tp_price    = p.tp_price;
   row.sl_dist     = (p.sl_price > 0) ? MathAbs(p.entry_price - p.sl_price) : 0;
   row.tp_dist     = (p.tp_price > 0) ? MathAbs(p.tp_price - p.entry_price) : 0;
   row.rr_planned  = (row.sl_dist > 0 && row.tp_dist > 0) ? row.tp_dist / row.sl_dist : 0;

   //--- 損益 ---
   row.profit      = p.profit;
   row.swap        = p.swap;
   row.commission  = p.commission;
   row.net_profit  = p.profit + p.swap + p.commission;

   //--- 資金・リスク ---
   row.balance_at_entry = p.balance_at_entry;
   row.balance_after    = p.balance_after;
   double csize = SymbolInfoDouble(p.symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   row.risk_usd = (row.sl_dist > 0 && csize > 0) ? row.sl_dist * p.vol_in * csize : -1;
   row.risk_pct = (row.risk_usd > 0 && p.balance_at_entry > 0)
                  ? row.risk_usd / p.balance_at_entry * 100.0 : -1;
   row.lot_per_1k = (p.balance_at_entry > 0) ? p.vol_in / (p.balance_at_entry / 1000.0) : -1;
   row.result_r   = (row.risk_usd > 0) ? row.net_profit / row.risk_usd : 0;

   //--- 発注メタ ---
   row.magic   = p.magic;
   row.comment = p.comment;

   //--- 環境スナップショット ---
   row.env_ok = EnrichEnvironment(p, row);
   if(!row.env_ok) g_rows_env_fail++;

   //--- SL/TP の ATR 換算（環境が取れた時のみ）---
   row.sl_dist_atr = (row.env_ok && row.h1_atr16 > 0 && row.sl_dist > 0)
                     ? row.sl_dist / row.h1_atr16 : 0;
   row.tp_dist_atr = (row.env_ok && row.h1_atr16 > 0 && row.tp_dist > 0)
                     ? row.tp_dist / row.h1_atr16 : 0;

   //--- 48h H1 MFE/MAE（現行と同じ物差し: エントリーバーの次から48本）---
   row.h1_ok = false;
   row.h1_mfe_usd = 0; row.h1_mae_usd = 0;
   row.h1_mfe_idx = -1; row.h1_mae_idx = -1; row.h1_bars_traced = 0;
   int sh_h1_bar = iBarShift(p.symbol, PERIOD_H1, p.entry_server, false);
   if(sh_h1_bar >= 0)
      row.h1_ok = TraceMaeMfe48(p.symbol, sh_h1_bar, H1_Trace_Bars_48h,
                                p.entry_price, p.direction,
                                row.h1_mfe_usd, row.h1_mae_usd,
                                row.h1_mfe_idx, row.h1_mae_idx, row.h1_bars_traced);

   //--- in-trade MFE/MAE（保有期間中 / M5→H1 フォールバック）---
   row.it_ok = false; row.it_tf = "NA";
   row.it_mfe_usd = 0; row.it_mae_usd = 0; row.it_bars = 0;
   if(has_exit)
   {
      if(Intrade_Use_M5 &&
         TraceIntrade(p.symbol, PERIOD_M5, p.entry_server, p.exit_server,
                      p.entry_price, p.direction,
                      row.it_mfe_usd, row.it_mae_usd, row.it_bars))
      {
         row.it_ok = true; row.it_tf = "M5";
      }
      else if(TraceIntrade(p.symbol, PERIOD_H1, p.entry_server, p.exit_server,
                           p.entry_price, p.direction,
                           row.it_mfe_usd, row.it_mae_usd, row.it_bars))
      {
         row.it_ok = true; row.it_tf = "H1";
      }
   }

   WriteRow(fout, row);
   g_rows_written++;
}

//+==================================================================+
//| EnrichEnvironment                                                |
//|   Trade_Snapshot_Builder v1.32 と同じ物差しで                    |
//|   H1/H4/D1 スナップショットを row に詰める。                     |
//|   取得 shift = エントリー時刻が属するバー + 1（直前確定バー）    |
//+==================================================================+
bool EnrichEnvironment(const PosAgg &p, AccountRow &row)
{
   //--- 初期化（env 取得失敗時は空欄出力するが、構造体はゼロ埋め）---
   row.h1_atr16 = 0; row.h1_atr32 = 0; row.h1_ratio = 0;
   row.h1_atr_median = 0; row.h1_atr_ratio_median = 0;
   row.h1_atr_zone = "NA"; row.h1_adx32 = 0; row.h1_dip = 0; row.h1_din = 0;
   row.h1_pattern = "NA";
   row.h4_atr8 = 0; row.h4_atr46 = 0; row.h4_ratio = 0; row.h4_diff = 0;
   row.h4_adx46 = 0; row.h4_dip = 0; row.h4_din = 0;
   row.h4_cross_bars = -1; row.h4_cross_dir = "NA"; row.h4_phase_auto = "NA";
   row.d1_atr22 = 0; row.d1_atr42 = 0; row.d1_ratio = 0;
   row.d1_adx22 = 0; row.d1_dip = 0; row.d1_din = 0;
   row.d1_cross_bars = -1; row.d1_phase = "NA";

   int hi = GetSymHandles(p.symbol);
   if(hi < 0) return false;

   int sh_h1_bar = iBarShift(p.symbol, PERIOD_H1, p.entry_server, false);
   int sh_h4_bar = iBarShift(p.symbol, PERIOD_H4, p.entry_server, false);
   int sh_d1_bar = iBarShift(p.symbol, PERIOD_D1, p.entry_server, false);
   if(sh_h1_bar < 0 || sh_h4_bar < 0 || sh_d1_bar < 0)
   {
      PrintFormat("[WARN] iBarShift fail pos=%I64d (%s %s) h1=%d h4=%d d1=%d "
                  "→ 過去チャートの履歴DL不足の可能性",
                  p.position_id, p.symbol,
                  TimeToString(p.entry_server, TIME_DATE|TIME_MINUTES),
                  sh_h1_bar, sh_h4_bar, sh_d1_bar);
      return false;
   }

   //--- 直前確定バー（v1.32 の未来情報混入対策と同じ）---
   int sh_h1 = sh_h1_bar + 1;
   int sh_h4 = sh_h4_bar + 1;
   int sh_d1 = sh_d1_bar + 1;

   //--- H1 ---
   row.h1_atr16 = GetBufValue(g_handles[hi].hATR_S_H1, 0, sh_h1);
   row.h1_atr32 = GetBufValue(g_handles[hi].hATR_L_H1, 0, sh_h1);
   row.h1_adx32 = GetBufValue(g_handles[hi].hADX_H1,   0, sh_h1);
   row.h1_dip   = GetBufValue(g_handles[hi].hADX_H1,   1, sh_h1);
   row.h1_din   = GetBufValue(g_handles[hi].hADX_H1,   2, sh_h1);
   row.h1_ratio = (row.h1_atr32 > 0) ? row.h1_atr16 / row.h1_atr32 : 0;
   if(row.h1_atr16 <= 0) return false;

   int median_bars = H1_ATR_Median_Weeks * 5 * 24;
   row.h1_atr_median = CalcAtrMedian(g_handles[hi].hATR_S_H1, sh_h1, median_bars);
   row.h1_atr_ratio_median = (row.h1_atr_median > 0) ? row.h1_atr16 / row.h1_atr_median : 0;
   row.h1_atr_zone = ClassifyAtrZone(row.h1_atr_ratio_median);
   row.h1_pattern  = ComputeH1Pattern(g_handles[hi].hATR_S_H1, sh_h1);

   //--- H4 ---
   row.h4_atr8  = GetBufValue(g_handles[hi].hATR_S_H4, 0, sh_h4);
   row.h4_atr46 = GetBufValue(g_handles[hi].hATR_L_H4, 0, sh_h4);
   row.h4_adx46 = GetBufValue(g_handles[hi].hADX_H4,   0, sh_h4);
   row.h4_dip   = GetBufValue(g_handles[hi].hADX_H4,   1, sh_h4);
   row.h4_din   = GetBufValue(g_handles[hi].hADX_H4,   2, sh_h4);
   row.h4_ratio = (row.h4_atr46 > 0) ? row.h4_atr8 / row.h4_atr46 : 0;
   row.h4_diff  = row.h4_atr8 - row.h4_atr46;

   int h4_cd = 0;
   row.h4_cross_bars = FindCrossFromHandles(g_handles[hi].hATR_S_H4, g_handles[hi].hATR_L_H4,
                                            sh_h4, H4_Cross_LookBack, h4_cd);
   row.h4_cross_dir  = CrossDirLabel(h4_cd);
   row.h4_phase_auto = ComputeH4PhaseAuto(row.h4_ratio, row.h4_cross_dir, row.h4_diff);

   //--- D1 ---
   row.d1_atr22 = GetBufValue(g_handles[hi].hATR_S_D1, 0, sh_d1);
   row.d1_atr42 = GetBufValue(g_handles[hi].hATR_L_D1, 0, sh_d1);
   row.d1_adx22 = GetBufValue(g_handles[hi].hADX_D1,   0, sh_d1);
   row.d1_dip   = GetBufValue(g_handles[hi].hADX_D1,   1, sh_d1);
   row.d1_din   = GetBufValue(g_handles[hi].hADX_D1,   2, sh_d1);
   row.d1_ratio = (row.d1_atr42 > 0) ? row.d1_atr22 / row.d1_atr42 : 0;

   int d1_cd = 0;
   row.d1_cross_bars = FindCrossFromHandles(g_handles[hi].hATR_S_D1, g_handles[hi].hATR_L_D1,
                                            sh_d1, D1_Cross_LookBack, d1_cd);
   row.d1_phase = CrossDirLabel(d1_cd);

   return true;
}

//+==================================================================+
//| GetSymHandles : シンボル別ハンドル（キャッシュ）                  |
//+==================================================================+
int GetSymHandles(const string sym)
{
   for(int i = 0; i < ArraySize(g_handles); i++)
      if(g_handles[i].sym == sym) return g_handles[i].ok ? i : -1;

   //--- 新規生成 ---
   SymbolSelect(sym, true);   // Market Watch に無いと iATR が失敗するため
   int idx = ArraySize(g_handles);
   ArrayResize(g_handles, idx + 1);
   SymHandles h;
   h.sym = sym;
   h.hATR_S_H1 = iATR(sym, PERIOD_H1, H1_ATR_Short);
   h.hATR_L_H1 = iATR(sym, PERIOD_H1, H1_ATR_Long);
   h.hADX_H1   = iADX(sym, PERIOD_H1, H1_ADX_Period);
   h.hATR_S_H4 = iATR(sym, PERIOD_H4, H4_ATR_Short);
   h.hATR_L_H4 = iATR(sym, PERIOD_H4, H4_ATR_Long);
   h.hADX_H4   = iADX(sym, PERIOD_H4, H4_ADX_Period);
   h.hATR_S_D1 = iATR(sym, PERIOD_D1, D1_ATR_Short);
   h.hATR_L_D1 = iATR(sym, PERIOD_D1, D1_ATR_Long);
   h.hADX_D1   = iADX(sym, PERIOD_D1, D1_ADX_Period);
   h.ok = (h.hATR_S_H1 != INVALID_HANDLE && h.hATR_L_H1 != INVALID_HANDLE &&
           h.hADX_H1   != INVALID_HANDLE && h.hATR_S_H4 != INVALID_HANDLE &&
           h.hATR_L_H4 != INVALID_HANDLE && h.hADX_H4   != INVALID_HANDLE &&
           h.hATR_S_D1 != INVALID_HANDLE && h.hATR_L_D1 != INVALID_HANDLE &&
           h.hADX_D1   != INVALID_HANDLE);
   g_handles[idx] = h;

   if(!h.ok)
   {
      PrintFormat("[ERR] %s の指標ハンドル生成失敗 err=%d", sym, GetLastError());
      return -1;
   }

   //--- 計算完了待ち（初回のみ）---
   int tries = 0;
   while(BarsCalculated(h.hADX_H1) < 0 && tries < 50) { Sleep(100); tries++; }
   Sleep(500);
   if(Verbose) PrintFormat("[INFO] handles ready: %s (wait=%d)", sym, tries);
   return idx;
}

void ReleaseAllHandles()
{
   for(int i = 0; i < ArraySize(g_handles); i++)
   {
      if(g_handles[i].hATR_S_H1 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_S_H1);
      if(g_handles[i].hATR_L_H1 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_L_H1);
      if(g_handles[i].hADX_H1   != INVALID_HANDLE) IndicatorRelease(g_handles[i].hADX_H1);
      if(g_handles[i].hATR_S_H4 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_S_H4);
      if(g_handles[i].hATR_L_H4 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_L_H4);
      if(g_handles[i].hADX_H4   != INVALID_HANDLE) IndicatorRelease(g_handles[i].hADX_H4);
      if(g_handles[i].hATR_S_D1 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_S_D1);
      if(g_handles[i].hATR_L_D1 != INVALID_HANDLE) IndicatorRelease(g_handles[i].hATR_L_D1);
      if(g_handles[i].hADX_D1   != INVALID_HANDLE) IndicatorRelease(g_handles[i].hADX_D1);
   }
}

//+==================================================================+
//| TraceMaeMfe48                                                    |
//|   Trade_Snapshot_Builder の TraceMaeMfe_Segmented から           |
//|   48h 単一セグメントへ簡約（走査範囲・定義は完全同一）。          |
//|   エントリーバーの次のバーから trace_n 本を走査する。            |
//+==================================================================+
bool TraceMaeMfe48(const string sym, int entry_shift, int trace_n,
                   double entry_price, const string &direction,
                   double &mfe, double &mae,
                   int &mfe_idx, int &mae_idx, int &bars_traced)
{
   mfe = 0; mae = 0; mfe_idx = -1; mae_idx = -1; bars_traced = 0;

   bool is_buy = (direction == "BUY");
   int start_shift = entry_shift - 1;
   if(start_shift < 0) return false;

   int desired_end = entry_shift - trace_n;
   int end_shift   = (desired_end < 0) ? 0 : desired_end;
   int n_bars      = start_shift - end_shift + 1;
   if(n_bars <= 0) return false;

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(sym, PERIOD_H1, end_shift, n_bars, highs) <= 0) return false;
   if(CopyLow (sym, PERIOD_H1, end_shift, n_bars, lows)  <= 0) return false;

   double best_favor = -DBL_MAX, worst_adverse = -DBL_MAX;
   int    best_k = -1, worst_k = -1;
   for(int k = 0; k < n_bars; k++)
   {
      if(highs[k] <= 0 || lows[k] <= 0) continue;
      double adverse = is_buy ? entry_price - lows[k]  : highs[k] - entry_price;
      double favor   = is_buy ? highs[k] - entry_price : entry_price - lows[k];
      if(favor   > best_favor)    { best_favor = favor;      best_k  = k; }
      if(adverse > worst_adverse) { worst_adverse = adverse; worst_k = k; }
   }
   if(best_k  >= 0) { mfe = MathMax(0.0, best_favor);    mfe_idx = n_bars - best_k; }
   if(worst_k >= 0) { mae = MathMax(0.0, worst_adverse); mae_idx = n_bars - worst_k; }
   bars_traced = n_bars;
   return true;
}

//+==================================================================+
//| TraceIntrade                                                     |
//|   entry_server〜exit_server のバー範囲で MFE/MAE を計算。        |
//|   注意: エントリーバー自身を含む（バー内のエントリー前の動きが   |
//|   混入し得る。M5 なら汚染は最大5分で軽微 → SPEC に明記）。       |
//+==================================================================+
bool TraceIntrade(const string sym, ENUM_TIMEFRAMES tf,
                  datetime t_entry, datetime t_exit,
                  double entry_price, const string &direction,
                  double &mfe, double &mae, int &bars)
{
   mfe = 0; mae = 0; bars = 0;
   if(t_exit < t_entry) return false;

   bool is_buy = (direction == "BUY");
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   int nh = CopyHigh(sym, tf, t_entry, t_exit, highs);
   int nl = CopyLow (sym, tf, t_entry, t_exit, lows);
   if(nh <= 0 || nl <= 0) return false;
   int n = MathMin(nh, nl);

   double best_favor = -DBL_MAX, worst_adverse = -DBL_MAX;
   for(int k = 0; k < n; k++)
   {
      if(highs[k] <= 0 || lows[k] <= 0) continue;
      double adverse = is_buy ? entry_price - lows[k]  : highs[k] - entry_price;
      double favor   = is_buy ? highs[k] - entry_price : entry_price - lows[k];
      if(favor   > best_favor)    best_favor    = favor;
      if(adverse > worst_adverse) worst_adverse = adverse;
   }
   if(best_favor    > -DBL_MAX) mfe = MathMax(0.0, best_favor);
   if(worst_adverse > -DBL_MAX) mae = MathMax(0.0, worst_adverse);
   bars = n;
   return true;
}

//+==================================================================+
//| 時刻変換（Trade_Snapshot_Builder と同一ロジック）                |
//+==================================================================+
datetime JstToServer(datetime jst)
{
   datetime utc = jst - (datetime)(JST_Offset_Hours * 3600);
   long offset_sec;
   if(Use_Auto_Server_Offset)
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   else
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   return utc + (datetime)offset_sec;
}

datetime ServerToJst(datetime server_time)
{
   long offset_sec;
   if(Use_Auto_Server_Offset)
      offset_sec = (long)(TimeTradeServer() - TimeGMT());
   else
      offset_sec = (long)(Manual_Server_Offset_Hours * 3600);
   datetime utc = server_time - (datetime)offset_sec;
   return utc + (datetime)(JST_Offset_Hours * 3600);
}

string FormatJstBarTime(datetime server_time)
{
   if(server_time == 0) return "";
   datetime jst = ServerToJst(server_time);
   string s = TimeToString(jst, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "-");
   return s;
}

//+==================================================================+
//| 指標ユーティリティ（Trade_Snapshot_Builder と同一ロジック）      |
//+==================================================================+
double GetBufValue(int handle, int buf, int shift)
{
   if(handle == INVALID_HANDLE) return 0;
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buf, shift, 1, tmp) <= 0) return 0;
   return tmp[0];
}

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

string ClassifyAtrZone(double ratio)
{
   if(ratio <= 0) return "NA";
   if(ratio < ATR_Zone_Low_Ratio)  return "LOW";
   if(ratio > ATR_Zone_High_Ratio) return "HIGH";
   return "NORMAL";
}

int FindCrossFromHandles(int hS, int hL, int shift, int max_look, int &dir_out)
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

string ComputeH1Pattern(int hATR, int shift)
{
   int need = ATR_Vel_Bars * 2 + 2;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hATR, 0, shift, need, arr) <= 0) return "NA";
   if(ArraySize(arr) < need) return "NA";
   if(arr[0] <= 0 || arr[ATR_Vel_Bars] <= 0 || arr[ATR_Vel_Bars*2] <= 0)
      return "NA";

   double vel3 = (arr[0] - arr[ATR_Vel_Bars]) / arr[ATR_Vel_Bars] * 100.0;
   double vel3_prev = (arr[ATR_Vel_Bars] - arr[ATR_Vel_Bars*2]) / arr[ATR_Vel_Bars*2] * 100.0;
   double accel = vel3 - vel3_prev;

   if(MathAbs(vel3) < ATR_Flat_Thresh)     return "FLAT";
   if(vel3 > ATR_Expand_Thresh && accel>0) return "EXPANDING";
   if(vel3 > 0 && accel > 0)               return "RISING_ACCEL";
   if(vel3 > 0 && accel <= 0)              return "RISING_DECEL";
   if(vel3 < 0 && accel < 0)               return "CONTRACTING";
   if(vel3 < 0 && accel >= 0)              return "CONTRACTING_SLOW";
   return "FLAT";
}

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
//| CSV 出力                                                          |
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

string SanitizeCsv(string s)
{
   StringReplace(s, ",", ";");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
}

//+==================================================================+
//| WriteHeaderUtf8 : 69列                                            |
//+==================================================================+
void WriteHeaderUtf8(int fh)
{
   string line =
      // [1-9] 基本
      "position_id,symbol,direction,volume,entries,exits,"
      "entry_jst,exit_jst,duration_h,"
      // [10-18] 価格・SL/TP設計
      "entry_price,exit_price,sl_price,tp_price,"
      "sl_dist,tp_dist,rr_planned,sl_dist_atr,tp_dist_atr,"
      // [19-22] 損益
      "profit,swap,commission,net_profit,"
      // [23-28] 資金・リスク
      "balance_at_entry,balance_after,risk_usd,risk_pct,lot_per_1k,result_r,"
      // [29-30] 発注メタ
      "magic,entry_comment,"
      // [31-40] H1 スナップショット（Trade_Snapshot_Builder 互換列名）
      "h1_atr16,h1_atr32,h1_atr_ratio,h1_atr_median,h1_atr_ratio_median,h1_atr_zone,"
      "h1_adx32,h1_di_plus,h1_di_minus,h1_pattern,"
      // [41-50] H4 スナップショット
      "h4_atr8,h4_atr46,h4_atr_ratio,h4_atr_diff,"
      "h4_adx46,h4_di_plus,h4_di_minus,"
      "h4_cross_bars,h4_cross_dir,h4_phase_auto,"
      // [51-58] D1 スナップショット
      "d1_atr22,d1_atr42,d1_atr_ratio,"
      "d1_adx22,d1_di_plus,d1_di_minus,"
      "d1_cross_bars,d1_phase,"
      // [59-64] H1 48h MAE/MFE
      "h1_trace_ok,"
      "h1_mfe_usd_48h,h1_mfe_bar_idx_48h,h1_mae_usd_48h,h1_mae_bar_idx_48h,h1_bars_traced_48h,"
      // [65-69] in-trade MFE/MAE
      "intrade_trace_ok,intrade_tf,intrade_mfe_usd,intrade_mae_usd,intrade_bars";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| WriteRow : 69列                                                   |
//+==================================================================+
void WriteRow(int fh, const AccountRow &row)
{
   string line = "";
   //--- [1-9] 基本 ---
   line += IntegerToString(row.position_id) + ",";
   line += row.symbol + ",";
   line += row.direction + ",";
   line += DoubleToString(row.volume, 2) + ",";
   line += IntegerToString(row.entries) + ",";
   line += IntegerToString(row.exits) + ",";
   line += row.entry_jst + ",";
   line += row.exit_jst + ",";
   line += DoubleToString(row.duration_h, 2) + ",";
   //--- [10-18] 価格・SL/TP設計 ---
   line += DoubleToString(row.entry_price, 3) + ",";
   line += (row.exit_price > 0 ? DoubleToString(row.exit_price, 3) : "") + ",";
   line += (row.sl_price > 0 ? DoubleToString(row.sl_price, 3) : "") + ",";
   line += (row.tp_price > 0 ? DoubleToString(row.tp_price, 3) : "") + ",";
   line += (row.sl_dist > 0 ? DoubleToString(row.sl_dist, 3) : "") + ",";
   line += (row.tp_dist > 0 ? DoubleToString(row.tp_dist, 3) : "") + ",";
   line += (row.rr_planned > 0 ? DoubleToString(row.rr_planned, 3) : "") + ",";
   line += (row.sl_dist_atr > 0 ? DoubleToString(row.sl_dist_atr, 3) : "") + ",";
   line += (row.tp_dist_atr > 0 ? DoubleToString(row.tp_dist_atr, 3) : "") + ",";
   //--- [19-22] 損益 ---
   line += DoubleToString(row.profit, 2) + ",";
   line += DoubleToString(row.swap, 2) + ",";
   line += DoubleToString(row.commission, 2) + ",";
   line += DoubleToString(row.net_profit, 2) + ",";
   //--- [23-28] 資金・リスク ---
   line += DoubleToString(row.balance_at_entry, 2) + ",";
   line += DoubleToString(row.balance_after, 2) + ",";
   line += (row.risk_usd > 0 ? DoubleToString(row.risk_usd, 2) : "") + ",";
   line += (row.risk_pct > 0 ? DoubleToString(row.risk_pct, 3) : "") + ",";
   line += (row.lot_per_1k >= 0 ? DoubleToString(row.lot_per_1k, 4) : "") + ",";
   line += (row.risk_usd > 0 ? DoubleToString(row.result_r, 3) : "") + ",";
   //--- [29-30] 発注メタ ---
   line += IntegerToString(row.magic) + ",";
   line += row.comment + ",";
   //--- [31-40] H1 スナップショット ---
   if(row.env_ok)
   {
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
      //--- [41-50] H4 ---
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
      //--- [51-58] D1 ---
      line += DoubleToString(row.d1_atr22, 4) + ",";
      line += DoubleToString(row.d1_atr42, 4) + ",";
      line += DoubleToString(row.d1_ratio, 4) + ",";
      line += DoubleToString(row.d1_adx22, 2) + ",";
      line += DoubleToString(row.d1_dip, 2) + ",";
      line += DoubleToString(row.d1_din, 2) + ",";
      line += IntegerToString(row.d1_cross_bars) + ",";
      line += row.d1_phase + ",";
   }
   else
   {
      line += ",,,,,,,,,,";   // H1 10列
      line += ",,,,,,,,,,";   // H4 10列
      line += ",,,,,,,,";     // D1 8列
   }
   //--- [59-64] H1 48h MAE/MFE ---
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
   //--- [65-69] in-trade MFE/MAE ---
   line += (row.it_ok ? "1" : "0") + ",";
   line += row.it_tf + ",";
   if(row.it_ok)
   {
      line += DoubleToString(row.it_mfe_usd, 3) + ",";
      line += DoubleToString(row.it_mae_usd, 3) + ",";
      line += IntegerToString(row.it_bars);
   }
   else
   {
      line += ",,";
   }

   WriteUtf8String(fh, line + "\n");
}
//+------------------------------------------------------------------+
