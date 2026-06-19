//+------------------------------------------------------------------+
//|  Signal_Fire_Logger_EA_v1.mq5                                   |
//|                                                                  |
//|  系統C（シグナル発火ログ）専用EA。                                |
//|  Script版 Signal_Fire_Logger_v1.mq5（OnStart型）を常駐EAに移植し、|
//|  VPS上のMT5でXAUUSD H1チャート1枚から signal_fires.csv を         |
//|  24h無人生成する。OnTimerで BT_StartTime〜直近確定足をフル再生成。 |
//|                                                                  |
//|  移植元（ロジックは1ミリも変えずコピペ移植 — 触らず温存）:        |
//|    - Signal_Fire_Logger_v1.mq5 (OnStart / 65列 /                 |
//|        iATR・iADX・iMA 10ハンドル / series一括コピー方式)         |
//|        → signal_fires.csv (UTF-8 BOM)                            |
//|                                                                  |
//|  移植方針（コー_指示書_系統C_SignalFire_EA化_v1.md）:             |
//|    - OnStart → OnInit / OnTimer / OnDeinit / RunFullScan へ分解   |
//|    - Sleep(3000) は移植せず HandlesReady()（10ハンドル           |
//|      BarsCalculated>0 ゲート）で代替                              |
//|    - ハンドルは Fire_InitHandles() でグローバル化（hFire_ 接頭辞）|
//|      し常駐維持。解放は OnDeinit の Fire_ReleaseHandles() のみ。  |
//|    - 旧 OnStart の FATAL return は RunFullScan 内では             |
//|      「その回スキップ」（EAは生かして次回 OnTimer で再試行）      |
//|    - 単独移植のため接頭辞リネーム不要（Logger中身そのまま）       |
//|    - 走査期間は BT_StartTime/BT_EndTime 方式を維持               |
//|                                                                  |
//|  研究目的（固定・変更禁止 / 移植元 L7-13 を継承）:                |
//|    v4 シグナルの発火を過去再現し、あろさんがシグナルへの理解を    |
//|    深めるための可視化データを作る。                               |
//|    - v4 本体は一切変更しない（読むだけ）                          |
//|    - シグナルの改良・最適化は目的に含まない                       |
//|    - 研究ルール準拠: シグナル評価文脈の MFE/MAE は OK。           |
//|      結果フィッティング禁止。                                     |
//|                                                                  |
//|  ロジック源泉（絶対原則）:                                        |
//|    発火ロジック・フィルター条件は signals/ATR_WidthSignal_v4.mq5 |
//|    から忠実移植（移植元 Logger 経由）。本EAも v4 を import/参照   |
//|    せず、Logger に移植済みの定数・ロジックをそのまま使う。        |
//|    周期・閾値は v4 の input デフォルト値を「定数」として持つ      |
//|    （input 化禁止。input は走査期間・EA制御・出力ファイルのみ）。 |
//|                                                                  |
//|  v4 との対応（shift 規約）: 移植元 L21-27 を継承。               |
//|    全指標を series 配列で一括コピーし、v4 と同一インデックス演算  |
//|    で判定（shift 変換を挟まない）。走査は確定バーのみ (i >= 1)。  |
//|                                                                  |
//|  出力: MQL5/Files/signal_fires.csv (UTF-8 BOM / 全量上書き)      |
//|  JST/DST 変換: 移植元のまま（TimeTradeServer-TimeGMT 自動算出。  |
//|    過去日の DST 跨ぎは time_server 列が厳密値）                   |
//|                                                                  |
//|  指示書: data/vps/コー_指示書_系統C_SignalFire_EA化_v1.md         |
//|  作成日: 2026-06-19                                              |
//|  作成: コー                                                       |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "1.00"
#property strict

//+-----[ 入力パラメータ ]------------------------------------------+
input group "=== 走査期間（移植元から維持）==="
input datetime BT_StartTime = D'2025.03.01 00:00';  // 走査開始（サーバー時刻）
input datetime BT_EndTime   = 0;                    // 走査終了（0 = 実行時点）

input group "=== EA制御（新規）==="
input int      Update_Interval_Min = 60;            // ready後の再生成周期（分）
input int      First_Run_Delay_Sec = 15;            // 初回タイマー（ready待ちの短間隔, 秒）

input group "=== 出力 ==="
input string   Output_File  = "signal_fires.csv";   // 出力CSV（回帰検証で別名可）

input group "=== デバッグ ==="
input bool     Verbose      = true;

//+-----[ 定数: v4 input デフォルト値の固定（input 化禁止）]---------+
//   出典: signals/ATR_WidthSignal_v4.mq5 L82-163 の input デフォルト
const string ALLOWED_SYMBOL     = "XAUUSD";

// --- H1 (v4 L83-87) ---
const int    H1_ATR_SHORT       = 16;
const int    H1_ATR_LONG        = 32;
const int    H1_ADX_PERIOD      = 32;
const int    H1_MA_PERIOD       = 32;
const int    ATR_MEDIAN_WEEKS   = 8;

// --- H4 (v4 L91-94) ---
const int    H4_ATR_SHORT       = 8;
const int    H4_ATR_LONG        = 46;
const int    H4_ADX_PERIOD      = 46;
// H4_MA_Period=46 は v4 で取得のみ・判定未使用のため Logger では持たない

// --- D1 (v4 L98-100) ---
const int    D1_ATR_SHORT       = 22;
const int    D1_ATR_LONG        = 42;
const int    D1_ADX_PERIOD      = 22;

// --- ATRゾーン閾値 (v4 L104-105) ---
const double ATR_LOW_RATIO      = 0.70;
const double ATR_HIGH_RATIO     = 1.40;

// --- ATRペア閾値 (v4 L109-110) ---
const double ATR_PAIR_EXPAND    = 1.05;
const double ATR_PAIR_CONTRACT  = 0.95;

// --- パターン共通 (v4 L114-116) ---
const int    ATR_VEL_BARS       = 3;
const double ATR_EXPAND_THRESH  = 10.0;
const double ATR_FLAT_THRESH    = 3.0;

// --- PatA (v4 L120-121) ---
const double PATA_VEL3_MIN      = 8.0;
const double PATA_VEL3_MAX      = 15.0;

// --- PatB (v4 L125) ---
const double PATB_VEL3_MIN      = 5.0;

// --- PatD (v4 L129-131) ---
const int    PATD_CROSSBARS_MAX = 3;
const double PATD_H1_ADX_MIN    = 18.0;
const double PATD_DI_STRENGTH_MIN = 5.0;

// --- PatE (v4 L135-138) ---
const double PATE_PAIR_MIN      = 0.85;
const double PATE_PAIR_MAX      = 0.95;
const double PATE_MA_DIST_MAX   = 0.5;
const int    PATE_LOOKBACK      = 3;

// --- 共通NG (v4 L142-143) ---
const double NG_H1_ADX_MAX      = 40.0;
const double NG_ATR_RATIO_MAX   = 2.00;

// --- フィルター閾値 (v4 L159, L162) ---
const double FILTER_F7_SPREAD_THRESH = 1.0;
const double FILTER_F9_WEAK_ADX_THRESH = 20.0;

// --- クロス検索 lookback (v4 OnCalculate 内の即値) ---
const int    H4_CROSS_LOOKBACK  = 20;   // v4 L668
const int    D1_CROSS_LOOKBACK  = 30;   // v4 L697

// --- MFE/MAE 追跡 ---
const int    TRACE_BARS_48H     = 48;

// --- タイムゾーン（Trade_Snapshot_Builder と同じ規約）---
const int    JST_OFFSET_HOURS   = 9;

//+==================================================================+
//| FireRow 構造体                                                   |
//|   CSV 1行分のフィールド集約。WriteRow の引数を 1つに集約         |
//|   （C4 教訓: MQL5 の関数引数は最大 64 個。構造体で回避）         |
//|   フィールド数 = 出力カラム数 65 と一致                          |
//+==================================================================+
struct FireRow
{
   //--- [1-7] キー / 価格 ---
   int      fire_id;
   string   date_jst;          // YYYY-MM-DD (JST, 発火バー open 基準)
   string   time_jst;          // YYYY-MM-DD HH:MM (JST)
   string   time_server;       // YYYY-MM-DD HH:MM (server)
   string   pattern;           // PatA..PatE
   string   direction;         // BUY / SELL
   double   entry_price;       // 発火バー close
   //--- [8-13] H1 ATR ---
   double   h1_atr16;
   double   h1_atr32;
   double   h1_atr_median;
   double   h1_atr_ratio;      // atr16 / median (v4 の atr_ratio)
   string   atr_zone;          // LOW / NORMAL / HIGH
   double   h1_pair;           // atr16 / atr32
   //--- [14-17] H1 パターン ---
   string   h1_pair_state;     // EXPAND / NEUTRAL / CONTRACT (v4 h1_pair_phase)
   string   h1_pattern;        // RISING_DECEL 等
   double   h1_vel3;
   double   h1_accel;
   //--- [18-22] H1 ADX/DI ---
   double   h1_adx32;
   string   h1_adx_zone;       // LOW / MID / HIGH
   double   h1_di_plus;
   double   h1_di_minus;
   double   h1_di_spread;
   //--- [23-24] H1 MA ---
   double   h1_ma;
   double   h1_ma_dist;        // (close-MA)/ATR32
   //--- [25-28] H4 ATR ---
   double   h4_atr8;
   double   h4_atr46;
   double   h4_pair;
   string   h4_pair_state;
   //--- [29-33] H4 ADX/DI ---
   double   h4_adx46;
   string   h4_adx_zone;
   double   h4_di_plus;
   double   h4_di_minus;
   double   h4_di_spread;
   //--- [34-35] H4 クロス ---
   int      h4_cross_bars;     // H4バー数。-1=lookback内クロスなし
   string   h4_cross_dir;      // UP / DOWN / NONE
   //--- [36-41] D1 ---
   double   d1_atr22;
   double   d1_atr42;
   double   d1_adx22;
   double   d1_di_plus;
   double   d1_di_minus;
   string   d1_di_dir;         // UP / DN
   //--- [42-43] D1 クロス ---
   string   cross_dir;         // BU / PD / NONE (v4 d1_atr_cross_dir)
   int      d1_cross_bars;     // D1バー数。-1=lookback内クロスなし
   //--- [44-53] フィルター F1〜F9 + pass_all ---
   bool     f1;
   bool     f2;
   bool     f3;
   bool     f4;
   bool     f5;
   bool     f6;
   bool     f7;
   bool     f8;
   bool     f9;
   bool     pass_all;
   //--- [54-65] MFE/MAE（発火方向基準）---
   double   mfe_12h;
   double   mae_12h;
   double   mfe_24h;
   double   mae_24h;
   double   mfe_36h;
   double   mae_36h;
   double   mfe_48h;
   double   mae_48h;
   int      mfe_bar_idx_48h;   // 発火後 1..48 本目
   int      mae_bar_idx_48h;
   int      bars_traced;
};

//+==================================================================+
//| グローバル: 指標ハンドル（hFire_ 接頭辞・10本）                   |
//|   移植元 OnStart L253-262 のローカル変数をグローバル化。          |
//+==================================================================+
int hFire_ATR_S_H1 = INVALID_HANDLE, hFire_ATR_L_H1 = INVALID_HANDLE;
int hFire_ADX_H1   = INVALID_HANDLE, hFire_MA_H1    = INVALID_HANDLE;
int hFire_ATR_S_H4 = INVALID_HANDLE, hFire_ATR_L_H4 = INVALID_HANDLE;
int hFire_ADX_H4   = INVALID_HANDLE;
int hFire_ATR_S_D1 = INVALID_HANDLE, hFire_ATR_L_D1 = INVALID_HANDLE;
int hFire_ADX_D1   = INVALID_HANDLE;

//+-----[ 集計カウンタ ]--------------------------------------------+
int g_fire_count   = 0;
int g_pass_count   = 0;
int g_bars_scanned = 0;

//+-----[ EA制御 ]--------------------------------------------------+
bool g_first_run = false;

//+==================================================================+
//| OnInit                                                           |
//+==================================================================+
int OnInit()
{
   Print("==== Signal_Fire_Logger_EA v1.00 OnInit ====");
   PrintFormat("Symbol(chart): %s, Allowed: %s", _Symbol, ALLOWED_SYMBOL);
   PrintFormat("Output: %s", Output_File);
   PrintFormat("Scan: %s -> %s (server time)",
               TimeToString(BT_StartTime, TIME_DATE|TIME_MINUTES),
               (BT_EndTime == 0) ? "now"
                  : TimeToString(BT_EndTime, TIME_DATE|TIME_MINUTES));

   //--- シンボル制約: XAUUSD以外で起動拒否（移植元 L245-250）---
   if(_Symbol != ALLOWED_SYMBOL)
   {
      PrintFormat("[FATAL] チャートシンボル %s ≠ %s. %s チャートで起動してください.",
                  _Symbol, ALLOWED_SYMBOL, ALLOWED_SYMBOL);
      return(INIT_FAILED);
   }

   //--- ハンドル初期化（iATR/iADX/iMA 10本）---
   if(!Fire_InitHandles())
   {
      Print("[FATAL] 指標ハンドル生成失敗。終了。");
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
   //--- 10ハンドルの計算完了まで持ち越し（旧 Sleep(3000) の代替）---
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

   //--- BT_StartTime〜直近確定足をフル再生成・上書き ---
   RunFullScan();
}

//+==================================================================+
//| OnDeinit                                                         |
//+==================================================================+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Fire_ReleaseHandles();
   PrintFormat("==== Signal_Fire_Logger_EA v1.00 OnDeinit (reason=%d) ====", reason);
}

//+==================================================================+
//| Fire_InitHandles                                                 |
//|   移植元 OnStart L253-273 のハンドル生成を切り出し、              |
//|   グローバルハンドルへ生成する。                                  |
//|   （v4 L262-274 と同一構成。H4 MA は判定未使用のため省略）        |
//+==================================================================+
bool Fire_InitHandles()
{
   string sym = _Symbol;
   hFire_ATR_S_H1 = iATR(sym, PERIOD_H1, H1_ATR_SHORT);
   hFire_ATR_L_H1 = iATR(sym, PERIOD_H1, H1_ATR_LONG);
   hFire_ADX_H1   = iADX(sym, PERIOD_H1, H1_ADX_PERIOD);
   hFire_MA_H1    = iMA (sym, PERIOD_H1, H1_MA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   hFire_ATR_S_H4 = iATR(sym, PERIOD_H4, H4_ATR_SHORT);
   hFire_ATR_L_H4 = iATR(sym, PERIOD_H4, H4_ATR_LONG);
   hFire_ADX_H4   = iADX(sym, PERIOD_H4, H4_ADX_PERIOD);
   hFire_ATR_S_D1 = iATR(sym, PERIOD_D1, D1_ATR_SHORT);
   hFire_ATR_L_D1 = iATR(sym, PERIOD_D1, D1_ATR_LONG);
   hFire_ADX_D1   = iADX(sym, PERIOD_D1, D1_ADX_PERIOD);

   if(hFire_ATR_S_H1==INVALID_HANDLE || hFire_ATR_L_H1==INVALID_HANDLE ||
      hFire_ADX_H1==INVALID_HANDLE   || hFire_MA_H1==INVALID_HANDLE   ||
      hFire_ATR_S_H4==INVALID_HANDLE || hFire_ATR_L_H4==INVALID_HANDLE ||
      hFire_ADX_H4==INVALID_HANDLE   ||
      hFire_ATR_S_D1==INVALID_HANDLE || hFire_ATR_L_D1==INVALID_HANDLE ||
      hFire_ADX_D1==INVALID_HANDLE)
   {
      PrintFormat("[ERR] 指標ハンドル生成失敗 err=%d", GetLastError());
      return false;
   }
   return true;
}

//+==================================================================+
//| Fire_ReleaseHandles                                              |
//|   移植元 ReleaseAll (引数10個) をグローバルハンドル直接解放の     |
//|   引数なし関数へ。OnDeinit からのみ呼ぶ（常駐維持）。            |
//+==================================================================+
void Fire_ReleaseHandles()
{
   if(hFire_ATR_S_H1 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_S_H1);
   if(hFire_ATR_L_H1 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_L_H1);
   if(hFire_ADX_H1   != INVALID_HANDLE) IndicatorRelease(hFire_ADX_H1);
   if(hFire_MA_H1    != INVALID_HANDLE) IndicatorRelease(hFire_MA_H1);
   if(hFire_ATR_S_H4 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_S_H4);
   if(hFire_ATR_L_H4 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_L_H4);
   if(hFire_ADX_H4   != INVALID_HANDLE) IndicatorRelease(hFire_ADX_H4);
   if(hFire_ATR_S_D1 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_S_D1);
   if(hFire_ATR_L_D1 != INVALID_HANDLE) IndicatorRelease(hFire_ATR_L_D1);
   if(hFire_ADX_D1   != INVALID_HANDLE) IndicatorRelease(hFire_ADX_D1);
}

//+==================================================================+
//| HandlesReady                                                     |
//|   10ハンドルすべて !=INVALID_HANDLE かつ BarsCalculated>0 で true。|
//|   旧 OnStart の Sleep(3000) ゲートの代替。                        |
//+==================================================================+
bool HandlesReady()
{
   int handles[10];
   handles[0] = hFire_ATR_S_H1; handles[1] = hFire_ATR_L_H1;
   handles[2] = hFire_ADX_H1;   handles[3] = hFire_MA_H1;
   handles[4] = hFire_ATR_S_H4; handles[5] = hFire_ATR_L_H4;
   handles[6] = hFire_ADX_H4;
   handles[7] = hFire_ATR_S_D1; handles[8] = hFire_ATR_L_D1;
   handles[9] = hFire_ADX_D1;

   for(int i = 0; i < 10; i++)
   {
      if(handles[i] == INVALID_HANDLE) return false;
      if(BarsCalculated(handles[i]) <= 0) return false;
   }
   return true;
}

//+==================================================================+
//| RunFullScan                                                      |
//|   旧 OnStart 本体（移植元 L276-662 のうち、シンボルチェック・     |
//|   ハンドル生成・Sleep(3000)・末尾 ReleaseAll を除いた全部）。     |
//|   - 冒頭でカウンタを 0 リセット（毎回フル再生成）                 |
//|   - FATAL時の return は「その回スキップ」（EAは次回 OnTimer再試行）|
//|   - ReleaseAll は呼ばない（ハンドル常駐維持、OnDeinitで解放）     |
//+==================================================================+
void RunFullScan()
{
   //--- カウンタ 0 リセット（毎回フル再生成のため）---
   g_fire_count   = 0;
   g_pass_count   = 0;
   g_bars_scanned = 0;

   if(Verbose)
   {
      Print("==== [Fire] signal_fires generate ====");
      PrintFormat("Scan: %s -> %s (server time)",
                  TimeToString(BT_StartTime, TIME_DATE|TIME_MINUTES),
                  (BT_EndTime == 0) ? "now"
                     : TimeToString(BT_EndTime, TIME_DATE|TIME_MINUTES));
   }

   //--- 走査範囲の H1 インデックス決定（series: idx=0 が最新）---
   int start_idx = iBarShift(_Symbol, PERIOD_H1, BT_StartTime, false);
   if(start_idx < 0)
   {
      Print("[FATAL] BT_StartTime のバーが見つからない（履歴不足の可能性）。"
            "この回はスキップ。");
      return;
   }

   //--- コピーサイズ（v4 L495,508 と同じ余裕設計）---
   //    判定に必要な最古参照 = i + median_bars（中央値窓）           ---
   //    その他: i+ATR_VEL_BARS*2（vel/accel）, i+50+1（H1クロス余裕）---
   int median_bars = ATR_MEDIAN_WEEKS * 5 * 24;   // = 960
   int copy_size   = start_idx + 1 + median_bars + ATR_VEL_BARS * 2 + 80;

   //--- H1 一括取得（v4 L510-525 対応）---
   double atr_s_h1[], atr_l_h1[], adx_h1[], dip_h1[], din_h1[], ma_h1[];
   double h1_close[], h1_high[], h1_low[];
   datetime h1_time[];
   ArraySetAsSeries(atr_s_h1, true);  ArraySetAsSeries(atr_l_h1, true);
   ArraySetAsSeries(adx_h1,   true);  ArraySetAsSeries(dip_h1,   true);
   ArraySetAsSeries(din_h1,   true);  ArraySetAsSeries(ma_h1,    true);
   ArraySetAsSeries(h1_close, true);  ArraySetAsSeries(h1_high,  true);
   ArraySetAsSeries(h1_low,   true);  ArraySetAsSeries(h1_time,  true);

   bool copy_ok = true;
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_S_H1, 0, 0, copy_size, atr_s_h1) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_L_H1, 0, 0, copy_size, atr_l_h1) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H1,   0, 0, copy_size, adx_h1)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H1,   1, 0, copy_size, dip_h1)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H1,   2, 0, copy_size, din_h1)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_MA_H1,    0, 0, copy_size, ma_h1)    > 0);
   copy_ok = copy_ok && (CopyClose(_Symbol, PERIOD_H1, 0, copy_size, h1_close) > 0);
   copy_ok = copy_ok && (CopyHigh (_Symbol, PERIOD_H1, 0, copy_size, h1_high)  > 0);
   copy_ok = copy_ok && (CopyLow  (_Symbol, PERIOD_H1, 0, copy_size, h1_low)   > 0);
   copy_ok = copy_ok && (CopyTime (_Symbol, PERIOD_H1, 0, copy_size, h1_time)  > 0);
   if(!copy_ok)
   {
      PrintFormat("[FATAL] H1 データ取得失敗 err=%d (要求 %d 本。チャート設定の"
                  "「最大バー数」を確認)。この回はスキップ。", GetLastError(), copy_size);
      return;
   }
   //--- 実取得本数（最小値を有効サイズとする）---
   int h1_size = ArraySize(atr_s_h1);
   h1_size = MathMin(h1_size, ArraySize(atr_l_h1));
   h1_size = MathMin(h1_size, ArraySize(adx_h1));
   h1_size = MathMin(h1_size, ArraySize(dip_h1));
   h1_size = MathMin(h1_size, ArraySize(din_h1));
   h1_size = MathMin(h1_size, ArraySize(ma_h1));
   h1_size = MathMin(h1_size, ArraySize(h1_close));
   h1_size = MathMin(h1_size, ArraySize(h1_high));
   h1_size = MathMin(h1_size, ArraySize(h1_low));
   h1_size = MathMin(h1_size, ArraySize(h1_time));
   if(h1_size < copy_size)
      PrintFormat("[WARN] H1 実取得 %d 本 < 要求 %d 本。期間前半で中央値計算"
                  "不可のバーはスキップされる（v4 と同挙動）", h1_size, copy_size);

   //--- H4 一括取得（v4 L527-545 対応）---
   int h4_copy_size = copy_size / 4 + 60;
   double atr_s_h4[], atr_l_h4[], adx_h4[], dip_h4[], din_h4[];
   datetime h4_time[];
   ArraySetAsSeries(atr_s_h4, true);  ArraySetAsSeries(atr_l_h4, true);
   ArraySetAsSeries(adx_h4,   true);  ArraySetAsSeries(dip_h4,   true);
   ArraySetAsSeries(din_h4,   true);  ArraySetAsSeries(h4_time,  true);

   copy_ok = true;
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_S_H4, 0, 0, h4_copy_size, atr_s_h4) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_L_H4, 0, 0, h4_copy_size, atr_l_h4) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H4,   0, 0, h4_copy_size, adx_h4)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H4,   1, 0, h4_copy_size, dip_h4)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_H4,   2, 0, h4_copy_size, din_h4)   > 0);
   copy_ok = copy_ok && (CopyTime(_Symbol, PERIOD_H4, 0, h4_copy_size, h4_time) > 0);
   if(!copy_ok)
   {
      PrintFormat("[FATAL] H4 データ取得失敗 err=%d。この回はスキップ。", GetLastError());
      return;
   }
   int h4_size = ArraySize(atr_s_h4);
   h4_size = MathMin(h4_size, ArraySize(atr_l_h4));
   h4_size = MathMin(h4_size, ArraySize(adx_h4));
   h4_size = MathMin(h4_size, ArraySize(dip_h4));
   h4_size = MathMin(h4_size, ArraySize(din_h4));
   h4_size = MathMin(h4_size, ArraySize(h4_time));

   //--- D1 一括取得（v4 L547-563 対応）---
   int d1_copy_size = copy_size / 24 + 90;
   double atr_s_d1[], atr_l_d1[], adx_d1[], dip_d1[], din_d1[];
   datetime d1_time[];
   ArraySetAsSeries(atr_s_d1, true);  ArraySetAsSeries(atr_l_d1, true);
   ArraySetAsSeries(adx_d1,   true);  ArraySetAsSeries(dip_d1,   true);
   ArraySetAsSeries(din_d1,   true);  ArraySetAsSeries(d1_time,  true);

   copy_ok = true;
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_S_D1, 0, 0, d1_copy_size, atr_s_d1) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ATR_L_D1, 0, 0, d1_copy_size, atr_l_d1) > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_D1,   0, 0, d1_copy_size, adx_d1)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_D1,   1, 0, d1_copy_size, dip_d1)   > 0);
   copy_ok = copy_ok && (CopyBuffer(hFire_ADX_D1,   2, 0, d1_copy_size, din_d1)   > 0);
   copy_ok = copy_ok && (CopyTime(_Symbol, PERIOD_D1, 0, d1_copy_size, d1_time) > 0);
   if(!copy_ok)
   {
      PrintFormat("[FATAL] D1 データ取得失敗 err=%d。この回はスキップ。", GetLastError());
      return;
   }
   int d1_size = ArraySize(atr_s_d1);
   d1_size = MathMin(d1_size, ArraySize(atr_l_d1));
   d1_size = MathMin(d1_size, ArraySize(adx_d1));
   d1_size = MathMin(d1_size, ArraySize(dip_d1));
   d1_size = MathMin(d1_size, ArraySize(din_d1));
   d1_size = MathMin(d1_size, ArraySize(d1_time));

   //--- 出力 CSV オープン（UTF-8 BOM / 全量上書き）---
   int fout = FileOpen(Output_File, FILE_WRITE|FILE_BIN, ',');
   if(fout == INVALID_HANDLE)
   {
      PrintFormat("[FATAL] 出力CSV open失敗: %s err=%d。この回はスキップ。",
                  Output_File, GetLastError());
      return;
   }
   WriteUtf8Bom(fout);
   WriteHeaderUtf8(fout);

   //--- メインループ: 古い側 (start_idx) → 新しい側 (i=1) ----------+
   //    i=0 は形成中バーなので走査しない（確定バーのみ）             |
   //    v4 OnCalculate L566-832 のバー判定を i 単位で忠実移植        |
   //+----------------------------------------------------------------+
   int scan_oldest = MathMin(start_idx, h1_size - 1);
   for(int i = scan_oldest; i >= 1; i--)
   {
      datetime h1_t = h1_time[i];
      if(h1_t < BT_StartTime) continue;
      if(BT_EndTime > 0 && h1_t > BT_EndTime) break;
      g_bars_scanned++;

      //--- H1基本値（v4 L575-582）---
      double atr_s = atr_s_h1[i];
      double atr_l = atr_l_h1[i];
      double h1adx = adx_h1[i];
      double h1dip = dip_h1[i];
      double h1din = din_h1[i];
      double ma    = ma_h1[i];
      double price = h1_close[i];
      if(atr_s<=0 || atr_l<=0 || h1adx<=0 || ma<=0) continue;

      //--- 共通NG: 過熱（v4 L585）---
      if(h1adx > NG_H1_ADX_MAX) continue;

      //--- H1 ATR中央値・ratio（v4 L588-594）---
      double atr_med = CalcATRMedian(atr_s_h1, i, median_bars);
      if(atr_med <= 0) continue;
      double atr_ratio = atr_s / atr_med;
      if(atr_ratio > NG_ATR_RATIO_MAX) continue;

      string atr_zone = (atr_ratio < ATR_LOW_RATIO)  ? "LOW"  :
                        (atr_ratio > ATR_HIGH_RATIO) ? "HIGH" : "NORMAL";

      //--- H1 ATRペア（v4 L597-599）---
      double h1_pair = atr_s / atr_l;
      string h1_pair_phase = (h1_pair > ATR_PAIR_EXPAND)   ? "EXPAND"  :
                             (h1_pair < ATR_PAIR_CONTRACT) ? "CONTRACT": "NEUTRAL";

      //--- vel3 & accel（v4 L606-617）---
      double vel3 = 0, accel = 0;
      if(i + ATR_VEL_BARS < h1_size && atr_s_h1[i+ATR_VEL_BARS] > 0)
         vel3 = (atr_s - atr_s_h1[i+ATR_VEL_BARS]) / atr_s_h1[i+ATR_VEL_BARS] * 100.0;

      double vel3_prev = 0;
      if(i + ATR_VEL_BARS*2 < h1_size)
      {
         double ap  = atr_s_h1[i + ATR_VEL_BARS];
         double ap2 = atr_s_h1[i + ATR_VEL_BARS*2];
         if(ap2 > 0) vel3_prev = (ap - ap2) / ap2 * 100.0;
      }
      accel = vel3 - vel3_prev;

      string h1_pat = AtrPattern(vel3, accel);

      //--- 直前N本の CONTRACTING_SLOW 判定: PatE用（v4 L622-635）---
      bool had_contract_slow = false;
      for(int b = 1; b <= PATE_LOOKBACK; b++)
      {
         if(i+b+ATR_VEL_BARS*2 >= h1_size) break;
         double va = atr_s_h1[i+b];
         double va_s = atr_s_h1[i+b+ATR_VEL_BARS];
         if(va_s <= 0) continue;
         double v_b = (va - va_s) / va_s * 100.0;
         double va_s2 = atr_s_h1[i+b+ATR_VEL_BARS*2];
         double v_b_prev = (va_s2 > 0) ? (va_s - va_s2) / va_s2 * 100.0 : 0;
         double a_b = v_b - v_b_prev;
         string pat_b = AtrPattern(v_b, a_b);
         if(pat_b == "CONTRACTING_SLOW") { had_contract_slow = true; break; }
      }

      //--- ADX zone & DI方向（v4 L638-640）---
      string h1_adz = (h1adx < 20) ? "LOW" : (h1adx < 30) ? "MID" : "HIGH";
      double h1_di_spread = h1dip - h1din;
      bool h1_up = (h1dip > h1din);

      //--- MA位置（v4 L643-648）---
      double ma_dist = (price - ma) / atr_l;

      //--- H4 該当バー探索（v4 L651-664）---
      int hi_idx = FindBarIndexAtOrBefore(h4_time, h1_t, h4_size);
      if(hi_idx < 0) continue;

      double h4_as = atr_s_h4[hi_idx];
      double h4_al = atr_l_h4[hi_idx];
      double h4adx = adx_h4[hi_idx];
      double h4dip = dip_h4[hi_idx];
      double h4din = din_h4[hi_idx];
      if(h4_as<=0 || h4_al<=0 || h4adx<=0) continue;

      double h4_pair = h4_as / h4_al;
      string h4_pair_phase = (h4_pair > ATR_PAIR_EXPAND)   ? "EXPAND"  :
                             (h4_pair < ATR_PAIR_CONTRACT) ? "CONTRACT": "NEUTRAL";

      //--- H4 ATRクロス（v4 L667-668）---
      int h4_cross_dir = 0;
      int h4_cross_bars = FindATRCross(atr_s_h4, atr_l_h4, hi_idx,
                                       H4_CROSS_LOOKBACK, h4_cross_dir);

      string h4_adz = (h4adx < 20) ? "LOW" : (h4adx < 30) ? "MID" : "HIGH";
      double h4_di_spread = h4dip - h4din;
      double h4_di_strength = MathAbs(h4_di_spread);
      bool h4_up = (h4dip > h4din);

      //--- D1 該当バー探索（v4 L685-693）---
      int di_idx = FindBarIndexAtOrBefore(d1_time, h1_t, d1_size);
      if(di_idx < 0) continue;

      double d1_as  = atr_s_d1[di_idx];
      double d1_al  = atr_l_d1[di_idx];
      double d1adx  = adx_d1[di_idx];
      double d1dip  = dip_d1[di_idx];
      double d1din  = din_d1[di_idx];
      if(d1_as<=0 || d1_al<=0 || d1adx<=0) continue;

      //--- D1 ATRクロス方向 BU/PD/NONE（v4 L696-700）---
      int d1_cross_dir = 0;
      int d1_cross_bars = FindATRCross(atr_s_d1, atr_l_d1, di_idx,
                                       D1_CROSS_LOOKBACK, d1_cross_dir);
      string d1_atr_cross_dir = (d1_cross_dir > 0) ? "BU" :
                                (d1_cross_dir < 0) ? "PD" : "NONE";
      string di_dir_d1 = (d1dip > d1din) ? "UP" : "DN";

      //--- 環境スナップショット行（共通部分を先に詰める）---
      FireRow env;
      env.fire_id      = 0;  // 発火時に採番
      env.date_jst     = "";
      env.time_jst     = "";
      env.time_server  = "";
      env.pattern      = "";
      env.direction    = "";
      env.entry_price  = price;
      env.h1_atr16     = atr_s;
      env.h1_atr32     = atr_l;
      env.h1_atr_median = atr_med;
      env.h1_atr_ratio = atr_ratio;
      env.atr_zone     = atr_zone;
      env.h1_pair      = h1_pair;
      env.h1_pair_state = h1_pair_phase;
      env.h1_pattern   = h1_pat;
      env.h1_vel3      = vel3;
      env.h1_accel     = accel;
      env.h1_adx32     = h1adx;
      env.h1_adx_zone  = h1_adz;
      env.h1_di_plus   = h1dip;
      env.h1_di_minus  = h1din;
      env.h1_di_spread = h1_di_spread;
      env.h1_ma        = ma;
      env.h1_ma_dist   = ma_dist;
      env.h4_atr8      = h4_as;
      env.h4_atr46     = h4_al;
      env.h4_pair      = h4_pair;
      env.h4_pair_state = h4_pair_phase;
      env.h4_adx46     = h4adx;
      env.h4_adx_zone  = h4_adz;
      env.h4_di_plus   = h4dip;
      env.h4_di_minus  = h4din;
      env.h4_di_spread = h4_di_spread;
      env.h4_cross_bars = h4_cross_bars;
      env.h4_cross_dir = (h4_cross_bars >= 0)
                         ? ((h4_cross_dir > 0) ? "UP" : "DOWN") : "NONE";
      env.d1_atr22     = d1_as;
      env.d1_atr42     = d1_al;
      env.d1_adx22     = d1adx;
      env.d1_di_plus   = d1dip;
      env.d1_di_minus  = d1din;
      env.d1_di_dir    = di_dir_d1;
      env.cross_dir    = d1_atr_cross_dir;
      env.d1_cross_bars = d1_cross_bars;

      //--- 時刻文字列（発火バーの open 時刻。チャート上の矢印バーと一致）---
      env.time_server = FormatDateTime(h1_t);
      datetime jst    = ServerToJst(h1_t);
      env.time_jst    = FormatDateTime(jst);
      env.date_jst    = StringSubstr(env.time_jst, 0, 10);

      //================================================================
      // PatA: 大値幅期待（v4 L717-732）
      //================================================================
      bool patA_base = (atr_zone=="NORMAL" && h1_pat=="RISING_DECEL" &&
                        vel3 >= PATA_VEL3_MIN && vel3 <= PATA_VEL3_MAX);
      if(patA_base && h4_up && h1_up)
         RecordFire(fout, env, "PatA", "BUY", i, h1_high, h1_low, h1_size);
      if(patA_base && !h4_up && !h1_up)
         RecordFire(fout, env, "PatA", "SELL", i, h1_high, h1_low, h1_size);

      //================================================================
      // PatB: 押し目/戻り売り（v4 L737-752）
      //================================================================
      bool patB_base = (atr_zone=="NORMAL" && h1_pat=="RISING_DECEL" &&
                        vel3 >= PATB_VEL3_MIN);
      if(patB_base && h4_up && !h1_up)
         RecordFire(fout, env, "PatB", "BUY", i, h1_high, h1_low, h1_size);
      if(patB_base && !h4_up && h1_up)
         RecordFire(fout, env, "PatB", "SELL", i, h1_high, h1_low, h1_size);

      //================================================================
      // PatC: 初動（v4 L757-773）
      //================================================================
      bool patC_base = (atr_zone=="NORMAL" && h1_pat=="EXPANDING" &&
                        atr_ratio > 1.0 &&
                        h4_adz=="LOW" && (h1_adz=="MID" || h1_adz=="HIGH"));
      if(patC_base && h4_up && h1_up)
         RecordFire(fout, env, "PatC", "BUY", i, h1_high, h1_low, h1_size);
      if(patC_base && !h4_up && !h1_up)
         RecordFire(fout, env, "PatC", "SELL", i, h1_high, h1_low, h1_size);

      //================================================================
      // PatD: H4 ATRクロス節目（v4 L780-803）
      //================================================================
      bool h4_cross_recent = (h4_cross_bars >= 0 && h4_cross_bars <= PATD_CROSSBARS_MAX);
      bool patD_h1_pat_ok = (h1_pat=="RISING_ACCEL" || h1_pat=="RISING_DECEL" ||
                             h1_pat=="EXPANDING");
      bool patD_base = (h4_cross_recent &&
                        (atr_zone=="LOW" || atr_zone=="NORMAL") &&
                        patD_h1_pat_ok &&
                        h1adx > PATD_H1_ADX_MIN &&
                        h4_di_strength >= PATD_DI_STRENGTH_MIN);
      if(patD_base && h4_cross_dir > 0 && h4_up)
         RecordFire(fout, env, "PatD", "BUY", i, h1_high, h1_low, h1_size);
      if(patD_base && h4_cross_dir < 0 && !h4_up)
         RecordFire(fout, env, "PatD", "SELL", i, h1_high, h1_low, h1_size);

      //================================================================
      // PatE: ボトムアウト＋MA接近（v4 L810-832）
      //================================================================
      bool h1_pair_bottom = (h1_pair >= PATE_PAIR_MIN && h1_pair <= PATE_PAIR_MAX);
      bool h1_pat_turn   = (h1_pat=="RISING_ACCEL" || h1_pat=="EXPANDING");
      bool ma_close      = (MathAbs(ma_dist) < PATE_MA_DIST_MAX);
      bool patE_base = (h1_pair_bottom && had_contract_slow && h1_pat_turn &&
                        ma_close &&
                        (h1_adz=="LOW" || h1_adz=="MID") &&
                        h4_di_strength >= PATD_DI_STRENGTH_MIN);
      if(patE_base && h4_di_spread > 0)
         RecordFire(fout, env, "PatE", "BUY", i, h1_high, h1_low, h1_size);
      if(patE_base && h4_di_spread < 0)
         RecordFire(fout, env, "PatE", "SELL", i, h1_high, h1_low, h1_size);

      if(Verbose && g_bars_scanned % 2000 == 0)
         PrintFormat("[INFO] scanned %d bars... fires=%d", g_bars_scanned, g_fire_count);
   }

   FileClose(fout);

   Print("==== [Fire] signal_fires Complete ====");
   PrintFormat("  bars scanned = %d", g_bars_scanned);
   PrintFormat("  fires recorded = %d (pass_all=TRUE: %d)", g_fire_count, g_pass_count);
   PrintFormat("  Output: %s/MQL5/Files/%s",
               TerminalInfoString(TERMINAL_DATA_PATH), Output_File);
}

//+==================================================================+
//| RecordFire                                                       |
//|   1発火 = 1行。フィルター判定（ラベルのみ）+ MFE/MAE 追跡 +     |
//|   CSV 書き出し。multi-fire 仕様（同一バー複数パターン = 複数行） |
//|   は呼び出し側の構造で v4 と同一。                                |
//+==================================================================+
void RecordFire(int fout, const FireRow &env_in,
                const string pattern, const string direction,
                const int fire_idx,
                const double &h1_high[], const double &h1_low[],
                const int h1_size)
{
   FireRow row = env_in;
   g_fire_count++;
   row.fire_id   = g_fire_count;
   row.pattern   = pattern;
   row.direction = direction;

   //--- フィルター F1〜F9 ラベル付与（除外しない）---
   ComputeFilters(row);
   if(row.pass_all) g_pass_count++;

   //--- MFE/MAE 追跡（発火バーの次の H1 バーから 48本）---
   TraceFireMaeMfe(fire_idx, row.entry_price, direction,
                   h1_high, h1_low, h1_size, row);

   WriteRow(fout, row);
}

//+==================================================================+
//| ComputeFilters                                                   |
//|   v4 ApplyFilters (L339-387) の忠実移植。                        |
//|   違い: v4 は「抑制したら発火を消す」が、Logger は               |
//|   「全フィルター条件を個別に TRUE/FALSE ラベル化」する。         |
//|   v4 の input ON/OFF は全 ON（デフォルト）を定数として固定。     |
//|   pass_all = 9本すべて FALSE（= v4 実機で矢印が出た発火）。      |
//+==================================================================+
void ComputeFilters(FireRow &row)
{
   //--- 派生ラベル MID-H = NORMAL + ratio > 1.0（v4 L342）---
   bool is_mid_h = (row.atr_zone == "NORMAL" && row.h1_atr_ratio > 1.0);

   //--- F1: NONE × SELL全パターン（v4 L345）---
   row.f1 = (row.cross_dir == "NONE" && row.direction == "SELL");

   //--- F2: PatB × MID-H × SELL（v4 L349）---
   row.f2 = (row.pattern == "PatB" && is_mid_h && row.direction == "SELL");

   //--- F3: PatD × PD × BUY全Zone（v4 L353）---
   row.f3 = (row.pattern == "PatD" && row.cross_dir == "PD" && row.direction == "BUY");

   //--- F4: UP × NONE × MID-H × PatC × BUY（v4 L357-358）---
   row.f4 = (row.d1_di_dir == "UP" && row.cross_dir == "NONE"
             && is_mid_h && row.pattern == "PatC" && row.direction == "BUY");

   //--- F5: UP × BU × MID-H × PatB × BUY（v4 L362-363）---
   row.f5 = (row.d1_di_dir == "UP" && row.cross_dir == "BU"
             && is_mid_h && row.pattern == "PatB" && row.direction == "BUY");

   //--- F6: UP × PD × MID-H × PatC × BUY（v4 L367-368）---
   row.f6 = (row.d1_di_dir == "UP" && row.cross_dir == "PD"
             && is_mid_h && row.pattern == "PatC" && row.direction == "BUY");

   //--- F7: H4 DI_Spread拮抗 × SELL（v4 L372-373）---
   row.f7 = (MathAbs(row.h4_di_spread) < FILTER_F7_SPREAD_THRESH
             && row.direction == "SELL");

   //--- F8: PatC × NONE × SELL（v4 L377-378）---
   row.f8 = (row.pattern == "PatC" && row.cross_dir == "NONE"
             && row.direction == "SELL");

   //--- F9: PatA × 弱ADX × UP × SELL（v4 L382-383）---
   row.f9 = (row.pattern == "PatA" && row.d1_adx22 < FILTER_F9_WEAK_ADX_THRESH
             && row.d1_di_dir == "UP" && row.direction == "SELL");

   row.pass_all = !(row.f1 || row.f2 || row.f3 || row.f4 || row.f5 ||
                    row.f6 || row.f7 || row.f8 || row.f9);
}

//+==================================================================+
//| TraceFireMaeMfe                                                  |
//|   発火バー (series idx = fire_idx) の次の H1 バー (fire_idx-1)   |
//|   から 48本走査し、発火方向基準の MFE/MAE を 12/24/36/48h の     |
//|   累積セグメントで計算する。                                      |
//|   方式: XAUUSD_Daily_MFE_MAE_v1.mq5 TraceMaeMfe_Segmented と同じ |
//|   （ここでは既コピー済み series 配列を直接走査する実装）          |
//|                                                                  |
//|   bar_no = 発火後の何本目 (1..48)。idx = fire_idx - bar_no       |
//|   idx=0（形成中バー）も「現時点までの実績」として走査に含む       |
//|   （bars_traced で部分追跡を識別可能）                            |
//+==================================================================+
void TraceFireMaeMfe(const int fire_idx, const double entry_price,
                     const string direction,
                     const double &h1_high[], const double &h1_low[],
                     const int h1_size, FireRow &row)
{
   row.mfe_12h = 0; row.mae_12h = 0;
   row.mfe_24h = 0; row.mae_24h = 0;
   row.mfe_36h = 0; row.mae_36h = 0;
   row.mfe_48h = 0; row.mae_48h = 0;
   row.mfe_bar_idx_48h = -1;
   row.mae_bar_idx_48h = -1;
   row.bars_traced = 0;

   bool is_buy = (direction == "BUY");

   double best_favor_12 = -DBL_MAX, worst_adverse_12 = -DBL_MAX;
   double best_favor_24 = -DBL_MAX, worst_adverse_24 = -DBL_MAX;
   double best_favor_36 = -DBL_MAX, worst_adverse_36 = -DBL_MAX;
   double best_favor_48 = -DBL_MAX, worst_adverse_48 = -DBL_MAX;
   int    best_no_48 = -1, worst_no_48 = -1;

   for(int bar_no = 1; bar_no <= TRACE_BARS_48H; bar_no++)
   {
      int idx = fire_idx - bar_no;
      if(idx < 0) break;
      if(idx >= h1_size) continue;

      double hi = h1_high[idx];
      double lo = h1_low[idx];
      if(hi <= 0 || lo <= 0) continue;

      //--- 発火方向基準 ---
      //   BUY : favor = high - entry, adverse = entry - low
      //   SELL: favor = entry - low,  adverse = high - entry
      double favor   = is_buy ? (hi - entry_price) : (entry_price - lo);
      double adverse = is_buy ? (entry_price - lo) : (hi - entry_price);

      if(bar_no <= 48)
      {
         if(favor > best_favor_48)      { best_favor_48 = favor;      best_no_48 = bar_no; }
         if(adverse > worst_adverse_48) { worst_adverse_48 = adverse; worst_no_48 = bar_no; }
      }
      if(bar_no <= 36)
      {
         if(favor > best_favor_36)      best_favor_36 = favor;
         if(adverse > worst_adverse_36) worst_adverse_36 = adverse;
      }
      if(bar_no <= 24)
      {
         if(favor > best_favor_24)      best_favor_24 = favor;
         if(adverse > worst_adverse_24) worst_adverse_24 = adverse;
      }
      if(bar_no <= 12)
      {
         if(favor > best_favor_12)      best_favor_12 = favor;
         if(adverse > worst_adverse_12) worst_adverse_12 = adverse;
      }
      row.bars_traced++;
   }

   if(best_no_48 >= 0)
   {
      row.mfe_48h = MathMax(0.0, best_favor_48);
      row.mfe_bar_idx_48h = best_no_48;
   }
   if(worst_no_48 >= 0)
   {
      row.mae_48h = MathMax(0.0, worst_adverse_48);
      row.mae_bar_idx_48h = worst_no_48;
   }
   if(best_favor_36 > -DBL_MAX)    row.mfe_36h = MathMax(0.0, best_favor_36);
   if(worst_adverse_36 > -DBL_MAX) row.mae_36h = MathMax(0.0, worst_adverse_36);
   if(best_favor_24 > -DBL_MAX)    row.mfe_24h = MathMax(0.0, best_favor_24);
   if(worst_adverse_24 > -DBL_MAX) row.mae_24h = MathMax(0.0, worst_adverse_24);
   if(best_favor_12 > -DBL_MAX)    row.mfe_12h = MathMax(0.0, best_favor_12);
   if(worst_adverse_12 > -DBL_MAX) row.mae_12h = MathMax(0.0, worst_adverse_12);
}

//+==================================================================+
//| CalcATRMedian — v4 L406-421 の忠実移植（同一実装）               |
//+==================================================================+
double CalcATRMedian(const double &atr_arr[], int idx, int median_bars)
{
   int start = idx;
   int end   = idx + median_bars;
   if(end >= ArraySize(atr_arr)) return 0;

   double tmp[];
   ArrayResize(tmp, median_bars);
   int cnt = 0;
   for(int k = start; k < end; k++)
      if(atr_arr[k] > 0) tmp[cnt++] = atr_arr[k];
   if(cnt < 10) return 0;
   ArrayResize(tmp, cnt);
   ArraySort(tmp);
   return tmp[cnt/2];
}

//+==================================================================+
//| FindATRCross — v4 L428-452 の忠実移植（同一実装）                |
//+==================================================================+
int FindATRCross(const double &atr_s[], const double &atr_l[],
                 int idx, int max_look, int &dir_out)
{
   dir_out = 0;
   int size = MathMin(ArraySize(atr_s), ArraySize(atr_l));
   if(idx + 1 >= size) return -1;

   for(int k = 0; k <= max_look; k++)
   {
      int i_now = idx + k;
      int i_prev = idx + k + 1;
      if(i_prev >= size) break;
      if(atr_s[i_now] <= 0 || atr_l[i_now] <= 0 ||
         atr_s[i_prev] <= 0 || atr_l[i_prev] <= 0) continue;

      bool now_above  = (atr_s[i_now]  > atr_l[i_now]);
      bool prev_above = (atr_s[i_prev] > atr_l[i_prev]);
      if(now_above != prev_above)
      {
         dir_out = now_above ? 1 : -1;
         return k;
      }
   }
   return -1;
}

//+==================================================================+
//| AtrPattern — v4 L459-468 の忠実移植（閾値は定数化）              |
//+==================================================================+
string AtrPattern(double vel3, double accel)
{
   if(MathAbs(vel3) < ATR_FLAT_THRESH) return "FLAT";
   if(vel3 > ATR_EXPAND_THRESH && accel > 0) return "EXPANDING";
   if(vel3 > 0 && accel > 0) return "RISING_ACCEL";
   if(vel3 > 0 && accel <= 0) return "RISING_DECEL";
   if(vel3 < 0 && accel < 0) return "CONTRACTING";
   if(vel3 < 0 && accel >= 0) return "CONTRACTING_SLOW";
   return "FLAT";
}

//+==================================================================+
//| FindBarIndexAtOrBefore — v4 L474-481 の忠実移植                  |
//|   ※size には実取得本数（ArraySize ベース）を渡す                |
//+==================================================================+
int FindBarIndexAtOrBefore(const datetime &arr[], datetime t, int size)
{
   for(int k = 0; k < size; k++)
   {
      if(arr[k] <= t) return k;
   }
   return -1;
}

//+==================================================================+
//| ServerToJst — Trade_Snapshot_Builder と同じ規約                  |
//|   実行時の TimeTradeServer-TimeGMT 差で自動算出。                 |
//|   過去日が DST 境界を跨ぐ場合は JST 表記が最大1時間ズレる         |
//|   可能性あり（time_server 列が厳密値）。                          |
//+==================================================================+
datetime ServerToJst(datetime server_time)
{
   long offset_sec = (long)(TimeTradeServer() - TimeGMT());
   datetime utc = server_time - (datetime)offset_sec;
   return utc + (datetime)(JST_OFFSET_HOURS * 3600);
}

//+==================================================================+
//| FormatDateTime: "yyyy.mm.dd HH:MM" → "yyyy-mm-dd HH:MM"          |
//+==================================================================+
string FormatDateTime(datetime t)
{
   string s = TimeToString(t, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "-");
   return s;
}

//+==================================================================+
//| BoolStr                                                          |
//+==================================================================+
string BoolStr(bool b)
{
   return b ? "TRUE" : "FALSE";
}

//+==================================================================+
//| WriteUtf8Bom / WriteUtf8String                                   |
//|   流用元: Trade_Snapshot_Builder.mq5 / XAUUSD_Daily_MFE_MAE_v1   |
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
//| WriteHeaderUtf8 — 65列                                           |
//+==================================================================+
void WriteHeaderUtf8(int fh)
{
   string line =
      // [1-7] キー / 価格
      "fire_id,date,time_jst,time_server,pattern,direction,entry_price,"
      // [8-13] H1 ATR
      "h1_atr16,h1_atr32,h1_atr_median,h1_atr_ratio,atr_zone,h1_pair,"
      // [14-17] H1 パターン
      "h1_pair_state,h1_pattern,h1_vel3,h1_accel,"
      // [18-22] H1 ADX/DI
      "h1_adx32,h1_adx_zone,h1_di_plus,h1_di_minus,h1_di_spread,"
      // [23-24] H1 MA
      "h1_ma,h1_ma_dist,"
      // [25-28] H4 ATR
      "h4_atr8,h4_atr46,h4_pair,h4_pair_state,"
      // [29-33] H4 ADX/DI
      "h4_adx46,h4_adx_zone,h4_di_plus,h4_di_minus,h4_di_spread,"
      // [34-35] H4 クロス
      "h4_cross_bars,h4_cross_dir,"
      // [36-41] D1
      "d1_atr22,d1_atr42,d1_adx22,d1_di_plus,d1_di_minus,d1_di_dir,"
      // [42-43] D1 クロス
      "cross_dir,d1_cross_bars,"
      // [44-53] フィルター
      "f1_none_sell,f2_patb_midh_sell,f3_patd_pd_buy,f4_patc_up_none_midh,"
      "f5_patb_up_bu_midh,f6_patc_up_pd_midh,f7_tight_sell,f8_patc_none_sell,"
      "f9_pata_weakup_sell,pass_all,"
      // [54-65] MFE/MAE
      "mfe_12h,mae_12h,mfe_24h,mae_24h,mfe_36h,mae_36h,mfe_48h,mae_48h,"
      "mfe_bar_idx_48h,mae_bar_idx_48h,bars_traced";
   WriteUtf8String(fh, line + "\n");
}

//+==================================================================+
//| WriteRow — 構造体集約（C4 教訓: 64引数上限回避）                 |
//+==================================================================+
void WriteRow(int fh, const FireRow &r)
{
   string line = "";
   //--- [1-7] キー / 価格 ---
   line += IntegerToString(r.fire_id) + ",";
   line += r.date_jst + ",";
   line += r.time_jst + ",";
   line += r.time_server + ",";
   line += r.pattern + ",";
   line += r.direction + ",";
   line += DoubleToString(r.entry_price, 3) + ",";
   //--- [8-13] H1 ATR ---
   line += DoubleToString(r.h1_atr16, 3) + ",";
   line += DoubleToString(r.h1_atr32, 3) + ",";
   line += DoubleToString(r.h1_atr_median, 3) + ",";
   line += DoubleToString(r.h1_atr_ratio, 4) + ",";
   line += r.atr_zone + ",";
   line += DoubleToString(r.h1_pair, 4) + ",";
   //--- [14-17] H1 パターン ---
   line += r.h1_pair_state + ",";
   line += r.h1_pattern + ",";
   line += DoubleToString(r.h1_vel3, 2) + ",";
   line += DoubleToString(r.h1_accel, 2) + ",";
   //--- [18-22] H1 ADX/DI ---
   line += DoubleToString(r.h1_adx32, 2) + ",";
   line += r.h1_adx_zone + ",";
   line += DoubleToString(r.h1_di_plus, 2) + ",";
   line += DoubleToString(r.h1_di_minus, 2) + ",";
   line += DoubleToString(r.h1_di_spread, 2) + ",";
   //--- [23-24] H1 MA ---
   line += DoubleToString(r.h1_ma, 3) + ",";
   line += DoubleToString(r.h1_ma_dist, 3) + ",";
   //--- [25-28] H4 ATR ---
   line += DoubleToString(r.h4_atr8, 3) + ",";
   line += DoubleToString(r.h4_atr46, 3) + ",";
   line += DoubleToString(r.h4_pair, 4) + ",";
   line += r.h4_pair_state + ",";
   //--- [29-33] H4 ADX/DI ---
   line += DoubleToString(r.h4_adx46, 2) + ",";
   line += r.h4_adx_zone + ",";
   line += DoubleToString(r.h4_di_plus, 2) + ",";
   line += DoubleToString(r.h4_di_minus, 2) + ",";
   line += DoubleToString(r.h4_di_spread, 2) + ",";
   //--- [34-35] H4 クロス ---
   line += IntegerToString(r.h4_cross_bars) + ",";
   line += r.h4_cross_dir + ",";
   //--- [36-41] D1 ---
   line += DoubleToString(r.d1_atr22, 3) + ",";
   line += DoubleToString(r.d1_atr42, 3) + ",";
   line += DoubleToString(r.d1_adx22, 2) + ",";
   line += DoubleToString(r.d1_di_plus, 2) + ",";
   line += DoubleToString(r.d1_di_minus, 2) + ",";
   line += r.d1_di_dir + ",";
   //--- [42-43] D1 クロス ---
   line += r.cross_dir + ",";
   line += IntegerToString(r.d1_cross_bars) + ",";
   //--- [44-53] フィルター ---
   line += BoolStr(r.f1) + ",";
   line += BoolStr(r.f2) + ",";
   line += BoolStr(r.f3) + ",";
   line += BoolStr(r.f4) + ",";
   line += BoolStr(r.f5) + ",";
   line += BoolStr(r.f6) + ",";
   line += BoolStr(r.f7) + ",";
   line += BoolStr(r.f8) + ",";
   line += BoolStr(r.f9) + ",";
   line += BoolStr(r.pass_all) + ",";
   //--- [54-65] MFE/MAE ---
   line += DoubleToString(r.mfe_12h, 3) + ",";
   line += DoubleToString(r.mae_12h, 3) + ",";
   line += DoubleToString(r.mfe_24h, 3) + ",";
   line += DoubleToString(r.mae_24h, 3) + ",";
   line += DoubleToString(r.mfe_36h, 3) + ",";
   line += DoubleToString(r.mae_36h, 3) + ",";
   line += DoubleToString(r.mfe_48h, 3) + ",";
   line += DoubleToString(r.mae_48h, 3) + ",";
   line += IntegerToString(r.mfe_bar_idx_48h) + ",";
   line += IntegerToString(r.mae_bar_idx_48h) + ",";
   line += IntegerToString(r.bars_traced);
   WriteUtf8String(fh, line + "\n");
}
//+------------------------------------------------------------------+
