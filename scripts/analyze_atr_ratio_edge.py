"""
analyze_atr_ratio_edge.py — ATR Ratio 優位帯炙り出し（ケルトナー点灯条件設計用）

主軸: H1_ATR_Ratio_Median = iATR(H1,16) / median(iATR(H1,16), 直近960バー)
クロス: H1_ATR_Pair = iATR(H1,16)/iATR(H1,32)  (>1=拡張 / <1=収束)
層別: Direction(BUY/SELL), D1_DI_Dir(UP/DN)

固定決済: SL=ATR_Avg32×2.0, RR=1:1.6 → WIN=+1.6R / LOSS=-1.0R
"""
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import load_bt_csv, to_float

CSV = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'


def dedupe_6h(rows):
    parsed = []
    for r in rows:
        ot = r.get('OpenTime', '')
        try:
            dt = datetime.strptime(ot, '%Y.%m.%d %H:%M')
        except ValueError:
            try:
                dt = datetime.strptime(ot, '%Y-%m-%d %H:%M:%S')
            except ValueError:
                continue
        parsed.append((dt, r))
    parsed.sort(key=lambda x: x[0])
    kept, last = [], None
    for dt, r in parsed:
        if last is None or (dt - last).total_seconds() >= 6 * 3600:
            kept.append(r)
            last = dt
    return kept


def stats(rows):
    n = len(rows)
    if n == 0:
        return None
    wins = [r for r in rows if r.get('Result') == 'WIN']
    losses = [r for r in rows if r.get('Result') == 'LOSS']
    wp = sum(to_float(r.get('Profit_USD')) for r in wins)
    lp = sum(to_float(r.get('Profit_USD')) for r in losses)
    net = sum(to_float(r.get('Profit_USD')) for r in rows)
    wr = len(wins) / n * 100
    pf = (wp / abs(lp)) if lp != 0 else float('inf')
    # WR-implied PF (RR1.6固定なら理論上の PF)
    implied_pf = (1.6 * len(wins) / len(losses)) if losses else float('inf')
    avg_pips = sum(to_float(r.get('Profit_Pips')) for r in rows) / n
    avg_mfe = sum(to_float(r.get('MFE')) for r in rows) / n
    avg_mae = sum(to_float(r.get('MAE')) for r in rows) / n
    return dict(n=n, w=len(wins), l=len(losses), wr=wr, pf=pf,
                implied_pf=implied_pf, net=net, avg_pips=avg_pips,
                avg_mfe=avg_mfe, avg_mae=avg_mae)


def fp(pf):
    return 'inf' if pf == float('inf') else f'{pf:.2f}'


# 主軸ビン（Zone定義に整合: 0.70=LOW境界, 1.0=中央値, 1.40=HIGH境界）
def ratio_bin(v):
    if v < 0.70:
        return '1_<0.70(LOW)'
    if v < 1.00:
        return '2_0.70-1.00'
    if v < 1.20:
        return '3_1.00-1.20'
    if v < 1.40:
        return '4_1.20-1.40'
    if v < 1.70:
        return '5_1.40-1.70'
    return '6_1.70+'


def print_table(title, groups, order=None):
    print(f'\n### {title}')
    print(f"{'cell':<34}{'N':>4}{'WR%':>7}{'PF':>7}{'impPF':>7}{'Net$':>9}{'avgPip':>8}{'MFE':>7}{'MAE':>7}")
    keys = order if order else sorted(groups.keys())
    for k in keys:
        if k not in groups:
            continue
        s = stats(groups[k])
        if not s:
            continue
        flag = ' *' if s['n'] < 20 else ''
        print(f"{str(k):<34}{s['n']:>4}{s['wr']:>7.1f}{fp(s['pf']):>7}{fp(s['implied_pf']):>7}"
              f"{s['net']:>9.0f}{s['avg_pips']:>8.1f}{s['avg_mfe']:>7.1f}{s['avg_mae']:>7.1f}{flag}")


def main():
    raw = load_bt_csv(CSV)
    rows = dedupe_6h(raw)
    print(f"raw={len(raw)}  6h-dedup={len(rows)}")

    # Result値の確認
    rv = defaultdict(int)
    for r in raw:
        rv[r.get('Result')] += 1
    print("Result分布(raw):", dict(rv))

    # RR確認: TP_Pips/SL_Pips
    rr = [to_float(r.get('TP_Pips')) / to_float(r.get('SL_Pips'))
          for r in raw if to_float(r.get('SL_Pips')) > 0]
    print(f"TP/SL比 min={min(rr):.3f} max={max(rr):.3f} mean={sum(rr)/len(rr):.3f}")

    # 全体
    print('\n=== 全体(6h-dedup) ===')
    s = stats(rows)
    print(f"N={s['n']} WR={s['wr']:.1f}% PF={fp(s['pf'])} impPF={fp(s['implied_pf'])} Net=${s['net']:.0f}")

    # H1_Ratio_Median 分布
    vals = sorted(to_float(r.get('H1_ATR_Ratio_Median')) for r in rows)
    n = len(vals)
    pct = lambda p: vals[int(n * p)]
    print(f"\nH1_ATR_Ratio_Median 分布: min={vals[0]:.3f} P10={pct(.1):.3f} P25={pct(.25):.3f} "
          f"P50={pct(.5):.3f} P75={pct(.75):.3f} P90={pct(.9):.3f} max={vals[-1]:.3f}")

    # Zone分布
    zc = defaultdict(int)
    for r in rows:
        zc[ratio_bin(to_float(r.get('H1_ATR_Ratio_Median')))] += 1
    print("ビン件数:", {k: zc[k] for k in sorted(zc)})

    # ---- 1. 主軸: H1_Ratio bin (全方向) ----
    g = defaultdict(list)
    for r in rows:
        g[ratio_bin(to_float(r.get('H1_ATR_Ratio_Median')))].append(r)
    print_table('1. H1_ATR_Ratio_Median bin × 全方向', g, order=sorted(g))

    # ---- 2. 主軸 × Direction ----
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') == d:
                g[ratio_bin(to_float(r.get('H1_ATR_Ratio_Median')))].append(r)
        print_table(f'2. H1_Ratio bin × Direction={d}', g, order=sorted(g))

    # ---- 3. 主軸 × Direction × Pair(拡張/収束) ----
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') != d:
                continue
            pair = to_float(r.get('H1_ATR_Pair'))
            ps = 'EXP' if pair > 1.0 else 'CON'
            g[(ratio_bin(to_float(r.get('H1_ATR_Ratio_Median'))), ps)].append(r)
        print_table(f'3. H1_Ratio × Pair(1.0境界) × Dir={d}', g, order=sorted(g))

    # ---- 4. 主軸 × Direction × D1_DI_Dir (局面層別) ----
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') != d:
                continue
            g[(ratio_bin(to_float(r.get('H1_ATR_Ratio_Median'))), r.get('D1_DI_Dir'))].append(r)
        print_table(f'4. H1_Ratio × D1_DI_Dir × Dir={d}', g, order=sorted(g))

    # ---- 5. 主軸 × Direction × H1_ATR_Pattern ----
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') != d:
                continue
            g[(ratio_bin(to_float(r.get('H1_ATR_Ratio_Median'))), r.get('H1_ATR_Pattern'))].append(r)
        # N>=8 のみ
        g2 = {k: v for k, v in g.items() if len(v) >= 8}
        print_table(f'5. H1_Ratio × H1_ATR_Pattern × Dir={d} (N>=8のみ)', g2, order=sorted(g2))

    # ---- 6. H4_Ratio bin × Direction (H4側) ----
    def h4bin(v):
        if v < 0.70:
            return '1_<0.70'
        if v < 1.00:
            return '2_0.70-1.00'
        if v < 1.20:
            return '3_1.00-1.20'
        if v < 1.40:
            return '4_1.20-1.40'
        return '5_1.40+'
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') == d:
                g[h4bin(to_float(r.get('H4_ATR_Ratio_Median')))].append(r)
        print_table(f'6. H4_ATR_Ratio_Median bin × Dir={d}', g, order=sorted(g))

    # ---- 7. H1_Ratio × H4_Ratio 二軸 (拡張整合) × Direction ----
    for d in ('BUY', 'SELL'):
        g = defaultdict(list)
        for r in rows:
            if r.get('Direction') != d:
                continue
            h1 = 'H1lo' if to_float(r.get('H1_ATR_Ratio_Median')) < 1.0 else 'H1hi'
            h4 = 'H4lo' if to_float(r.get('H4_ATR_Ratio_Median')) < 1.0 else 'H4hi'
            g[(h1, h4)].append(r)
        print_table(f'7. H1_Ratio<>1.0 × H4_Ratio<>1.0 × Dir={d}', g, order=sorted(g))


if __name__ == '__main__':
    main()
