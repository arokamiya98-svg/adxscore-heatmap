#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DXY H1 手描き波 二次分析
  ⑤ 波の連鎖構造（入れ子 or 交互チェーン）
  ⑥ 規模クラス分け（入れ子があれば階層で、なければduration分位で）
  ⑦ 規模別の周期候補 + MFE/MAE
"""
import csv, statistics
from datetime import datetime

PATH = "/Users/aro/Desktop/ADXSCORE/data/dxy/FractalWaveLog_H1_DXY.csv"

def f(x):
    try: return float(x)
    except: return None

rows = []
with open(PATH, encoding="utf-8-sig") as fh:
    for r in csv.DictReader(fh):
        r["duration"] = int(r["duration_bars"])
        r["t_start"] = datetime.strptime(r["start_time"], "%Y.%m.%d %H:%M")
        r["t_end"]   = datetime.strptime(r["end_time"],   "%Y.%m.%d %H:%M")
        for k in ("mfe_pips","mae_pips","price_change_pips","atr_s_start","atr_s_end"):
            r[k+"_f"] = f(r[k])
        rows.append(r)
rows.sort(key=lambda r: (r["t_start"], r["t_end"]))

print("=" * 70)
print("⑤ 波の連鎖構造")
print("=" * 70)

# 入れ子: 他の波に完全に内包される波
nested = 0
container = 0
for a in rows:
    inside = any(b is not a and b["t_start"] <= a["t_start"] and a["t_end"] <= b["t_end"] for b in rows)
    contains = any(b is not a and a["t_start"] <= b["t_start"] and b["t_end"] <= a["t_end"] for b in rows)
    a["is_nested"] = inside
    a["is_container"] = contains
    if inside: nested += 1
    if contains: container += 1
print(f"他の波に完全内包される波: {nested} / 78")
print(f"他の波を内包する波:       {container} / 78")

# 部分重なり
overlap = 0
for i, a in enumerate(rows):
    for b in rows[i+1:]:
        if b["t_start"] < a["t_end"] and a["t_end"] < b["t_end"]:
            overlap += 1
print(f"部分重なりペア:           {overlap}")

# 交互チェーン: 時系列で BU→PD→BU… の並びと、前の波の終点≒次の波の始点か
seq = "".join("B" if r["pattern_type"] == "BU" else "P" for r in rows)
alt = sum(1 for i in range(len(seq)-1) if seq[i] != seq[i+1])
print(f"\n時系列パターン列: {seq}")
print(f"交互率（隣が異種）: {alt}/{len(seq)-1} = {alt/(len(seq)-1)*100:.0f}%")

gaps = []
for i in range(len(rows)-1):
    gap_h = (rows[i+1]["t_start"] - rows[i]["t_end"]).total_seconds() / 3600
    gaps.append(gap_h)
gz = sorted(gaps)
print(f"波間ギャップ(時間): 中央値={statistics.median(gz):.0f}h  p25={gz[int(len(gz)*.25)]:.0f}h  p75={gz[int(len(gz)*.75)]:.0f}h  min={gz[0]:.0f}h  max={gz[-1]:.0f}h")
neg = sum(1 for g in gaps if g < -1)
print(f"重なり(gap<-1h)の箇所: {neg} / {len(gaps)}")

print()
print("=" * 70)
print("⑥ 規模クラス（BU/PD別 duration三分位: 小/中/大）")
print("=" * 70)

def terciles(grp):
    ds = sorted(r["duration"] for r in grp)
    n = len(ds)
    t1, t2 = ds[n//3], ds[2*n//3]
    return t1, t2

def cls_of(d, t1, t2):
    return "小" if d < t1 else ("大" if d >= t2 else "中")

def pstats(vals, label, dec=1):
    if not vals:
        print(f"    {label}: n=0"); return
    vs = sorted(vals)
    n = len(vs)
    print(f"    {label}: n={n}  中央値={statistics.median(vs):.{dec}f}  平均={statistics.mean(vs):.{dec}f}  "
          f"p25={vs[int(n*0.25)]:.{dec}f}  p75={vs[min(n-1,int(n*0.75))]:.{dec}f}")

for name in ("BU", "PD"):
    grp = [r for r in rows if r["pattern_type"] == name]
    t1, t2 = terciles(grp)
    print(f"\n--- {name}（三分位境界: {t1} / {t2} bars） ---")
    for cls in ("小", "中", "大"):
        sub = [r for r in grp if cls_of(r["duration"], t1, t2) == cls]
        durs = [r["duration"] for r in sub]
        print(f"  [{cls}] n={len(sub)}  duration中央値={statistics.median(durs):.0f}  範囲={min(durs)}-{max(durs)}")
        pstats([r["mfe_pips_f"] for r in sub], "MFE(pips)")
        pstats([r["mae_pips_f"] for r in sub], "MAE(pips)")
        atr_chg = [(r["atr_s_end_f"]-r["atr_s_start_f"])/r["atr_s_start_f"]*100 for r in sub if r["atr_s_start_f"]]
        pstats(atr_chg, "ATR変化率%")

print()
print("=" * 70)
print("⑦ 周期候補（反周期メソッド）")
print("=" * 70)
bu = [r for r in rows if r["pattern_type"] == "BU"]
pd = [r for r in rows if r["pattern_type"] == "PD"]
mb = statistics.median([r["duration"] for r in bu])
mp = statistics.median([r["duration"] for r in pd])
print(f"全体:   BU中央値={mb:.0f}  PD中央値={mp:.0f}  サイクル(BU+PD)={mb+mp:.0f}")
print(f"  → 短期候補 ≈ {mb:.0f}  長期候補 ≈ {2*mb:.0f}(2x規則) 〜 {mb+mp:.0f}(フルサイクル)")
for name, grp in (("BU", bu), ("PD", pd)):
    t1, t2 = terciles(grp)
    for cls in ("小", "中", "大"):
        sub = [r["duration"] for r in grp if cls_of(r["duration"], t1, t2) == cls]
        print(f"  {name}[{cls}] duration中央値 = {statistics.median(sub):.0f}")
