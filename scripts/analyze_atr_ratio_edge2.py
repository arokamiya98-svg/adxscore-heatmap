"""ATR Ratio エッジ — ゲート境界の精緻化 + 時系列分散検査"""
import sys
from collections import defaultdict
from datetime import datetime
sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import load_bt_csv, to_float
from analyze_atr_ratio_edge import dedupe_6h, stats, fp

CSV = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'
rows = dedupe_6h(load_bt_csv(CSV))


def show(label, sub):
    s = stats(sub)
    if not s:
        print(f"{label:<40} N=0")
        return
    flag = ' *' if s['n'] < 20 else ''
    print(f"{label:<40}N={s['n']:>3} WR={s['wr']:>5.1f}% PF={fp(s['pf']):>5} impPF={fp(s['implied_pf']):>5} Net=${s['net']:>6.0f}{flag}")


def R(r):
    return to_float(r.get('H1_ATR_Ratio_Median'))


def yrmo(rows_):
    c = defaultdict(int)
    for r in rows_:
        ot = r.get('OpenTime', '')[:7]
        c[ot] += 1
    return dict(sorted(c.items()))


print("=== A. 細刻みビン × Direction ===")
fine = [('<0.70', 0, 0.70), ('0.70-0.85', 0.70, 0.85), ('0.85-1.00', 0.85, 1.00),
        ('1.00-1.10', 1.00, 1.10), ('1.10-1.20', 1.10, 1.20),
        ('1.20-1.40', 1.20, 1.40), ('1.40+', 1.40, 9)]
for d in ('BUY', 'SELL'):
    print(f"-- {d} --")
    for lab, lo, hi in fine:
        sub = [r for r in rows if r.get('Direction') == d and lo <= R(r) < hi]
        show(f"  {lab}", sub)

print("\n=== B. 累積しきい値カット(下限0.70想定) × Direction ===")
for d in ('BUY', 'SELL'):
    print(f"-- {d} --")
    for T in (1.00, 1.10, 1.20):
        lowband = [r for r in rows if r.get('Direction') == d and 0.70 <= R(r) < T]
        highband = [r for r in rows if r.get('Direction') == d and R(r) >= T]
        show(f"  0.70<=R<{T}", lowband)
        show(f"  R>={T}", highband)

print("\n=== C. SELL の局面ゲート効果 (1.00<=R<1.20) ===")
sell_band = [r for r in rows if r.get('Direction') == 'SELL' and 1.00 <= R(r) < 1.20]
show("  SELL 1.00-1.20 全局面", sell_band)
show("  SELL 1.00-1.20 × DN", [r for r in sell_band if r.get('D1_DI_Dir') == 'DN'])
show("  SELL 1.00-1.20 × UP", [r for r in sell_band if r.get('D1_DI_Dir') == 'UP'])

print("\n=== D. 推奨ゲート候補の最終確認 ===")
show("BUY  0.70<=R<1.00 (押し目帯)", [r for r in rows if r.get('Direction') == 'BUY' and 0.70 <= R(r) < 1.00])
show("BUY  0.70<=R<1.00 & Pair>1(EXP)", [r for r in rows if r.get('Direction') == 'BUY' and 0.70 <= R(r) < 1.00 and to_float(r.get('H1_ATR_Pair')) > 1.0])
show("BUY  0.70<=R<1.20 (緩め)", [r for r in rows if r.get('Direction') == 'BUY' and 0.70 <= R(r) < 1.20])
show("SELL 1.00<=R<1.20 & DN", [r for r in rows if r.get('Direction') == 'SELL' and 1.00 <= R(r) < 1.20 and r.get('D1_DI_Dir') == 'DN'])
show("DIR非依存 0.70<=R<1.20", [r for r in rows if 0.70 <= R(r) < 1.20])
show("DIR非依存 R>=1.20 (OFF候補)", [r for r in rows if R(r) >= 1.20])

print("\n=== E. 推奨帯の時系列分散(YYYY-MM別件数) ===")
print("BUY 0.70-1.00:", yrmo([r for r in rows if r.get('Direction') == 'BUY' and 0.70 <= R(r) < 1.00]))
print("SELL 1.00-1.20×DN:", yrmo([r for r in rows if r.get('Direction') == 'SELL' and 1.00 <= R(r) < 1.20 and r.get('D1_DI_Dir') == 'DN']))

print("\n=== F. 局面分布(全体のDI_Dir偏り確認) ===")
di = defaultdict(int)
for r in rows:
    di[r.get('D1_DI_Dir')] += 1
print("D1_DI_Dir:", dict(di), f"  DN率={di.get('DN',0)/len(rows)*100:.1f}%")
