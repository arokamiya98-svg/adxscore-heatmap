#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DXY H1 手描きBU/PD波の一次分析
  ① 全体俯瞰（期間・件数・重複チェック）
  ② duration分布 → 波の規模（大中小）クラスタ確認
  ③ 規模別の周期候補（反周期メソッド: 短期=BU中央値, 長期=サイクル）
  ④ BU/PDごとの MFE/MAE（方向中立の上振れ/下振れにも展開）
入力: FractalWaveLog_H1_DXY.csv (UTF-8 BOM, 65列)
"""
import csv, statistics, sys
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
        for k in ("price_change_pips","atr_s_start","atr_s_end","atr_s_delta",
                  "atr_s_ratio","mfe_pips","mae_pips","mfe_mae_ratio",
                  "q1_change_pips","q2_change_pips","q3_change_pips","q4_change_pips",
                  "adx_start","adx_end","line_delta"):
            r[k+"_f"] = f(r[k])
        rows.append(r)

rows.sort(key=lambda r: r["t_start"])

print("=" * 70)
print("① 全体俯瞰")
print("=" * 70)
bu = [r for r in rows if r["pattern_type"] == "BU"]
pd = [r for r in rows if r["pattern_type"] == "PD"]
print(f"総数: {len(rows)}  BU={len(bu)}  PD={len(pd)}")
print(f"期間: {rows[0]['t_start']} 〜 {max(r['t_end'] for r in rows)}")

# 重複チェック（同一 start/end/type）
seen, dups = set(), 0
for r in rows:
    key = (r["start_time"], r["end_time"], r["pattern_type"])
    if key in seen: dups += 1
    seen.add(key)
print(f"重複線: {dups}")

def pstats(vals, label):
    if not vals:
        print(f"  {label}: n=0"); return
    vs = sorted(vals)
    n = len(vs)
    p25 = vs[int(n*0.25)]; p75 = vs[min(n-1, int(n*0.75))]
    print(f"  {label}: n={n}  中央値={statistics.median(vs):.1f}  平均={statistics.mean(vs):.1f}  "
          f"p25={p25:.1f}  p75={p75:.1f}  min={vs[0]:.1f}  max={vs[-1]:.1f}")

print()
print("=" * 70)
print("② duration分布（波の規模）")
print("=" * 70)
pstats([r["duration"] for r in bu], "BU duration(bars)")
pstats([r["duration"] for r in pd], "PD duration(bars)")

# テキストヒストグラム（5barビン）
print("\n  ヒストグラム（5barビン, B=BU / P=PD）")
maxd = max(r["duration"] for r in rows)
for lo in range(0, maxd + 5, 5):
    hi = lo + 5
    nb = sum(1 for r in bu if lo <= r["duration"] < hi)
    np_ = sum(1 for r in pd if lo <= r["duration"] < hi)
    if nb + np_ == 0: continue
    print(f"  {lo:3d}-{hi:3d}: {'B'*nb}{'P'*np_}  ({nb+np_})")

print("\n  duration全ソート(BU):", sorted(r["duration"] for r in bu))
print("  duration全ソート(PD):", sorted(r["duration"] for r in pd))

# PD/BU比（φチェック）
mb = statistics.median([r["duration"] for r in bu])
mp = statistics.median([r["duration"] for r in pd])
print(f"\n  PD/BU duration中央値比: {mp/mb:.3f}  (φ=1.618, XAU H1手描き≒23/17=1.35)")

print()
print("=" * 70)
print("③ ATR拡張/収縮の振幅（XAU肖像との比較用）")
print("=" * 70)
for name, grp in (("BU", bu), ("PD", pd)):
    chg = [ (r["atr_s_end_f"]-r["atr_s_start_f"])/r["atr_s_start_f"]*100
            for r in grp if r["atr_s_start_f"] ]
    pstats(chg, f"{name} ATR短期変化率%")

print()
print("=" * 70)
print("④ MFE/MAE（BU/PD別）")
print("=" * 70)
print("※ スクリプト定義: BU=上方向を有利/PD=下方向を有利 と仮置きした値")
for name, grp in (("BU", bu), ("PD", pd)):
    print(f"\n--- {name} ---")
    pstats([r["mfe_pips_f"] for r in grp], "MFE(pips)")
    pstats([r["mae_pips_f"] for r in grp], "MAE(pips)")
    pstats([r["mfe_mae_ratio_f"] for r in grp if r["mfe_mae_ratio_f"] is not None and r["mfe_mae_ratio_f"] < 900], "MFE/MAE比")
    pstats([r["price_change_pips_f"] for r in grp], "price変化(pips)")

# 方向中立に展開: 上振れ/下振れ
print("\n--- 方向中立（波の間の最大上振れ/最大下振れ） ---")
for name, grp in (("BU", bu), ("PD", pd)):
    up = [ r["mfe_pips_f"] if r["pattern_type"]=="BU" else r["mae_pips_f"] for r in grp ]
    dn = [ r["mae_pips_f"] if r["pattern_type"]=="BU" else r["mfe_pips_f"] for r in grp ]
    pstats(up, f"{name} 最大上振れ(pips)")
    pstats(dn, f"{name} 最大下振れ(pips)")

# 四分位プロファイル（波の中のどこで動くか）
print("\n--- 四分位プロファイル（q1〜q4 の price変化平均, pips） ---")
for name, grp in (("BU", bu), ("PD", pd)):
    qs = []
    for q in ("q1","q2","q3","q4"):
        vals = [r[q+"_change_pips_f"] for r in grp if r[q+"_change_pips_f"] is not None]
        qs.append(statistics.mean(vals) if vals else 0)
    print(f"  {name}: q1={qs[0]:+.1f}  q2={qs[1]:+.1f}  q3={qs[2]:+.1f}  q4={qs[3]:+.1f}")
