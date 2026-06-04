#!/usr/bin/env python3
"""
generate_trades_calendar.py
───────────────────────────
トレードカレンダー v0.2
- 背景: H4 ADX強度 × DI方向 (凪/弱/強 × UP/DOWN/拮抗)
- 右上バッジ: h4_phase_auto (BU/PD/凪/凪離脱/収束底), 凪離脱は警告色
- ATR表示は廃止 (粒度差で誤解を生むため、あろさん指摘 2026-06-04)

入力:
    data/trades/raw/FX_*.csv
    data/weekly_waves.json
出力:
    data/trades/processed/trades_calendar.html (git管理外)
"""
import csv
import json
from collections import defaultdict
from datetime import datetime, timedelta, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "trades" / "raw"
OUT = ROOT / "data" / "trades" / "processed"
WAVES = ROOT / "data" / "weekly_waves.json"
OUT.mkdir(parents=True, exist_ok=True)

# ---- 入力 ----
src = sorted(RAW.glob("FX_*.csv"))[-1]
with open(src, encoding="utf-8") as f:
    trade_rows = list(csv.DictReader(f))
with open(WAVES, encoding="utf-8") as f:
    weeks = json.load(f)

# ---- 週マップ ----
week_map = {w["week"]: w for w in weeks}

def date_to_iso_week(d):
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"

# ---- トレード日次集計 ----
trade_by_date = defaultdict(list)
for r in trade_rows:
    try:
        d = datetime.strptime(r["約定日"][:10], "%Y/%m/%d").date()
    except Exception:
        continue
    trade_by_date[d].append({
        "pl": float(r["損益"]) if r["損益"] else 0,
        "order": r["オーダー"],
        "star": r["評価"],
        "lot": float(r["ロット"]) if r["ロット"] else 0,
    })

all_dates = sorted(trade_by_date.keys())
start = all_dates[0].replace(day=1)
end_d = all_dates[-1]
end = (end_d.replace(day=28) + timedelta(days=4)).replace(day=1)

# ---- ADX×DI → 背景クラス ----
# 閾値: ADX<15=凪, 15-25=弱, >=25=強。 spread > 5=UP, <-5=DOWN, それ以外=拮抗。
def adx_style(rec):
    if not rec:
        return "ax-none", "—", "—"
    adx = rec.get("h4_adx46")
    spread = rec.get("h4_di_spread")
    if adx is None or spread is None:
        return "ax-none", "—", "—"
    # 凪
    if adx < 15:
        meta = f"ADX{adx:.0f}"
        return "ax-nagi", meta, "凪"
    # DI拮抗
    if abs(spread) <= 5:
        meta = f"ADX{adx:.0f} ⇄{spread:+.0f}"
        return "ax-flat", meta, "拮抗"
    # 方向あり
    direction = "UP" if spread > 0 else "DOWN"
    strength = "strong" if adx >= 25 else "mild"
    cls = f"ax-{direction.lower()}-{strength}"
    arrow = "↑" if direction == "UP" else "↓"
    meta = f"ADX{adx:.0f} {arrow}{abs(spread):.0f}"
    label = f"{direction}{'強' if strength=='strong' else '弱'}"
    return cls, meta, label

# ---- フェーズバッジ ----
PHASE_BADGE = {
    "BU":     ("ph-bu",     "BU"),
    "PD":     ("ph-pd",     "PD"),
    "凪":     ("ph-nagi",   "凪"),
    "凪離脱": ("ph-leave",  "離脱"),  # ★警告色
    "収束底": ("ph-bottom", "底"),
}

def get_rec(d):
    return week_map.get(date_to_iso_week(d))

# ---- カレンダー ----
def month_iter(s, e):
    cur = s
    while cur < e:
        yield cur
        cur = cur.replace(year=cur.year+1, month=1) if cur.month == 12 else cur.replace(month=cur.month+1)

def month_cells(year, month):
    first = date(year, month, 1)
    start_d = first - timedelta(days=first.weekday())
    last_day = (date(year+1, 1, 1) - timedelta(days=1)) if month == 12 else (date(year, month+1, 1) - timedelta(days=1))
    end_d = last_day + timedelta(days=(6 - last_day.weekday()))
    cur = start_d
    while cur <= end_d:
        yield cur
        cur += timedelta(days=1)

# ---- HTML ----
html = []
html.append("""<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8">
<title>Trades Calendar — マニ v0.2</title>
<style>
* { box-sizing: border-box; }
body {
  margin: 0; background: #05090f; color: #8abaee;
  font-family: -apple-system, BlinkMacSystemFont, 'Hiragino Sans', sans-serif;
  font-size: 12px; padding: 20px;
}
h1 { font-size: 14px; color: #5a9adf; margin: 0 0 4px; letter-spacing: .08em; }
.sub { font-size: 10px; color: #2a4a6a; margin-bottom: 18px; }

.legend {
  display: flex; gap: 12px; margin-bottom: 22px; flex-wrap: wrap;
  font-size: 10px; color: #6a8aaa;
  padding: 10px 12px;
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
}
.legend .grp { display: flex; gap: 8px; align-items: center; }
.legend .grp .ttl { color: #4a7aaa; font-weight: 600; margin-right: 4px; }
.legend .sw {
  width: 22px; height: 14px; border-radius: 2px; display: inline-block;
}
.legend .ph {
  display: inline-block; padding: 1px 5px; border-radius: 3px; font-size: 9px; font-weight: 600;
}

.month {
  margin-bottom: 28px;
  border: 1px solid #162844;
  border-radius: 6px;
  background: #080d16;
  padding: 12px;
}
.month-title { font-size: 13px; color: #5a9adf; margin-bottom: 4px; font-weight: 600; letter-spacing: .05em; }
.month-stats { font-size: 10px; color: #4a7aaa; margin-bottom: 10px; }

.cal { display: grid; grid-template-columns: repeat(7, 1fr); gap: 4px; }
.dow {
  text-align: center; font-size: 10px; color: #2a4a6a; font-weight: 600;
  padding: 4px 0; letter-spacing: .1em;
}
.dow.sat { color: #4a7aaa; }
.dow.sun { color: #aa4a4a; }

.cell {
  aspect-ratio: 1 / 1.15;
  border: 1px solid #0b1825;
  border-radius: 4px;
  padding: 4px;
  display: flex; flex-direction: column;
  font-size: 10px; position: relative;
  background: #05090f;
  overflow: hidden;
}
.cell.outside { opacity: 0.2; }
.cell .day { font-size: 11px; font-weight: 600; color: #4a7aaa; line-height: 1; }
.cell.sat .day { color: #5a8acc; }
.cell.sun .day { color: #cc6a6a; }
.cell .adx-meta {
  font-size: 8px; color: #6a8aaa; margin-top: 1px; letter-spacing: .02em;
  opacity: 0.85;
}
.cell .ph-badge {
  position: absolute; top: 3px; right: 3px;
  font-size: 8px; font-weight: 700; padding: 1px 4px; border-radius: 3px;
  letter-spacing: .03em;
}
.ph-bu     { background: rgba(0,80,40,0.5);   color: #4dffa0; }
.ph-pd     { background: rgba(40,8,80,0.5);   color: #b07af8; }
.ph-nagi   { background: rgba(40,40,55,0.5);  color: #999; }
.ph-leave  { background: #ffcc00;             color: #1a1000; box-shadow: 0 0 4px rgba(255,204,0,0.5); }
.ph-bottom { background: rgba(0,60,80,0.5);   color: #4dccff; }

.cell .star {
  position: absolute; bottom: 26px; right: 3px;
  font-size: 8px; color: #FFD700; opacity: 0.85;
}
.cell .trade {
  margin-top: auto;
  font-size: 11px; font-weight: 700; text-align: center;
  padding: 2px; border-radius: 3px;
}
.tr-win { background: #001a38; color: #5ab8ff; border: 1px solid #1a5090; }
.tr-loss { background: #200008; color: #ef6060; border: 1px solid #5a0a0a; }
.tr-zero { background: #1a1a1a; color: #888; }
.cell .lot { font-size: 8px; color: #6a8aaa; text-align: center; opacity: 0.7; line-height: 1; margin-top: 1px;}

/* ---- ADX × DI 背景パレット ---- */
.ax-none           { background: #05090f; }
.ax-nagi           { background: #0a0a12; border-color: #1a1a22; }
.ax-flat           { background: #150a25; border-color: #3a205a; }
.ax-up-mild        { background: #001020; border-color: #1a3a5a; }
.ax-up-strong      { background: #002a4a; border-color: #2a6090; }
.ax-down-mild      { background: #1a0510; border-color: #4a1a28; }
.ax-down-strong    { background: #3a0818; border-color: #8a2a3a; }
/* 凪離脱の警告枠 */
.cell.leave-warn { box-shadow: inset 0 0 0 1px #ffcc0066; }

.totals {
  margin-top: 18px; padding: 14px;
  background: #080d16; border: 1px solid #162844; border-radius: 6px;
  font-size: 11px;
}
.totals .k { color: #6a8aaa; }
.totals .v { color: #8abaee; font-weight: 600; margin-right: 18px; }

.notes {
  margin-top: 10px; font-size: 10px; color: #4a6a8a;
  line-height: 1.6;
}
</style></head><body>
""")

html.append(f'<h1>TRADES CALENDAR — マニ v0.2</h1>')
html.append(f'<div class="sub">入力: {src.name} / 期間: {all_dates[0]:%Y-%m-%d} 〜 {all_dates[-1]:%Y-%m-%d} / 生成: {datetime.now():%Y-%m-%d %H:%M}</div>')

# legend
html.append('<div class="legend">')
html.append('<div class="grp"><span class="ttl">背景=H4 ADX×DI:</span>')
html.append('<span class="sw ax-nagi"></span>凪(ADX&lt;15)')
html.append('<span class="sw ax-flat"></span>拮抗(|spread|≤5)')
html.append('<span class="sw ax-up-mild"></span>UP弱')
html.append('<span class="sw ax-up-strong"></span>UP強(ADX≥25)')
html.append('<span class="sw ax-down-mild"></span>DOWN弱')
html.append('<span class="sw ax-down-strong"></span>DOWN強(ADX≥25)')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">構造ラベル(H4 Phase Auto):</span>')
for phase, (cls, lbl) in PHASE_BADGE.items():
    html.append(f'<span class="ph {cls}">{lbl}</span>')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">★n:</span>時間帯タグ</div>')
html.append('</div>')

# 月ループ
for m_start in month_iter(start, end):
    cells_in = list(month_cells(m_start.year, m_start.month))
    month_trades = [t for d, ts in trade_by_date.items() if d.year==m_start.year and d.month==m_start.month for t in ts]
    pl_sum = sum(t["pl"] for t in month_trades)
    n_win = sum(1 for t in month_trades if t["pl"]>0)
    n_loss = sum(1 for t in month_trades if t["pl"]<0)

    html.append('<div class="month">')
    html.append(f'<div class="month-title">{m_start.year}年 {m_start.month}月</div>')
    html.append(f'<div class="month-stats">トレード {len(month_trades)}件 (勝{n_win} / 負{n_loss}) — 損益 ¥{pl_sum:+,.0f}</div>')
    html.append('<div class="cal">')

    for i, dow in enumerate(["月","火","水","木","金","土","日"]):
        cls = "dow" + (" sat" if i==5 else (" sun" if i==6 else ""))
        html.append(f'<div class="{cls}">{dow}</div>')

    for d in cells_in:
        is_outside = d.month != m_start.month
        rec = get_rec(d)
        ax_cls, adx_meta, ax_label = adx_style(rec)
        phase = (rec or {}).get("h4_phase_auto", "—")
        ph_tuple = PHASE_BADGE.get(phase)

        classes = ["cell", ax_cls]
        if is_outside: classes.append("outside")
        if d.weekday()==5: classes.append("sat")
        elif d.weekday()==6: classes.append("sun")
        if phase == "凪離脱": classes.append("leave-warn")

        trades = trade_by_date.get(d, [])
        title = f"{d:%Y-%m-%d} | {ax_label} | {adx_meta} | {phase}"
        html.append(f'<div class="{" ".join(classes)}" title="{title}">')
        html.append(f'<div class="day">{d.day}</div>')
        if adx_meta != "—":
            html.append(f'<div class="adx-meta">{adx_meta}</div>')

        if ph_tuple:
            ph_cls, ph_lbl = ph_tuple
            html.append(f'<div class="ph-badge {ph_cls}">{ph_lbl}</div>')

        if trades:
            total_pl = sum(t["pl"] for t in trades)
            stars = ",".join(sorted(set(t["star"] for t in trades if t["star"])))
            lots = sum(t["lot"] for t in trades)
            arrows = "".join("↑" if t["order"]=="買い" else "↓" for t in trades)
            if stars:
                html.append(f'<div class="star">★{stars}</div>')
            tr_cls = "tr-win" if total_pl>0 else ("tr-loss" if total_pl<0 else "tr-zero")
            sign = "+" if total_pl > 0 else ""
            html.append(f'<div class="trade {tr_cls}">{arrows} {sign}{int(total_pl/1000):+d}k</div>')
            html.append(f'<div class="lot">lot {lots:.2f}</div>')

        html.append('</div>')

    html.append('</div></div>')

# サマリ
all_trades = [t for ts in trade_by_date.values() for t in ts]
total_pl = sum(t["pl"] for t in all_trades)
n_win = sum(1 for t in all_trades if t["pl"]>0)
n_loss = sum(1 for t in all_trades if t["pl"]<0)
html.append('<div class="totals">')
html.append(f'<span class="k">全期間</span> <span class="v">{all_dates[0]:%Y-%m-%d} 〜 {all_dates[-1]:%Y-%m-%d}</span>')
html.append(f'<span class="k">トレード</span> <span class="v">{len(all_trades)}件</span>')
html.append(f'<span class="k">勝/負</span> <span class="v">{n_win} / {n_loss}</span>')
html.append(f'<span class="k">総損益</span> <span class="v">¥{total_pl:+,.0f}</span>')
html.append('</div>')

html.append('<div class="notes">')
html.append('読み方: <b>背景色</b>でその週の地合い (ADX強度×DI方向) が瞬時にわかる。<b>右上バッジ</b>で構造ラベル (BU/PD/凪/凪離脱/収束底) が出る。 ')
html.append('<b>「BUバッジだがADXは弱/凪」</b>の日は要警戒 — 構造的にはBU期だが実勢トレンドが出てない＝凪離脱フェイクの温床。 ')
html.append('<b>凪離脱バッジ (黄)</b> は最重要監視対象。')
html.append('</div>')

html.append('</body></html>')

out_path = OUT / "trades_calendar.html"
out_path.write_text("\n".join(html), encoding="utf-8")
print(f"✅ 出力: {out_path}")
print(f"   トレード日数: {len(trade_by_date)}")

# サニティ
missing = [d for d in all_dates if get_rec(d) is None or get_rec(d).get("h4_adx46") is None]
if missing:
    print(f"   ⚠️ ADXデータ未取得日: {len(missing)} (例: {missing[:3]})")
else:
    print(f"   ✓ 全トレード日のADX取得OK")
