"""
46版 ATR_RATIO 分布の多軸クロス分析

目的:
- ATR_RATIO 分布 × 勝敗 × 局面 × 方向
- H1 × H4 × D1 ATR_RATIO 3軸クロス
- オープン探索: 勝敗で大きく分布が違う他列

対象: data/bt/ATR_WidthSignal_BT_h4adx46.csv (6h重複削除後)
"""
import sys
import statistics
from collections import defaultdict

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import load_bt_csv, to_float, bt_overview
from compare_30_46_filtered import filter_6h_duplicates


# ============================================================
# ユーティリティ
# ============================================================

def dist_stats(values):
    """連続変数の統計値 (N, mean, p25, p50, p75, min, max)"""
    vals = [v for v in values if v is not None]
    if not vals:
        return {'n': 0}
    vals_s = sorted(vals)
    n = len(vals_s)
    def pct(p):
        idx = max(0, min(n-1, int(round(p * (n-1)))))
        return vals_s[idx]
    return {
        'n': n,
        'mean': round(statistics.mean(vals_s), 3),
        'p25': round(pct(0.25), 3),
        'p50': round(pct(0.50), 3),
        'p75': round(pct(0.75), 3),
        'min': round(min(vals_s), 3),
        'max': round(max(vals_s), 3),
    }


def fmt(s):
    """dict を1行で整形"""
    if s.get('n', 0) == 0:
        return 'N=0'
    return (f"N={s['n']:>3} mean={s['mean']:>6.3f} "
            f"p25={s['p25']:>6.3f} p50={s['p50']:>6.3f} p75={s['p75']:>6.3f} "
            f"[{s['min']:.2f}-{s['max']:.2f}]")


def overview_short(rows):
    """1行overview"""
    ov = bt_overview(rows)
    if ov['n'] == 0:
        return 'N=0'
    return f"N={ov['n']:>3} WR={ov['wr_pct']:>5.1f}% PF={ov['pf']:>5.2f} Net=${ov['net_usd']:>+7.1f}"


def bin_by_quartile(rows, col):
    """指定列で四分位（Q1=低/Q2/Q3/Q4=高）に分割"""
    vals = sorted([to_float(r.get(col)) for r in rows])
    n = len(vals)
    if n < 4:
        return None
    q1 = vals[int(n*0.25)]
    q2 = vals[int(n*0.50)]
    q3 = vals[int(n*0.75)]
    bins = {'Q1(低)': [], 'Q2': [], 'Q3': [], 'Q4(高)': []}
    for r in rows:
        v = to_float(r.get(col))
        if v <= q1:
            bins['Q1(低)'].append(r)
        elif v <= q2:
            bins['Q2'].append(r)
        elif v <= q3:
            bins['Q3'].append(r)
        else:
            bins['Q4(高)'].append(r)
    return bins, (q1, q2, q3)


def bin_3way(rows, col, low_threshold=0.95, high_threshold=1.10):
    """ATR_RATIO を3区分: 凪(<0.95) / 中(0.95-1.10) / 拡張(>1.10)
       閾値はXAUUSDでの ATR_RATIO の自然な分布点を参考に設定
    """
    bins = {'凪(低)': [], '中': [], '拡張(高)': []}
    for r in rows:
        v = to_float(r.get(col))
        if v < low_threshold:
            bins['凪(低)'].append(r)
        elif v <= high_threshold:
            bins['中'].append(r)
        else:
            bins['拡張(高)'].append(r)
    return bins


# ============================================================
# Section 1: ATR_RATIO 分布 × 勝敗 × 局面 × 方向
# ============================================================

def section_1_ratio_distribution(rows, ratio_col, tf_name):
    print(f"\n--- {tf_name} ({ratio_col}) ---")

    # 1-A. 全体 × WIN/LOSS
    wins = [r for r in rows if r.get('Result') == 'WIN']
    losses = [r for r in rows if r.get('Result') == 'LOSS']

    s_win = dist_stats([to_float(r.get(ratio_col)) for r in wins])
    s_loss = dist_stats([to_float(r.get(ratio_col)) for r in losses])
    s_all = dist_stats([to_float(r.get(ratio_col)) for r in rows])

    print(f"  [全体 × 勝敗]")
    print(f"    全体 : {fmt(s_all)}")
    print(f"    WIN  : {fmt(s_win)}")
    print(f"    LOSS : {fmt(s_loss)}")
    delta_mean = s_win.get('mean', 0) - s_loss.get('mean', 0)
    delta_p50 = s_win.get('p50', 0) - s_loss.get('p50', 0)
    print(f"    Δmean(WIN-LOSS): {delta_mean:+.3f}  Δp50: {delta_p50:+.3f}")

    # 1-B. 局面別 (D1_ATR_Cross_Dir)
    print(f"  [局面別 (D1_ATR_Cross_Dir)]")
    for regime in ['BU', 'PD', 'NONE']:
        grp = [r for r in rows if r.get('D1_ATR_Cross_Dir') == regime]
        if not grp:
            continue
        s_grp = dist_stats([to_float(r.get(ratio_col)) for r in grp])
        print(f"    {regime:<5}: {fmt(s_grp)}")

    # 1-C. 方向別 × 勝敗
    print(f"  [方向別 × 勝敗]")
    for direction in ['BUY', 'SELL']:
        grp = [r for r in rows if r.get('Direction') == direction]
        if not grp:
            continue
        g_win = [r for r in grp if r.get('Result') == 'WIN']
        g_loss = [r for r in grp if r.get('Result') == 'LOSS']
        s_w = dist_stats([to_float(r.get(ratio_col)) for r in g_win])
        s_l = dist_stats([to_float(r.get(ratio_col)) for r in g_loss])
        delta = s_w.get('mean', 0) - s_l.get('mean', 0)
        print(f"    {direction} WIN  : {fmt(s_w)}")
        print(f"    {direction} LOSS : {fmt(s_l)}  Δmean={delta:+.3f}")

    # 1-D. 帯別（3区分 凪/中/拡張） × WR/PF
    print(f"  [3区分帯別 (凪<0.95 / 中 / 拡張>1.10) × WR/PF/Net]")
    bins = bin_3way(rows, ratio_col, 0.95, 1.10)
    for bname, brows in bins.items():
        print(f"    {bname:<7}: {overview_short(brows)}")

    # 1-E. 帯別 × 方向別
    print(f"  [帯別 × Direction]")
    for bname, brows in bins.items():
        for direction in ['BUY', 'SELL']:
            sub = [r for r in brows if r.get('Direction') == direction]
            if len(sub) >= 5:
                print(f"    {bname:<7} × {direction}: {overview_short(sub)}")


# ============================================================
# Section 2: H1 × H4 × D1 ATR_RATIO 3軸クロス
# ============================================================

def section_2_three_axis_cross(rows):
    """H1 ratio × H4 ratio × D1 (ATR_Pair等) を3区分でクロス"""
    print("\n=== Section 2: H1 × H4 × D1 ATR_RATIO 3軸クロス ===")

    # D1 については D1_ATR_Pair（Short/Long ratio相当）を生成
    # D1_ATR_Short / D1_ATR_Long の比を ratio として扱う
    d1_ratios = []
    for r in rows:
        s = to_float(r.get('D1_ATR_Short'))
        l = to_float(r.get('D1_ATR_Long'))
        d1_ratios.append(s/l if l > 0 else None)

    # 3区分閾値
    def classify(v, lo, hi):
        if v is None:
            return None
        if v < lo:
            return '凪'
        elif v <= hi:
            return '中'
        else:
            return '拡張'

    # 各 row に Bin タグを付ける
    tagged = []
    for r, d1r in zip(rows, d1_ratios):
        h1 = classify(to_float(r.get('H1_ATR_Ratio_Median')), 0.95, 1.10)
        h4 = classify(to_float(r.get('H4_ATR_Ratio_Median')), 0.95, 1.10)
        d1 = classify(d1r, 0.95, 1.10)
        if h1 and h4 and d1:
            tagged.append((h1, h4, d1, r))

    print(f"  3軸タグ付与可能数: {len(tagged)}/{len(rows)}")

    # 3軸クロス
    cube = defaultdict(list)
    for h1, h4, d1, r in tagged:
        cube[(h1, h4, d1)].append(r)

    print(f"\n  [全組み合わせ (N>=5)]")
    print(f"  {'H1':<5} {'H4':<5} {'D1':<5} | {'N':>4} {'WR%':>5} {'PF':>6} {'Net':>9}")
    print(f"  " + "-"*55)
    items = sorted(cube.items(), key=lambda x: (x[0][0], x[0][1], x[0][2]))
    for (h1, h4, d1), grp in items:
        if len(grp) < 5:
            continue
        ov = bt_overview(grp)
        print(f"  {h1:<5} {h4:<5} {d1:<5} | {ov['n']:>4} {ov['wr_pct']:>5.1f} {ov['pf']:>6.2f} ${ov['net_usd']:>+7.1f}")

    # 注目組み合わせ抽出
    print(f"\n  [注目: 想定ケース]")
    cases = [
        ('全凪 (H1=凪 × H4=凪 × D1=凪)', [('凪', '凪', '凪')]),
        ('全拡張 (H1=拡張 × H4=拡張 × D1=拡張)', [('拡張', '拡張', '拡張')]),
        ('時間軸ねじれ (H1=拡張 × H4=凪)', [(h1, h4, d1) for h1 in ['拡張'] for h4 in ['凪'] for d1 in ['凪', '中', '拡張']]),
        ('短期ピーク先行 (H1=凪 × H4=拡張)', [(h1, h4, d1) for h1 in ['凪'] for h4 in ['拡張'] for d1 in ['凪', '中', '拡張']]),
    ]
    for case_name, keys in cases:
        merged = []
        for k in keys:
            merged.extend(cube.get(k, []))
        if len(merged) >= 5:
            print(f"    {case_name}: {overview_short(merged)}")
        else:
            print(f"    {case_name}: N={len(merged)} (サンプル不足)")


# ============================================================
# Section 3: オープン探索 (勝敗で分布差が大きい列)
# ============================================================

def section_3_open_exploration(rows):
    """各列 (連続変数) で WIN vs LOSS の mean 差を測り、上位列を抽出"""
    print("\n=== Section 3: オープン探索 ===")

    # 候補列
    candidate_cols = [
        # DI
        'H1_DI_Plus', 'H1_DI_Minus', 'H1_DI_Spread',
        'H4_DI_Plus', 'H4_DI_Minus', 'H4_DI_Spread',
        'D1_DI_Plus', 'D1_DI_Minus', 'D1_DI_Spread',
        # DI Vel / Slope
        'H1_DI_Plus_Vel3', 'H1_DI_Plus_Vel8', 'H1_DI_Plus_Slope',
        'H1_DI_Minus_Vel3', 'H1_DI_Minus_Vel8', 'H1_DI_Minus_Slope',
        'H4_DI_Plus_Vel3', 'H4_DI_Plus_Vel8', 'H4_DI_Plus_Slope',
        'H4_DI_Minus_Vel3', 'H4_DI_Minus_Vel8', 'H4_DI_Minus_Slope',
        # ADX
        'H1_ADX', 'H4_ADX', 'D1_ADX',
        # MA Dist
        'H1_MA_Dist', 'H4_MA_Dist',
        # ATR
        'H1_ATR_Median', 'H4_ATR_Median',
        'H1_Vel3', 'H4_Vel3', 'H1_ATR_Accel', 'H4_ATR_Accel',
        # H4 Cross
        'H4_Cross_Bars_H4', 'H4_Cross_Bars_H1conv',
        # Hour
        'Hour',
    ]

    wins = [r for r in rows if r.get('Result') == 'WIN']
    losses = [r for r in rows if r.get('Result') == 'LOSS']

    # 各列について effect size 風に評価: |Δmean| / pooled_std
    print(f"  [WIN vs LOSS 差分が大きい列 上位10]")
    scored = []
    for col in candidate_cols:
        wv = [to_float(r.get(col)) for r in wins]
        lv = [to_float(r.get(col)) for r in losses]
        if not wv or not lv:
            continue
        m_w = statistics.mean(wv)
        m_l = statistics.mean(lv)
        all_v = wv + lv
        try:
            std = statistics.stdev(all_v) if len(all_v) > 1 else 0
        except statistics.StatisticsError:
            std = 0
        if std == 0:
            continue
        effect = abs(m_w - m_l) / std
        scored.append((col, m_w, m_l, effect, std))

    scored.sort(key=lambda x: -x[3])
    print(f"  {'Col':<28} {'WIN mean':>10} {'LOSS mean':>10} {'Δ':>8} {'effect':>7}")
    print(f"  " + "-"*70)
    for col, m_w, m_l, eff, std in scored[:10]:
        print(f"  {col:<28} {m_w:>10.3f} {m_l:>10.3f} {(m_w-m_l):>+8.3f} {eff:>7.3f}")

    return scored[:5]


def section_3b_top_columns_detail(rows, top_cols):
    """上位列について四分位帯別の WR/PF を見る"""
    print(f"\n  [上位列 詳細: 帯別 WR/PF/Net]")
    for col_info in top_cols:
        col = col_info[0]
        result = bin_by_quartile(rows, col)
        if result is None:
            continue
        bins, (q1, q2, q3) = result
        print(f"\n  --- {col} (q1={q1:.2f}, q2={q2:.2f}, q3={q3:.2f}) ---")
        for bname, brows in bins.items():
            print(f"    {bname:<6}: {overview_short(brows)}")


# ============================================================
# Main
# ============================================================

def main():
    print("=" * 70)
    print("46版 ATR_RATIO 分布の多軸クロス分析")
    print("=" * 70)

    path = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'
    rows_raw = load_bt_csv(path)
    rows = filter_6h_duplicates(rows_raw)

    print(f"\n[前提]")
    print(f"  入力: {path}")
    print(f"  raw N={len(rows_raw)}, 6h後 N={len(rows)}")
    ov = bt_overview(rows)
    print(f"  6h後 overview: WR={ov['wr_pct']}% PF={ov['pf']} Net=${ov['net_usd']}")

    # 局面・方向の偏り確認
    print(f"\n[サンプル偏り確認]")
    for regime in ['BU', 'PD', 'NONE']:
        cnt = sum(1 for r in rows if r.get('D1_ATR_Cross_Dir') == regime)
        print(f"  D1_ATR_Cross_Dir={regime}: {cnt} ({cnt/len(rows)*100:.1f}%)")
    for di_dir in ['UP', 'DN']:
        cnt = sum(1 for r in rows if r.get('D1_DI_Dir') == di_dir)
        print(f"  D1_DI_Dir={di_dir}: {cnt} ({cnt/len(rows)*100:.1f}%)")
    for direction in ['BUY', 'SELL']:
        cnt = sum(1 for r in rows if r.get('Direction') == direction)
        print(f"  Direction={direction}: {cnt} ({cnt/len(rows)*100:.1f}%)")

    # ===== Section 1 =====
    print("\n" + "=" * 70)
    print("Section 1: ATR_RATIO 分布 × 勝敗 × 局面 × 方向")
    print("=" * 70)
    section_1_ratio_distribution(rows, 'H1_ATR_Ratio_Median', 'H1 (ATR16/32)')
    section_1_ratio_distribution(rows, 'H4_ATR_Ratio_Median', 'H4 (ATR8/46)')

    # D1 ATR_Ratio相当を一時列として追加
    for r in rows:
        s = to_float(r.get('D1_ATR_Short'))
        l = to_float(r.get('D1_ATR_Long'))
        r['_D1_ATR_Ratio'] = (s/l) if l > 0 else 0
    section_1_ratio_distribution(rows, '_D1_ATR_Ratio', 'D1 (ATR22/42 計算値)')

    # ===== Section 2 =====
    print("\n" + "=" * 70)
    section_2_three_axis_cross(rows)

    # ===== Section 3 =====
    print("\n" + "=" * 70)
    top_cols = section_3_open_exploration(rows)
    section_3b_top_columns_detail(rows, top_cols)


if __name__ == '__main__':
    main()
