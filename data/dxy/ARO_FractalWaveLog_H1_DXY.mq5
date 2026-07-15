//+------------------------------------------------------------------+
//|  ARO_FractalWaveLog_H1_DXY.mq5                                   |
//|                                                                  |
//|  H1 × DXY (US Dollar Index) 専用 WaveLog                         |
//|                                                                  |
//|  XAU版からの変更点：                                               |
//|    ① 対象シンボル: XAUUSD → DXY (USDX/DOLLARIDX等)               |
//|    ② pip_size: 0.1 → 0.01 (DXYは小数3桁基準)                     |
//|    ③ Symbol判定: XAU/GOLD → DXY/USDX/DOLLAR                      |
//|    ④ パラメータinputで変更可能（デフォルトは8/46/46/46を踏襲）     |
//|                                                                  |
//|  ※DXYは XAU と価格スケールが大きく異なる（70〜130）。             |
//|    pip_size = Point × 10 を基本にしつつ、手動オーバーライドも可能。 |
//|                                                                  |
//|  使い方：                                                         |
//|    1. DXY H1チャートを開く                                        |
//|    2. サブウィンドウ2にATR Velocity Rhythmを表示                    |
//|    3. サブウィンドウ2にBU/PDトレンドラインを引く                    |
//|    4. （任意）チャート全体に垂直線とフィボタイムゾーンを引く         |
//|    5. このスクリプトを実行 → CSV出力                                |
//|                                                                  |
//|  出力ファイル：                                                    |
//|    FractalWaveLog_H1_DXY.csv         : 波形データ（メイン）        |
//|    FractalWaveLog_H1_DXY_Vlines.csv  : 垂直線時系列データ          |
//+------------------------------------------------------------------+
#property copyright "aro strategy lab"
#property version   "3.00"
#property script_show_inputs
#property strict

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== 出力ファイル名 ==="
input string CSV_BaseName        = "FractalWaveLog_H1_DXY";

input group "=== 対象サブウィンドウ ==="
input int    Target_Subwindow    = 2;
input bool   Read_All_Subwindows = false;

input group "=== ATR設定（H1: 暫定24/30・DXY周期は未調整） ==="
input int    ATR_Period_Short    = 24;
input int    ATR_Period_Long     = 30;
input int    ATR_Median_Window   = 200;
input double ATR_Low_Ratio       = 0.70;
input double ATR_High_Ratio      = 1.40;
input int    ATR_Bottom_Lookback = 20;
input double ATR_Bottom_Tolerance_Pct = 10.0;

input group "=== Velocity設定 ==="
input int    Vel_Window_Short    = 4;
input int    Vel_Window_Long     = 8;

input group "=== ADX設定（H1: 暫定28） ==="
input int    ADX_Period          = 28;

input group "=== MA設定（H1: SMA 30 Close 暫定） ==="
input int    MA_Period           = 30;

input group "=== ATR短期/長期クロス検出 ==="
input int    Cross_Search_Bars   = 300;

input group "=== フィボナッチタイムゾーン ==="
input int    Fib_Within_Bars     = 3;
input bool   Verbose_Fib         = false;

input group "=== 垂直線 ==="
input bool   Export_Vlines       = true;

input group "=== TF/シンボルチェック ==="
input bool   Enforce_H1          = true;   // H1以外で起動したら停止
input bool   Enforce_DXY         = false;  // trueならDXY/USDX/DOLLAR以外で警告
input double Manual_Pip_Size     = 0.0;    // 0=自動判定、手動指定する場合は値を入れる(例: 0.01)

input group "=== その他 ==="
input bool   Verbose_Print       = true;

//+------------------------------------------------------------------+
//| グローバル                                                         |
//+------------------------------------------------------------------+
int hATR_S, hATR_L, hADX, hMA;
double g_pip_size = 0.01;  // DXYデフォルト

struct FibTimeZone { datetime time; int idx; };
FibTimeZone g_fib_lines[];

struct VLine { datetime time; string name; };
VLine g_vlines[];

string g_csv_main  = "";
string g_csv_vline = "";

//+------------------------------------------------------------------+
//| ユーティリティ                                                     |
//+------------------------------------------------------------------+
double GetBufValue(int handle, int buffer_index, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer_index, shift, 1, arr) <= 0) return 0;
   if(ArraySize(arr) == 0) return 0;
   return arr[0];
}

double GetValueByTime(int handle, int buffer_index, datetime time)
{
   int shift = iBarShift(_Symbol, PERIOD_H1, time, false);
   if(shift < 0) return 0;
   return GetBufValue(handle, buffer_index, shift);
}

//+------------------------------------------------------------------+
//| ATR系計算                                                          |
//+------------------------------------------------------------------+
double CalcATRMedianAt(datetime ref_time, int bars)
{
   int shift = iBarShift(_Symbol, PERIOD_H1, ref_time, false);
   if(shift < 0) return 0;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hATR_S, 0, shift, bars, arr) <= 0) return 0;
   int n = ArraySize(arr);
   if(n < 10) return 0;
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++) tmp[i] = arr[i];
   ArraySort(tmp);
   return tmp[n/2];
}

bool IsATRAtBottom(datetime ref_time, int lookback, double tolerance_pct)
{
   int shift = iBarShift(_Symbol, PERIOD_H1, ref_time, false);
   if(shift < 0) return false;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hATR_S, 0, shift, lookback, arr) <= 0) return false;
   int n = ArraySize(arr);
   if(n == 0) return false;
   double cur = arr[0];
   double min_val = arr[ArrayMinimum(arr)];
   if(min_val <= 0) return false;
   return (cur - min_val) / min_val * 100.0 <= tolerance_pct;
}

//+------------------------------------------------------------------+
//| Velocity計算                                                       |
//+------------------------------------------------------------------+
double CalcVelAtTime(datetime ref_time, int vel_window)
{
   int shift = iBarShift(_Symbol, PERIOD_H1, ref_time, false);
   if(shift < 0) return 0;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hATR_S, 0, shift, vel_window + 1, arr) <= 0) return 0;
   if(ArraySize(arr) < vel_window + 1) return 0;
   double cur  = arr[0];
   double prev = arr[vel_window];
   if(prev <= 0) return 0;
   return (cur - prev) / prev * 100.0;
}

//+------------------------------------------------------------------+
//| ATR短期/長期クロス情報取得                                          |
//| ref_timeの時点から過去N本遡って直近クロスを探す                     |
//|   返り値: bars_since_cross（負ならクロスなし）                      |
//|         : cross_direction ("UP" = 短期が長期を上抜け / "DOWN" = 下抜け)|
//+------------------------------------------------------------------+
void FindRecentATRCross(datetime ref_time, int search_bars,
                        int &bars_since_cross, string &cross_dir, datetime &cross_time)
{
   bars_since_cross = -1;
   cross_dir = "NONE";
   cross_time = 0;

   int shift = iBarShift(_Symbol, PERIOD_H1, ref_time, false);
   if(shift < 0) return;

   double a_s[], a_l[];
   ArraySetAsSeries(a_s, true);
   ArraySetAsSeries(a_l, true);
   if(CopyBuffer(hATR_S, 0, shift, search_bars + 1, a_s) <= 0) return;
   if(CopyBuffer(hATR_L, 0, shift, search_bars + 1, a_l) <= 0) return;
   int n = MathMin(ArraySize(a_s), ArraySize(a_l));
   if(n < 3) return;

   for(int i = 1; i < n; i++)
   {
      if(a_s[i] <= 0 || a_l[i] <= 0 || a_s[i-1] <= 0 || a_l[i-1] <= 0) continue;
      bool prev_above = (a_s[i]   > a_l[i]);
      bool cur_above  = (a_s[i-1] > a_l[i-1]);
      if(prev_above != cur_above)
      {
         bars_since_cross = i - 1;
         cross_dir = (cur_above ? "UP" : "DOWN");
         datetime tarr[];
         ArraySetAsSeries(tarr, true);
         if(CopyTime(_Symbol, PERIOD_H1, shift + bars_since_cross, 1, tarr) == 1)
            cross_time = tarr[0];
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| MA傾き計算（pips/bar）                                             |
//|   ref_timeの直近 N=5本でのMAの傾きを返す                            |
//+------------------------------------------------------------------+
double CalcMASlope(datetime ref_time, int lookback)
{
   int shift = iBarShift(_Symbol, PERIOD_H1, ref_time, false);
   if(shift < 0) return 0;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(hMA, 0, shift, lookback + 1, arr) <= 0) return 0;
   if(ArraySize(arr) < lookback + 1) return 0;
   double cur  = arr[0];
   double prev = arr[lookback];
   return (cur - prev) / lookback / g_pip_size;
}

//+------------------------------------------------------------------+
//| MFE/MAE / Quartile計算                                            |
//+------------------------------------------------------------------+
void CalcMfeMae(datetime t_start, datetime t_end, bool is_bu,
                double &mfe_pips, double &mae_pips,
                double &q1, double &q2, double &q3, double &q4)
{
   mfe_pips = 0; mae_pips = 0;
   q1 = 0; q2 = 0; q3 = 0; q4 = 0;

   int s_shift = iBarShift(_Symbol, PERIOD_H1, t_start, false);
   int e_shift = iBarShift(_Symbol, PERIOD_H1, t_end,   false);
   if(s_shift < 0 || e_shift < 0) return;
   if(s_shift <= e_shift) return;

   int bars = s_shift - e_shift;
   if(bars < 4) return;

   double price_start = iClose(_Symbol, PERIOD_H1, s_shift);

   double mfe_val = 0, mae_val = 0;
   for(int k = s_shift; k >= e_shift; k--)
   {
      double hi = iHigh(_Symbol, PERIOD_H1, k);
      double lo = iLow (_Symbol, PERIOD_H1, k);
      if(is_bu)
      {
         double up_move = hi - price_start;
         double dn_move = price_start - lo;
         if(up_move > mfe_val) mfe_val = up_move;
         if(dn_move > mae_val) mae_val = dn_move;
      }
      else
      {
         double dn_move = price_start - lo;
         double up_move = hi - price_start;
         if(dn_move > mfe_val) mfe_val = dn_move;
         if(up_move > mae_val) mae_val = up_move;
      }
   }
   mfe_pips = mfe_val / g_pip_size;
   mae_pips = mae_val / g_pip_size;

   int q_step = bars / 4;
   if(q_step < 1) return;
   double p0 = iClose(_Symbol, PERIOD_H1, s_shift);
   double p1 = iClose(_Symbol, PERIOD_H1, s_shift - q_step);
   double p2 = iClose(_Symbol, PERIOD_H1, s_shift - q_step*2);
   double p3 = iClose(_Symbol, PERIOD_H1, s_shift - q_step*3);
   double p4 = iClose(_Symbol, PERIOD_H1, e_shift);
   q1 = (p1 - p0) / g_pip_size;
   q2 = (p2 - p1) / g_pip_size;
   q3 = (p3 - p2) / g_pip_size;
   q4 = (p4 - p3) / g_pip_size;
}

//+------------------------------------------------------------------+
//| フィボナッチタイムゾーン読み込み                                     |
//+------------------------------------------------------------------+
void CollectFibTimeZones()
{
   ArrayResize(g_fib_lines, 0);
   int total = ObjectsTotal(0, -1, OBJ_FIBOTIMES);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, OBJ_FIBOTIMES);
      if(name == "") continue;

      datetime t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      if(t0 == 0 || t1 == 0) continue;

      int levels = (int)ObjectGetInteger(0, name, OBJPROP_LEVELS);
      if(levels <= 0)
      {
         int defaults[] = {0,1,2,3,5,8,13,21,34,55,89};
         for(int k = 0; k < ArraySize(defaults); k++)
         {
            int span = (int)(t1 - t0);
            if(span <= 0) continue;
            datetime line_t = t0 + (datetime)((long)defaults[k] * (long)span);
            int idx = ArraySize(g_fib_lines);
            ArrayResize(g_fib_lines, idx + 1);
            g_fib_lines[idx].time = line_t;
            g_fib_lines[idx].idx  = defaults[k];
         }
      }
      else
      {
         int span = (int)(t1 - t0);
         if(span <= 0) continue;
         for(int k = 0; k < levels; k++)
         {
            double lv = ObjectGetDouble(0, name, OBJPROP_LEVELVALUE, k);
            datetime line_t = t0 + (datetime)((long)(lv) * (long)span);
            int idx = ArraySize(g_fib_lines);
            ArrayResize(g_fib_lines, idx + 1);
            g_fib_lines[idx].time = line_t;
            g_fib_lines[idx].idx  = (int)lv;
         }
      }
   }
   PrintFormat("フィボタイムゾーン線 総数: %d", ArraySize(g_fib_lines));
}

void FindNearestFib(datetime t, int &nearest_idx, int &nearest_dist_bars, bool &within)
{
   nearest_idx = -1;
   nearest_dist_bars = 9999;
   within = false;

   int n = ArraySize(g_fib_lines);
   if(n == 0) return;

   int t_shift = iBarShift(_Symbol, PERIOD_H1, t, false);
   if(t_shift < 0) return;

   int best_abs = 9999;
   int best_idx = -1;
   int best_dist = 9999;

   for(int i = 0; i < n; i++)
   {
      int f_shift = iBarShift(_Symbol, PERIOD_H1, g_fib_lines[i].time, false);
      if(f_shift < 0) continue;
      int dist = t_shift - f_shift;
      int a = MathAbs(dist);
      if(a < best_abs)
      {
         best_abs = a;
         best_idx = g_fib_lines[i].idx;
         best_dist = -dist;
      }
   }
   nearest_idx = best_idx;
   nearest_dist_bars = best_dist;
   within = (best_abs <= Fib_Within_Bars);
}

//+------------------------------------------------------------------+
//| 垂直線収集                                                          |
//+------------------------------------------------------------------+
void CollectVLines()
{
   ArrayResize(g_vlines, 0);
   int total = ObjectsTotal(0, -1, OBJ_VLINE);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, OBJ_VLINE);
      if(name == "") continue;
      datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      if(t == 0) continue;
      int idx = ArraySize(g_vlines);
      ArrayResize(g_vlines, idx + 1);
      g_vlines[idx].time = t;
      g_vlines[idx].name = name;
   }

   int n = ArraySize(g_vlines);
   for(int i = 0; i < n - 1; i++)
   {
      for(int j = 0; j < n - i - 1; j++)
      {
         if(g_vlines[j].time > g_vlines[j+1].time)
         {
            VLine tmp = g_vlines[j];
            g_vlines[j] = g_vlines[j+1];
            g_vlines[j+1] = tmp;
         }
      }
   }
   PrintFormat("垂直線 総数: %d", n);
}

void FindNearestVLine(datetime t,
                      int &nearest_dist_bars,
                      datetime &nearest_time,
                      datetime &prev_time, datetime &next_time)
{
   nearest_dist_bars = 9999;
   nearest_time = 0;
   prev_time = 0;
   next_time = 0;

   int n = ArraySize(g_vlines);
   if(n == 0) return;

   int t_shift = iBarShift(_Symbol, PERIOD_H1, t, false);
   if(t_shift < 0) return;

   int best_abs = 9999;
   for(int i = 0; i < n; i++)
   {
      datetime vt = g_vlines[i].time;
      if(vt <= t)
      {
         if(prev_time == 0 || vt > prev_time) prev_time = vt;
      }
      else
      {
         if(next_time == 0 || vt < next_time) next_time = vt;
      }

      int v_shift = iBarShift(_Symbol, PERIOD_H1, vt, false);
      if(v_shift < 0) continue;
      int dist = t_shift - v_shift;
      int a = MathAbs(dist);
      if(a < best_abs)
      {
         best_abs = a;
         nearest_dist_bars = -dist;
         nearest_time = vt;
      }
   }
}

//+------------------------------------------------------------------+
//| サブウィンドウ番号取得                                              |
//+------------------------------------------------------------------+
int GetObjectSubwindow(string name)
{
   return ObjectFind(0, name);
}

//+------------------------------------------------------------------+
//| BOM付きCSV書き出しヘルパー                                          |
//+------------------------------------------------------------------+
void WriteBOM(int fh)
{
   uchar bom[3] = {0xEF, 0xBB, 0xBF};
   FileWriteArray(fh, bom, 0, 3);
}

void WriteCsvText(int fh, string text)
{
   uchar buf[];
   int len = StringToCharArray(text, buf, 0, -1, CP_UTF8);
   // StringToCharArrayは末尾に\0を付けるので除外
   if(len > 0 && buf[len-1] == 0) len--;
   if(len > 0) FileWriteArray(fh, buf, 0, len);
}

void WriteCsvLine(int fh, string &fields[], int n)
{
   string line = "";
   for(int i = 0; i < n; i++)
   {
      if(i > 0) line += ",";
      line += fields[i];
   }
   line += "\n";
   WriteCsvText(fh, line);
}

//+------------------------------------------------------------------+
//| トレンドライン1本処理                                              |
//+------------------------------------------------------------------+
bool ProcessLine(string name, int wave_id, int fh)
{
   datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   double   v1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double   v2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);

   if(t1 == 0 || t2 == 0) return false;

   datetime t_start, t_end;
   double   v_start, v_end;
   if(t1 <= t2) { t_start = t1; t_end = t2; v_start = v1; v_end = v2; }
   else         { t_start = t2; t_end = t1; v_start = v2; v_end = v1; }

   string pattern_type;
   bool is_bu;
   if(v_end > v_start)      { pattern_type = "BU"; is_bu = true; }
   else if(v_end < v_start) { pattern_type = "PD"; is_bu = false; }
   else                     { return false; }

   int s_shift = iBarShift(_Symbol, PERIOD_H1, t_start, false);
   int e_shift = iBarShift(_Symbol, PERIOD_H1, t_end,   false);
   if(s_shift < 0 || e_shift < 0) return false;
   int duration_bars = s_shift - e_shift;
   if(duration_bars <= 0) return false;

   double line_delta = v_end - v_start;
   double line_slope = line_delta / duration_bars;

   double price_start = iClose(_Symbol, PERIOD_H1, s_shift);
   double price_end   = iClose(_Symbol, PERIOD_H1, e_shift);
   double price_change_pips = (price_end - price_start) / g_pip_size;
   double price_change_pct  = (price_start > 0) ? (price_end - price_start) / price_start * 100.0 : 0;

   //--- ATR短期(8)
   double atr8_s = GetValueByTime(hATR_S, 0, t_start);
   double atr8_e = GetValueByTime(hATR_S, 0, t_end);
   double atr8_delta = atr8_e - atr8_s;
   double atr8_med = CalcATRMedianAt(t_start, ATR_Median_Window);
   double atr8_ratio = (atr8_med > 0) ? atr8_s / atr8_med : 0;
   string atr8_zone = (atr8_ratio < ATR_Low_Ratio)  ? "LOW" :
                      (atr8_ratio > ATR_High_Ratio) ? "HIGH" : "NORMAL";
   bool atr8_bottom = IsATRAtBottom(t_start, ATR_Bottom_Lookback, ATR_Bottom_Tolerance_Pct);

   //--- ATR長期(46)
   double atr46_s = GetValueByTime(hATR_L, 0, t_start);
   double atr46_e = GetValueByTime(hATR_L, 0, t_end);
   double ratio_s = (atr46_s > 0) ? atr8_s / atr46_s : 0;
   double ratio_e = (atr46_e > 0) ? atr8_e / atr46_e : 0;

   //--- ATR8/46クロス
   int    cross_bars; string cross_dir; datetime cross_t;
   FindRecentATRCross(t_start, Cross_Search_Bars, cross_bars, cross_dir, cross_t);

   //--- Velocity
   double vel4_s = CalcVelAtTime(t_start, Vel_Window_Short);
   double vel4_e = CalcVelAtTime(t_end,   Vel_Window_Short);
   double vel8_s = CalcVelAtTime(t_start, Vel_Window_Long);
   double vel8_e = CalcVelAtTime(t_end,   Vel_Window_Long);

   //--- ADX(46)
   double adx46_s   = GetValueByTime(hADX, 0, t_start);
   double adx46_e   = GetValueByTime(hADX, 0, t_end);
   double adx46_dip = GetValueByTime(hADX, 1, t_start);
   double adx46_din = GetValueByTime(hADX, 2, t_start);
   string adx46_dir = (adx46_dip > adx46_din) ? "UP" : "DOWN";

   //--- MA(46/Close/SMA)
   double ma46_s = GetValueByTime(hMA, 0, t_start);
   double ma46_e = GetValueByTime(hMA, 0, t_end);
   double ma46_dist_s_pips = (price_start - ma46_s) / g_pip_size;
   double ma46_dist_e_pips = (price_end   - ma46_e) / g_pip_size;
   double ma46_slope_pips_bar = CalcMASlope(t_start, 5);
   string price_vs_ma_s = (price_start >= ma46_s) ? "ABOVE" : "BELOW";
   string price_vs_ma_e = (price_end   >= ma46_e) ? "ABOVE" : "BELOW";

   //--- フィボ距離
   int fib_idx; int fib_dist; bool fib_within;
   FindNearestFib(t_start, fib_idx, fib_dist, fib_within);

   //--- 垂直線距離
   int vl_dist; datetime vl_near, vl_prev, vl_next;
   FindNearestVLine(t_start, vl_dist, vl_near, vl_prev, vl_next);
   int days_since_prev = (vl_prev == 0) ? -1 : (int)((t_start - vl_prev) / 86400);
   int days_until_next = (vl_next == 0) ? -1 : (int)((vl_next - t_start) / 86400);

   //--- MFE/MAE/Quartile
   double mfe_p, mae_p, q1c, q2c, q3c, q4c;
   CalcMfeMae(t_start, t_end, is_bu, mfe_p, mae_p, q1c, q2c, q3c, q4c);
   double mfe_mae_ratio = (mae_p > 0) ? mfe_p / mae_p : (mfe_p > 0 ? 999.0 : 0);

   //--- 時間情報
   MqlDateTime mdt;
   TimeToStruct(t_start, mdt);
   string wday_str[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};

   //--- CSV出力（61列）
   string fields[80];
   int n = 0;
   fields[n++] = IntegerToString(wave_id);
   fields[n++] = pattern_type;
   fields[n++] = TimeToString(t_start, TIME_DATE|TIME_MINUTES);
   fields[n++] = TimeToString(t_end,   TIME_DATE|TIME_MINUTES);
   fields[n++] = IntegerToString(duration_bars);

   fields[n++] = DoubleToString(v_start, 3);
   fields[n++] = DoubleToString(v_end,   3);
   fields[n++] = DoubleToString(line_delta, 3);
   fields[n++] = DoubleToString(line_slope, 4);

   fields[n++] = DoubleToString(price_start, 2);
   fields[n++] = DoubleToString(price_end,   2);
   fields[n++] = DoubleToString(price_change_pips, 1);
   fields[n++] = DoubleToString(price_change_pct,  2);

   // ATR8系
   fields[n++] = DoubleToString(atr8_s, 3);
   fields[n++] = DoubleToString(atr8_e, 3);
   fields[n++] = DoubleToString(atr8_delta, 3);
   fields[n++] = DoubleToString(atr8_med, 3);
   fields[n++] = DoubleToString(atr8_ratio, 3);
   fields[n++] = atr8_zone;

   // ATR46 + フラクタル比率
   fields[n++] = DoubleToString(atr46_s, 3);
   fields[n++] = DoubleToString(atr46_e, 3);
   fields[n++] = DoubleToString(ratio_s, 3);
   fields[n++] = DoubleToString(ratio_e, 3);

   // ATRクロス情報
   fields[n++] = IntegerToString(cross_bars);
   fields[n++] = cross_dir;
   fields[n++] = (cross_t == 0) ? "" : TimeToString(cross_t, TIME_DATE);

   // Velocity
   fields[n++] = DoubleToString(vel4_s, 2);
   fields[n++] = DoubleToString(vel4_e, 2);
   fields[n++] = DoubleToString(vel8_s, 2);
   fields[n++] = DoubleToString(vel8_e, 2);

   // ADX46
   fields[n++] = DoubleToString(adx46_s, 2);
   fields[n++] = DoubleToString(adx46_e, 2);
   fields[n++] = DoubleToString(adx46_e - adx46_s, 2);
   fields[n++] = DoubleToString(adx46_dip, 2);
   fields[n++] = DoubleToString(adx46_din, 2);
   fields[n++] = adx46_dir;

   // MA46（新規）
   fields[n++] = DoubleToString(ma46_s, 3);
   fields[n++] = DoubleToString(ma46_e, 3);
   fields[n++] = DoubleToString(ma46_dist_s_pips, 1);
   fields[n++] = DoubleToString(ma46_dist_e_pips, 1);
   fields[n++] = DoubleToString(ma46_slope_pips_bar, 3);
   fields[n++] = price_vs_ma_s;
   fields[n++] = price_vs_ma_e;

   // フィボ
   fields[n++] = IntegerToString(fib_idx);
   fields[n++] = IntegerToString(fib_dist);
   fields[n++] = fib_within ? "TRUE" : "FALSE";

   // 垂直線
   fields[n++] = IntegerToString(vl_dist);
   fields[n++] = (vl_near == 0) ? "" : TimeToString(vl_near, TIME_DATE);
   fields[n++] = IntegerToString(days_since_prev);
   fields[n++] = IntegerToString(days_until_next);

   // MFE/MAE
   fields[n++] = DoubleToString(mfe_p, 1);
   fields[n++] = DoubleToString(mae_p, 1);
   fields[n++] = DoubleToString(mfe_mae_ratio, 2);

   // Quartile
   fields[n++] = DoubleToString(q1c, 1);
   fields[n++] = DoubleToString(q2c, 1);
   fields[n++] = DoubleToString(q3c, 1);
   fields[n++] = DoubleToString(q4c, 1);

   // 時間補助
   fields[n++] = IntegerToString(mdt.hour);
   fields[n++] = wday_str[mdt.day_of_week];
   fields[n++] = IntegerToString(mdt.mon);
   fields[n++] = atr8_bottom ? "TRUE" : "FALSE";

   // 周期メタ情報（どの周期で抽出したCSVかの自己記録）
   fields[n++] = IntegerToString(ATR_Period_Short);
   fields[n++] = IntegerToString(ATR_Period_Long);
   fields[n++] = IntegerToString(ADX_Period);
   fields[n++] = IntegerToString(MA_Period);

   WriteCsvLine(fh, fields, n);

   if(Verbose_Print)
      PrintFormat("[#%d] %s | %s→%s (%d bars) | price %+.1f pips | ATR8 %.2f→%.2f (zone:%s) | ADX46 %.1f→%.1f (%s) | MA46 dist %+.1f→%+.1f pips | cross %s in %d bars",
                  wave_id, pattern_type,
                  TimeToString(t_start, TIME_DATE),
                  TimeToString(t_end,   TIME_DATE),
                  duration_bars,
                  price_change_pips,
                  atr8_s, atr8_e, atr8_zone,
                  adx46_s, adx46_e, adx46_dir,
                  ma46_dist_s_pips, ma46_dist_e_pips,
                  cross_dir, cross_bars);
   return true;
}

//+------------------------------------------------------------------+
//| 垂直線CSV出力                                                      |
//+------------------------------------------------------------------+
void ExportVlinesCsv()
{
   int n = ArraySize(g_vlines);
   if(n == 0) { Print("垂直線なし: スキップ"); return; }

   int fh = FileOpen(g_csv_vline, FILE_WRITE|FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("ERROR: 垂直線CSVオープン失敗 - %d", GetLastError());
      return;
   }

   WriteBOM(fh);
   WriteCsvText(fh, "vline_id,time,prev_gap_bars,next_gap_bars,prev_gap_days,next_gap_days,name\n");

   for(int i = 0; i < n; i++)
   {
      int shift = iBarShift(_Symbol, PERIOD_H1, g_vlines[i].time, false);
      int prev_gap_bars = -1, next_gap_bars = -1;
      int prev_gap_days = -1, next_gap_days = -1;

      if(i > 0)
      {
         int s_prev = iBarShift(_Symbol, PERIOD_H1, g_vlines[i-1].time, false);
         if(s_prev >= 0 && shift >= 0) prev_gap_bars = s_prev - shift;
         prev_gap_days = (int)((g_vlines[i].time - g_vlines[i-1].time) / 86400);
      }
      if(i < n - 1)
      {
         int s_next = iBarShift(_Symbol, PERIOD_H1, g_vlines[i+1].time, false);
         if(s_next >= 0 && shift >= 0) next_gap_bars = shift - s_next;
         next_gap_days = (int)((g_vlines[i+1].time - g_vlines[i].time) / 86400);
      }

      string line = StringFormat("%d,%s,%d,%d,%d,%d,%s\n",
                                 i+1,
                                 TimeToString(g_vlines[i].time, TIME_DATE|TIME_MINUTES),
                                 prev_gap_bars, next_gap_bars,
                                 prev_gap_days, next_gap_days,
                                 g_vlines[i].name);
      WriteCsvText(fh, line);
   }
   FileClose(fh);
   PrintFormat("垂直線CSV出力: %s（%d本）", g_csv_vline, n);
}

//+------------------------------------------------------------------+
//| メイン                                                             |
//+------------------------------------------------------------------+
void OnStart()
{
   //--- TFチェック
   if(Enforce_H1 && _Period != PERIOD_H1)
   {
      PrintFormat("ERROR: H1専用スクリプトです。現在のTF=%s で起動しないでください。",
                  EnumToString((ENUM_TIMEFRAMES)_Period));
      MessageBox("このスクリプトはH1専用です。\nH1チャートで起動してください。",
                 "ARO WaveLog H1 DXY", MB_ICONERROR);
      return;
   }

   //--- Symbolチェック
   string sym = _Symbol;
   string sym_upper = sym;
   StringToUpper(sym_upper);
   bool is_dxy = (StringFind(sym_upper, "DXY")    >= 0 ||
                  StringFind(sym_upper, "USDX")   >= 0 ||
                  StringFind(sym_upper, "DOLLAR") >= 0 ||
                  StringFind(sym_upper, "USDOL")  >= 0);
   if(Enforce_DXY && !is_dxy)
   {
      PrintFormat("ERROR: DXY専用です。現在のシンボル=%s", sym);
      MessageBox("このスクリプトはDXY (USDollar Index) 専用です。",
                 "ARO WaveLog H1 DXY", MB_ICONERROR);
      return;
   }

   g_csv_main  = CSV_BaseName + ".csv";
   g_csv_vline = CSV_BaseName + "_Vlines.csv";

   Print("=== ARO_FractalWaveLog H1 DXY v3 開始 ===");
   PrintFormat("Symbol=%s TF=H1 (is_dxy=%s)", _Symbol, is_dxy ? "YES" : "NO");
   PrintFormat("ATR短期=%d 長期=%d  ADX=%d  MA=%d(SMA/Close)",
               ATR_Period_Short, ATR_Period_Long, ADX_Period, MA_Period);

   //--- pip_size決定（優先度: 手動指定 > 自動判定）
   if(Manual_Pip_Size > 0)
   {
      g_pip_size = Manual_Pip_Size;
      PrintFormat("pip_size = %.5f (手動指定)", g_pip_size);
   }
   else
   {
      // DXYは Digits=3 が標準（例: 104.523）→ Point=0.001、pip=0.01
      // ブローカーによっては Digits=2 (104.52) もあるので動的に判定
      double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(_Digits == 3 || _Digits == 5)
         g_pip_size = pt * 10;   // 3桁→0.01, 5桁→0.0001
      else if(_Digits == 2 || _Digits == 4)
         g_pip_size = pt;         // 2桁→0.01, 4桁→0.0001
      else
         g_pip_size = pt;
      PrintFormat("pip_size = %.5f (自動判定: Digits=%d, Point=%.5f)",
                  g_pip_size, _Digits, pt);
   }

   // ハンドル生成
   hATR_S = iATR(_Symbol, PERIOD_H1, ATR_Period_Short);
   hATR_L = iATR(_Symbol, PERIOD_H1, ATR_Period_Long);
   hADX   = iADX(_Symbol, PERIOD_H1, ADX_Period);
   hMA    = iMA (_Symbol, PERIOD_H1, MA_Period, 0, MODE_SMA, PRICE_CLOSE);

   if(hATR_S==INVALID_HANDLE || hATR_L==INVALID_HANDLE ||
      hADX==INVALID_HANDLE   || hMA==INVALID_HANDLE)
   {
      Print("ERROR: インジハンドル生成失敗");
      return;
   }
   Sleep(700);

   //--- フィボ/垂直線収集
   CollectFibTimeZones();
   CollectVLines();

   //--- メインCSVオープン（BIN + BOMでNumbers対応）
   int fh = FileOpen(g_csv_main, FILE_WRITE|FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("ERROR: CSVオープン失敗 - %d", GetLastError());
      return;
   }

   //--- BOM書き込み
   WriteBOM(fh);

   //--- ヘッダー（65列・汎用列名＋周期メタ4列）
   string header =
      "wave_id,pattern_type,start_time,end_time,duration_bars,"
      "line_start_value,line_end_value,line_delta,line_slope,"
      "price_start,price_end,price_change_pips,price_change_pct,"
      "atr_s_start,atr_s_end,atr_s_delta,atr_s_median,atr_s_ratio,atr_s_zone,"
      "atr_l_start,atr_l_end,atr_sl_ratio_start,atr_sl_ratio_end,"
      "atr_cross_bars_ago,atr_cross_dir,atr_cross_time,"
      "vel4_start,vel4_end,vel8_start,vel8_end,"
      "adx_start,adx_end,adx_delta,adx_di_plus,adx_di_minus,adx_dir,"
      "ma_start,ma_end,ma_dist_start_pips,ma_dist_end_pips,ma_slope_pips_bar,price_vs_ma_start,price_vs_ma_end,"
      "fib_nearest_idx,fib_nearest_distance,fib_within_3bars,"
      "vline_nearest_distance,vline_nearest_time,days_since_prev_vline,days_until_next_vline,"
      "mfe_pips,mae_pips,mfe_mae_ratio,"
      "q1_change_pips,q2_change_pips,q3_change_pips,q4_change_pips,"
      "hour_at_start,weekday_at_start,month_at_start,atr_s_at_bottom,atr_period_short,atr_period_long,adx_period,ma_period\n";
   WriteCsvText(fh, header);

   //--- トレンドライン処理
   int total = ObjectsTotal(0, -1, OBJ_TREND);
   int wave_id = 0;
   int cnt_bu = 0, cnt_pd = 0, cnt_skip = 0;
   PrintFormat("検出トレンドライン総数: %d", total);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, OBJ_TREND);
      if(name == "") continue;
      int sub = GetObjectSubwindow(name);
      if(sub < 0) { cnt_skip++; continue; }

      if(!Read_All_Subwindows && sub != Target_Subwindow)
      {
         cnt_skip++;
         continue;
      }

      if(ProcessLine(name, wave_id+1, fh))
      {
         wave_id++;
         double v1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         double v2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
         datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
         double vs = (t1 <= t2) ? v1 : v2;
         double ve = (t1 <= t2) ? v2 : v1;
         if(ve > vs) cnt_bu++; else if(ve < vs) cnt_pd++;
      }
   }

   FileClose(fh);

   //--- 垂直線CSV
   if(Export_Vlines) ExportVlinesCsv();

   Print("=== 出力完了 ===");
   PrintFormat("波形総数: %d (BU=%d, PD=%d) スキップ=%d",
               wave_id, cnt_bu, cnt_pd, cnt_skip);
   PrintFormat("メインCSV: %s\\MQL5\\Files\\%s",
               TerminalInfoString(TERMINAL_DATA_PATH), g_csv_main);

   if(cnt_bu > 0 && cnt_pd > 0)
   {
      double ratio = (double)cnt_pd / (double)cnt_bu;
      PrintFormat("★BU/PD件数比: PD/BU = %.3f (φ=1.618)", ratio);
   }

   IndicatorRelease(hATR_S);
   IndicatorRelease(hATR_L);
   IndicatorRelease(hADX);
   IndicatorRelease(hMA);
}
//+------------------------------------------------------------------+
