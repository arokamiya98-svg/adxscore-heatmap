#!/usr/bin/env python3
"""
process_wavelog.py
──────────────────
FractalWaveLog CSV (D1 + H4) を読んで weekly_waves.json を生成する。

v3.2対応:
  優先1: FractalWaveLog_D1_weekly.csv が存在する場合 → 週次時系列データを直接使用
          （ADX22/DI/ATRが週単位で正確にサンプリングされた値）
  フォールバック: 上記がない場合は従来の波形レベルマッピングを使用

入力:
  mt5_data/FractalWaveLog_D1_v3_1.csv   (UTF-16) ← 波形レベル（常に使用）
  mt5_data/FractalWaveLog_D1_weekly.csv (UTF-16) ← 週次時系列（v3.2スクリプトで生成）
  mt5_data/FractalWaveLog_H4_XAU.csv   (UTF-8-sig)

出力:
  data/weekly_waves.json
"""

import csv, json, os, math
from datetime import datetime, timedelta
from collections import defaultdict

BASE_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D1_CSV      = os.path.join(BASE_DIR, "mt5_data", "FractalWaveLog_D1_v3_1.csv")
D1_WEEKLY   = os.path.join(BASE_DIR, "mt5_data", "FractalWaveLog_D1_weekly.csv")
H4_CSV      = os.path.join(BASE_DIR, "mt5_data", "FractalWaveLog_H4_XAU.csv")
H4_WEEKLY   = os.path.join(BASE_DIR, "mt5_data", "FractalWaveLog_H4_weekly.csv")
H4_PHASE_AUTO_CSV = os.path.join(BASE_DIR, "mt5_data", "H4PhaseAuto_weekly.csv")  # v2 5段階
ADX_WEEKLY  = os.path.join(BASE_DIR, "mt5_data", "ADX_Weekly_Above_v4.csv")
ADX_WEEKLY_FALLBACK = os.path.join(BASE_DIR, "mt5_data", "ADX_Weekly_Above_v3.csv")
OUT_JSON    = os.path.join(BASE_DIR, "data", "weekly_waves.json")

# ── ヘルパー ──────────────────────────────────────────────────────────
def parse_mt5_time(s: str) -> datetime:
    s = s.strip()
    for fmt in ("%Y.%m.%d %H:%M", "%Y.%m.%d", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    raise ValueError(f"Unknown time format: {s}")

def iso_week(dt: datetime) -> str:
    iso = dt.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"

def week_monday(week_str: str) -> datetime:
    """ISO週の月曜日を返す"""
    yr, wk = week_str.split("-W")
    return datetime.strptime(f"{yr} {wk} 1", "%G %V %u")

def safe_float(s, default=None):
    try:
        return float(s.strip())
    except (ValueError, AttributeError):
        return default

def safe_str(s, default="—"):
    s = s.strip() if s else ""
    return s if s else default

# ── Fibo ゾーン 短縮表示 ─────────────────────────────────────────────
FIB_ZONE_SHORT = {
    "BU_EARLY":  "BU早期",
    "BU_LATE":   "BU後期",
    "PD_ZONE":   "PD圏内",
    "PD_EXT":    "PD延長",
    "PD_LATE":   "PD後期",
    "BEYOND":    "超過",
    "PRE_BU":    "BU前",
    "BU_CONT":   "BU継続",
}

# ── ATR クラス変換 ────────────────────────────────────────────────────
def atr_to_class(ratio: float) -> str:
    if ratio < 0.90:  return "CONTRACT"
    if ratio <= 1.10: return "NEUTRAL"
    return "EXPAND"

# ── ATR 3区分ゾーン（カイ閾値・状態ラベル / 数値ではない） ────────────
# D1: 凪 ≤0.95 / 中 0.95〜1.10 / 拡張 >1.10
# H4: 凪 ≤0.97 / 中 0.97〜1.10 / 拡張 >1.10
# 根拠: data/bt/PATTERN_REGIME_MAP_v2_AtrRatioDist.md（カイ分析）
def atr_zone3(ratio, tf: str = "D1") -> str:
    if ratio is None:
        return "—"
    threshold_low  = 0.95 if tf == "D1" else 0.97
    threshold_high = 1.10
    if ratio <= threshold_low:  return "凪"
    if ratio >  threshold_high: return "拡張"
    return "中"

# ── H4 Phase Auto v2（5段階） ────────────────────────────────────────
# 仕様: data/bt/h4_phase_auto_spec.md
# 入力:
#   atr_ratio  = ATR8 / ATR46
#   cross_dir  = "BU" / "PD" / "NONE"（mq5側で BU/PD に統一済み）
#   atr_diff   = ATR8 - ATR46（生値）
# 出力: "BU" / "PD" / "凪" / "収束底" / "凪離脱" / "—"
#
# 凪帯（ratio ≤ 0.97）を diff で3層に細分:
#   diff < -1.0 → 収束底 (PF 2.50 N=82, ボトムアウト前で両方向強い)
#   diff > +1.0 → 凪離脱 (PF 0.49 N=40, ★フェイク警告)
#   それ以外    → 凪    (PF 1.20 N=87, 中立)
# 拡張帯（ratio > 0.97）: cross_dir に従って BU / PD（NONE は "—"）
NAGI_RATIO_THRESH = 0.97
NAGI_DIFF_THRESH  = 1.0

def h4_phase_auto(atr_ratio, cross_dir, atr_diff):
    if atr_ratio is None or atr_ratio <= 0:
        return "—"
    # 凪帯
    if atr_ratio <= NAGI_RATIO_THRESH:
        if atr_diff is None:
            return "凪"
        if atr_diff < -NAGI_DIFF_THRESH:
            return "収束底"
        if atr_diff >  NAGI_DIFF_THRESH:
            return "凪離脱"
        return "凪"
    # 拡張帯
    if cross_dir == "BU": return "BU"
    if cross_dir == "PD": return "PD"
    return "—"  # NONE

# ── D1 weekly CSV 読み込み（v3.2スクリプト出力） ─────────────────────
def load_d1_weekly(path: str) -> dict:
    """
    FractalWaveLog_D1_weekly.csv を読んで {iso_week: {...}} を返す。
    週ごとに ADX22/DI/ATR が実測値で入っているので波形レベルCSVより正確。
    エンコーディングは UTF-16（MQL5のFileOpen FILE_UNICODE）。
    """
    try:
        with open(path, encoding="utf-16") as f:
            rows = list(csv.DictReader(f))
    except UnicodeError:
        # UTF-8-sigでもう一度試す
        with open(path, encoding="utf-8-sig") as f:
            rows = list(csv.DictReader(f))

    result = {}
    for r in rows:
        wk = r.get("iso_week", "").strip()
        if not wk or not wk.startswith("20"):
            continue
        di_plus  = safe_float(r.get("di_plus"))
        di_minus = safe_float(r.get("di_minus"))
        di_spread = (di_plus - di_minus) if (di_plus is not None and di_minus is not None) else None
        atr_ratio = safe_float(r.get("atr22_42_ratio"))
        result[wk] = {
            "week":         wk,
            "d1_pattern":   safe_str(r.get("d1_pattern")),
            "d1_adx22":     safe_float(r.get("adx22")),
            "d1_di_dir":    safe_str(r.get("di_dir")),
            "d1_di_plus":   di_plus,
            "d1_di_minus":  di_minus,
            "d1_di_spread": di_spread,
            "d1_atr_ratio": atr_ratio,
            "atr_class":    atr_to_class(atr_ratio) if atr_ratio is not None else "—",
            "fib_zone":     safe_str(r.get("fib_zone")),
            "fib_pos":      safe_float(r.get("fib_pos")),
            # 以下は波形レベルCSVから補完（この時点では空）
            "d1_atr_zone":  "—",
            "d1_atr_trend": "—",
            "fib_level":    None,
            "fib_bu_days":  None,
            "fib_pd_days":  None,
            "fib_days_to_end": None,
            "fib_anchor":   "—",
            "phase_align":  "—",
        }
    return result

# ── H4 週次CSV 読み込み（v3.1スクリプト出力） ────────────────────────
def load_h4_weekly(path: str) -> dict:
    """
    FractalWaveLog_H4_weekly.csv を読んで {iso_week: {...}} を返す。
    UTF-8-sig（BOM付きUTF-8）形式。
    """
    try:
        with open(path, encoding="utf-8-sig") as f:
            rows = list(csv.DictReader(f))
    except UnicodeError:
        with open(path, encoding="utf-16") as f:
            rows = list(csv.DictReader(f))

    result = {}
    for r in rows:
        wk = r.get("iso_week", "").strip()
        if not wk or not wk.startswith("20"):
            continue
        di_plus  = safe_float(r.get("di_plus"))
        di_minus = safe_float(r.get("di_minus"))
        di_spread = (di_plus - di_minus) if (di_plus is not None and di_minus is not None) else None
        atr_ratio = safe_float(r.get("atr8_46_ratio"))
        result[wk] = {
            "h4_pattern":    safe_str(r.get("h4_pattern")),
            "h4_adx46":      safe_float(r.get("adx46")),
            "h4_di_dir":     safe_str(r.get("di_dir")),
            "h4_di_plus":    di_plus,
            "h4_di_minus":   di_minus,
            "h4_di_spread":  di_spread,
            "h4_atr_ratio":  atr_ratio,
            "h4_atr_class":  atr_to_class(atr_ratio) if atr_ratio is not None else "—",
            "h4_ma46_side":  safe_str(r.get("price_vs_ma46")),
        }
    return result

# ── H4 Phase Auto CSV 読み込み（mq5 ARO_H4PhaseAuto_v1 出力） ─────────
def load_h4_phase_auto(path: str) -> dict:
    """
    H4PhaseAuto_weekly.csv を読んで {iso_week: {h4_phase_auto, h4_cross_dir, h4_atr_diff, ...}} を返す。
    エンコーディング: UTF-16（mq5 FILE_UNICODE）。
    フィールド:
      Week, WeekEndTime, H4_BarTime,
      H4_ATR_Short, H4_ATR_Long, H4_ATR_Ratio, H4_ATR_Diff,
      H4_Cross_Bars, H4_Cross_Dir, H4_Phase_Auto
    """
    if not os.path.exists(path):
        return {}
    rows = []
    for enc in ("utf-16", "utf-8-sig", "utf-8"):
        try:
            with open(path, encoding=enc) as f:
                rows = list(csv.DictReader(f))
            break
        except UnicodeError:
            continue
        except Exception:
            continue
    result = {}
    for r in rows:
        wk = r.get("Week", "").strip()
        if not wk or not wk.startswith("20"):
            continue
        ratio = safe_float(r.get("H4_ATR_Ratio"))
        diff  = safe_float(r.get("H4_ATR_Diff"))
        cross_dir = safe_str(r.get("H4_Cross_Dir"), default="NONE")
        # mq5 側で既に判定済みの Phase Auto を採用（再計算はせず信用）
        # ただし py 側でも算出して整合確認できるよう、再計算結果も保持しておく
        phase_mq5 = safe_str(r.get("H4_Phase_Auto"), default="—")
        phase_recalc = h4_phase_auto(ratio, cross_dir, diff)
        # 整合確認: 不一致時はログだけ出して mq5 値を優先
        if phase_mq5 not in ("—", "") and phase_recalc != phase_mq5:
            print(f"   ⚠️ Phase Auto mismatch [{wk}]: mq5={phase_mq5} py={phase_recalc} (ratio={ratio} diff={diff} cross={cross_dir})")
        phase_final = phase_mq5 if phase_mq5 not in ("—", "") else phase_recalc
        result[wk] = {
            "h4_phase_auto":      phase_final,
            "h4_cross_dir":       cross_dir,
            "h4_atr_diff":        diff,
            "h4_atr_ratio_auto":  ratio,   # 比較用（既存 h4_atr_ratio と並列保持）
            "h4_cross_bars":      safe_float(r.get("H4_Cross_Bars")),
        }
    return result

# ── D1 波形CSV 読み込み ───────────────────────────────────────────────
def load_d1_waves(path: str) -> list:
    with open(path, encoding="utf-16") as f:
        rows = list(csv.DictReader(f))
    waves = []
    for r in rows:
        try:
            st = parse_mt5_time(r["start_time"])
            et = parse_mt5_time(r["end_time"])
        except (ValueError, KeyError):
            continue
        waves.append({
            "wave_id":      r.get("wave_id","").strip(),
            "pattern":      safe_str(r.get("pattern_type")),
            "start":        st,
            "end":          et,
            # ADX + DI
            "adx22_end":    safe_float(r.get("adx22_end")),
            "adx22_di_dir": safe_str(r.get("adx22_di_dir")),
            "adx22_mean":   safe_float(r.get("adx22_mean")),
            "di_plus":      safe_float(r.get("adx22_di_plus_start")),
            "di_minus":     safe_float(r.get("adx22_di_minus_start")),
            "di_spread":    (safe_float(r.get("adx22_di_plus_start"), 0)
                             - safe_float(r.get("adx22_di_minus_start"), 0)),
            # ATR（atr22_42_ratio_end = ATR22/ATR42）
            "atr22_ratio":  safe_float(r.get("atr22_42_ratio_end")),
            "atr22_zone":   safe_str(r.get("atr22_zone")),
            "atr_trend":    safe_str(r.get("range_ratio_trend")),
            # Fibo
            "fib_zone":          safe_str(r.get("fib_zone")),
            "fib_pos":           safe_float(r.get("fib_pos")),
            "fib_nearest_level": safe_float(r.get("fib_nearest_level")),
            "fib_bu_days":       safe_float(r.get("fib_bu_days")),
            "fib_pd_days":       safe_float(r.get("fib_pd_pred_days")),
            "fib_days_to_end":   safe_float(r.get("fib_days_to_pred_end")),
            "fib_anchor_time":   safe_str(r.get("fib_anchor_time")),
            "fib_peak_time":     safe_str(r.get("fib_peak_time")),
            # H4参照値
            "h4_adx_end":   safe_float(r.get("h4_adx_end")),
            "h4_di_dir":    safe_str(r.get("h4_di_dir")),
            # Phase
            "phase_align":  safe_str(r.get("phase_align")),
        })
    return sorted(waves, key=lambda w: w["start"])

# ── H4 CSV 読み込み ───────────────────────────────────────────────────
def load_h4_waves(path: str) -> list:
    with open(path, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    waves = []
    for r in rows:
        try:
            st = parse_mt5_time(r["start_time"])
            et = parse_mt5_time(r["end_time"])
        except (ValueError, KeyError):
            continue
        waves.append({
            "wave_id":     r.get("wave_id","").strip(),
            "pattern":     safe_str(r.get("pattern_type")),
            "start":       st,
            "end":         et,
            # ADX + DI
            "adx46_end":   safe_float(r.get("adx46_end")),
            "adx46_dir":   safe_str(r.get("adx46_dir")),
            "h4_di_plus":  safe_float(r.get("adx46_di_plus")),
            "h4_di_minus": safe_float(r.get("adx46_di_minus")),
            "h4_di_spread":(safe_float(r.get("adx46_di_plus"), 0)
                            - safe_float(r.get("adx46_di_minus"), 0)),
            # ATR
            "atr8_ratio_end":  safe_float(r.get("atr8_46_ratio_end")),
            "atr8_zone":       safe_str(r.get("atr8_zone")),
            "atr_cross_dir":   safe_str(r.get("atr_cross_dir")),
            "atr_cross_bars":  safe_float(r.get("atr_cross_bars_ago")),
            # MA
            "ma46_slope":  safe_float(r.get("ma46_slope_pips_bar")),
            "price_vs_ma": safe_str(r.get("price_vs_ma46_end")),
            # Fib proximity
            "fib_within_3bars": safe_str(r.get("fib_within_3bars")),
        })
    return sorted(waves, key=lambda w: w["start"])

# ── 週ごとにウェーブをマッピング（フォールバック用） ─────────────────
def map_waves_to_weeks(d1_waves: list, h4_waves: list) -> dict:
    """
    各ISOweek に対して、そのweekにアクティブだったD1/H4ウェーブを返す。
    D1は1波だけ（その週をカバーする最新のもの）。
    H4は複数ありうるので最後に終わったものを代表とする。
    """
    all_dates = set()
    for w in d1_waves + h4_waves:
        d = w["start"]
        while d <= w["end"] + timedelta(days=7):
            all_dates.add(d.date())
            d += timedelta(days=1)

    all_weeks = set()
    for dt in all_dates:
        all_weeks.add(iso_week(datetime.combine(dt, datetime.min.time())))

    result = {}
    for week in sorted(all_weeks):
        mon = week_monday(week)
        sun = mon + timedelta(days=6)

        d1_active = [
            w for w in d1_waves
            if w["start"].date() <= sun.date() and w["end"].date() >= mon.date()
        ]
        d1 = d1_active[-1] if d1_active else None

        h4_active = [
            w for w in h4_waves
            if w["start"].date() <= sun.date() and w["end"].date() >= mon.date()
        ]
        h4 = h4_active[-1] if h4_active else None

        if not d1 and not h4:
            continue

        atr_class = "—"
        if d1 and d1["atr22_ratio"] is not None:
            atr_class = atr_to_class(d1["atr22_ratio"])

        h4_atr_cross = "—"
        if h4 and h4["atr_cross_dir"] != "—":
            bars = int(h4["atr_cross_bars"]) if h4["atr_cross_bars"] is not None else "?"
            h4_atr_cross = f"{h4['atr_cross_dir']} {bars}bar前"

        result[week] = {
            "week": week,
            # ── D1 ──
            "d1_pattern":    d1["pattern"]       if d1 else "—",
            "d1_adx22":      d1["adx22_end"]    if d1 else None,
            "d1_di_dir":     d1["adx22_di_dir"] if d1 else "—",
            "d1_di_plus":    d1["di_plus"]      if d1 else None,
            "d1_di_minus":   d1["di_minus"]     if d1 else None,
            "d1_di_spread":  d1["di_spread"]    if d1 else None,
            "d1_atr_ratio":  d1["atr22_ratio"]  if d1 else None,
            "d1_atr_zone":   d1["atr22_zone"]   if d1 else "—",
            "d1_atr_zone3":  atr_zone3(d1["atr22_ratio"] if d1 else None, "D1"),
            "d1_atr_trend":  d1["atr_trend"]    if d1 else "—",
            "atr_class":     atr_class,
            "phase_align":   d1["phase_align"]  if d1 else "—",
            # ── Fibo ──
            "fib_zone":      d1["fib_zone"]     if d1 else "—",
            "fib_pos":       d1["fib_pos"]      if d1 else None,
            "fib_level":     d1["fib_nearest_level"] if d1 else None,
            "fib_bu_days":   d1["fib_bu_days"]  if d1 else None,
            "fib_pd_days":   d1["fib_pd_days"]  if d1 else None,
            "fib_days_to_end": d1["fib_days_to_end"] if d1 else None,
            "fib_anchor":    d1["fib_anchor_time"] if d1 else "—",
            # ── H4 ──
            "h4_pattern":    h4["pattern"]        if h4 else "—",
            "h4_adx46":      h4["adx46_end"]      if h4 else None,
            "h4_di_dir":     h4["adx46_dir"]      if h4 else "—",
            "h4_di_plus":    h4["h4_di_plus"]     if h4 else None,
            "h4_di_minus":   h4["h4_di_minus"]    if h4 else None,
            "h4_di_spread":  h4["h4_di_spread"]   if h4 else None,
            "h4_atr_ratio":  h4["atr8_ratio_end"] if h4 else None,
            "h4_atr_class":  atr_to_class(h4["atr8_ratio_end"]) if (h4 and h4["atr8_ratio_end"] is not None) else "—",
            "h4_atr_zone3":  atr_zone3(h4["atr8_ratio_end"] if h4 else None, "H4"),
            "h4_atr_cross":  h4_atr_cross,
            "h4_ma46_side":  h4["price_vs_ma"] if h4 else "—",
            # ── TIER計算 ──
            "tier":          calc_tier(
                                d1["pattern"] if d1 else "—",
                                h4["pattern"] if h4 else "—",
                                atr_class
                             ),
        }
    return result

# ── ADX週次CSV読み込み（ADX_Weekly_Above_v4.csv） ────────────────────
def load_adx_weekly(path: str, symbol: str = "XAUUSD") -> dict:
    """
    ADX_Weekly_Above_v4.csv を読んで {iso_week: {h1_avg_adx, h4_pct20, h4_pct25, adx_score}} を返す
    Week列フォーマット: "2024-W01"
    複数銘柄が混在している場合は symbol でフィルタリングする（デフォルト=XAUUSD）
    H4強閾値: v4以降 = 25（列名 H4_Pct_Above25）、旧v3 = 30（列名 H4_Pct_Above30）の両方を読む
    """
    result = {}
    for enc in ["utf-16", "utf-8-sig", "utf-8"]:
        try:
            with open(path, encoding=enc) as f:
                reader = csv.DictReader(f)
                for r in reader:
                    wk = r.get("Week", "").strip()
                    if not wk:
                        continue
                    # 銘柄フィルター（複数銘柄CSVでの上書き防止）
                    sym = r.get("Symbol", "").strip()
                    if sym and sym != symbol:
                        continue
                    h1_adx   = safe_float(r.get("H1_AvgADX"))
                    h4_pct20 = safe_float(r.get("H4_Pct_Above20"))
                    h1_pct20 = safe_float(r.get("H1_Pct_Above20"))
                    # v4: Above25列を優先、なければ旧Above30列にフォールバック
                    # ※ or演算子は0.0を偽扱いするためis not Noneで判定
                    _p25 = safe_float(r.get("H4_Pct_Above25"))
                    _p30 = safe_float(r.get("H4_Pct_Above30"))
                    h4_pct25 = _p25 if _p25 is not None else _p30
                    result[wk] = {
                        "h1_avg_adx":  h1_adx,
                        "h4_pct20":    h4_pct20,
                        "h4_pct25":    h4_pct25,
                        "h1_pct20":    h1_pct20,
                        "adx_score":   calc_adx_score(h1_adx, h4_pct20, h4_pct25),
                    }
            return result
        except Exception:
            continue
    return result

def calc_adx_score(h1_avg_adx, h4_pct20, h4_pct25) -> float:
    """
    ADXスコア（0〜100）
    Step1: H1正規化（ADX10=0点, ADX40=100点）
    Step2: 幾何平均（片方ゼロでほぼゼロ設計）
    Step3: H4_25ボーナス乗数（×1.0〜1.5）
           ※ H4 ADX(46)は平滑化強く30超えが少ないため閾値を25に変更（2026-05実測ベース）
    """
    if h1_avg_adx is None or h4_pct20 is None or h4_pct25 is None:
        return None
    h1_norm = max(0.0, min(100.0, (h1_avg_adx - 10.0) / 30.0 * 100.0))
    a = max(0.1, h1_norm)
    b = max(0.1, h4_pct20)
    base  = math.sqrt(a * b) * 0.85
    bonus = 1.0 + (h4_pct25 / 100.0) * 0.5
    return round(min(100.0, base * bonus), 1)

# ── TIER計算 ─────────────────────────────────────────────────────────
def calc_tier(d1: str, h4: str, atr: str) -> str:
    if d1 == "BU" and h4 == "BU":
        if atr == "CONTRACT": return "S"
        if atr == "NEUTRAL":  return "A"
        return "B"
    if d1 == "PD" and h4 == "NONE" and atr == "CONTRACT":
        return "A*"
    if d1 == "BU":
        return "B"
    if d1 == "PD" and atr == "CONTRACT":
        return "C"
    return "D"

# ── 週次データと波形レベルデータのマージ ─────────────────────────────
def merge_weekly_with_waves(weekly_d1: dict, d1_waves: list, h4_waves: list) -> dict:
    """
    週次時系列データ（weekly_d1）に H4 波形データと Fibo補完データを合体させる。
    """
    # H4 waves を週にマッピング（既存ロジック流用）
    all_weeks = set(weekly_d1.keys())
    result = {}

    for week in sorted(all_weeks):
        mon = week_monday(week)
        sun = mon + timedelta(days=6)

        # D1波形からFibo等の補完データを取得
        d1_active = [
            w for w in d1_waves
            if w["start"].date() <= sun.date() and w["end"].date() >= mon.date()
        ]
        d1w = d1_active[-1] if d1_active else None

        # H4 波形
        h4_active = [
            w for w in h4_waves
            if w["start"].date() <= sun.date() and w["end"].date() >= mon.date()
        ]
        h4 = h4_active[-1] if h4_active else None

        wd = weekly_d1.get(week, {})
        atr_class = wd.get("atr_class", "—")

        h4_atr_cross = "—"
        if h4 and h4["atr_cross_dir"] != "—":
            bars = int(h4["atr_cross_bars"]) if h4["atr_cross_bars"] is not None else "?"
            h4_atr_cross = f"{h4['atr_cross_dir']} {bars}bar前"

        result[week] = {
            "week": week,
            # ── D1（週次時系列からの正確な値） ──
            "d1_pattern":    wd.get("d1_pattern", "—"),
            "d1_adx22":      wd.get("d1_adx22"),
            "d1_di_dir":     wd.get("d1_di_dir", "—"),
            "d1_di_plus":    wd.get("d1_di_plus"),
            "d1_di_minus":   wd.get("d1_di_minus"),
            "d1_di_spread":  wd.get("d1_di_spread"),
            "d1_atr_ratio":  wd.get("d1_atr_ratio"),
            "d1_atr_zone":   d1w["atr22_zone"]  if d1w else "—",
            "d1_atr_zone3":  atr_zone3(wd.get("d1_atr_ratio"), "D1"),
            "d1_atr_trend":  d1w["atr_trend"]   if d1w else "—",
            "atr_class":     atr_class,
            "phase_align":   d1w["phase_align"] if d1w else "—",
            # ── Fibo（週次CSVに含まれる、D1波形で補完） ──
            "fib_zone":      wd.get("fib_zone", d1w["fib_zone"]   if d1w else "—"),
            "fib_pos":       wd.get("fib_pos",  d1w["fib_pos"]    if d1w else None),
            "fib_level":     d1w["fib_nearest_level"] if d1w else None,
            "fib_bu_days":   d1w["fib_bu_days"]  if d1w else None,
            "fib_pd_days":   d1w["fib_pd_days"]  if d1w else None,
            "fib_days_to_end": d1w["fib_days_to_end"] if d1w else None,
            "fib_anchor":    d1w["fib_anchor_time"] if d1w else "—",
            # ── H4（h4_weekly があれば週次値、なければ波形値） ──
            "h4_pattern":    h4["pattern"]        if h4 else "—",
            "h4_adx46":      h4["adx46_end"]      if h4 else None,
            "h4_di_dir":     h4["adx46_dir"]      if h4 else "—",
            "h4_di_plus":    h4["h4_di_plus"]     if h4 else None,
            "h4_di_minus":   h4["h4_di_minus"]    if h4 else None,
            "h4_di_spread":  h4["h4_di_spread"]   if h4 else None,
            "h4_atr_ratio":  h4["atr8_ratio_end"] if h4 else None,
            "h4_atr_class":  atr_to_class(h4["atr8_ratio_end"]) if (h4 and h4["atr8_ratio_end"] is not None) else "—",
            "h4_atr_zone3":  atr_zone3(h4["atr8_ratio_end"] if h4 else None, "H4"),
            "h4_atr_cross":  h4_atr_cross,
            "h4_ma46_side":  h4["price_vs_ma"] if h4 else "—",
            # ── TIER ──
            "tier": calc_tier(
                wd.get("d1_pattern", "—"),
                h4["pattern"] if h4 else "—",
                atr_class
            ),
        }
    return result

def merge_weekly_with_waves_h4(base_result: dict, h4_weekly: dict) -> dict:
    """
    既存の weekly result に H4 週次時系列データを上書きマージする。
    H4 weekly CSV の値（ADX46, DI+/-, ATR比率）が優先。
    """
    for week, h4w in h4_weekly.items():
        if week not in base_result:
            continue
        r = base_result[week]
        # H4週次CSV値で上書き（より正確な週次実測値）
        h4_pattern = h4w.get("h4_pattern", "—")
        r["h4_pattern"]   = h4_pattern if h4_pattern not in ("—", "-", "") else r["h4_pattern"]
        r["h4_adx46"]     = h4w.get("h4_adx46")   or r["h4_adx46"]
        r["h4_di_dir"]    = h4w.get("h4_di_dir", "—") if h4w.get("h4_di_dir") not in ("—", "") else r["h4_di_dir"]
        r["h4_di_plus"]   = h4w.get("h4_di_plus")   if h4w.get("h4_di_plus")  is not None else r["h4_di_plus"]
        r["h4_di_minus"]  = h4w.get("h4_di_minus")  if h4w.get("h4_di_minus") is not None else r["h4_di_minus"]
        r["h4_di_spread"] = h4w.get("h4_di_spread") if h4w.get("h4_di_spread") is not None else r["h4_di_spread"]
        # H4 ATR ratio（週次CSV値で上書き、ない場合は据置）→ zone3 再評価
        h4_ratio_new = h4w.get("h4_atr_ratio")
        if h4_ratio_new is not None:
            r["h4_atr_ratio"] = h4_ratio_new
            r["h4_atr_zone3"] = atr_zone3(h4_ratio_new, "H4")
        r["h4_atr_class"] = h4w.get("h4_atr_class", "—") if h4w.get("h4_atr_class") not in ("—", "") else r["h4_atr_class"]
        r["h4_ma46_side"] = h4w.get("h4_ma46_side", "—") if h4w.get("h4_ma46_side") not in ("—", "") else r["h4_ma46_side"]
        # TIERも再計算
        r["tier"] = calc_tier(r["d1_pattern"], h4_pattern, r["atr_class"])
    return base_result

# ── メイン ────────────────────────────────────────────────────────────
def main():
    print("📂 Loading D1 FractalWaveLog (波形レベル)...")
    d1_waves = load_d1_waves(D1_CSV)
    print(f"   {len(d1_waves)} D1 waves loaded")
    for w in d1_waves[-3:]:
        print(f"   Wave {w['wave_id']} [{w['pattern']}] {w['start'].date()} → {w['end'].date()}")

    print("\n📂 Loading H4 FractalWaveLog...")
    h4_waves = load_h4_waves(H4_CSV)
    print(f"   {len(h4_waves)} H4 waves loaded")
    for w in h4_waves[-3:]:
        print(f"   Wave {w['wave_id']} [{w['pattern']}] {w['start'].date()} → {w['end'].date()}")

    # ── D1 週次時系列CSV があれば優先使用 ────────────────────────────
    d1_weekly_mode = os.path.exists(D1_WEEKLY)
    if d1_weekly_mode:
        print(f"\n✅ D1 週次CSV: {os.path.basename(D1_WEEKLY)} → v3.2モード")
        weekly_d1 = load_d1_weekly(D1_WEEKLY)
        print(f"   {len(weekly_d1)} weeks")
        weekly = merge_weekly_with_waves(weekly_d1, d1_waves, h4_waves)
    else:
        print(f"\n⚠️  D1 週次CSVなし → フォールバック（波形レベルマッピング）")
        print("   ※ ARO_FractalWaveLog_D1_v3_2.mq5 をD1チャートで実行してください")
        weekly = map_waves_to_weeks(d1_waves, h4_waves)

    # ── H4 週次時系列CSV があれば上書きマージ ────────────────────────
    if os.path.exists(H4_WEEKLY):
        print(f"\n✅ H4 週次CSV: {os.path.basename(H4_WEEKLY)} → H4週次上書きモード")
        h4_weekly_data = load_h4_weekly(H4_WEEKLY)
        print(f"   {len(h4_weekly_data)} weeks")
        weekly = merge_weekly_with_waves_h4(weekly, h4_weekly_data)
    else:
        print(f"\n⚠️  H4 週次CSVなし → H4は波形レベル値を使用")
        print("   ※ ARO_FractalWaveLog_H4_XAU_v3_1.mq5 をH4チャートで実行してください")

    # ── H4 Phase Auto CSV があれば新フィールドをマージ（v2 5段階） ──────
    h4_phase_data = load_h4_phase_auto(H4_PHASE_AUTO_CSV)
    if h4_phase_data:
        print(f"\n✅ H4 Phase Auto CSV: {os.path.basename(H4_PHASE_AUTO_CSV)} → 5段階Phase付与")
        print(f"   {len(h4_phase_data)} weeks")
        matched_pa = 0
        for wk, row in weekly.items():
            if wk in h4_phase_data:
                pa = h4_phase_data[wk]
                row["h4_phase_auto"] = pa["h4_phase_auto"]
                row["h4_cross_dir"]  = pa["h4_cross_dir"]
                row["h4_atr_diff"]   = pa["h4_atr_diff"]
                # h4_atr_ratio が欠落していた週への補完（auto側 = 自動取得で確実）
                if row.get("h4_atr_ratio") is None and pa.get("h4_atr_ratio_auto") is not None:
                    row["h4_atr_ratio"] = pa["h4_atr_ratio_auto"]
                    row["h4_atr_zone3"] = atr_zone3(pa["h4_atr_ratio_auto"], "H4")
                matched_pa += 1
            else:
                row.setdefault("h4_phase_auto", "—")
                row.setdefault("h4_cross_dir",  "—")
                row.setdefault("h4_atr_diff",   None)
        print(f"   マッチ: {matched_pa} weeks")
    else:
        print(f"\n⚠️  H4 Phase Auto CSV なし → 5段階Phaseは欠落")
        print(f"   ※ ARO_H4PhaseAuto_v1.mq5 をH4チャートで実行してください")
        for row in weekly.values():
            row.setdefault("h4_phase_auto", "—")
            row.setdefault("h4_cross_dir",  "—")
            row.setdefault("h4_atr_diff",   None)

    print(f"\n   {len(weekly)} weeks generated")

    # ── ADX週次スコアマージ（v4優先、なければv3フォールバック） ──────────
    adx_csv_path = None
    if os.path.exists(ADX_WEEKLY):
        adx_csv_path = ADX_WEEKLY
    elif os.path.exists(ADX_WEEKLY_FALLBACK):
        adx_csv_path = ADX_WEEKLY_FALLBACK
        print(f"\n⚠️  v4 CSVなし → v3 フォールバック使用")

    if adx_csv_path:
        print(f"\n✅ ADX週次CSV: {os.path.basename(adx_csv_path)}")
        adx_data = load_adx_weekly(adx_csv_path, symbol="XAUUSD")
        print(f"   {len(adx_data)} weeks (XAUUSD)")
        matched = 0
        for wk, row in weekly.items():
            if wk in adx_data:
                a = adx_data[wk]
                row["adx_score"]   = a["adx_score"]
                row["h1_avg_adx"]  = a["h1_avg_adx"]
                row["h4_pct20"]    = a["h4_pct20"]
                row["h4_pct25"]    = a["h4_pct25"]
                row["h1_pct20"]    = a["h1_pct20"]
                matched += 1
            else:
                row.setdefault("adx_score",  None)
                row.setdefault("h1_avg_adx", None)
                row.setdefault("h4_pct20",   None)
                row.setdefault("h4_pct25",   None)
                row.setdefault("h1_pct20",   None)
        print(f"   マッチ: {matched} weeks")
    else:
        print(f"\n⚠️  ADX週次CSVなし（v4/v3どちらも見つからず）")
        print("   ※ ADX_Weekly_Above_v4.mq5 をXAUUSDチャートで実行してください")
        for row in weekly.values():
            row.setdefault("adx_score",  None)
            row.setdefault("h1_avg_adx", None)
            row.setdefault("h4_pct20",   None)
            row.setdefault("h4_pct30",   None)
            row.setdefault("h1_pct20",   None)

    # 最新5週を表示
    print("\n=== 最新5週 ===")
    for wk in sorted(weekly.keys())[-5:]:
        w = weekly[wk]
        d1a = f"{w['d1_adx22']:.1f}" if w.get('d1_adx22') else "—"
        h4a = f"{w['h4_adx46']:.1f}" if w.get('h4_adx46') else "—"
        sp  = f"{w['d1_di_spread']:+.1f}" if w.get('d1_di_spread') is not None else "—"
        print(f"{wk}: D1={w['d1_pattern']:>2} ADX={d1a:>5} DI={sp:>6} | "
              f"H4={w['h4_pattern']:>2} ADX={h4a:>5} | "
              f"ATR={w['atr_class']:>8} | TIER={w['tier']:>2} | Fibo={w['fib_zone']}")

    # JSON出力
    out = list(weekly.values())
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2, default=str)

    print(f"\n✅ Saved: {OUT_JSON}  ({len(out)} weeks)")

if __name__ == "__main__":
    main()
