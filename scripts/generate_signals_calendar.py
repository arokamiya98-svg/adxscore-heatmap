#!/usr/bin/env python3
"""
generate_signals_calendar.py
────────────────────────────
シグナル検証カレンダー v1.0（generate_daily_calendar.py を複製・改造）
指示書: data/mani_room/マニ_指示書_シグナル検証カレンダー_v0.1.md

目的（固定・変更禁止）:
  稼働中 v4 シグナルの発火を可視化・認識して、
  あろさんが自分の使ってるシグナルへの理解を深める。
  - シグナルの評価・改良ツールではない（8〜9月メンテの管轄）
  - 月別・損益集計の類は作らない（研究ルール準拠）
  - 実トレード表示は「有無 + 方向」のみ（執行確認用オーバーレイ）

設計判断（マニ）:
  (1) カレンダーは月〜土の6列グリッド
      - signal_fires.csv は JST 日付基準。サーバー金曜深夜 = JST 土曜の発火が
        31件存在する（weekday 分布: 月80/火51/水69/木97/金61/土31）
      - daily_calendar の月〜金 5列を流用すると土曜発火31件が欠落し
        「389件全件表示」の完了条件を満たせない → 6列に拡張
  (2) 日セルのドットは「全件描画」（+n 集約はしない）
      - 最大14件/日。flex-wrap の小グリフで全件入る
      - 集約するとフィルター切替時の表示数管理が複雑化し、
        「欠落ゼロ」の検証可能性も下がるため全件描画を採用
  (3) ドットの言語 = v4 実機と完全一致
      - 色 = パターン（v4矢印色テーブル）、形 = 方向（▲BUY / ▼SELL）
      - 色を方向に使わない（v4と同じ視覚言語、認識の一貫性）
  (4) pass_all=FALSE は opacity 0.3 の薄表示
      - 「実機なら見えなかった発火」の見える化（本ツールの核心）
  (5) ドット描画は in-month セルのみ
      - 週の端で隣月セルが重複描画されると 389 件カウントが壊れるため
        outside セルにはドットを置かない
  (6) ドリルダウンは右サイドの固定ドロワー
      - 16ヶ月分の縦長カレンダーをスクロールしながら日クリックで参照できる

入力:
    mt5_data/signal_fires.csv                       (UTF-8-sig, 64列×389行)
    data/mani_room/enriched/trades_enriched_full.csv (UTF-8-sig, オーバーレイ用)
出力:
    data/trades/processed/signals_calendar.html （自己完結HTML、外部依存なし）
"""
import csv
import json
from collections import defaultdict
from datetime import datetime, timedelta, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIRES_CSV = ROOT / "mt5_data" / "signal_fires.csv"
ENRICHED = ROOT / "data" / "mani_room" / "enriched" / "trades_enriched_full.csv"
OUT = ROOT / "data" / "trades" / "processed"
OUT.mkdir(parents=True, exist_ok=True)
OUT_HTML = OUT / "signals_calendar.html"

# ============================================================
# v4 実機 矢印色テーブル（指示書 §3.2、完全一致・変更禁止）
# ============================================================
PATTERN_COLORS = {
    "PatA": {"BUY": "#FFD700", "SELL": "#DAA520"},  # Gold / Goldenrod
    "PatB": {"BUY": "#00FFFF", "SELL": "#00BFFF"},  # Aqua / DeepSkyBlue
    "PatC": {"BUY": "#32CD32", "SELL": "#2E8B57"},  # LimeGreen / SeaGreen
    "PatD": {"BUY": "#FF00FF", "SELL": "#C71585"},  # Magenta / MediumVioletRed
    "PatE": {"BUY": "#FFA500", "SELL": "#FF8C00"},  # Orange / DarkOrange
}
PATTERNS = ["PatA", "PatB", "PatC", "PatD", "PatE"]

# フィルター列 → 表示名（v4 の F1〜F9）
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
# 入力: signal_fires.csv
# ⚠️ 必ず utf-8-sig。utf-8 だと先頭列キーが "﻿fire_id" になり全マッチ失敗
#    （BOM事件、generate_daily_calendar.py v0.2 bugfix 参照）
# ============================================================
with open(FIRES_CSV, encoding="utf-8-sig") as f:
    raw_rows = list(csv.DictReader(f))

assert "fire_id" in raw_rows[0], f"BOM混入の疑い: 先頭キー={list(raw_rows[0].keys())[0]!r}"

fires = []
for r in raw_rows:
    d = datetime.strptime(r["date"], "%Y-%m-%d").date()
    hits = [label for col, label in FILTER_COLS if r.get(col) == "TRUE"]
    fires.append({
        "fid": r["fire_id"],
        "date": r["date"],
        "_d": d,
        "time_jst": r["time_jst"][11:16],          # "HH:MM"
        "time_server": r["time_server"][5:16],     # "MM-DD HH:MM"（日付跨ぎ明示）
        "pattern": r["pattern"],
        "direction": r["direction"],
        "entry_price": _f(r["entry_price"]),
        "pass_all": r["pass_all"] == "TRUE",
        "filter_hits": hits,
        # 環境（段階ラベル優先 + 生値は補助）
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
        "cross_dir": r["cross_dir"],               # D1 ATRクロス局面 BU/PD/NONE
        "d1_cross_bars": r["d1_cross_bars"],
        "d1_adx22": _f(r["d1_adx22"]),
        "d1_di_dir": r["d1_di_dir"],
        # MFE/MAE 推移（48h固定追跡、研究ルール準拠の固定窓）
        "mfe": [_f(r["mfe_12h"]), _f(r["mfe_24h"]), _f(r["mfe_36h"]), _f(r["mfe_48h"])],
        "mae": [_f(r["mae_12h"]), _f(r["mae_24h"]), _f(r["mae_36h"]), _f(r["mae_48h"])],
        "bars_traced": _f(r["bars_traced"]),
    })

fires.sort(key=lambda x: (x["date"], x["time_jst"], int(x["fid"])))
fires_by_date = defaultdict(list)
for fr in fires:
    fires_by_date[fr["_d"]].append(fr)

n_total = len(fires)
n_pass = sum(1 for fr in fires if fr["pass_all"])
n_supp = n_total - n_pass

# ============================================================
# 入力: trades_enriched_full.csv（オーバーレイ: 有無 + 方向のみ）
# ============================================================
trades_by_date = defaultdict(list)
n_trades = 0
if ENRICHED.exists():
    with open(ENRICHED, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            ej = (r.get("entry_jst") or "").strip()
            if not ej:
                continue
            try:
                d = datetime.strptime(ej[:10], "%Y-%m-%d").date()
            except ValueError:
                continue
            trades_by_date[d].append(r.get("direction", "").upper())
            n_trades += 1

# ============================================================
# カレンダー期間（CSVから自動: 月初〜最終月の翌月頭）
# ============================================================
all_fire_dates = sorted(fires_by_date.keys())
start = all_fire_dates[0].replace(day=1)
end_d = all_fire_dates[-1]
end = (end_d.replace(day=28) + timedelta(days=4)).replace(day=1)

def month_iter(s, e):
    cur = s
    while cur < e:
        yield cur
        cur = cur.replace(year=cur.year + 1, month=1) if cur.month == 12 else cur.replace(month=cur.month + 1)

def month_weekdays_sat(year, month):
    """月内の月〜土を週グループで返す（土曜発火31件があるため6列）"""
    first = date(year, month, 1)
    start_d = first - timedelta(days=first.weekday())
    last_day = (date(year + 1, 1, 1) - timedelta(days=1)) if month == 12 else (date(year, month + 1, 1) - timedelta(days=1))
    end_dd = last_day + timedelta(days=(6 - last_day.weekday()))
    cur = start_d
    weeks_list, cur_week = [], []
    while cur <= end_dd:
        if cur.weekday() < 6:  # 月〜土
            cur_week.append(cur)
        if cur.weekday() == 5:  # 土曜で区切り
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
<title>Signals Calendar — マニ v1.0</title>
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

/* ===== フィルターバー ===== */
.filter-bar {
  position: sticky; top: 0; z-index: 50;
  display: flex; flex-wrap: wrap; gap: 10px 18px;
  padding: 10px 14px; background: #080d16ee;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 14px; align-items: center;
  backdrop-filter: blur(4px);
}
.filter-bar .fgrp { display: flex; align-items: center; gap: 7px; }
.filter-bar .fttl { font-size: 9.5px; color: #4a6a8a; letter-spacing: .05em; }
.pat-cb {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 10.5px; cursor: pointer; user-select: none;
  padding: 2px 7px; border-radius: 3px;
  border: 1px solid #1a3454; background: #0a1320;
  color: #c8d8e8; transition: opacity .15s;
}
.pat-cb input { display: none; }
.pat-cb .sw { width: 9px; height: 9px; border-radius: 2px; display: inline-block; }
.pat-cb.off { opacity: 0.3; }
.seg-btn {
  background: #0a1320; color: #6a8aaa;
  border: 1px solid #1a3454; padding: 3px 11px;
  font-size: 10.5px; cursor: pointer; font-family: inherit;
  transition: background .15s, color .15s;
}
.seg-btn:first-of-type { border-radius: 3px 0 0 3px; }
.seg-btn:last-of-type { border-radius: 0 3px 3px 0; }
.seg-btn + .seg-btn { border-left: none; }
.seg-btn.active { background: #1a3a6a; color: #d8e8f8; font-weight: 700; }
.trade-toggle {
  background: #0a1320; color: #6a8aaa;
  border: 1px solid #1a3454; border-radius: 3px;
  padding: 3px 11px; font-size: 10.5px; cursor: pointer; font-family: inherit;
}
.trade-toggle.active { background: #3a2a0a; color: #ffd060; border-color: #6a5a2a; font-weight: 700; }
#visible-count { font-size: 11px; color: #8abaee; font-weight: 700; font-variant-numeric: tabular-nums; }
#visible-count .dim { color: #4a6a8a; font-weight: 400; }

/* ===== 凡例 ===== */
.legend {
  display: flex; gap: 18px; margin-bottom: 18px; flex-wrap: wrap;
  font-size: 10px; color: #6a8aaa;
  padding: 10px 14px; background: #080d16;
  border: 1px solid #162844; border-radius: 6px;
  align-items: center;
}
.legend .grp { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.legend .ttl { color: #4a7aaa; font-weight: 600; margin-right: 2px; }
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

/* ===== 日セル ===== */
.cell {
  border-radius: 4px; min-height: 64px;
  background: #0a0f18; border: 1px solid #0b1825;
  position: relative; overflow: hidden;
  display: flex; flex-direction: column;
}
.cell.outside { opacity: 0.15; }
.cell.has-fires { cursor: pointer; }
.cell.has-fires:hover { border-color: #2a5a9a; background: #0c1422; }
.cell.drill-open { border-color: #4a90e2; box-shadow: inset 0 0 0 1px #4a90e2; }
.cell .day-hdr {
  display: flex; justify-content: space-between; align-items: center;
  padding: 2px 5px; font-size: 10px; font-weight: 600; color: #6a8aaa;
  background: rgba(0,0,0,0.3);
}
.cell .fires-box {
  flex: 1; display: flex; flex-wrap: wrap; align-content: flex-start;
  gap: 1px 2px; padding: 3px 4px;
}
.fire-dot {
  font-size: 11px; line-height: 1.1;
  text-shadow: 0 1px 2px rgba(0,0,0,0.7);
}
.fire-dot.suppressed { opacity: 0.3; }   /* pass_all=FALSE: 実機なら見えなかった発火 */
.fire-dot.fhide { display: none; }        /* フィルターで非表示 */
/* 実トレードオーバーレイ（有無+方向のみ、デフォルトOFF） */
.cell .trade-mark {
  display: none;
  position: absolute; right: 3px; bottom: 2px;
  font-size: 9px; font-weight: 700; color: #ffd060;
  text-shadow: 0 1px 2px rgba(0,0,0,0.8);
  letter-spacing: .04em;
}
body.show-trades .cell.has-trade { box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); }
body.show-trades .cell .trade-mark { display: block; }

/* ===== ドリルダウンドロワー ===== */
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

/* 発火カード */
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
/* MFE/MAE ステップバー */
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

.notes { margin-top: 10px; font-size: 10px; color: #4a6a8a; line-height: 1.6; }
.notes b { color: #6a8aaa; }
</style></head><body>
""")

gen_ts = datetime.now().strftime("%Y-%m-%d %H:%M")
html.append('<h1>SIGNALS CALENDAR — v4発火検証 マニ v1.0</h1>')
html.append(f'<div class="sub">入力: {FIRES_CSV.name} / 発火 {n_total}件 (pass {n_pass} / 抑制 {n_supp}) / '
            f'期間: {all_fire_dates[0]:%Y-%m-%d} 〜 {all_fire_dates[-1]:%Y-%m-%d} / '
            f'実トレード {n_trades}件 (オーバーレイ用) / 生成: {gen_ts}</div>')
html.append('<div class="purpose"><b>目的:</b> 稼働中 v4 シグナルの発火を可視化して、自分の使ってるシグナルへの理解を深める。'
            '評価・改良ツールではない（8〜9月メンテの管轄）。'
            '<b>薄いドット = pass_all=FALSE（フィルター抑制、実機チャートには出ていない発火）</b>。'
            '日付は JST 基準（サーバー金曜深夜 = JST 土曜の発火があるため土曜列あり）。</div>')

# ===== フィルターバー =====
html.append('<div class="filter-bar">')
html.append('<div class="fgrp"><span class="fttl">パターン:</span>')
for p in PATTERNS:
    c_buy = PATTERN_COLORS[p]["BUY"]
    html.append(f'<label class="pat-cb" data-pat="{p}"><input type="checkbox" checked>'
                f'<span class="sw" style="background:{c_buy};"></span>{p}</label>')
html.append('</div>')
html.append('<div class="fgrp"><span class="fttl">発火:</span>'
            '<button class="seg-btn active" data-pass="all">全発火</button>'
            '<button class="seg-btn" data-pass="pass">pass_all のみ</button></div>')
html.append('<div class="fgrp"><span class="fttl">方向:</span>'
            '<button class="seg-btn active" data-dir="ALL">ALL</button>'
            '<button class="seg-btn" data-dir="BUY">BUY ▲</button>'
            '<button class="seg-btn" data-dir="SELL">SELL ▼</button></div>')
html.append('<div class="fgrp"><button class="trade-toggle" id="trade-toggle">実トレード表示 OFF</button></div>')
html.append(f'<div class="fgrp"><span id="visible-count"></span></div>')
html.append('</div>')

# ===== 凡例 =====
html.append('<div class="legend">')
html.append('<div class="grp"><span class="ttl">色=パターン (v4矢印色と同一):</span>')
for p in PATTERNS:
    html.append(f'<span class="lg-dot"><span style="color:{PATTERN_COLORS[p]["BUY"]};">▲</span>'
                f'<span style="color:{PATTERN_COLORS[p]["SELL"]};">▼</span> {p}</span>')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">形=方向:</span><span>▲ BUY / ▼ SELL（色は方向に使わない）</span></div>')
html.append('<div class="grp"><span class="ttl">薄表示:</span>'
            '<span class="lg-dot" style="opacity:0.3;color:#FFD700;">▲</span>'
            '<span>pass_all=FALSE（フィルター抑制 = 実機では見えなかった発火）</span></div>')
html.append('<div class="grp"><span class="ttl">実トレード(ON時):</span>'
            '<span style="box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); padding:1px 6px; border-radius:3px;">枠</span>'
            '<span style="color:#ffd060;font-weight:700;">▲/▼=エントリー方向</span>'
            '<span style="opacity:0.6;">有無+方向のみ（執行確認用）</span></div>')
html.append('</div>')

# ===== 月ループ =====
emitted_dot_count = 0          # 検証用: HTML に出した fire-dot 数
emitted_dot_fids = []          # 検証用: 出した fire_id
cell_dates_rendered = set()    # 検証用: in-month セルの日付集合
DOW_LABELS = ["月", "火", "水", "木", "金", "土"]

for m_start in month_iter(start, end):
    weeks_list = month_weekdays_sat(m_start.year, m_start.month)
    m_fires = [fr for d, frs in fires_by_date.items()
               if d.year == m_start.year and d.month == m_start.month for fr in frs]
    m_pass = sum(1 for fr in m_fires if fr["pass_all"])
    m_supp = len(m_fires) - m_pass

    html.append('<div class="month">')
    html.append(f'<div class="month-title">{m_start.year}年 {m_start.month}月</div>')
    html.append(f'<div class="month-stats">発火 {len(m_fires)}件（pass {m_pass} / 抑制 {m_supp}）</div>')
    html.append('<div class="dow-row">')
    for i, dow in enumerate(DOW_LABELS):
        html.append(f'<div class="dow{" sat" if i == 5 else ""}">{dow}</div>')
    html.append('</div>')

    for week_days in weeks_list:
        html.append('<div class="week-cells">')
        for d in week_days:
            is_outside = d.month != m_start.month
            if is_outside:
                # outside セルにはドットを描画しない（隣月との二重描画防止 → 389件保証）
                html.append(f'<div class="cell outside"><div class="day-hdr"><span>{d.day}</span></div></div>')
                continue

            cell_dates_rendered.add(d)
            day_fires = fires_by_date.get(d, [])
            day_trades = trades_by_date.get(d, [])
            classes = ["cell"]
            if day_fires:
                classes.append("has-fires")
            if day_trades:
                classes.append("has-trade")

            tip_parts = [f"{d:%Y-%m-%d} ({['月','火','水','木','金','土','日'][d.weekday()]})"]
            for fr in day_fires:
                state = "pass" if fr["pass_all"] else "抑制"
                tip_parts.append(f"{fr['time_jst']} {fr['pattern']} {fr['direction']} ({state})")
            title = " | ".join(tip_parts)

            html.append(f'<div class="{" ".join(classes)}" data-date="{d:%Y-%m-%d}" title="{title}">')
            html.append('<div class="day-hdr">')
            html.append(f'<span>{d.day}</span>')
            if day_fires:
                html.append(f'<span style="font-size:8px;color:#3a5a7a;">{len(day_fires)}</span>')
            html.append('</div>')
            html.append('<div class="fires-box">')
            for fr in day_fires:
                col = PATTERN_COLORS[fr["pattern"]][fr["direction"]]
                glyph = "▲" if fr["direction"] == "BUY" else "▼"
                supp_cls = "" if fr["pass_all"] else " suppressed"
                html.append(f'<span class="fire-dot{supp_cls}" data-fid="{fr["fid"]}" '
                            f'data-pat="{fr["pattern"]}" data-dir="{fr["direction"]}" '
                            f'data-pass="{1 if fr["pass_all"] else 0}" '
                            f'style="color:{col};">{glyph}</span>')
                emitted_dot_count += 1
                emitted_dot_fids.append(fr["fid"])
            html.append('</div>')
            if day_trades:
                marks = "".join("▲" if t == "BUY" else "▼" for t in day_trades)
                html.append(f'<span class="trade-mark">{marks}</span>')
            html.append('</div>')
        html.append('</div>')
    html.append('</div>')

html.append('<div class="notes">'
            '<b>注:</b> サーバー時間 = チャート表示時間（ドリルダウンに併記、チャート照合用）。'
            'MFE/MAE は発火後 48h 固定追跡（12/24/36/48h スナップショット、USD建て）。'
            '環境値は段階ラベル優先（生値は括弧内の補助表示）。'
            'このツールは発火の認識用 — 月別・累計の損益/勝率サマリーは置かない（研究ルール準拠）。'
            '</div>')

# ============================================================
# JSON データ埋め込み（ドリルダウン用、自己完結HTML）
# ============================================================
fires_json = [{k: v for k, v in fr.items() if k != "_d"} for fr in fires]
json_blob = json.dumps(fires_json, ensure_ascii=False).replace("</", "<\\/")
colors_blob = json.dumps(PATTERN_COLORS)

html.append('<div id="drill">'
            '<div class="drill-head"><span class="drill-title" id="drill-title"></span>'
            '<button class="drill-close" id="drill-close">閉じる ✕</button></div>'
            '<div class="drill-note">サーバー時間 = チャート表示時間（照合用）。'
            '薄カード = pass_all=FALSE（実機チャート非表示の発火）。バー長 = カード内の最大値基準（伸び方の形を見る用）。</div>'
            '<div class="drill-body" id="drill-body"></div></div>')

html.append("<script>")
html.append(f"const FIRES = {json_blob};")
html.append(f"const PAT_COLORS = {colors_blob};")
html.append("""
// ============ インデックス ============
const byDate = {};
for (const f of FIRES) {
  (byDate[f.date] = byDate[f.date] || []).push(f);
}

// ============ フィルター状態 ============
const state = { pats: new Set(["PatA","PatB","PatC","PatD","PatE"]), pass: "all", dir: "ALL" };

function fireVisible(pat, dir, pass) {
  if (!state.pats.has(pat)) return false;
  if (state.pass === "pass" && !pass) return false;
  if (state.dir !== "ALL" && dir !== state.dir) return false;
  return true;
}

function applyFilters() {
  let vis = 0, visPass = 0, visSupp = 0;
  document.querySelectorAll(".fire-dot").forEach(el => {
    const ok = fireVisible(el.dataset.pat, el.dataset.dir, el.dataset.pass === "1");
    el.classList.toggle("fhide", !ok);
    if (ok) { vis++; if (el.dataset.pass === "1") visPass++; else visSupp++; }
  });
  const total = document.querySelectorAll(".fire-dot").length;
  document.getElementById("visible-count").innerHTML =
    `表示中 ${vis} <span class="dim">/ ${total}件（pass ${visPass} / 抑制 ${visSupp}）</span>`;
  // ドリルダウンが開いていれば再描画（フィルター連動）
  if (openDate) renderDrill(openDate);
}

// パターンチェックボックス
document.querySelectorAll(".pat-cb").forEach(lbl => {
  lbl.addEventListener("change", () => {
    const p = lbl.dataset.pat;
    if (lbl.querySelector("input").checked) { state.pats.add(p); lbl.classList.remove("off"); }
    else { state.pats.delete(p); lbl.classList.add("off"); }
    applyFilters();
  });
});
// pass 切替
document.querySelectorAll(".seg-btn[data-pass]").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".seg-btn[data-pass]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.pass = btn.dataset.pass;
    applyFilters();
  });
});
// 方向切替
document.querySelectorAll(".seg-btn[data-dir]").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".seg-btn[data-dir]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.dir = btn.dataset.dir;
    applyFilters();
  });
});
// 実トレードオーバーレイ（有無+方向のみ）
const tradeBtn = document.getElementById("trade-toggle");
tradeBtn.addEventListener("click", () => {
  const on = document.body.classList.toggle("show-trades");
  tradeBtn.classList.toggle("active", on);
  tradeBtn.textContent = on ? "実トレード表示 ON" : "実トレード表示 OFF";
});

// ============ ドリルダウン ============
let openDate = null;
const drill = document.getElementById("drill");

function fmt(v, digits) {
  return (v === null || v === undefined) ? "—" : v.toFixed(digits === undefined ? 1 : digits);
}

function mmSteps(f) {
  // カード内最大値で正規化 → 「伸び方の形」を見る
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

function renderDrill(dateStr) {
  openDate = dateStr;
  const all = byDate[dateStr] || [];
  const shown = all.filter(f => fireVisible(f.pattern, f.direction, f.pass_all));
  const hidden = all.length - shown.length;
  document.getElementById("drill-title").textContent =
    `${dateStr} — 発火 ${all.length}件${hidden ? `（フィルターで ${hidden} 件非表示中）` : ""}`;
  document.getElementById("drill-body").innerHTML =
    shown.length ? shown.map(fireCard).join("")
      : '<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">現在のフィルター条件で表示できる発火がありません</div>';
  drill.classList.add("open");
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
  const cell = document.querySelector(`.cell[data-date="${dateStr}"]`);
  if (cell) cell.classList.add("drill-open");
}

document.querySelectorAll(".cell.has-fires").forEach(cell => {
  cell.addEventListener("click", () => renderDrill(cell.dataset.date));
});
document.getElementById("drill-close").addEventListener("click", () => {
  drill.classList.remove("open");
  openDate = null;
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
});

applyFilters();
""")
html.append("</script></body></html>")

OUT_HTML.write_text("\n".join(html), encoding="utf-8")

# ============================================================
# セルフチェック（完了条件の検証出力 — 指示書 §5）
# ============================================================
print("=" * 60)
print("signals_calendar.html セルフチェック")
print("=" * 60)
print(f"[1] CSV読込件数            : {n_total} 件（期待 389）")
print(f"[2] HTML描画 fire-dot 数   : {emitted_dot_count} 件（期待 389）")
missing_fids = set(fr["fid"] for fr in fires) - set(emitted_dot_fids)
print(f"[3] 欠落 fire_id           : {sorted(missing_fids) if missing_fids else 'なし（欠落ゼロ）'}")
dup = len(emitted_dot_fids) - len(set(emitted_dot_fids))
print(f"[4] 重複描画               : {dup} 件（期待 0）")
print(f"[5] pass_all 集計          : TRUE {n_pass} / FALSE {n_supp}（期待 265 / 124）")
not_in_cells = [d for d in fires_by_date if d not in cell_dates_rendered]
print(f"[6] セル未描画の発火日     : {not_in_cells if not_in_cells else 'なし（全発火日がカレンダー内）'}")
sat_fires = sum(len(v) for d, v in fires_by_date.items() if d.weekday() == 5)
sun_fires = sum(len(v) for d, v in fires_by_date.items() if d.weekday() == 6)
print(f"[7] 土曜発火（6列の根拠）  : {sat_fires} 件 / 日曜発火: {sun_fires} 件（日曜列は不要）")

assert n_total == 389, "CSV件数が389ではない"
assert emitted_dot_count == 389, "HTML描画数が389ではない"
assert not missing_fids and dup == 0, "欠落または重複あり"
assert (n_pass, n_supp) == (265, 124), "pass_all集計が指示書と不一致"
assert not not_in_cells, "カレンダー外の発火日あり"

print()
print("[8] ドリルダウン検証 (2026-06-04 / 2026-06-05):")
for ds in ("2026-06-04", "2026-06-05"):
    day = [fr for fr in fires if fr["date"] == ds]
    print(f"  {ds}: {len(day)} 件")
    for fr in day:
        hits = ", ".join(fr["filter_hits"]) if fr["filter_hits"] else "ヒットなし"
        print(f"    [{fr['pattern']} {fr['direction']}] {fr['time_jst']} JST (server {fr['time_server']}) "
              f"@ {fr['entry_price']:.2f} pass_all={'✅' if fr['pass_all'] else '⛔'}")
        print(f"      環境: ATR Zone={fr['atr_zone']} / H1 ADX={fr['h1_adx_zone']}({fr['h1_adx32']:.1f}) / "
              f"H1 pat={fr['h1_pattern']} / D1 cross={fr['cross_dir']}({fr['d1_cross_bars']}本) / "
              f"D1 DI={fr['d1_di_dir']} / H4 cross={fr['h4_cross_dir']} / H4 ADX={fr['h4_adx_zone']}({fr['h4_adx46']:.1f})")
        print(f"      フィルター: {hits}")
        mm = " → ".join(f"{h}h: {mfe:.1f}/{mae:.1f}" for h, mfe, mae in
                        zip((12, 24, 36, 48), fr["mfe"], fr["mae"]))
        print(f"      MFE/MAE: {mm}")
print()
print(f"出力: {OUT_HTML}")
print("全チェック PASS ✅")
