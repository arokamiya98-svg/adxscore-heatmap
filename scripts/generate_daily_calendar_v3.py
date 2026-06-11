#!/usr/bin/env python3
"""
generate_daily_calendar_v3.py
─────────────────────────────
日次認識カレンダー v3（新規ファイル / 既存 generate_daily_calendar.py は変更禁止・保存）

正書  : data/mani_room/正書_日次認識カレンダーv3_2026-06-11.md
指示書: data/mani_room/マニ_指示書_日次認識カレンダーv3_v0.1.md

認識ターゲット（正書 §1）:
  「純粋に認識ツールの土台で、どう相場が動いて、そこにシグナルとトレード実弾が
   どう機能したか」
  ①相場の動き（色 + MFE/MAEバー）②シグナルの機能（v4発火）③実弾の機能（執行結果）
  → 3つの「結果」の見比べ。D1 ADX は「因果」（戦略側）なので色に混ぜない。

v3 の核心変更（指示書 §4.2）:
  - 強度（明度・彩度段階）= 日次合成スコア（calc_daily_score 現行式そのまま）
  - 方向（色相 青/赤）    = H1 DI spread の符号 ← h4_di_spread から変更
      * daily_aggregate.csv には h1_di_spread_close（確定情報）のみ収録
        → 「日次平均」の代替として close を採用（v1.2 の「DI 方向 = close」設計と整合）
      * 週次フォールバック日（daily CSV 期間外）は H1 DI が存在しないため
        h4_di_spread に退避（ツールチップに src 表記）
  - 確信度（彩度補正）    = H1 と H4 の DI 方向一致 → フル彩度 / 不一致 → 一段ダウン
  - 凪/レンジ判定: スコアのみ（h4_adx46<15 条件を撤去）。グレーの見た目は現行踏襲、
    ラベル文字のみ「凪」→「レンジ」（凪=ATR収束の別概念、nagi-vs-range-distinction）
  - 連続グラデーション禁止（段階化維持）

セルの視覚要素（指示書 §4.1 — これだけ）:
  1. 背景色（環境の強度と方向）
  2. MFE/MAE バー（値動きの形）
  3. シグナルドット（v4発火、signals_calendar v2 と同一視覚言語）
  4. トレードマーク（枠線+方向▲▼、デフォルトON・トグルあり）
  削除: H1 ADX 数値・金額・スコア数値・タグ等のセル内文字情報（→ ホバー/ドロワーへ降格）

v3 設計判断（マニ、レポートに明記）:
  - D1 帯（週上部の帯）を タブ1 から撤去: D1 は「因果」レイヤーで、本カレンダーの
    認識ターゲット（結果の見比べ）の外。情報はツールチップに残す
  - H4 Phase バッジ / 凪離脱警告枠も同理由でセルから撤去（ツールチップに残す）
  - カレンダーは月〜土の6列: signal_fires.csv に JST 土曜発火が31件あり、
    5列だと「389件全件表示」の完了条件を満たせない（signals_calendar と同判断）
  - 期間 = 発火期間 ∪ トレード期間（2025-03〜、発火389件全件を出すため）

入力（すべて utf-8-sig）:
    data/mani_room/raw/imports/FX_*.csv (最新)
    data/mani_room/enriched/trades_enriched_full.csv
    mt5_data/daily_aggregate.csv（優先） + data/weekly_waves.json（フォールバック）
    mt5_data/daily_mfe_mae_48h.csv
    mt5_data/signal_fires.csv（64列×389発火）★v3追加
出力:
    data/trades/processed/daily_calendar_v3.html（自己完結、CDN/fetch なし）
"""
import csv
import json
import math
from collections import defaultdict
from datetime import datetime, timedelta, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRADES_DIR = ROOT / "data" / "mani_room" / "raw" / "imports"
ENRICHED = ROOT / "data" / "mani_room" / "enriched" / "trades_enriched_full.csv"
OUT = ROOT / "data" / "trades" / "processed"
WAVES = ROOT / "data" / "weekly_waves.json"
DAILY_MFE_MAE = ROOT / "mt5_data" / "daily_mfe_mae_48h.csv"
DAILY_AGG = ROOT / "mt5_data" / "daily_aggregate.csv"
FIRES_CSV = ROOT / "mt5_data" / "signal_fires.csv"
OUT.mkdir(parents=True, exist_ok=True)
OUT_HTML = OUT / "daily_calendar_v3.html"

# ============================================================
# v4 実機 矢印色テーブル（signals_calendar v2 と完全一致・変更禁止）
# ============================================================
PATTERN_COLORS = {
    "PatA": {"BUY": "#FFD700", "SELL": "#DAA520"},
    "PatB": {"BUY": "#00FFFF", "SELL": "#00BFFF"},
    "PatC": {"BUY": "#32CD32", "SELL": "#2E8B57"},
    "PatD": {"BUY": "#FF00FF", "SELL": "#C71585"},
    "PatE": {"BUY": "#FFA500", "SELL": "#FF8C00"},
}
PATTERNS = ["PatA", "PatB", "PatC", "PatD", "PatE"]
FILTER_COLS = [
    ("f1_none_sell", "F1 none_sell"),
    ("f2_patb_midh_sell", "F2 patb_midh_sell"),
    ("f3_patd_pd_buy", "F3 patd_pd_buy"),
    ("f4_patc_up_none_midh", "F4 patc_up_none_midh"),
    ("f5_patb_up_bu_midh", "F5 patb_up_bu_midh"),
    ("f6_patc_up_pd_midh", "F6 patc_up_pd_midh"),
    ("f7_tight_sell", "F7 tight_sell"),
    ("f8_patc_none_sell", "F8 patc_none_sell"),
    ("f9_pata_weakup_sell", "F9 pata_weakup_sell"),
]

# ============================================================
# ユーティリティ
# ============================================================
def _f(x):
    """安全 float 変換（空欄は None）"""
    if x is None or x == "":
        return None
    try:
        return float(x)
    except (ValueError, TypeError):
        return None

# ============================================================
# 入力1: トレードログ FX_*.csv（タブ2 分析用 + セル MFE/MAE バー用）
# ============================================================
src = sorted(TRADES_DIR.glob("FX_*.csv"))[-1]
with open(src, encoding="utf-8") as f:
    trade_rows = list(csv.DictReader(f))
with open(WAVES, encoding="utf-8") as f:
    weeks = json.load(f)

# enriched — trade_id ベースでマップ（utf-8-sig 必須、BOM事件再発防止）
enriched_map = {}
if ENRICHED.exists():
    with open(ENRICHED, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            tid = r.get("trade_id", "").strip()
            if tid:
                enriched_map[tid] = r

# 仮想 48h MFE/MAE（JST 14:00 仮想エントリー）
daily_mfe_mae_map = {}
if DAILY_MFE_MAE.exists():
    with open(DAILY_MFE_MAE, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                d = datetime.strptime(r["date"], "%Y-%m-%d").date()
            except Exception:
                continue
            daily_mfe_mae_map[d] = {
                "buy_mfe": _f(r.get("buy_mfe_usd")),
                "buy_mae": _f(r.get("buy_mae_usd")),
                "sell_mfe": _f(r.get("sell_mfe_usd")),
                "sell_mae": _f(r.get("sell_mae_usd")),
                "entry_price": _f(r.get("virtual_entry_price")),
                "bars_traced": _f(r.get("bars_traced")),
            }

# 全期間 MFE/MAE 正規化基準（p95、v1.1 から踏襲）
def _calc_bar_norm_base():
    all_vals = []
    for v in daily_mfe_mae_map.values():
        for k in ("buy_mfe", "buy_mae", "sell_mfe", "sell_mae"):
            x = v.get(k)
            if x is not None and x > 0:
                all_vals.append(x)
    if not all_vals:
        return 300.0
    all_vals.sort(reverse=True)
    p95_idx = max(0, int(len(all_vals) * 0.05))
    return all_vals[p95_idx]

BAR_NORM_BASE = _calc_bar_norm_base()

week_map = {w["week"]: w for w in weeks}

# ============================================================
# 入力2: 日次 daily_aggregate.csv（C2出力、優先データソース — v1.2 踏襲）
# ============================================================
def _parse_daily_agg_row(r):
    return {
        "d1_adx22": _f(r.get("d1_adx22")),
        "d1_di_plus": _f(r.get("d1_di_plus")),
        "d1_di_minus": _f(r.get("d1_di_minus")),
        "d1_di_spread": _f(r.get("d1_di_spread")),
        "d1_di_dir": r.get("d1_di_dir", "").strip() or None,
        "d1_atr22": _f(r.get("d1_atr22")),
        "d1_atr42": _f(r.get("d1_atr42")),
        "d1_atr22_42_ratio": _f(r.get("d1_atr22_42_ratio")),
        "h4_adx46": _f(r.get("h4_adx46_mean")),
        "h4_adx_max": _f(r.get("h4_adx46_max")),
        "h4_adx_close": _f(r.get("h4_adx46_close")),
        "h4_di_plus": _f(r.get("h4_di_plus_close")),
        "h4_di_minus": _f(r.get("h4_di_minus_close")),
        "h4_di_spread": _f(r.get("h4_di_spread_close")),
        "h4_di_dir": r.get("h4_di_dir", "").strip() or None,
        "h4_atr8": _f(r.get("h4_atr8_close")),
        "h4_atr46": _f(r.get("h4_atr46_close")),
        "h4_atr8_46_ratio": _f(r.get("h4_atr8_46_ratio_close")),
        "h1_avg_adx": _f(r.get("h1_adx32_mean")),
        "h1_adx_max": _f(r.get("h1_adx32_max")),
        "h1_adx_close": _f(r.get("h1_adx32_close")),
        "h1_di_plus": _f(r.get("h1_di_plus_close")),
        "h1_di_minus": _f(r.get("h1_di_minus_close")),
        # ★v3 方向色相の主ソース（close = 確定情報。日次CSVに mean は無い）
        "h1_di_spread": _f(r.get("h1_di_spread_close")),
        "h1_di_dir": r.get("h1_di_dir", "").strip() or None,
        "h1_atr16": _f(r.get("h1_atr16_close")),
        "h1_atr32": _f(r.get("h1_atr32_close")),
        "h1_atr16_32_ratio": _f(r.get("h1_atr16_32_ratio_close")),
        "_source": "daily_agg",
    }

daily_agg_map = {}
if DAILY_AGG.exists():
    with open(DAILY_AGG, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                d = datetime.strptime(r["date"], "%Y-%m-%d").date()
            except Exception:
                continue
            daily_agg_map[d] = _parse_daily_agg_row(r)

def date_to_iso_week(d):
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"

def get_rec(d):
    """日次データ優先 + 週次フォールバック（v1.2 踏襲）"""
    week_rec = week_map.get(date_to_iso_week(d))
    daily_rec = daily_agg_map.get(d)
    if daily_rec is None:
        return week_rec
    merged = dict(daily_rec)
    if week_rec:
        for k in (
            "h4_phase_auto", "d1_pattern", "tier",
            "fib_zone", "fib_pos", "fib_level", "fib_bu_days", "fib_pd_days",
            "fib_days_to_end", "fib_anchor",
            "h4_pattern", "h4_atr_ratio", "h4_atr_class", "h4_atr_zone3",
            "h4_atr_cross", "h4_ma46_side", "h4_cross_dir", "h4_atr_diff",
            "d1_atr_ratio", "d1_atr_zone", "d1_atr_zone3", "d1_atr_trend",
            "atr_class", "phase_align",
            "adx_score", "h4_pct20", "h4_pct25", "h1_pct20",
        ):
            if k in week_rec and k not in merged:
                merged[k] = week_rec[k]
    return merged

# ============================================================
# 入力3: トレード日次集計（FX CSV ベース、タブ2 分析 + セルバー用 — v2.0 踏襲）
# ============================================================
trade_by_date = defaultdict(list)
for r in trade_rows:
    try:
        d = datetime.strptime(r["約定日"][:10], "%Y/%m/%d").date()
    except Exception:
        continue
    entry_rate = _f(r["新規レート"]) or 0
    direction = "BUY" if r["オーダー"] == "買い" else "SELL"
    enriched_row = None
    for er in enriched_map.values():
        try:
            er_d = datetime.strptime(er["約定日"][:10], "%Y/%m/%d").date()
        except Exception:
            continue
        if er_d != d:
            continue
        if er.get("direction", "").upper() != direction:
            continue
        ep = _f(er.get("entry_price"))
        if ep is not None and abs(ep - entry_rate) < 0.01:
            enriched_row = er
            break
    h4_mfe = h4_mae = None
    h1_atr_ratio = None
    if enriched_row:
        h4_mfe = _f(enriched_row.get("h4_mfe_usd_48h"))
        h4_mae = _f(enriched_row.get("h4_mae_usd_48h"))
        h1_atr_ratio = _f(enriched_row.get("h1_atr_ratio"))
    decision_tag = (r.get("反省") or "").strip() or None
    trade_by_date[d].append({
        "pl": float(r["損益"]) if r["損益"] else 0,
        "order": r["オーダー"],
        "star": r["評価"],
        "lot": float(r["ロット"]) if r["ロット"] else 0,
        "pips": float(r["pips"]) if r["pips"] else 0,
        "entry_rate": entry_rate,
        "exit_rate": float(r["決済レート"]) if r["決済レート"] else 0,
        "h4_mfe_48h": h4_mfe,
        "h4_mae_48h": h4_mae,
        "decision_tag": decision_tag,
        "h1_atr_ratio": h1_atr_ratio,
    })

all_trade_dates = sorted(trade_by_date.keys())

# ============================================================
# 入力4: signal_fires.csv（★v3 追加。signals_calendar v2 と同一の読み方）
# ============================================================
with open(FIRES_CSV, encoding="utf-8-sig") as f:
    raw_fire_rows = list(csv.DictReader(f))
assert "fire_id" in raw_fire_rows[0], f"BOM混入の疑い: 先頭キー={list(raw_fire_rows[0].keys())[0]!r}"

fires = []
for r in raw_fire_rows:
    d = datetime.strptime(r["date"], "%Y-%m-%d").date()
    hits = [label for col, label in FILTER_COLS if r.get(col) == "TRUE"]
    fires.append({
        "fid": r["fire_id"],
        "date": r["date"],
        "_d": d,
        "time_jst": r["time_jst"][11:16],
        "time_server": r["time_server"][5:16],
        "pattern": r["pattern"],
        "direction": r["direction"],
        "entry_price": _f(r["entry_price"]),
        "pass_all": r["pass_all"] == "TRUE",
        "filter_hits": hits,
        "atr_zone": r["atr_zone"],
        "h1_atr_ratio": _f(r["h1_atr_ratio"]),
        "h1_adx_zone": r["h1_adx_zone"],
        "h1_adx32": _f(r["h1_adx32"]),
        "h1_pattern": r["h1_pattern"],
        "h1_di_spread": _f(r["h1_di_spread"]),
        "h4_adx_zone": r["h4_adx_zone"],
        "h4_adx46": _f(r["h4_adx46"]),
        "h4_di_spread": _f(r["h4_di_spread"]),
        "h4_cross_dir": r["h4_cross_dir"],
        "h4_cross_bars": r["h4_cross_bars"],
        "cross_dir": r["cross_dir"],
        "d1_cross_bars": r["d1_cross_bars"],
        "d1_adx22": _f(r["d1_adx22"]),
        "d1_di_dir": r["d1_di_dir"],
        "mfe": [_f(r["mfe_12h"]), _f(r["mfe_24h"]), _f(r["mfe_36h"]), _f(r["mfe_48h"])],
        "mae": [_f(r["mae_12h"]), _f(r["mae_24h"]), _f(r["mae_36h"]), _f(r["mae_48h"])],
        "bars_traced": _f(r["bars_traced"]),
    })

fires.sort(key=lambda x: (x["date"], x["time_jst"], int(x["fid"])))
fires_by_date = defaultdict(list)
for fr in fires:
    fires_by_date[fr["_d"]].append(fr)

n_fires_total = len(fires)
n_fires_pass = sum(1 for fr in fires if fr["pass_all"])
n_fires_supp = n_fires_total - n_fires_pass

# ============================================================
# 入力5: ドロワー用トレードカードデータ（signals_calendar v2 と同一の読み方）
#   - pips は CSV 生値/100 = USD 価格幅（MFE/MAE と同スケール）
#   - 金額・ロットは出さない（視覚格下げ、指示書 §4.5）
# ============================================================
dtrades = []
dtrades_by_date = defaultdict(list)
if ENRICHED.exists():
    with open(ENRICHED, encoding="utf-8-sig") as f:
        e_rows = list(csv.DictReader(f))
    assert "trade_id" in e_rows[0], f"BOM混入の疑い: 先頭キー={list(e_rows[0].keys())[0]!r}"
    for r in e_rows:
        ej = (r.get("entry_jst") or "").strip()
        if not ej:
            continue
        try:
            d = datetime.strptime(ej[:10], "%Y-%m-%d").date()
        except ValueError:
            continue
        ex = (r.get("exit_jst") or "").strip()
        if ex:
            exit_disp = ex[11:16] if ex[:10] == ej[:10] else ex[5:16]
        else:
            exit_disp = "—"
        pips_raw = _f(r.get("pips"))
        dtrades.append({
            "tid": r.get("trade_id", "").strip(),
            "date": ej[:10],
            "_d": d,
            "entry_time": ej[11:16],
            "exit_disp": exit_disp,
            "direction": (r.get("direction") or "").upper(),
            "pips": None if pips_raw is None else pips_raw / 100.0,
            "style": (r.get("スタイル") or "").strip(),
            "star": (r.get("評価") or "").strip(),
            "tag": (r.get("反省") or "").strip(),
            "reason": (r.get("新規理由") or "").strip(),
            "mfe": [_f(r.get("h1_mfe_usd_12h")), _f(r.get("h1_mfe_usd_24h")),
                    _f(r.get("h1_mfe_usd_36h")), _f(r.get("h1_mfe_usd_48h"))],
            "mae": [_f(r.get("h1_mae_usd_12h")), _f(r.get("h1_mae_usd_24h")),
                    _f(r.get("h1_mae_usd_36h")), _f(r.get("h1_mae_usd_48h"))],
            "bars_traced": _f(r.get("h1_bars_traced_48h")),
        })
dtrades.sort(key=lambda t: (t["date"], t["entry_time"]))
for t in dtrades:
    dtrades_by_date[t["_d"]].append(t)
n_dtrades = len(dtrades)
n_dtrade_days = len(dtrades_by_date)

# ============================================================
# カレンダー期間 = 発火期間 ∪ トレード期間（389件全件表示のため）
# ============================================================
all_fire_dates = sorted(fires_by_date.keys())
period_first = min(all_fire_dates[0], all_trade_dates[0])
period_last = max(all_fire_dates[-1], all_trade_dates[-1])
start = period_first.replace(day=1)
end = (period_last.replace(day=28) + timedelta(days=4)).replace(day=1)

# ============================================================
# 日次合成スコア（calc_daily_score 現行式そのまま — 指示書 §4.2「変更禁止」）
# ============================================================
def calc_daily_score(h1_adx, h4_adx, d1_adx=None, d1_di_dir=None, h4_di_dir=None):
    """日次 H1×H4(+D1) 合成スコア (0-100) — v2.0 現行式そのまま"""
    if h1_adx is None or h4_adx is None:
        return None
    H1_norm = max(0.0, min(1.0, (h1_adx - 10.0) / 25.0))
    H4_norm = max(0.0, min(1.0, (h4_adx - 15.0) / 20.0))
    D1_norm = 0.0
    if d1_adx is not None:
        D1_norm = max(0.0, min(1.0, (d1_adx - 18.0) / 15.0))
    D1_aligned = 1 if (d1_di_dir == h4_di_dir and d1_di_dir in ("UP", "DOWN")) else 0
    score = H1_norm * 50.0 + H4_norm * 30.0 + D1_aligned * D1_norm * 20.0
    return round(min(100.0, score), 1)

# スコア段階化テーブル（v2.0 現行のまま、連続グラデ禁止）
SCORE_STEPS = [
    (80, 56, 100, "s5", 3),
    (60, 40, 85,  "s4", 1),
    (40, 28, 68,  "s3", 0),
    (20, 18, 50,  "s2", 0),
    (10, 12, 38,  "s1", 0),
]
SCORE_NAGI_MAX = 15  # スコア 15 未満は「レンジ」（旧ラベル「凪」、グレーの見た目は同一）

def score_step(score):
    if score is None or score < SCORE_NAGI_MAX:
        return None
    for lo, light, sat, name, glow in SCORE_STEPS:
        if score >= lo:
            return (light, sat, name, glow)
    return None

# ============================================================
# v3 背景色ロジック（指示書 §4.2 の核心）
# ============================================================
def _norm_dir(s):
    """DI方向文字列の正規化: daily CSV=BULL/BEAR/FLAT, weekly=UP/DOWN → UP/DOWN/FLAT"""
    if s in ("BULL", "UP"):
        return "UP"
    if s in ("BEAR", "DOWN"):
        return "DOWN"
    return "FLAT"

def v3_bg_style(rec):
    """v3 セル背景:
      強度（明度・彩度段階・グロウ）= 日次合成スコア（score_step）
      色相（青/赤）                = H1 DI spread の符号（週次fallback時は H4 に退避）
      確信度（彩度一段ダウン）     = H1×H4 DI 方向不一致
      レンジ判定                   = スコアのみ（h4_adx<15 条件は撤去）
    """
    empty = {"bg": "#0a0a12", "border": "#1a1a22", "label": "—",
             "is_nagi": True, "glow": "", "score": None,
             "dir_src": None, "di_match": None}
    if not rec:
        return dict(empty)
    h4_adx = rec.get("h4_adx46")
    h1_adx = rec.get("h1_avg_adx")
    d1_adx = rec.get("d1_adx22")
    d1_di_dir = rec.get("d1_di_dir")
    h4_di_dir = rec.get("h4_di_dir")
    h1_adx_for_score = rec.get("h1_adx_max") or h1_adx
    h4_adx_for_score = rec.get("h4_adx_max") or h4_adx
    score = calc_daily_score(h1_adx_for_score, h4_adx_for_score, d1_adx, d1_di_dir, h4_di_dir)
    if score is None and h4_adx is None:
        return dict(empty)

    # ── レンジ判定: スコアのみ（v3 核心変更。グレー2段の見た目は v2.0 踏襲）──
    if score is None or score < SCORE_NAGI_MAX:
        if score is not None and score < 10:
            gray, gray_b = 18, 22
        else:
            gray, gray_b = 30, 34
        return {
            "bg": f"rgb({gray},{gray},{gray_b})",
            "border": f"rgb({gray+12},{gray+12},{gray_b+12})",
            "label": "レンジ",
            "is_nagi": True,
            "glow": "",
            "score": score,
            "dir_src": None,
            "di_match": None,
        }

    step = score_step(score)
    if step is None:
        out = dict(empty)
        out["score"] = score
        return out
    lightness, step_sat, step_name, glow_strength = step

    # ── 方向ソース: H1 DI spread（無ければ H4 に退避 = 週次fallback日）──
    h1_spread = rec.get("h1_di_spread")
    if h1_spread is not None:
        dir_spread, dir_src = h1_spread, "H1"
    else:
        dir_spread, dir_src = rec.get("h4_di_spread"), "H4(fallback)"

    if dir_spread is None:
        hue, di_sat = 220, 0.3  # 方向データ欠損 → 中立青・低彩度
    else:
        norm = max(-1.0, min(1.0, dir_spread / 30.0))
        if norm > 0:
            hue = 220
            di_sat = 0.3 + 0.5 * norm
        else:
            hue = 0
            di_sat = 0.3 + 0.5 * abs(norm)

    # ── 確信度: H1×H4 DI 方向一致 → フル彩度 / 不一致 → 一段ダウン（段階、連続でない）──
    h1_dir = _norm_dir(rec.get("h1_di_dir"))
    h4_dir = _norm_dir(rec.get("h4_di_dir"))
    if dir_src.startswith("H4"):
        di_match = None  # H1 データ無し → 判定不能、ペナルティなし
        conf = 1.0
    elif h1_dir != "FLAT" and h4_dir != "FLAT" and h1_dir == h4_dir:
        di_match = True
        conf = 1.0
    else:
        di_match = False
        conf = 0.6  # 一段ダウン（迷い相場の表現）

    di_factor = 0.6 + 0.5 * (di_sat - 0.3)  # 0.6〜1.0（DI spread 強度、v2.0 踏襲）
    sat_pct = int(min(100, step_sat * di_factor * conf))
    bg = f"hsl({hue}, {sat_pct}%, {lightness}%)"
    if glow_strength >= 1:
        border_l = min(lightness + 22, 75)
        border_sat = min(100, sat_pct + 5)
    else:
        border_l = min(lightness + 12, 60)
        border_sat = sat_pct
    border = f"hsl({hue}, {border_sat}%, {border_l}%)"
    if glow_strength == 3:
        glow = f"box-shadow: 0 0 10px hsla({hue},{sat_pct}%,60%,0.55), inset 0 0 14px hsla({hue},{sat_pct}%,55%,0.35);"
    elif glow_strength == 2:
        glow = f"box-shadow: 0 0 7px hsla({hue},{sat_pct}%,55%,0.45), inset 0 0 10px hsla({hue},{sat_pct}%,50%,0.28);"
    elif glow_strength == 1:
        glow = f"box-shadow: 0 0 5px hsla({hue},{sat_pct}%,50%,0.35), inset 0 0 7px hsla({hue},{sat_pct}%,45%,0.20);"
    else:
        glow = ""
    label = "UP" if (dir_spread or 0) > 5 else ("DOWN" if (dir_spread or 0) < -5 else "拮抗")
    return {
        "bg": bg,
        "border": border,
        "label": label,
        "is_nagi": False,
        "glow": glow,
        "score": score,
        "dir_src": dir_src,
        "di_match": di_match,
    }

# ============================================================
# v2.0 互換の色判定（レポート比較用のみ。HTML には使わない）
# ============================================================
def v2_color_label(rec):
    """v2.0 の h4_bg_style 相当の「色ラベル」を返す（比較検証用）"""
    if not rec:
        return "—"
    h4_adx = rec.get("h4_adx46")
    h1_adx = rec.get("h1_avg_adx")
    di_spread = rec.get("h4_di_spread")
    h1_adx_for_score = rec.get("h1_adx_max") or h1_adx
    h4_adx_for_score = rec.get("h4_adx_max") or h4_adx
    score = calc_daily_score(h1_adx_for_score, h4_adx_for_score,
                             rec.get("d1_adx22"), rec.get("d1_di_dir"), rec.get("h4_di_dir"))
    if score is None and h4_adx is None:
        return "—"
    is_nagi_score = score is None or score < SCORE_NAGI_MAX
    is_nagi_adx = h4_adx is not None and h4_adx < 15  # v2.0 の H4 凪条件（v3 で撤去したもの）
    if is_nagi_score or is_nagi_adx:
        return "灰(凪)"
    step = score_step(score)
    if step is None:
        return "灰(凪)"
    if di_spread is None:
        return f"青{step[2]}(中立)"
    return (f"青{step[2]}" if di_spread > 0 else f"赤{step[2]}") + f"({di_spread:+.1f})"

def v3_color_label(rec):
    """v3_bg_style の「色ラベル」（比較検証用）"""
    st = v3_bg_style(rec)
    if st["score"] is None and st["is_nagi"]:
        return "—" if st["label"] == "—" else "灰(レンジ)"
    if st["is_nagi"]:
        return "灰(レンジ)"
    hue_txt = "青" if "hsl(220" in st["bg"] else "赤"
    step = score_step(st["score"])
    mm = "" if st["di_match"] in (True, None) else "/彩度↓"
    return f"{hue_txt}{step[2]}{mm}"

# ============================================================
# 月ループユーティリティ（月〜土の6列 — 土曜発火31件のため）
# ============================================================
def month_iter(s, e):
    cur = s
    while cur < e:
        yield cur
        cur = cur.replace(year=cur.year + 1, month=1) if cur.month == 12 else cur.replace(month=cur.month + 1)

def month_weekdays_sat(year, month):
    first = date(year, month, 1)
    start_d = first - timedelta(days=first.weekday())
    last_day = (date(year + 1, 1, 1) - timedelta(days=1)) if month == 12 else (date(year, month + 1, 1) - timedelta(days=1))
    end_dd = last_day + timedelta(days=(6 - last_day.weekday()))
    cur = start_d
    weeks_list, cur_week = [], []
    while cur <= end_dd:
        if cur.weekday() < 6:
            cur_week.append(cur)
        if cur.weekday() == 5:
            if cur_week:
                weeks_list.append(cur_week)
            cur_week = []
        cur += timedelta(days=1)
    if cur_week:
        weeks_list.append(cur_week)
    return weeks_list

# ============================================================
# HTML 生成
# ============================================================
html = []
html.append("""<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8">
<title>DAILY RESEARCH CALENDAR — v3</title>
<style>
* { box-sizing: border-box; }
body {
  margin: 0; background: #05090f; color: #8abaee;
  font-family: -apple-system, BlinkMacSystemFont, 'Hiragino Sans', sans-serif;
  font-size: 12px; padding: 20px;
}
h1 { font-size: 14px; color: #5a9adf; margin: 0 0 4px; letter-spacing: .08em; }
.sub { font-size: 10px; color: #2a4a6a; margin-bottom: 14px; }
.purpose {
  font-size: 10px; color: #4a6a8a; margin-bottom: 14px; line-height: 1.6;
  padding: 8px 12px; background: #080d16; border: 1px solid #162844; border-radius: 6px;
}
.purpose b { color: #6a8aaa; }

/* ===== タブ ===== */
.tabs {
  display: flex; gap: 4px; margin-bottom: 18px;
  border-bottom: 1px solid #162844;
}
.tab-btn {
  background: transparent; color: #4a6a8a;
  border: 1px solid transparent; border-bottom: none;
  padding: 8px 18px; font-size: 12px; cursor: pointer;
  letter-spacing: .04em; font-family: inherit;
  border-radius: 4px 4px 0 0;
  transition: background 0.15s, color 0.15s;
  margin-bottom: -1px;
}
.tab-btn:hover { color: #6a8aaa; background: rgba(20,40,68,0.3); }
.tab-btn.active {
  color: #5a9adf; background: #080d16;
  border-color: #162844; border-bottom: 1px solid #080d16;
  font-weight: 700;
}
.tab-pane { display: none; }
.tab-pane.active { display: block; }

/* ===== ツールバー（タブ1） ===== */
.toolbar {
  display: flex; flex-wrap: wrap; gap: 10px 18px;
  padding: 10px 14px; background: #080d16;
  border: 1px solid #162844; border-radius: 6px;
  margin-bottom: 12px; align-items: center;
  font-size: 10.5px;
}
.trade-toggle {
  background: #0a1320; color: #6a8aaa;
  border: 1px solid #1a3454; border-radius: 3px;
  padding: 3px 11px; font-size: 10.5px; cursor: pointer; font-family: inherit;
}
.trade-toggle.active { background: #3a2a0a; color: #ffd060; border-color: #6a5a2a; font-weight: 700; }

/* ===== 凡例 ===== */
.legend {
  display: flex; gap: 16px; margin-bottom: 18px; flex-wrap: wrap;
  font-size: 10px; color: #6a8aaa;
  padding: 12px 14px; background: #080d16;
  border: 1px solid #162844; border-radius: 6px;
}
.legend .grp { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.legend .ttl { color: #4a7aaa; font-weight: 600; margin-right: 4px; }
.legend .sw {
  width: 22px; height: 14px; border-radius: 2px; display: inline-block;
  border: 1px solid rgba(255,255,255,0.08);
}
.legend .lg-dot { font-size: 11px; }

/* ===== 月 ===== */
.month {
  margin-bottom: 24px; border: 1px solid #162844;
  border-radius: 6px; background: #080d16; padding: 12px;
}
.month-title { font-size: 13px; color: #5a9adf; margin-bottom: 2px; font-weight: 600; letter-spacing: .05em; }
.month-stats { font-size: 10px; color: #4a7aaa; margin-bottom: 8px; }
.dow-row { display: grid; grid-template-columns: repeat(6, 1fr); gap: 3px; padding: 0 3px; margin-bottom: 2px; }
.dow { text-align: center; font-size: 10px; color: #2a4a6a; font-weight: 600; padding: 3px 0; letter-spacing: .08em; }
.dow.sat { color: #3a5a8a; }
.week-cells {
  display: grid; grid-template-columns: repeat(6, 1fr); gap: 3px;
  background: rgba(0,0,0,0.2); padding: 3px; border-radius: 3px;
  margin-bottom: 4px;
}

/* ===== 日セル =====
 * 視覚要素は4つだけ: 背景色 / MFE/MAEバー / シグナルドット / トレードマーク
 * テキスト情報（H1 ADX・スコア・金額・タグ）は廃止 → ホバー/ドロワーへ降格
 */
.cell {
  border-radius: 4px;
  display: grid;
  grid-template-rows: 15px 1fr 17px;  /* 日付 / 環境色+バー / シグナルドット */
  min-height: 86px;
  position: relative;
  background: #05090f;
  border: 1px solid #0b1825;
  overflow: hidden;
}
.cell.outside { opacity: 0.15; }
.cell.has-fires, .cell.has-trade { cursor: pointer; }
.cell.has-fires:hover, .cell.has-trade:hover { border-color: #2a5a9a; }
.cell.drill-open { border-color: #4a90e2; box-shadow: inset 0 0 0 1px #4a90e2; }

.cell .day-hdr {
  display: flex; justify-content: flex-start; align-items: center;
  padding: 1px 5px;
  font-size: 10px; font-weight: 600; color: #6a8aaa;
  background: rgba(0,0,0,0.3);
}

/* 環境レーン（背景色 = 強度×方向、中央 = MFE/MAE バー） */
.cell .env-main {
  position: relative;
  display: flex; align-items: center; justify-content: center;
  padding: 0 5px;
}
/* MFE/MAE バー（中央 tick から左右へ。トレード日 = 実測 / 非トレード日 = 仮想レンジ） */
.cell .env-main .vbar {
  width: 92%; height: 5px;
  position: relative;
  background: rgba(0,0,0,0.35);
  border-radius: 1px;
}
.cell .env-main .vbar .tick {
  position: absolute; left: 50%; top: -2px; bottom: -2px;
  width: 1px; background: rgba(255,255,255,0.42); z-index: 2;
}
/* トレード日（実測 H4 48h: 右=MFE伸 / 左=MAE踏） */
.cell .env-main .vbar .b-mfe {
  position: absolute; left: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(90,184,255,0.6), rgba(90,184,255,0.95));
  border-radius: 0 1px 1px 0;
}
.cell .env-main .vbar .b-mae {
  position: absolute; right: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(239,96,96,0.95), rgba(239,96,96,0.6));
  border-radius: 1px 0 0 1px;
}
/* 非トレード日（仮想 JST14:00 48h 値動きレンジ: 右=上方向 / 左=下方向、淡色） */
.cell .env-main .vbar.virtual { opacity: 0.72; }
.cell .env-main .vbar .b-up {
  position: absolute; left: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(110,180,230,0.5), rgba(110,180,230,0.85));
  border-radius: 0 1px 1px 0;
}
.cell .env-main .vbar .b-down {
  position: absolute; right: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(220,120,120,0.85), rgba(220,120,120,0.5));
  border-radius: 1px 0 0 1px;
}

/* シグナルドット行（signals_calendar v2 と同一視覚言語） */
.cell .fires-box {
  display: flex; flex-wrap: wrap; align-content: flex-start;
  gap: 0 2px; padding: 1px 4px;
  background: rgba(0,0,0,0.3);
  overflow: hidden;
}
.fire-dot {
  font-size: 10px; line-height: 1.2;
  text-shadow: 0 1px 2px rgba(0,0,0,0.7);
}
.fire-dot.suppressed { opacity: 0.3; }  /* pass_all=FALSE: 実機なら見えなかった発火 */

/* トレードマーク（枠線 + 方向▲▼、signals_calendar v2 と同言語、デフォルトON） */
.cell .trade-mark {
  display: none;
  position: absolute; right: 3px; top: 1px;
  font-size: 9px; font-weight: 700; color: #ffd060;
  text-shadow: 0 1px 2px rgba(0,0,0,0.8);
  letter-spacing: .04em;
  z-index: 3;
}
body.show-trades .cell.has-trade { box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); }
body.show-trades .cell .trade-mark { display: block; }

/* ===== ドロワー（signals_calendar v2 流用） ===== */
#drill {
  position: fixed; top: 0; right: 0; bottom: 0; width: 400px;
  background: #08111c; border-left: 1px solid #1a3454;
  box-shadow: -6px 0 18px rgba(0,0,0,0.55);
  z-index: 100; display: none; flex-direction: column;
}
#drill.open { display: flex; }
#drill .drill-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 12px 14px; border-bottom: 1px solid #1a2a44;
}
#drill .drill-title { font-size: 13px; color: #b0c8e8; font-weight: 600; letter-spacing: .04em; }
#drill .drill-close {
  background: #0e1a2a; color: #b8d0ee; border: 1px solid #1a3454;
  border-radius: 3px; padding: 3px 10px; font-size: 11px; cursor: pointer; font-family: inherit;
}
#drill .drill-close:hover { background: #142844; }
#drill .drill-note { font-size: 9px; color: #4a6a8a; padding: 6px 14px 0; line-height: 1.5; }
#drill .drill-body { flex: 1; overflow-y: auto; padding: 10px 14px 20px; }
#drill .drill-env {
  font-size: 10px; color: #8abaee; line-height: 1.7;
  padding: 8px 12px; margin-bottom: 10px;
  background: #0a1320; border: 1px solid #1a2a44; border-radius: 6px;
}
#drill .drill-env .k { color: #4a6a8a; margin-right: 3px; }
#drill .drill-env .v { color: #c8d8e8; margin-right: 9px; }

.fire-card {
  border: 1px solid #1a2a44; border-radius: 6px;
  background: #0a1320; margin-bottom: 10px; padding: 10px 12px;
}
.fire-card.suppressed { opacity: 0.55; border-style: dashed; }
.fire-card .fc-head {
  display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
  font-size: 12px; font-weight: 700;
}
.fire-card .fc-pat {
  padding: 1px 7px; border-radius: 3px; font-size: 11px;
  color: #05090f; letter-spacing: .03em;
}
.fire-card .fc-time { color: #c8d8e8; font-weight: 600; }
.fire-card .fc-server { color: #4a6a8a; font-size: 9.5px; font-weight: 400; }
.fire-card .fc-pass { margin-left: auto; font-size: 10px; font-weight: 700; }
.fire-card .fc-pass.ok { color: #5ad88a; }
.fire-card .fc-pass.ng { color: #c87a4a; }
.fire-card .fc-row { font-size: 10.5px; color: #8abaee; line-height: 1.7; }
.fire-card .fc-row .k { color: #4a6a8a; margin-right: 3px; }
.fire-card .fc-row .v { color: #c8d8e8; margin-right: 9px; }
.fire-card .fc-row .raw { color: #4a6a8a; font-size: 9px; }
.fire-card .fc-filters { font-size: 10px; margin-top: 4px; }
.fire-card .fc-filters.hit { color: #e0a060; }
.fire-card .fc-filters.nohit { color: #4a8a6a; }
.mm-steps { margin-top: 7px; }
.mm-steps .mm-ttl { font-size: 9px; color: #4a6a8a; margin-bottom: 3px; letter-spacing: .04em; }
.mm-row { display: grid; grid-template-columns: 26px 1fr 1fr; gap: 0 6px; align-items: center; margin-bottom: 2px; }
.mm-row .mm-h { font-size: 9px; color: #4a6a8a; text-align: right; font-variant-numeric: tabular-nums; }
.mm-bar-wrap { position: relative; height: 10px; background: rgba(0,0,0,0.35); border-radius: 1px; }
.mm-bar { position: absolute; top: 1px; bottom: 1px; border-radius: 1px; }
.mm-bar.mae { right: 0; background: linear-gradient(90deg, rgba(239,96,96,0.85), rgba(239,96,96,0.5)); }
.mm-bar.mfe { left: 0; background: linear-gradient(90deg, rgba(90,184,255,0.5), rgba(90,184,255,0.85)); }
.mm-num { position: absolute; top: -1px; font-size: 8.5px; font-variant-numeric: tabular-nums; }
.mm-bar-wrap.w-mae .mm-num { left: 3px; color: #ef9090; }
.mm-bar-wrap.w-mfe .mm-num { right: 3px; color: #8ac8ff; }
.mm-legend { display: flex; gap: 10px; font-size: 8.5px; color: #4a6a8a; margin-top: 2px; }
.mm-legend .mfe-k { color: #8ac8ff; }
.mm-legend .mae-k { color: #ef9090; }

.trade-sec-hdr {
  display: flex; align-items: center; gap: 8px;
  margin: 16px 0 8px; font-size: 10px; font-weight: 700;
  color: #d8b060; letter-spacing: .08em;
}
.trade-sec-hdr::before, .trade-sec-hdr::after {
  content: ""; flex: 1; height: 1px; background: #4a3c1a;
}
.trade-card {
  border: 1px solid #4a3c1a; border-radius: 6px;
  background: #0e0c07; margin-bottom: 10px; padding: 10px 12px;
}
.trade-card .tc-head {
  display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
  font-size: 12px; font-weight: 700;
}
.trade-card .tc-dir {
  padding: 1px 7px; border-radius: 3px; font-size: 11px;
  color: #ffd060; background: rgba(255,208,96,0.10);
  border: 1px solid #6a5a2a; letter-spacing: .03em;
}
.trade-card .tc-time { color: #c8d8e8; font-weight: 600; }
.trade-card .tc-pips {
  margin-left: auto; font-size: 12px; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.trade-card .tc-pips.pos { color: #5ab8ff; }
.trade-card .tc-pips.neg { color: #ef6060; }
.trade-card .tc-pips.flat { color: #8a9ab0; }
.trade-card .tc-meta { font-size: 10.5px; color: #c8d8e8; display: flex; gap: 12px; flex-wrap: wrap; }
.trade-card .tc-meta .k { color: #6a5a3a; margin-right: 3px; }
.trade-card .tc-tag { color: #d8c890; }
.trade-card .tc-tag.other { color: #5a6a7a; }
.trade-card .tc-reason { margin-top: 8px; font-size: 10px; }
.trade-card .tc-reason summary {
  cursor: pointer; color: #6a5a3a; user-select: none; letter-spacing: .04em;
}
.trade-card .tc-reason summary:hover { color: #a89060; }
.trade-card .tc-reason[open] summary { color: #c8a860; }
.trade-card .tc-reason-body {
  margin-top: 6px; color: #a8b8cc; line-height: 1.7;
  white-space: pre-wrap; background: rgba(0,0,0,0.35);
  padding: 8px 10px; border-radius: 4px;
}

.notes { margin-top: 10px; font-size: 10px; color: #4a6a8a; line-height: 1.6; }
.notes b { color: #6a8aaa; }

/* ===== タブ2: 詳細分析（v2.0 から欠落なく移設） ===== */
.overview-summary {
  margin-bottom: 18px; padding: 14px 16px;
  background: #080d16; border: 1px solid #162844; border-radius: 6px;
  display: flex; flex-wrap: wrap; gap: 22px; font-size: 11px;
}
.overview-summary .stat-blk { display: flex; flex-direction: column; gap: 2px; }
.overview-summary .stat-k { font-size: 9.5px; color: #4a6a8a; letter-spacing: .05em; }
.overview-summary .stat-v {
  font-size: 16px; color: #8abaee; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.overview-summary .stat-v.pos { color: #5ab8ff; }
.overview-summary .stat-v.neg { color: #ef6060; }
.overview-warning {
  margin-bottom: 18px; padding: 10px 14px;
  background: rgba(200,180,80,0.08);
  border: 1px solid rgba(200,180,80,0.25); border-radius: 6px;
  font-size: 10.5px; color: rgba(220,200,140,0.85); line-height: 1.6;
}
.overview-warning b { color: rgba(240,220,160,1); }
.pie-grid {
  display: grid; grid-template-columns: repeat(2, 1fr);
  gap: 14px; margin-bottom: 18px;
}
.pie-card {
  background: #080d16; border: 1px solid #162844; border-radius: 6px;
  padding: 14px; display: flex; flex-direction: column;
}
.pie-card-title { font-size: 12px; color: #5a9adf; font-weight: 600; letter-spacing: .04em; margin-bottom: 4px; }
.pie-card-sub { font-size: 9.5px; color: #4a6a8a; margin-bottom: 12px; line-height: 1.5; }
.pie-card-body { display: grid; grid-template-columns: 140px 1fr; gap: 14px; align-items: center; }
.pie-svg-wrap { display: flex; align-items: center; justify-content: center; }
.pie-svg { display: block; }
.pie-slice { cursor: pointer; transition: opacity 0.15s, filter 0.15s, transform 0.15s; }
.pie-svg .pie-slice:hover { filter: brightness(1.18) saturate(1.1); }
.pie-svg .pie-slice.pie-slice-active { filter: brightness(1.25) drop-shadow(0 0 4px rgba(160,200,255,0.55)); }
.pie-legend-row.pie-slice { padding: 1px 4px; border-radius: 2px; }
.pie-legend-row.pie-slice:hover { background: rgba(40,70,110,0.20); }
.pie-legend-row.pie-slice.pie-slice-active {
  background: rgba(74,144,226,0.18);
  outline: 1px solid rgba(120,170,230,0.45);
}
.pie-legend { display: flex; flex-direction: column; gap: 4px; font-size: 10px; font-variant-numeric: tabular-nums; }
.pie-legend-row { display: grid; grid-template-columns: 12px 1fr auto auto; gap: 6px; align-items: center; }
.pie-legend-sw { width: 12px; height: 12px; border-radius: 2px; border: 1px solid rgba(255,255,255,0.08); }
.pie-legend-k { color: #c8d8e8; }
.pie-legend-n { color: #6a8aaa; font-weight: 600; text-align: right; }
.pie-legend-pct { color: #4a6a8a; font-size: 9px; text-align: right; min-width: 32px; }
.pie-empty { font-size: 10px; color: #3a5a7a; padding: 30px 0; text-align: center; }

.sig-table tbody tr[data-pattern] { transition: background 0.15s; }
.drilldown-wrap {
  margin-top: 14px; padding: 14px;
  background: #08111c; border: 1px solid #1a2a44; border-radius: 6px;
}
.drilldown-head { margin-bottom: 10px; }
.drilldown-title { font-size: 13px; color: #b0c8e8; font-weight: 600; letter-spacing: .04em; margin-bottom: 4px; }
.drilldown-summary {
  padding: 8px 12px; background: #0a1525;
  border-left: 3px solid #4a90e2; border-radius: 3px;
  font-size: 11px; color: #b8d0ee; margin-bottom: 6px;
}
.drilldown-summary b { color: #8aa8ce; font-weight: 500; margin-right: 4px; }
.drilldown-hint { font-size: 10px; color: #6a8aaa; opacity: 0.85; display: flex; align-items: center; gap: 10px; }
.drill-clear-btn {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #1a3454; border-radius: 3px;
  padding: 3px 9px; font-size: 10px; cursor: pointer;
  font-family: inherit;
  transition: background 0.15s, border-color 0.15s;
}
.drill-clear-btn:hover { background: #142844; border-color: #2a4a74; }
.drill-table th[data-sort="asc"]::after { content: " ▲"; color: #4a90e2; font-size: 9px; }
.drill-table th[data-sort="desc"]::after { content: " ▼"; color: #4a90e2; font-size: 9px; }
.detail-table th[data-sort="asc"]::after { content: " ▲"; color: #4a90e2; font-size: 9px; }
.detail-table th[data-sort="desc"]::after { content: " ▼"; color: #4a90e2; font-size: 9px; }
.pivot-hint { font-size: 10px; color: #6a8aaa; opacity: 0.85; margin-top: 6px; padding: 0 4px; }

.detail-head { padding: 0 4px 12px; }
.detail-title { font-size: 14px; color: #b0c8e8; font-weight: 600; letter-spacing: .05em; margin-bottom: 4px; }
.detail-sub { font-size: 11px; color: #6a8aaa; line-height: 1.5; }
.detail-sub b { color: #d0a060; }
.filter-bar {
  display: flex; flex-wrap: wrap; gap: 10px 14px;
  padding: 12px 14px; background: #08111c;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 10px; align-items: center;
}
.filter-bar label {
  font-size: 10px; color: #7a9ac0;
  display: flex; align-items: center; gap: 5px;
  letter-spacing: .03em;
}
.filter-bar select {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #2a4060; padding: 3px 8px;
  border-radius: 4px; font-size: 11px;
  font-family: inherit; cursor: pointer;
}
.filter-bar select:hover { border-color: #4a6090; }
.f-reset {
  background: #2a3050; color: #b0c0d8; border: 1px solid #4a5070;
  padding: 4px 12px; border-radius: 4px; font-size: 10px;
  cursor: pointer; font-family: inherit;
}
.f-reset:hover { background: #3a4060; }
.pivot-bar {
  padding: 8px 14px; background: #0a1320;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 10px;
}
.pivot-bar label {
  font-size: 10px; color: #7a9ac0;
  display: inline-flex; align-items: center; gap: 6px;
  letter-spacing: .03em;
}
.pivot-bar select {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #2a4060; padding: 3px 8px;
  border-radius: 4px; font-size: 11px; cursor: pointer;
}
.result-summary {
  padding: 10px 14px; background: #08121f;
  border-left: 3px solid #4a90e2; border-radius: 3px;
  margin-bottom: 10px; font-size: 12px; color: #b8d0ee;
  letter-spacing: .02em;
}
.result-summary b { color: #8aa8ce; font-weight: 500; margin-right: 4px; }
.pivot-table, .detail-table {
  width: 100%; border-collapse: collapse;
  margin-bottom: 10px; font-size: 11px;
}
.pivot-table th, .detail-table th {
  background: #0e1a2a; color: #a8c0e0; padding: 7px 10px;
  text-align: left; border-bottom: 1px solid #2a4060;
  font-weight: 500; letter-spacing: .03em;
}
.pivot-table td, .detail-table td {
  padding: 5px 10px; border-bottom: 1px solid #0e1828;
  color: #b8d0ee;
}
.pivot-table tr:hover, .detail-table tr:hover { background: #0a1525; }
.detail-table td.pos { color: #ffe080; font-weight: 500; }
.detail-table td.neg { color: #8090a0; }
.detail-table td.zero { color: #5a5a65; }
.trade-detail summary {
  cursor: pointer; padding: 8px 14px;
  background: #0a1320; border: 1px solid #1a2a44;
  border-radius: 4px; font-size: 11px; color: #8aa8ce;
  margin-bottom: 8px; letter-spacing: .03em;
}
.trade-detail summary:hover { background: #0e1a2a; }
.trade-detail[open] summary { background: #0e1a2a; }
</style></head><body class="show-trades">
""")

gen_ts = datetime.now().strftime("%Y-%m-%d %H:%M")
html.append('<h1>DAILY RESEARCH CALENDAR — v3</h1>')
html.append(f'<div class="sub">入力: {src.name} + {FIRES_CSV.name} / '
            f'発火 {n_fires_total}件 (pass {n_fires_pass} / 抑制 {n_fires_supp}) / '
            f'実トレード {n_dtrades}件・{n_dtrade_days}日 / '
            f'日次集計 {len(daily_agg_map)}日 / '
            f'期間: {period_first:%Y-%m-%d} 〜 {period_last:%Y-%m-%d} / '
            f'バー正規化基準(p95): {BAR_NORM_BASE:.0f} USD / 生成: {gen_ts}</div>')
html.append('<div class="purpose"><b>認識ターゲット:</b> どう相場が動いて（色 + MFE/MAEバー）、'
            'そこにシグナル（v4発火ドット）とトレード実弾（枠+▲▼）がどう機能したか。3つの<b>結果の見比べ</b>。'
            ' 色相 = <b>H1 DI</b>（日次の結果。D1 ADX は戦略側の「因果」なので色に混ぜない）。'
            ' 強度 = 日次合成スコア段階。<b>不一致（H1×H4 DI）は彩度ダウン = 迷い相場</b>。'
            ' グレー = レンジ（スコア&lt;15。ADX/スコアベースの判定。ATR収束の「凪」とは別概念）。'
            ' セルクリック → 右ドロワーにシグナルカード + 実トレードカード。</div>')

# ===== タブナビゲーション（2タブ） =====
html.append('<div class="tabs">')
html.append('<button class="tab-btn" data-tab="calendar">全体像</button>')
html.append('<button class="tab-btn" data-tab="detail">詳細分析</button>')
html.append('</div>')

# ============================================================
# タブ1: 全体像カレンダー
# ============================================================
html.append('<div class="tab-pane" id="tab-calendar">')

# ツールバー
html.append('<div class="toolbar">')
html.append('<button class="trade-toggle active" id="trade-toggle">実トレード表示 ON</button>')
html.append('<span style="color:#4a6a8a;">OFF にすると「シグナルのみ」表示に即切替</span>')
html.append('</div>')

# 凡例
html.append('<div class="legend">')
html.append('<div class="grp"><span class="ttl">背景色（強度=スコア段階 / 色相=H1 DI方向）:</span>')
html.append('<span class="sw" style="background:rgb(30,30,34);"></span>レンジ (スコア&lt;15)')
html.append('<span class="sw" style="background:hsl(220,38%,12%);"></span>15+')
html.append('<span class="sw" style="background:hsl(220,50%,18%);"></span>20+')
html.append('<span class="sw" style="background:hsl(220,68%,28%);"></span>40+')
html.append('<span class="sw" style="background:hsl(220,85%,40%);box-shadow:0 0 5px hsla(220,85%,50%,0.35);"></span>60+')
html.append('<span class="sw" style="background:hsl(220,100%,56%);box-shadow:0 0 10px hsla(220,100%,60%,0.55);"></span>80+')
html.append('<span class="sw" style="background:hsl(0,85%,40%);box-shadow:0 0 5px hsla(0,85%,50%,0.35);margin-left:8px;"></span>H1 DI− (赤系)')
html.append('<span class="sw" style="background:hsl(220,40%,28%);margin-left:8px;"></span>彩度↓ = H1×H4 DI不一致（迷い）')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">中央バー:</span>')
html.append('<span style="color:#5ab8ff;font-weight:700;">右=MFE伸/上方向</span>')
html.append('<span style="color:#ef6060;font-weight:700;">左=MAE踏/下方向</span>')
html.append(f'<span style="opacity:0.6;font-size:9px;">トレード日=実測(H4 48h) / 非トレード日=仮想レンジ(JST14:00, 淡色) / バー長=p95 {BAR_NORM_BASE:.0f}USD 基準。数値はホバーで</span>')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">ドット=v4発火 (色=パターン):</span>')
for p in PATTERNS:
    html.append(f'<span class="lg-dot"><span style="color:{PATTERN_COLORS[p]["BUY"]};">▲</span>'
                f'<span style="color:{PATTERN_COLORS[p]["SELL"]};">▼</span> {p}</span>')
html.append('<span class="lg-dot" style="opacity:0.3;color:#FFD700;">▲</span>'
            '<span>薄=pass_all=FALSE（実機非表示の発火）</span>')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">実トレード:</span>'
            '<span style="box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); padding:1px 6px; border-radius:3px;">枠</span>'
            '<span style="color:#ffd060;font-weight:700;">▲/▼=エントリー方向</span>'
            '<span style="opacity:0.6;">詳細（pips・MFE/MAE推移・タグ）は日クリック</span></div>')
html.append('</div>')

# ===== 月ループ（6列・月〜土） =====
emitted_dot_count = 0
emitted_dot_fids = []
cell_dates_rendered = set()
emitted_trade_cells = set()
emitted_trade_marks = 0
DOW_LABELS6 = ["月", "火", "水", "木", "金", "土"]
DOW_JA = ["月", "火", "水", "木", "金", "土", "日"]

for m_start in month_iter(start, end):
    weeks_list = month_weekdays_sat(m_start.year, m_start.month)
    m_fires = [fr for d, frs in fires_by_date.items()
               if d.year == m_start.year and d.month == m_start.month for fr in frs]
    m_pass = sum(1 for fr in m_fires if fr["pass_all"])
    m_trades = [t for d, ts in dtrades_by_date.items()
                if d.year == m_start.year and d.month == m_start.month for t in ts]

    html.append('<div class="month">')
    html.append(f'<div class="month-title">{m_start.year}年 {m_start.month}月</div>')
    html.append(f'<div class="month-stats">発火 {len(m_fires)}件（pass {m_pass} / 抑制 {len(m_fires)-m_pass}）'
                f' / 実トレード {len(m_trades)}件</div>')
    html.append('<div class="dow-row">')
    for i, dow in enumerate(DOW_LABELS6):
        html.append(f'<div class="dow{" sat" if i == 5 else ""}">{dow}</div>')
    html.append('</div>')

    for week_days in weeks_list:
        html.append('<div class="week-cells">')
        for d in week_days:
            is_outside = d.month != m_start.month
            if is_outside:
                # outside セルはドット/マークを描かない（隣月二重描画防止 → 389件保証）
                html.append(f'<div class="cell outside"><div class="day-hdr"><span>{d.day}</span></div>'
                            '<div class="env-main"></div><div class="fires-box"></div></div>')
                continue

            cell_dates_rendered.add(d)
            rec = get_rec(d)
            st = v3_bg_style(rec)
            day_fires = fires_by_date.get(d, [])
            day_trades_fx = trade_by_date.get(d, [])     # MFE/MAE バー用（FX CSV + enriched）
            day_dtrades = dtrades_by_date.get(d, [])     # マーク + ドロワー用（enriched）

            classes = ["cell"]
            if day_fires:
                classes.append("has-fires")
            if day_dtrades:
                classes.append("has-trade")

            # ── ホバー（title）= その日のサマリー（数値はここに降格） ──
            tip = [f"{d:%Y-%m-%d} ({DOW_JA[d.weekday()]})"]
            if rec:
                if st["score"] is not None:
                    tip.append(f"スコア={st['score']:.1f}" + ("（レンジ）" if st["is_nagi"] else ""))
                if rec.get("h1_di_spread") is not None:
                    tip.append(f"H1 DI spread={rec['h1_di_spread']:+.1f}")
                if rec.get("h4_di_spread") is not None:
                    tip.append(f"H4 DI spread={rec['h4_di_spread']:+.1f}")
                if st["di_match"] is False:
                    tip.append("H1×H4 DI不一致（彩度↓）")
                if st["dir_src"] == "H4(fallback)":
                    tip.append("方向ソース=H4（週次fallback、H1 DI無し）")
                if rec.get("h1_avg_adx") is not None:
                    h1m = rec.get("h1_adx_max")
                    tip.append(f"H1 ADX mean/max={rec['h1_avg_adx']:.1f}/{h1m:.1f}" if h1m is not None
                               else f"H1 ADX={rec['h1_avg_adx']:.1f}")
                if rec.get("h4_adx46") is not None:
                    h4m = rec.get("h4_adx_max")
                    tip.append(f"H4 ADX mean/max={rec['h4_adx46']:.1f}/{h4m:.1f}" if h4m is not None
                               else f"H4 ADX46={rec['h4_adx46']:.1f}")
                if rec.get("d1_pattern"):
                    tip.append(f"D1 pattern={rec['d1_pattern']}（因果・参考）")
                if rec.get("d1_adx22") is not None:
                    tip.append(f"D1 ADX22={rec['d1_adx22']:.1f}")
                ph = rec.get("h4_phase_auto")
                if ph and ph != "—":
                    tip.append(f"H4 Phase={ph}")
            if day_fires:
                n_p = sum(1 for fr in day_fires if fr["pass_all"])
                tip.append(f"発火 {len(day_fires)}件 (pass {n_p}/抑制 {len(day_fires)-n_p})")
                for fr in day_fires:
                    tip.append(f"{fr['time_jst']} {fr['pattern']} {fr['direction']} ({'pass' if fr['pass_all'] else '抑制'})")
            if day_trades_fx:
                mfes = [t["h4_mfe_48h"] for t in day_trades_fx if t.get("h4_mfe_48h") is not None]
                maes = [t["h4_mae_48h"] for t in day_trades_fx if t.get("h4_mae_48h") is not None]
                if mfes:
                    tip.append(f"実測 H4 48h MFE={max(mfes):.1f} USD")
                if maes:
                    tip.append(f"実測 H4 48h MAE={max(maes):.1f} USD")
                total_pl = sum(t["pl"] for t in day_trades_fx)
                tip.append(f"損益 ¥{total_pl:+,.0f}（金額はホバー/ドロワーのみ）")
            for t in day_dtrades:
                tip.append(f"実トレード {t['entry_time']} {t['direction']}")
            if not day_trades_fx:
                virtual_tip = daily_mfe_mae_map.get(d)
                if virtual_tip and virtual_tip["buy_mfe"] is not None:
                    tip.append(f"仮想(JST14:00) 上={max(v for v in (virtual_tip['buy_mfe'], virtual_tip['sell_mae']) if v is not None):.1f}"
                               f" 下={max(v for v in (virtual_tip['buy_mae'], virtual_tip['sell_mfe']) if v is not None):.1f} USD")
            title = " | ".join(tip)

            html.append(f'<div class="{" ".join(classes)}" data-date="{d:%Y-%m-%d}" title="{title}">')
            html.append(f'<div class="day-hdr"><span>{d.day}</span></div>')

            # ── 環境レーン: 背景色 + MFE/MAE バー（テキストなし） ──
            html.append(f'<div class="env-main" style="background:{st["bg"]}; border-top:1px solid {st["border"]};{st["glow"]}">')
            if day_trades_fx:
                mfes = [t["h4_mfe_48h"] for t in day_trades_fx if t.get("h4_mfe_48h") is not None]
                maes = [t["h4_mae_48h"] for t in day_trades_fx if t.get("h4_mae_48h") is not None]
                mfe_v = max(mfes) if mfes else None
                mae_v = max(maes) if maes else None
                if mfe_v is not None or mae_v is not None:
                    mfe_pct = min(100, (mfe_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    mae_pct = min(100, (mae_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    html.append('<div class="vbar">'
                                f'<div class="b-mae" style="width:{mae_pct:.1f}%;"></div>'
                                f'<div class="b-mfe" style="width:{mfe_pct:.1f}%;"></div>'
                                '<div class="tick"></div></div>')
            else:
                virtual = daily_mfe_mae_map.get(d)
                if virtual and (virtual["buy_mfe"] is not None or virtual["sell_mfe"] is not None):
                    up_vals = [v for v in (virtual["buy_mfe"], virtual["sell_mae"]) if v is not None]
                    dn_vals = [v for v in (virtual["buy_mae"], virtual["sell_mfe"]) if v is not None]
                    up_v = max(up_vals) if up_vals else None
                    dn_v = max(dn_vals) if dn_vals else None
                    up_pct = min(100, (up_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    dn_pct = min(100, (dn_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    html.append('<div class="vbar virtual">'
                                f'<div class="b-down" style="width:{dn_pct:.1f}%;"></div>'
                                f'<div class="b-up" style="width:{up_pct:.1f}%;"></div>'
                                '<div class="tick"></div></div>')
            html.append('</div>')

            # ── シグナルドット行（signals_calendar v2 と同一視覚言語、全件描画） ──
            html.append('<div class="fires-box">')
            for fr in day_fires:
                col = PATTERN_COLORS[fr["pattern"]][fr["direction"]]
                glyph = "▲" if fr["direction"] == "BUY" else "▼"
                supp_cls = "" if fr["pass_all"] else " suppressed"
                html.append(f'<span class="fire-dot{supp_cls}" data-fid="{fr["fid"]}" '
                            f'style="color:{col};">{glyph}</span>')
                emitted_dot_count += 1
                emitted_dot_fids.append(fr["fid"])
            html.append('</div>')

            # ── トレードマーク（枠線 + ▲▼） ──
            if day_dtrades:
                marks = "".join("▲" if t["direction"] == "BUY" else "▼" for t in day_dtrades)
                html.append(f'<span class="trade-mark">{marks}</span>')
                emitted_trade_cells.add(d)
                emitted_trade_marks += len(day_dtrades)

            html.append('</div>')  # cell
        html.append('</div>')  # week-cells
    html.append('</div>')  # month

html.append('<div class="notes">'
            '<b>注:</b> 色相 = H1 DI spread の符号（日次CSVの close 確定値。週次fallback日のみ H4 退避、ホバーに明記）。'
            ' 強度 = 日次合成スコア段階（H1 50% / H4 30% / D1整合 20%、現行式）。'
            ' グレー = レンジ（スコア&lt;15。ADXベース判定であり、ATR収束の「凪」とは別概念）。'
            ' 彩度ダウン = H1×H4 DI 方向不一致（迷い相場）。'
            ' バー = 値動きの形（実測 or JST14:00 仮想、48h固定、USD建て、全期間p95正規化）。'
            ' 数値・金額はホバーとドロワーへ降格 — 一覧面は認識、詳細は掘った人だけ。'
            ' 月別・累計の損益/勝率サマリーは置かない（研究ルール準拠）。'
            '</div>')

html.append('</div>')  # tab-pane calendar

# ============================================================
# ドロワー（signals_calendar v2 流用）+ JSON 埋め込み
# ============================================================
fires_json = [{k: v for k, v in fr.items() if k != "_d"} for fr in fires]
fires_blob = json.dumps(fires_json, ensure_ascii=False).replace("</", "<\\/")
colors_blob = json.dumps(PATTERN_COLORS)
dtrades_json = [{k: v for k, v in t.items() if k != "_d"} for t in dtrades]
dtrades_blob = json.dumps(dtrades_json, ensure_ascii=False).replace("</", "<\\/")
# 日次環境サマリー（ドロワー上部用: スコア・方向・一致）
env_json = {}
for d in sorted(cell_dates_rendered):
    rec = get_rec(d)
    if not rec:
        continue
    st = v3_bg_style(rec)
    env_json[f"{d:%Y-%m-%d}"] = {
        "score": st["score"],
        "label": "レンジ" if st["is_nagi"] else st["label"],
        "h1_spread": rec.get("h1_di_spread"),
        "h4_spread": rec.get("h4_di_spread"),
        "di_match": st["di_match"],
        "dir_src": st["dir_src"],
    }
env_blob = json.dumps(env_json, ensure_ascii=False).replace("</", "<\\/")

html.append('<div id="drill">'
            '<div class="drill-head"><span class="drill-title" id="drill-title"></span>'
            '<button class="drill-close" id="drill-close">閉じる ✕</button></div>'
            '<div class="drill-note">サーバー時間 = チャート表示時間（照合用）。'
            '薄カード = pass_all=FALSE（実機チャート非表示の発火）。バー長 = カード内の最大値基準（伸び方の形を見る用）。'
            'トレードカードの pips は価格幅（USD、MFE/MAE と同スケール）。金額・ロットは出さない。</div>'
            '<div class="drill-body" id="drill-body"></div></div>')

html.append("<script>")
html.append(f"const FIRES = {fires_blob};")
html.append(f"const PAT_COLORS = {colors_blob};")
html.append(f"const DTRADES = {dtrades_blob};")
html.append(f"const DAY_ENV = {env_blob};")
html.append("""
// ============ インデックス ============
const firesByDate = {};
for (const f of FIRES) {
  (firesByDate[f.date] = firesByDate[f.date] || []).push(f);
}
const dtradesByDate = {};
for (const t of DTRADES) {
  (dtradesByDate[t.date] = dtradesByDate[t.date] || []).push(t);
}

// 実トレードオーバーレイ（トグルOFF = シグナルのみ）
const tradeBtn = document.getElementById("trade-toggle");
tradeBtn.addEventListener("click", () => {
  const on = document.body.classList.toggle("show-trades");
  tradeBtn.classList.toggle("active", on);
  tradeBtn.textContent = on ? "実トレード表示 ON" : "実トレード表示 OFF";
});

// ============ ドロワー（signals_calendar v2 流用） ============
let openDate = null;
const drill = document.getElementById("drill");

function fmt(v, digits) {
  return (v === null || v === undefined) ? "—" : v.toFixed(digits === undefined ? 1 : digits);
}
function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function mmSteps(f) {
  // カード内最大値で正規化 → 「伸び方の形」を見る（12→24→36→48h 同一フォーマット）
  const vals = [...f.mfe, ...f.mae].filter(v => v !== null);
  const mx = Math.max(...vals, 1);
  const hs = ["12h", "24h", "36h", "48h"];
  let rows = "";
  for (let i = 0; i < 4; i++) {
    const mfeW = f.mfe[i] === null ? 0 : (f.mfe[i] / mx * 100);
    const maeW = f.mae[i] === null ? 0 : (f.mae[i] / mx * 100);
    rows += `<div class="mm-row"><span class="mm-h">${hs[i]}</span>` +
      `<div class="mm-bar-wrap w-mae"><div class="mm-bar mae" style="width:${maeW.toFixed(1)}%;"></div>` +
      `<span class="mm-num">${fmt(f.mae[i])}</span></div>` +
      `<div class="mm-bar-wrap w-mfe"><div class="mm-bar mfe" style="width:${mfeW.toFixed(1)}%;"></div>` +
      `<span class="mm-num">${fmt(f.mfe[i])}</span></div></div>`;
  }
  let traced = "";
  if (f.bars_traced !== null && f.bars_traced < 48) {
    traced = `<div class="mm-legend">追跡 ${f.bars_traced}/48 本（期間端）</div>`;
  }
  return `<div class="mm-steps"><div class="mm-ttl">MFE/MAE 推移 (USD, 48h固定追跡)</div>${rows}` +
    `<div class="mm-legend"><span class="mae-k">◀ MAE (踏)</span><span class="mfe-k">MFE (伸) ▶</span></div>${traced}</div>`;
}

function fireCard(f) {
  const col = PAT_COLORS[f.pattern][f.direction];
  const glyph = f.direction === "BUY" ? "▲" : "▼";
  const passHtml = f.pass_all
    ? '<span class="fc-pass ok">pass_all ✅</span>'
    : '<span class="fc-pass ng">抑制 ⛔</span>';
  const filt = f.filter_hits.length
    ? `<div class="fc-filters hit">フィルター: ${f.filter_hits.join(", ")} にヒット → 実機非表示</div>`
    : '<div class="fc-filters nohit">フィルター: 9本中ヒットなし</div>';
  return `<div class="fire-card${f.pass_all ? "" : " suppressed"}">` +
    `<div class="fc-head"><span class="fc-pat" style="background:${col};">${f.pattern} ${glyph}${f.direction}</span>` +
    `<span class="fc-time">${f.time_jst} JST</span>` +
    `<span class="fc-server">(server ${f.time_server})</span>${passHtml}</div>` +
    `<div class="fc-row"><span class="k">@</span><span class="v">${fmt(f.entry_price, 2)}</span></div>` +
    `<div class="fc-row">` +
    `<span class="k">ATR Zone</span><span class="v">${f.atr_zone} <span class="raw">(ratio ${fmt(f.h1_atr_ratio, 2)})</span></span>` +
    `<span class="k">H1 ADX</span><span class="v">${f.h1_adx_zone} <span class="raw">(${fmt(f.h1_adx32)})</span></span>` +
    `<span class="k">H1 pat</span><span class="v">${f.h1_pattern}</span></div>` +
    `<div class="fc-row">` +
    `<span class="k">D1 cross</span><span class="v">${f.cross_dir} <span class="raw">(${f.d1_cross_bars}本)</span></span>` +
    `<span class="k">D1 DI</span><span class="v">${f.d1_di_dir} <span class="raw">(ADX ${fmt(f.d1_adx22, 0)})</span></span>` +
    `<span class="k">H4 cross</span><span class="v">${f.h4_cross_dir} <span class="raw">(${f.h4_cross_bars}本)</span></span>` +
    `<span class="k">H4 ADX</span><span class="v">${f.h4_adx_zone} <span class="raw">(${fmt(f.h4_adx46)})</span></span></div>` +
    filt + mmSteps(f);
}

function tradeCard(t) {
  const glyph = t.direction === "BUY" ? "▲" : "▼";
  let pipsCls = "flat", pipsTxt = "±0.0";
  if (t.pips !== null && t.pips > 0) { pipsCls = "pos"; pipsTxt = "+" + t.pips.toFixed(1); }
  else if (t.pips !== null && t.pips < 0) { pipsCls = "neg"; pipsTxt = t.pips.toFixed(1); }
  const meta = [];
  if (t.style) meta.push(`<span>${esc(t.style)}</span>`);
  if (t.star) meta.push(`<span>★${esc(t.star)}</span>`);
  if (t.tag) {
    const otherCls = t.tag === "その他" ? " other" : "";
    meta.push(`<span class="tc-tag${otherCls}">#${esc(t.tag)}</span>`);
  }
  const reason = t.reason
    ? `<details class="tc-reason"><summary>新規理由 ▸</summary>` +
      `<div class="tc-reason-body">${esc(t.reason)}</div></details>`
    : "";
  return `<div class="trade-card">` +
    `<div class="tc-head"><span class="tc-dir">${glyph} ${t.direction}</span>` +
    `<span class="tc-time">${t.entry_time} → ${t.exit_disp} JST</span>` +
    `<span class="tc-pips ${pipsCls}">${pipsTxt} pips</span></div>` +
    (meta.length ? `<div class="tc-meta">${meta.join("")}</div>` : "") +
    mmSteps(t) + reason + `</div>`;
}

function envBox(dateStr) {
  const e = DAY_ENV[dateStr];
  if (!e) return "";
  const parts = [];
  if (e.score !== null && e.score !== undefined)
    parts.push(`<span class="k">スコア</span><span class="v">${e.score.toFixed(1)}${e.label === "レンジ" ? "（レンジ）" : ""}</span>`);
  if (e.h1_spread !== null && e.h1_spread !== undefined)
    parts.push(`<span class="k">H1 DI</span><span class="v">${e.h1_spread > 0 ? "+" : ""}${e.h1_spread.toFixed(1)}</span>`);
  if (e.h4_spread !== null && e.h4_spread !== undefined)
    parts.push(`<span class="k">H4 DI</span><span class="v">${e.h4_spread > 0 ? "+" : ""}${e.h4_spread.toFixed(1)}</span>`);
  if (e.di_match === false) parts.push(`<span class="v" style="color:#d0a060;">H1×H4 不一致（迷い）</span>`);
  if (e.dir_src === "H4(fallback)") parts.push(`<span class="raw" style="color:#4a6a8a;">方向src=H4(週次fallback)</span>`);
  if (!parts.length) return "";
  return `<div class="drill-env">${parts.join("")}</div>`;
}

function renderDrill(dateStr) {
  openDate = dateStr;
  const all = firesByDate[dateStr] || [];
  const dayTrades = dtradesByDate[dateStr] || [];
  document.getElementById("drill-title").textContent =
    `${dateStr} — 発火 ${all.length}件` +
    (dayTrades.length ? ` / 実トレード ${dayTrades.length}件` : "");
  let body = envBox(dateStr);
  if (all.length) {
    body += all.map(fireCard).join("");
  } else {
    body += '<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">この日のシグナル発火はありません</div>';
  }
  if (dayTrades.length) {
    body += `<div class="trade-sec-hdr">実トレード ${dayTrades.length}件</div>` +
      dayTrades.map(tradeCard).join("");
  }
  document.getElementById("drill-body").innerHTML = body;
  drill.classList.add("open");
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
  const cell = document.querySelector(`.cell[data-date="${dateStr}"]`);
  if (cell) cell.classList.add("drill-open");
}

document.querySelectorAll(".cell.has-fires, .cell.has-trade").forEach(cell => {
  cell.addEventListener("click", () => renderDrill(cell.dataset.date));
});
document.getElementById("drill-close").addEventListener("click", () => {
  drill.classList.remove("open");
  openDate = null;
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
});
""")
html.append("</script>")

# ============================================================
# タブ2: 詳細分析（v2.0 の全体像+詳細分析を欠落なく移設）
# ============================================================
all_trades = [t for ts in trade_by_date.values() for t in ts]
total_pl = sum(t["pl"] for t in all_trades)
n_win = sum(1 for t in all_trades if t["pl"] > 0)
n_loss = sum(1 for t in all_trades if t["pl"] < 0)
decided_all = n_win + n_loss
total_mfe = sum((t.get("h4_mfe_48h") or 0) for t in all_trades)
total_mae = sum((t.get("h4_mae_48h") or 0) for t in all_trades)
wr_all = (n_win / decided_all * 100) if decided_all > 0 else None
wr_txt = f"{wr_all:.1f}%" if wr_all is not None else "—"
pl_cls = "pos" if total_pl > 0 else ("neg" if total_pl < 0 else "")

html.append('<div class="tab-pane" id="tab-detail">')

html.append('<div class="overview-summary">')
html.append(f'<div class="stat-blk"><span class="stat-k">期間</span><span class="stat-v" style="font-size:11px;">{all_trade_dates[0]:%Y-%m-%d} 〜 {all_trade_dates[-1]:%Y-%m-%d}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">件数</span><span class="stat-v">{len(all_trades)}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">勝/負/建値</span><span class="stat-v" style="font-size:13px;">{n_win}/{n_loss}/{len(all_trades)-decided_all}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">勝率(建値除外)</span><span class="stat-v">{wr_txt}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">損益合計</span><span class="stat-v {pl_cls}">¥{total_pl:+,.0f}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">MFE合計</span><span class="stat-v">{total_mfe:,.0f} USD</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">MAE合計</span><span class="stat-v">{total_mae:,.0f} USD</span></div>')
html.append('</div>')

html.append('<div class="overview-warning">')
html.append(f'<b>サンプル N={len(all_trades)}</b> — 方向性として参考程度、<b>統計的有意性なし</b>。')
html.append(' シグナル評価・クロス分析の事実情報として読む（戦略修正のためではない）。')
html.append(' [[research-purpose-and-rules]] 準拠。')
html.append('</div>')

# --- 円グラフ集計（v2.0 と同一ロジック） ---
PIE_CATEGORIES_DECISION = ["PAT-A", "PAT-B", "PAT-C", "PAT-D", "ATR収束底", "その他", "未分類"]
PIE_COLORS_DECISION = {
    "PAT-A":     "#5a9adf",
    "PAT-B":     "#7ab8e8",
    "PAT-C":     "#a8c8e8",
    "PAT-D":     "#d8a878",
    "ATR収束底": "#c878a8",
    "その他":    "#8a8a9a",
    "未分類":    "#4a4a5a",
}
decision_counts = {k: 0 for k in PIE_CATEGORIES_DECISION}
for t in all_trades:
    tag = (t.get("decision_tag") or "").strip()
    if not tag:
        decision_counts["未分類"] += 1
    elif tag in decision_counts:
        decision_counts[tag] += 1
    else:
        decision_counts["未分類"] += 1

result_counts = {"勝ち": n_win, "負け": n_loss, "建値": len(all_trades) - decided_all}
PIE_COLORS_RESULT = {"勝ち": "#ffe080", "負け": "#8090a0", "建値": "#5a5a65"}

phase_counts = {"BU": 0, "PD": 0, "RANGE": 0, "その他": 0}
PIE_COLORS_PHASE = {"BU": "#5ab8ff", "PD": "#a8c8e8", "RANGE": "#7878a0", "その他": "#4a4a5a"}
for d, ts in trade_by_date.items():
    rec = get_rec(d)
    if not rec:
        for _ in ts:
            phase_counts["その他"] += 1
        continue
    d1_adx = rec.get("d1_adx22")
    d1p = rec.get("d1_pattern") or "—"
    if d1_adx is not None and d1_adx < 18:
        lbl = "RANGE"
    elif d1p in ("BU", "PD"):
        lbl = d1p
    else:
        lbl = "その他"
    for _ in ts:
        phase_counts[lbl] += 1

DOW_LABELS = ["月", "火", "水", "木", "金"]
PIE_COLORS_DOW = {"月": "#5a9adf", "火": "#7ab8e8", "水": "#a8c8e8", "木": "#d8a878", "金": "#c878a8"}
dow_counts = {k: 0 for k in DOW_LABELS}
for d, ts in trade_by_date.items():
    if d.weekday() < 5:
        dow_counts[DOW_LABELS[d.weekday()]] += len(ts)

def render_pie(counts_dict, colors_dict, order=None, size=140, pie_key=""):
    """SVG 円グラフ（v2.0 から移設、クリッカブル扇形 + 凡例）"""
    keys = order if order else list(counts_dict.keys())
    total = sum(counts_dict.get(k, 0) for k in keys)
    if total == 0:
        return '<div class="pie-empty">データなし</div>', ''
    cx, cy, r = size / 2, size / 2, size / 2 - 2
    svg = [f'<svg class="pie-svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    nonzero = [(k, counts_dict.get(k, 0)) for k in keys if counts_dict.get(k, 0) > 0]
    if len(nonzero) == 1:
        k, _ = nonzero[0]
        svg.append(
            f'<circle class="pie-slice" cx="{cx}" cy="{cy}" r="{r}" '
            f'fill="{colors_dict.get(k, "#888")}" stroke="#05090f" stroke-width="1" '
            f'data-pie-key="{pie_key}" data-pie-value="{k}">'
            f'<title>{k}: {counts_dict.get(k, 0)}件 (100%)</title>'
            f'</circle>'
        )
    else:
        start_ang = -math.pi / 2
        for k in keys:
            v = counts_dict.get(k, 0)
            if v == 0:
                continue
            frac = v / total
            end_ang = start_ang + frac * 2 * math.pi
            x1 = cx + r * math.cos(start_ang)
            y1 = cy + r * math.sin(start_ang)
            x2 = cx + r * math.cos(end_ang)
            y2 = cy + r * math.sin(end_ang)
            large_arc = 1 if frac > 0.5 else 0
            color = colors_dict.get(k, "#888")
            pct = frac * 100
            svg.append(
                f'<path class="pie-slice" d="M {cx} {cy} L {x1:.2f} {y1:.2f} A {r} {r} 0 {large_arc} 1 {x2:.2f} {y2:.2f} Z" '
                f'fill="{color}" stroke="#05090f" stroke-width="1" '
                f'data-pie-key="{pie_key}" data-pie-value="{k}">'
                f'<title>{k}: {v}件 ({pct:.0f}%)</title>'
                f'</path>'
            )
            start_ang = end_ang
    svg.append('</svg>')
    legend = ['<div class="pie-legend">']
    for k in keys:
        v = counts_dict.get(k, 0)
        if v == 0:
            continue
        pct = v / total * 100
        color = colors_dict.get(k, "#888")
        legend.append(
            f'<div class="pie-legend-row pie-slice" data-pie-key="{pie_key}" data-pie-value="{k}">'
        )
        legend.append(f'<span class="pie-legend-sw" style="background:{color};"></span>')
        legend.append(f'<span class="pie-legend-k">{k}</span>')
        legend.append(f'<span class="pie-legend-n">{v}</span>')
        legend.append(f'<span class="pie-legend-pct">{pct:.0f}%</span>')
        legend.append('</div>')
    legend.append('</div>')
    return ''.join(svg), ''.join(legend)

html.append('<div class="pie-grid">')
pies_def = [
    ("反省タグ別", "あろさんの意思決定タグ（反省列）の分布。扇形クリックで下のテーブルが切り替わります。",
     decision_counts, PIE_COLORS_DECISION, PIE_CATEGORIES_DECISION, "pattern"),
    ("勝敗別", "勝ち / 負け / 建値の件数分布。扇形クリックで下のテーブルが切り替わります。",
     result_counts, PIE_COLORS_RESULT, ["勝ち", "負け", "建値"], "won"),
    ("D1フェーズ別", "トレード発生時の大局フェーズ分布（D1 ADX&lt;18=RANGE）。扇形クリックで下のテーブルが切り替わります。",
     phase_counts, PIE_COLORS_PHASE, ["BU", "PD", "RANGE", "その他"], "d1_phase"),
    ("曜日別", "トレード発生曜日の分布（土日除外）。扇形クリックで下のテーブルが切り替わります。",
     dow_counts, PIE_COLORS_DOW, DOW_LABELS, "dow"),
]
n_pies_rendered = 0
for title, sub, counts, colors, order, pie_key in pies_def:
    html.append('<div class="pie-card">')
    html.append(f'<div class="pie-card-title">{title}</div>')
    html.append(f'<div class="pie-card-sub">{sub}</div>')
    svg_html, legend_html = render_pie(counts, colors, order=order, pie_key=pie_key)
    html.append('<div class="pie-card-body">')
    html.append(f'<div class="pie-svg-wrap">{svg_html}</div>')
    html.append(legend_html if legend_html else '<div></div>')
    html.append('</div>')
    html.append('</div>')
    n_pies_rendered += 1
html.append('</div>')  # pie-grid

# --- 円グラフ起点ドリルダウンテーブル（v2.0 から移設） ---
html.append('<div id="drilldown-wrap" class="drilldown-wrap">')
html.append('<div class="drilldown-head">')
html.append('<div id="drilldown-title" class="drilldown-title">—</div>')
html.append('<div id="drilldown-summary" class="drilldown-summary"></div>')
html.append('<div class="drilldown-hint">'
            'ヒント: 列ヘッダ（H1 ATR / H4 ATR / MFE / MAE / 損益 / H1 ATR比）クリックで昇降ソート。'
            ' <button id="drilldown-clear" class="drill-clear-btn" type="button">全件表示に戻す</button>'
            '</div>')
html.append('</div>')
html.append('<table class="detail-table drill-table">')
html.append('<thead><tr><th>日付</th><th>方向</th><th>損益</th><th>MFE</th><th>MAE</th>'
            '<th>反省</th><th>D1</th><th>H1 ATR</th><th>H4 ATR</th><th>H1 ATR比</th><th>★</th></tr></thead>')
html.append('<tbody id="drilldown-tbody"></tbody>')
html.append('</table>')
html.append('</div>')

# --- フィルター × クロス集計（v2.0 から移設） ---
import json as _json
_detail_trades = []
_enr_by_key = {}
for _er in enriched_map.values():
    try:
        _src = (_er.get("約定日") or "").strip()
        _td = _src[:10].replace("/", "-") if _src else ""
        _dir = (_er.get("direction") or "").strip().upper()
        if _td and _dir:
            _enr_by_key.setdefault((_td, _dir), []).append(_er)
    except Exception:
        pass

def _di_dir(plus, minus):
    if plus is None or minus is None:
        return "—"
    diff = plus - minus
    if diff > 2:
        return "UP"
    if diff < -2:
        return "DOWN"
    return "FLAT"

for _d, _ts in trade_by_date.items():
    _rec = get_rec(_d)
    _date_us = str(_d)
    for _t in _ts:
        _pl = _t.get("pl", 0) or 0
        _won = "win" if _pl > 0 else ("loss" if _pl < 0 else "zero")
        _order = _t.get("order", "")
        _entry_dir = "UP" if _order == "買い" else ("DOWN" if _order == "売り" else "FLAT")
        _direction_en = "BUY" if _order == "買い" else "SELL"
        _enrs = _enr_by_key.get((_date_us, _direction_en), [])
        _enr = _enrs[0] if _enrs else {}
        def _ef(key):
            try:
                v = _enr.get(key)
                return float(v) if v not in (None, "", "—") else None
            except Exception:
                return None
        _h1_atr_abs = _ef("h1_atr32")
        _h4_atr_abs = _ef("h4_atr46")
        _h1_dir = _di_dir(_ef("h1_di_plus"), _ef("h1_di_minus"))
        _h4_dir = _di_dir(_ef("h4_di_plus"), _ef("h4_di_minus"))
        _d1_dir = _di_dir(_ef("d1_di_plus"), _ef("d1_di_minus"))
        _dirs = [_d1_dir, _h4_dir, _entry_dir]
        _ups = sum(1 for x in _dirs if x == "UP")
        _dns = sum(1 for x in _dirs if x == "DOWN")
        if _ups == 3 or _dns == 3:
            _align = "3揃"
        elif _ups == 2 or _dns == 2:
            _align = "2揃"
        else:
            _align = "不揃"
        _won_label = "勝ち" if _won == "win" else ("負け" if _won == "loss" else "建値")
        _d1_adx_val = (_rec or {}).get("d1_adx22") if _rec else None
        _d1p_val = (_rec or {}).get("d1_pattern") or "—" if _rec else "—"
        if _rec is None:
            _d1_phase = "その他"
        elif _d1_adx_val is not None and _d1_adx_val < 18:
            _d1_phase = "RANGE"
        elif _d1p_val in ("BU", "PD"):
            _d1_phase = _d1p_val
        else:
            _d1_phase = "その他"
        _dow_label = DOW_LABELS[_d.weekday()] if _d.weekday() < 5 else ""
        _detail_trades.append({
            "date": str(_d),
            "dow": _d.weekday(),
            "dow_label": _dow_label,
            "order": _order,
            "pl": _pl,
            "lot": _t.get("lot", 0),
            "star": _t.get("star", ""),
            "pattern": (_t.get("decision_tag") or "").strip() or "未分類",
            "mfe": _t.get("h4_mfe_48h"),
            "mae": _t.get("h4_mae_48h"),
            "h1_atr_ratio": _t.get("h1_atr_ratio"),
            "h1_atr_abs": _h1_atr_abs,
            "h4_atr_abs": _h4_atr_abs,
            "h1_dir": _h1_dir,
            "h4_dir": _h4_dir,
            "d1_dir": _d1_dir,
            "entry_dir": _entry_dir,
            "align": _align,
            "d1_pattern": (_rec or {}).get("d1_pattern") or "—",
            "d1_phase": _d1_phase,
            "h4_phase": (_rec or {}).get("h4_phase_auto") or "—",
            "won": _won,
            "won_label": _won_label,
        })

html.append('<div class="detail-head" style="margin-top:18px;">')
html.append('<div class="detail-title">詳細分析 — フィルター × クロス集計</div>')
html.append('<div class="detail-sub">フィルターで絞り込み → ピボット軸で集計 → クロス分析。'
            '<b>N=30 規模、方向性として統計的有意性なし</b>。'
            '<b>シグナル評価のため</b>表示（戦略修正のためではない）。</div>')
html.append('</div>')

html.append('<div class="filter-bar">')
html.append('<label>期間 <select id="f-period">'
            '<option value="all">全期間</option>'
            '<option value="apr+">4月以降</option>'
            '<option value="may+">5月以降</option>'
            '</select></label>')
html.append('<label>反省タグ <select id="f-pattern">'
            '<option value="all">全て</option>'
            '<option>PAT-A</option><option>PAT-B</option><option>PAT-C</option>'
            '<option>PAT-D</option><option>ATR収束底</option><option>その他</option><option>未分類</option>'
            '</select></label>')
html.append('<label>D1パターン <select id="f-d1">'
            '<option value="all">全て</option>'
            '<option>BU</option><option>PD</option>'
            '</select></label>')
html.append('<label>勝敗 <select id="f-won">'
            '<option value="all">全て</option>'
            '<option value="win">勝</option><option value="loss">負</option><option value="zero">建値</option>'
            '</select></label>')
html.append('<label>H1 ATR比 <select id="f-atr">'
            '<option value="all">全て</option>'
            '<option value="lt07">&lt;0.7</option>'
            '<option value="07-10">0.7-1.0</option>'
            '<option value="10-14">1.0-1.4</option>'
            '<option value="ge14">≥1.4</option>'
            '</select></label>')
html.append('<label>方向整合 <select id="f-align">'
            '<option value="all">全て</option>'
            '<option value="3揃">3揃 (D1×H4×エントリ)</option>'
            '<option value="2揃">2揃</option>'
            '<option value="不揃">不揃</option>'
            '</select></label>')
html.append('<label>方向 <select id="f-order">'
            '<option value="all">全て</option>'
            '<option value="買い">買い</option><option value="売り">売り</option>'
            '</select></label>')
html.append('<label>曜日 <select id="f-dow">'
            '<option value="all">全て</option>'
            '<option value="0">月</option><option value="1">火</option><option value="2">水</option>'
            '<option value="3">木</option><option value="4">金</option>'
            '</select></label>')
html.append('<button id="f-reset" class="f-reset">リセット</button>')
html.append('</div>')

html.append('<div class="pivot-bar">')
html.append('<label>ピボット軸 <select id="p-axis">'
            '<option value="pattern">反省タグ</option>'
            '<option value="d1_pattern">D1パターン</option>'
            '<option value="won">勝敗</option>'
            '<option value="atr_band">H1 ATR比 帯</option>'
            '<option value="align">方向整合</option>'
            '<option value="dow">曜日</option>'
            '<option value="order">方向</option>'
            '</select></label>')
html.append('<div class="pivot-hint">※ ATR 絶対値はカテゴリ化せず、下の詳細テーブルで列ヘッダクリック → 昇降ソートで「どのATR帯から変化するか」を直接探索する設計。</div>')
html.append('</div>')

html.append('<div class="result-summary" id="result-summary"></div>')
html.append('<table class="pivot-table">')
html.append('<thead><tr id="pivot-thead"></tr></thead>')
html.append('<tbody id="pivot-tbody"></tbody>')
html.append('</table>')
html.append('<details class="trade-detail" open>')
html.append('<summary>マッチしたトレード詳細</summary>')
html.append('<table class="detail-table" data-table="detail">')
html.append('<thead><tr><th>日付</th><th>方向</th><th>損益</th><th>MFE</th><th>MAE</th>'
            '<th>反省</th><th>D1</th><th>H1 ATR</th><th>H4 ATR</th><th>H1 ATR比</th><th>★</th></tr></thead>')
html.append('<tbody id="detail-tbody"></tbody>')
html.append('</table>')
html.append('</details>')

html.append('<script>const TRADES = ' + _json.dumps(_detail_trades, ensure_ascii=False) + ';</script>')
html.append('</div>')  # tab-pane detail

# ============================================================
# タブ切替 JS（2タブ: calendar / detail）
# ============================================================
html.append("""<script>
(function(){
  function activate(name){
    document.querySelectorAll('.tab-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.tab === name);
    });
    document.querySelectorAll('.tab-pane').forEach(p => {
      p.classList.toggle('active', p.id === 'tab-' + name);
    });
  }
  var params = new URLSearchParams(window.location.search);
  var initial = params.get('tab') || 'calendar';
  if (!['calendar', 'detail'].includes(initial)) initial = 'calendar';
  activate(initial);
  document.querySelectorAll('.tab-btn').forEach(b => {
    b.addEventListener('click', function(){
      var name = this.dataset.tab;
      activate(name);
      var url = new URL(window.location.href);
      url.searchParams.set('tab', name);
      window.history.replaceState({}, '', url.toString());
    });
  });
})();
</script>""")

# ============================================================
# 詳細分析タブ JS（v2.0 から欠落なく移設: フィルター/ピボット/ソート/円グラフ連動）
# ============================================================
html.append(r"""<script>
(function(){
  if (typeof TRADES === 'undefined') return;

  const ATR_BANDS = [
    {key: 'lt07',   min: -Infinity, max: 0.7,      label: '<0.7'},
    {key: '07-10',  min: 0.7,       max: 1.0,      label: '0.7-1.0'},
    {key: '10-14',  min: 1.0,       max: 1.4,      label: '1.0-1.4'},
    {key: 'ge14',   min: 1.4,       max: Infinity, label: '≥1.4'}
  ];
  function atrBand(r) {
    if (r == null) return 'none';
    for (const b of ATR_BANDS) {
      if (r >= b.min && r < b.max) return b.key;
    }
    return 'none';
  }
  TRADES.forEach(t => {
    t.atr_band = atrBand(t.h1_atr_ratio);
  });

  const DOW_LBL = ['月','火','水','木','金','土','日'];
  const WON_LBL = {win:'勝', loss:'負', zero:'建値'};
  const ATR_LBL = {lt07:'<0.7','07-10':'0.7-1.0','10-14':'1.0-1.4',ge14:'≥1.4',none:'欠損'};

  function $(id){ return document.getElementById(id); }
  function median(arr) {
    const s = arr.filter(x => x != null && !isNaN(x)).slice().sort((a,b)=>a-b);
    if (!s.length) return null;
    const m = Math.floor(s.length / 2);
    return s.length % 2 ? s[m] : (s[m-1] + s[m]) / 2;
  }
  function fmt(v, d) {
    d = d == null ? 1 : d;
    return (v == null || isNaN(v)) ? '—' : v.toFixed(d);
  }
  function yen(v) {
    const sign = v > 0 ? '+' : (v < 0 ? '−' : '');
    return sign + '¥' + Math.abs(v).toLocaleString('ja-JP');
  }
  function applyFilters() {
    const period = $('f-period').value;
    const pat = $('f-pattern').value;
    const d1  = $('f-d1').value;
    const won = $('f-won').value;
    const atr = $('f-atr').value;
    const align = ($('f-align') || {value:'all'}).value;
    const ord = $('f-order').value;
    const dow = $('f-dow').value;
    return TRADES.filter(t => {
      if (period === 'apr+' && t.date < '2026-04-01') return false;
      if (period === 'may+' && t.date < '2026-05-01') return false;
      if (pat !== 'all' && t.pattern !== pat) return false;
      if (d1  !== 'all' && t.d1_pattern !== d1) return false;
      if (won !== 'all' && t.won !== won) return false;
      if (atr !== 'all' && t.atr_band !== atr) return false;
      if (align !== 'all' && t.align !== align) return false;
      if (ord !== 'all' && t.order !== ord) return false;
      if (dow !== 'all' && String(t.dow) !== dow) return false;
      return true;
    });
  }
  function pivotKeyLabel(axisKey, k) {
    if (axisKey === 'dow') return DOW_LBL[parseInt(k)] || k;
    if (axisKey === 'won') return WON_LBL[k] || k;
    if (axisKey === 'atr_band') return ATR_LBL[k] || k;
    return k;
  }
  function pivot(trades, axisKey) {
    const groups = {};
    for (const t of trades) {
      const v = t[axisKey];
      const k = (v == null || v === '') ? '—' : String(v);
      if (!groups[k]) groups[k] = [];
      groups[k].push(t);
    }
    return Object.entries(groups).map(([k, ts]) => {
      const wins   = ts.filter(t => t.won === 'win').length;
      const losses = ts.filter(t => t.won === 'loss').length;
      const decided = wins + losses;
      return {
        key: k,
        n: ts.length,
        wins, losses,
        wr: decided > 0 ? wins / decided * 100 : null,
        mfe_med: median(ts.map(t => t.mfe)),
        mae_med: median(ts.map(t => t.mae)),
        pl_sum: ts.reduce((s, t) => s + (t.pl || 0), 0),
      };
    }).sort((a, b) => b.n - a.n);
  }
  function refresh() {
    const filtered = applyFilters();
    const axisKey = $('p-axis').value;

    const wins = filtered.filter(t => t.won === 'win').length;
    const losses = filtered.filter(t => t.won === 'loss').length;
    const zeros = filtered.filter(t => t.won === 'zero').length;
    const pl = filtered.reduce((s, t) => s + (t.pl || 0), 0);
    const decided = wins + losses;
    const wr = decided > 0 ? (wins / decided * 100).toFixed(1) + '%' : '—';
    $('result-summary').innerHTML =
      '<b>件数</b>' + filtered.length + ' ｜ ' +
      '<b>勝</b>' + wins + ' ｜ <b>負</b>' + losses + ' ｜ <b>建値</b>' + zeros + ' ｜ ' +
      '<b>勝率</b>' + wr + ' ｜ <b>損益</b>' + yen(pl);

    const pivoted = pivot(filtered, axisKey);
    $('pivot-thead').innerHTML =
      '<th>' + ($('p-axis').selectedOptions[0].text) + '</th>' +
      '<th>N</th><th>勝率</th><th>MFE中央</th><th>MAE中央</th><th>損益合計</th>';
    $('pivot-tbody').innerHTML = pivoted.map(r => {
      const lbl = pivotKeyLabel(axisKey, r.key);
      const wrTxt = r.wr != null ? r.wr.toFixed(1) + '%' : '—';
      const lowMark = r.n < 5 ? ' <span style="color:#d0a060;font-size:9px;">少</span>' : '';
      return '<tr><td>' + lbl + lowMark + '</td><td>' + r.n + '</td><td>' + wrTxt + '</td>' +
             '<td>' + fmt(r.mfe_med) + '</td><td>' + fmt(r.mae_med) + '</td>' +
             '<td>' + yen(r.pl_sum) + '</td></tr>';
    }).join('') || '<tr><td colspan="6" style="text-align:center;color:#5a6a8a;padding:14px;">該当データなし</td></tr>';

    $('detail-tbody').innerHTML = filtered.map(t => {
      const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
      return '<tr>' +
        '<td>' + t.date + '</td>' +
        '<td>' + t.order + '</td>' +
        '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
        '<td>' + fmt(t.mfe) + '</td>' +
        '<td>' + fmt(t.mae) + '</td>' +
        '<td>' + t.pattern + '</td>' +
        '<td>' + t.d1_pattern + '</td>' +
        '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
        '<td>' + (t.star || '') + '</td>' +
      '</tr>';
    }).join('') || '<tr><td colspan="11" style="text-align:center;color:#5a6a8a;padding:14px;">該当トレードなし</td></tr>';
  }
  ['f-period','f-pattern','f-d1','f-won','f-atr','f-align','f-order','f-dow','p-axis'].forEach(id => {
    const el = $(id);
    if (el) el.addEventListener('change', refresh);
  });
  const resetBtn = $('f-reset');
  if (resetBtn) {
    resetBtn.addEventListener('click', function(){
      ['f-period','f-pattern','f-d1','f-won','f-atr','f-align','f-order','f-dow'].forEach(id => {
        const el = $(id);
        if (el) el.value = 'all';
      });
      refresh();
    });
  }

  const SORT_KEYS = ['date','order','pl','mfe','mae','pattern','d1_pattern','h1_atr_abs','h4_atr_abs','h1_atr_ratio','star'];
  const NUMERIC_DETAIL_KEYS = new Set(['pl','mfe','mae','h1_atr_abs','h4_atr_abs','h1_atr_ratio']);
  let _sortKey = null, _sortDir = 1;
  function attachSort() {
    const ths = document.querySelectorAll('.detail-table:not(.drill-table) thead th');
    ths.forEach((th, idx) => {
      if (idx >= SORT_KEYS.length) return;
      th.style.cursor = 'pointer';
      th.title = 'クリックでソート（昇/降切替）';
      th.addEventListener('click', () => {
        const key = SORT_KEYS[idx];
        if (_sortKey === key) _sortDir = -_sortDir;
        else { _sortKey = key; _sortDir = 1; }
        ths.forEach(t => t.dataset.sort = '');
        th.dataset.sort = _sortDir > 0 ? 'asc' : 'desc';
        refresh();
      });
    });
  }
  attachSort();

  const _origRefresh = refresh;
  refresh = function() {
    _origRefresh();
    if (!_sortKey) return;
    const tbody = $('detail-tbody');
    if (!tbody) return;
    const isNumeric = NUMERIC_DETAIL_KEYS.has(_sortKey);
    const filtered = applyFilters().slice().sort((a, b) => {
      const va = a[_sortKey], vb = b[_sortKey];
      const aNil = (va == null || (isNumeric && isNaN(va)));
      const bNil = (vb == null || (isNumeric && isNaN(vb)));
      if (aNil && bNil) return 0;
      if (aNil) return 1;
      if (bNil) return -1;
      if (isNumeric) return (Number(va) - Number(vb)) * _sortDir;
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * _sortDir;
      return String(va).localeCompare(String(vb)) * _sortDir;
    });
    tbody.innerHTML = filtered.map(t => {
      const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
      return '<tr>' +
        '<td>' + t.date + '</td>' +
        '<td>' + t.order + '</td>' +
        '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
        '<td>' + fmt(t.mfe) + '</td>' +
        '<td>' + fmt(t.mae) + '</td>' +
        '<td>' + t.pattern + '</td>' +
        '<td>' + t.d1_pattern + '</td>' +
        '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
        '<td>' + (t.star || '') + '</td>' +
      '</tr>';
    }).join('');
  };

  // 円グラフ起点ドリルダウン（v2.0 から移設）
  const DRILL_SORT_KEYS = ['date','order','pl','mfe','mae','pattern','d1_pattern','h1_atr_abs','h4_atr_abs','h1_atr_ratio','star'];
  const NUMERIC_DRILL_KEYS = new Set(['pl','mfe','mae','h1_atr_abs','h4_atr_abs','h1_atr_ratio']);
  let _drillFilter = null;
  let _drillSortKey = null, _drillSortDir = 1;

  const PIE_KEY_TO_FIELD = {
    'pattern':  'pattern',
    'won':      'won_label',
    'd1_phase': 'd1_phase',
    'dow':      'dow_label',
  };
  const PIE_KEY_TO_TITLE = {
    'pattern':  '反省タグ別',
    'won':      '勝敗別',
    'd1_phase': 'D1フェーズ別',
    'dow':      '曜日別',
  };

  function renderDrilldown() {
    const wrap = document.getElementById('drilldown-wrap');
    if (!wrap) return;
    const title = document.getElementById('drilldown-title');
    const tbody = document.getElementById('drilldown-tbody');
    const summary = document.getElementById('drilldown-summary');

    let trades;
    let titleText;
    if (_drillFilter) {
      const field = PIE_KEY_TO_FIELD[_drillFilter.key];
      trades = TRADES.filter(t => String(t[field]) === String(_drillFilter.value));
      titleText = (PIE_KEY_TO_TITLE[_drillFilter.key] || _drillFilter.key) +
                  ': ' + _drillFilter.value + ' (' + trades.length + '件)';
    } else {
      trades = TRADES.slice();
      titleText = '全件表示 (' + trades.length + '件)';
    }

    if (_drillSortKey) {
      const isNumeric = NUMERIC_DRILL_KEYS.has(_drillSortKey);
      trades = trades.slice().sort((a, b) => {
        const va = a[_drillSortKey], vb = b[_drillSortKey];
        const aNil = (va == null || (isNumeric && (isNaN(va))));
        const bNil = (vb == null || (isNumeric && (isNaN(vb))));
        if (aNil && bNil) return 0;
        if (aNil) return 1;
        if (bNil) return -1;
        if (isNumeric) return (Number(va) - Number(vb)) * _drillSortDir;
        if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * _drillSortDir;
        return String(va).localeCompare(String(vb)) * _drillSortDir;
      });
    }

    if (title) title.textContent = titleText;
    if (summary) {
      const wins = trades.filter(t => t.won === 'win').length;
      const losses = trades.filter(t => t.won === 'loss').length;
      const zeros = trades.filter(t => t.won === 'zero').length;
      const pl = trades.reduce((s, t) => s + (t.pl || 0), 0);
      const decided = wins + losses;
      const wr = decided > 0 ? (wins / decided * 100).toFixed(1) + '%' : '—';
      summary.innerHTML = '<b>勝</b>' + wins + ' ｜ <b>負</b>' + losses + ' ｜ <b>建値</b>' + zeros +
                         ' ｜ <b>勝率</b>' + wr + ' ｜ <b>損益</b>' + yen(pl);
    }
    if (tbody) {
      tbody.innerHTML = trades.map(t => {
        const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
        return '<tr>' +
          '<td>' + t.date + '</td>' +
          '<td>' + t.order + '</td>' +
          '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
          '<td>' + fmt(t.mfe) + '</td>' +
          '<td>' + fmt(t.mae) + '</td>' +
          '<td>' + t.pattern + '</td>' +
          '<td>' + t.d1_pattern + '</td>' +
          '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
          '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
          '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
          '<td>' + (t.star || '') + '</td>' +
        '</tr>';
      }).join('') || '<tr><td colspan="11" style="text-align:center;color:#5a6a8a;padding:14px;">該当トレードなし</td></tr>';
    }
    wrap.style.display = 'block';
  }

  function attachDrillSort() {
    const ths = document.querySelectorAll('#drilldown-wrap thead th');
    ths.forEach((th, idx) => {
      if (idx >= DRILL_SORT_KEYS.length) return;
      th.style.cursor = 'pointer';
      th.title = 'クリックでソート（昇/降切替）';
      th.addEventListener('click', () => {
        const key = DRILL_SORT_KEYS[idx];
        if (_drillSortKey === key) _drillSortDir = -_drillSortDir;
        else { _drillSortKey = key; _drillSortDir = 1; }
        ths.forEach(t => t.dataset.sort = '');
        th.dataset.sort = _drillSortDir > 0 ? 'asc' : 'desc';
        renderDrilldown();
      });
    });
  }
  attachDrillSort();

  function attachPieClicks() {
    const slices = document.querySelectorAll('.pie-slice[data-pie-key][data-pie-value]');
    slices.forEach(el => {
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => {
        const k = el.dataset.pieKey;
        const v = el.dataset.pieValue;
        if (_drillFilter && _drillFilter.key === k && _drillFilter.value === v) {
          _drillFilter = null;
        } else {
          _drillFilter = {key: k, value: v};
        }
        document.querySelectorAll('.pie-slice').forEach(s => s.classList.remove('pie-slice-active'));
        if (_drillFilter) {
          document.querySelectorAll(
            '.pie-slice[data-pie-key="' + k + '"][data-pie-value="' + v + '"]'
          ).forEach(s => s.classList.add('pie-slice-active'));
        }
        _drillSortKey = null; _drillSortDir = 1;
        document.querySelectorAll('#drilldown-wrap thead th').forEach(t => t.dataset.sort = '');
        renderDrilldown();
      });
    });
  }
  attachPieClicks();

  const clearBtn = document.getElementById('drilldown-clear');
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      _drillFilter = null;
      _drillSortKey = null; _drillSortDir = 1;
      document.querySelectorAll('.pie-slice').forEach(s => s.classList.remove('pie-slice-active'));
      document.querySelectorAll('#drilldown-wrap thead th').forEach(t => t.dataset.sort = '');
      renderDrilldown();
    });
  }

  renderDrilldown();
  refresh();
})();
</script>""")

html.append('</body></html>')

OUT_HTML.write_text("\n".join(html), encoding="utf-8")

# ============================================================
# セルフチェック（完了条件の検証出力 — 指示書 §5）
# ============================================================
print("=" * 64)
print("daily_calendar_v3.html セルフチェック")
print("=" * 64)
print(f"[1] 発火CSV読込            : {n_fires_total} 件（期待 389）")
print(f"[2] タブ1 fire-dot 描画    : {emitted_dot_count} 件（期待 389）")
missing_fids = set(fr["fid"] for fr in fires) - set(emitted_dot_fids)
print(f"[3] 欠落 fire_id           : {sorted(missing_fids) if missing_fids else 'なし（欠落ゼロ）'}")
dup = len(emitted_dot_fids) - len(set(emitted_dot_fids))
print(f"[4] 重複描画               : {dup} 件（期待 0）")
print(f"[5] pass_all 集計          : TRUE {n_fires_pass} / FALSE {n_fires_supp}（期待 265 / 124）")
not_in_cells = [d for d in fires_by_date if d not in cell_dates_rendered]
print(f"[6] セル未描画の発火日     : {not_in_cells if not_in_cells else 'なし（全発火日がカレンダー内）'}")
assert n_fires_total == 389, "CSV件数が389ではない"
assert emitted_dot_count == 389, "タブ1描画数が389ではない"
assert not missing_fids and dup == 0, "欠落または重複あり"
assert (n_fires_pass, n_fires_supp) == (265, 124), "pass_all集計が指示書と不一致"
assert not not_in_cells, "カレンダー外の発火日あり"

print()
print(f"[7] 実トレード読込         : {n_dtrades} 件 / {n_dtrade_days} 日（期待 30 / 26）")
print(f"[8] has-trade セル描画     : {len(emitted_trade_cells)} 日（期待 = {n_dtrade_days}）")
print(f"[9] トレード方向マーク     : {emitted_trade_marks} 個（期待 = {n_dtrades}）")
assert (n_dtrades, n_dtrade_days) == (30, 26), "トレード件数/日数が30/26ではない"
assert len(emitted_trade_cells) == n_dtrade_days, "トレード日セル数が不一致"
assert emitted_trade_marks == n_dtrades, "トレードマーク数が不一致"
fx_days = set(trade_by_date.keys())
enr_days = set(dtrades_by_date.keys())
print(f"[10] FX_CSV日付 vs enriched日付: {'一致' if fx_days == enr_days else f'不一致 FXのみ={sorted(str(x) for x in fx_days-enr_days)} enrichedのみ={sorted(str(x) for x in enr_days-fx_days)}'}")

print()
out_text = OUT_HTML.read_text(encoding="utf-8")
print(f"[11] タブ2 移設チェック:")
print(f"     円グラフカード数       : {n_pies_rendered}（期待 4）")
print(f"     pie-slice 扇形+凡例    : {out_text.count('class=\"pie-slice')} 個（クリック連動対象）")
print(f"     drilldown テーブル     : {'あり' if 'drilldown-tbody' in out_text else '欠落!'}")
print(f"     フィルターバー         : {'あり' if 'f-period' in out_text else '欠落!'}")
print(f"     ピボット軸             : {'あり' if 'p-axis' in out_text else '欠落!'}")
print(f"     詳細テーブル+ソート    : {'あり' if 'detail-tbody' in out_text and 'attachSort' in out_text else '欠落!'}")
print(f"     TRADES 埋め込み件数    : {len(_detail_trades)}（期待 30）")
assert n_pies_rendered == 4
assert all(s in out_text for s in ('drilldown-tbody', 'f-period', 'p-axis', 'detail-tbody'))
assert len(_detail_trades) == 30

print()
print(f"[12] セル内テキスト削減チェック（v3 仕様）:")
for token, desc in (("adx-tiny", "スコア/ADX数値（セル右上）"), ("h1-aux", "H1 ADX レーン"),
                    ("env-memo", "環境メモ文字"), ("lot-info", "ロット/金額表示"),
                    ("mfe-mae-nums", "バー上の数値"), ("range-nums", "レンジ数値"),
                    ("d1-band", "D1帯（因果レイヤー）"), ("ph-badge", "Phaseバッジ")):
    n = out_text.count(token)
    print(f"     {desc:<28}: {'残存 ' + str(n) + ' 箇所 ✗' if n else '削除済 ✓'}")
    assert n == 0, f"{token} がセルに残存"
# レンジ判定ラベル: 凡例/ツールチップが「レンジ」表記であること
# （「H4 Phase=凪」はATR収束の構造ラベルで別概念のため残置 — nagi-vs-range-distinction）
assert "レンジ (スコア&lt;15)" in out_text, "凡例のレンジ表記が無い"
assert "凪 (&lt;15)" not in out_text, "旧「凪」凡例が残存"
print(f"     レンジ判定ラベル                : 「凪」→「レンジ」置換済 ✓（H4 Phase=凪 はATR概念のため残置）")

print()
print("[13] v2.0 vs v3 色変化比較（直近急落局面 2026-05-08〜05-22 / 6月第2週）:")
print(f"     {'日付':<11}{'スコア':>6} {'v2.0色(H4 DI)':<20} {'v3色(H1 DI)':<18} 変化")
compare_ranges = [(date(2026, 5, 8), date(2026, 5, 22)), (date(2026, 6, 8), date(2026, 6, 10))]
for lo, hi in compare_ranges:
    d = lo
    while d <= hi:
        if d.weekday() < 5:
            rec = get_rec(d)
            if rec:
                v2c = v2_color_label(rec)
                v3c = v3_color_label(rec)
                sc = v3_bg_style(rec)["score"]
                sc_txt = f"{sc:.1f}" if sc is not None else "—"
                ch = "←変化" if v2c.split("(")[0].rstrip("12345s") != v3c.split("(")[0].split("/")[0].rstrip("12345s") else ""
                print(f"     {d}  {sc_txt:>5} {v2c:<20} {v3c:<18} {ch}")
        d += timedelta(days=1)

print()
print(f"出力: {OUT_HTML}")
print(f"期間: {period_first} 〜 {period_last}（発火∪トレード、6列=月〜土）")
print(f"日次CSV: {len(daily_agg_map)}日 / 週次fallback対象期間あり（H1 DI無し日は方向src=H4表記）")
print("全チェック PASS ✅")
