"""
analyze_axis_deep_v2.py — 46周期版 二軸追加分析（修正版）

修正点: BU/PD/NONE は D1_ATR_Cross_Dir 列。D1_Pair_Phase（CONTRACT/EXPAND/NEUTRAL）と混同しない。

分析1: PatC × ATR_RATIO（H1 / H4それぞれ）の機能/死亡帯
分析2: PatA × D1_ADX22 強度 × Direction
分析3: フィルター追加候補シミュレーション

ベース: data/bt/ATR_WidthSignal_BT_h4adx46.csv (6h削除後 391件)
"""

import sys
sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import (
    load_bt_csv, bt_overview, regime_breakdown, to_float, zone_detail
)
from collections import defaultdict
import statistics
from datetime import datetime


CSV_PATH = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'


def dedupe_6h(rows):
    """OpenTime ベース 6h 重複削除（早いもの勝ち）"""
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

    kept = []
    last_dt = None
    for dt, r in parsed:
        if last_dt is None or (dt - last_dt).total_seconds() >= 6 * 3600:
            kept.append(r)
            last_dt = dt
    return kept


def quartile_bins(rows, col, n_bins=4):
    vals = sorted(to_float(r.get(col, 0)) for r in rows)
    n = len(vals)
    if n == 0:
        return None, [], []
    cuts = []
    for i in range(1, n_bins):
        idx = int(n * i / n_bins)
        cuts.append(vals[idx])
    ranges = []
    for i in range(n_bins):
        lo = vals[0] if i == 0 else cuts[i - 1]
        hi = vals[-1] if i == n_bins - 1 else cuts[i]
        ranges.append((lo, hi))

    def bin_func(row):
        v = to_float(row.get(col, 0))
        for i, c in enumerate(cuts):
            if v < c:
                return f'Q{i+1}'
        return f'Q{n_bins}'

    return bin_func, ranges, cuts


def quintile_bins(rows, col):
    return quartile_bins(rows, col, n_bins=5)


def adx_strength_label(adx_val):
    """ADX強度 標準区分（CLAUDE.md の D1ラベラー v1.2 定義に準拠）

    弱(<20) / 中(20-25) / 強(25-40) / 激強(>=40)
    """
    if adx_val < 20:
        return '1_弱(<20)'
    elif adx_val < 25:
        return '2_中(20-25)'
    elif adx_val < 40:
        return '3_強(25-40)'
    else:
        return '4_激強(>=40)'


# ---- D1局面ラベル: BU/PD/NONE は D1_ATR_Cross_Dir 列 ----
def d1_phase(row):
    return row.get('D1_ATR_Cross_Dir', '').strip().upper()


def run_analysis():
    print("=" * 70)
    print("46周期版 二軸追加分析 v2（修正版: D1_ATR_Cross_Dir 使用）")
    print("=" * 70)

    rows = load_bt_csv(CSV_PATH)
    print(f"\n[元データ] {len(rows)}件")

    rows = dedupe_6h(rows)
    print(f"[6h削除後] {len(rows)}件")

    patc = [r for r in rows if r.get('Pattern') == 'PatC']
    pata = [r for r in rows if r.get('Pattern') == 'PatA']
    print(f"PatC件数: {len(patc)} / PatA件数: {len(pata)}")

    # ========================================================
    # 0. ATR_RATIO 分布確認
    # ========================================================
    print("\n" + "=" * 70)
    print("0. ATR_RATIO 分布（全体, 6h削除後）")
    print("=" * 70)

    for col in ['H1_ATR_Ratio_Median', 'H4_ATR_Ratio_Median']:
        vals = sorted(to_float(r.get(col, 0)) for r in rows)
        n = len(vals)
        print(f"\n{col}:")
        print(f"  N={n} / min={vals[0]:.3f} / max={vals[-1]:.3f}")
        print(f"  P10={vals[n//10]:.3f} / P25={vals[n//4]:.3f} / "
              f"P50={vals[n//2]:.3f} / P75={vals[3*n//4]:.3f} / "
              f"P90={vals[9*n//10]:.3f}")
        print(f"  mean={statistics.mean(vals):.3f} / "
              f"median={statistics.median(vals):.3f}")

    # ========================================================
    # 1. PatC × ATR_RATIO 分析
    # ========================================================
    print("\n" + "=" * 70)
    print("1. PatC × ATR_RATIO 分析")
    print("=" * 70)

    # PatC全体（参考）
    ov_patc = bt_overview(patc)
    print(f"\n[PatC全体] N={ov_patc['n']} / WR={ov_patc['wr_pct']}% / "
          f"PF={ov_patc['pf']} / Net=${ov_patc['net_usd']}")

    # PatC内 BU/PD/NONE 局面分布（前提確認）
    print("\n--- 1-A. PatC × D1_ATR_Cross_Dir(BU/PD/NONE) × Direction ---")
    result = regime_breakdown(patc, [d1_phase, 'Direction'])
    print(f"\n{'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
              f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatCのATR_RATIO分布
    print("\n--- 1-B. PatC内 ATR_RATIO 分布 ---")
    for col in ['H1_ATR_Ratio_Median', 'H4_ATR_Ratio_Median']:
        vals = sorted(to_float(r.get(col, 0)) for r in patc)
        n = len(vals)
        if n > 0:
            print(f"\n{col} (PatC N={n}):")
            print(f"  min={vals[0]:.3f} / max={vals[-1]:.3f}")
            print(f"  P25={vals[n//4]:.3f} / P50={vals[n//2]:.3f} / "
                  f"P75={vals[3*n//4]:.3f}")

    # PatC × H1_ATR_Ratio 四分位 × Direction
    print("\n--- 1-C. PatC × H1_ATR_Ratio (四分位) × Direction ---")
    bin_func, ranges, cuts = quartile_bins(patc, 'H1_ATR_Ratio_Median')
    print(f"四分位 cuts: {[round(c, 3) for c in cuts]}")
    print(f"Q1=[{ranges[0][0]:.3f}-{ranges[0][1]:.3f}] / "
          f"Q2=[{ranges[1][0]:.3f}-{ranges[1][1]:.3f}] / "
          f"Q3=[{ranges[2][0]:.3f}-{ranges[2][1]:.3f}] / "
          f"Q4=[{ranges[3][0]:.3f}-{ranges[3][1]:.3f}]")
    if bin_func:
        result = regime_breakdown(patc, [bin_func, 'Direction'])
        print(f"\n{'Bin':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
        for key in sorted(result.keys()):
            ov = result[key]
            print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatC × H4_ATR_Ratio 四分位 × Direction
    print("\n--- 1-D. PatC × H4_ATR_Ratio (四分位) × Direction ---")
    bin_func, ranges, cuts = quartile_bins(patc, 'H4_ATR_Ratio_Median')
    print(f"四分位 cuts: {[round(c, 3) for c in cuts]}")
    print(f"Q1=[{ranges[0][0]:.3f}-{ranges[0][1]:.3f}] / "
          f"Q2=[{ranges[1][0]:.3f}-{ranges[1][1]:.3f}] / "
          f"Q3=[{ranges[2][0]:.3f}-{ranges[2][1]:.3f}] / "
          f"Q4=[{ranges[3][0]:.3f}-{ranges[3][1]:.3f}]")
    if bin_func:
        result = regime_breakdown(patc, [bin_func, 'Direction'])
        print(f"\n{'Bin':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
        for key in sorted(result.keys()):
            ov = result[key]
            print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatC × H1_ATR_Ratio 5区分 × Direction
    print("\n--- 1-E. PatC × H1_ATR_Ratio (5区分) × Direction ---")
    bin_func, ranges, cuts = quintile_bins(patc, 'H1_ATR_Ratio_Median')
    print(f"5区分 cuts: {[round(c, 3) for c in cuts]}")
    if bin_func:
        result = regime_breakdown(patc, [bin_func, 'Direction'])
        print(f"\n{'Bin':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
        for key in sorted(result.keys()):
            ov = result[key]
            print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # 局面相互作用: PatC × Phase × H1_ATR_Ratio Q帯
    print("\n--- 1-F. PatC × Phase(BU/PD/NONE) × H1_ATR_Ratio 中央値分割 × Dir ---")
    def ratio_high_low_h1(row):
        v = to_float(row.get('H1_ATR_Ratio_Median', 0))
        return 'H1Rt>1.10' if v > 1.10 else 'H1Rt<=1.10'

    result = regime_breakdown(patc, [d1_phase, ratio_high_low_h1, 'Direction'])
    print(f"\n{'Phase':<6} {'H1_R':<11} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 2:
            print(f"{key[0]:<6} {key[1]:<11} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatC × Phase × H4_ATR_Ratio Q帯
    print("\n--- 1-G. PatC × Phase(BU/PD/NONE) × H4_ATR_Ratio 中央値分割 × Dir ---")
    def ratio_high_low_h4(row):
        v = to_float(row.get('H4_ATR_Ratio_Median', 0))
        return 'H4Rt>1.10' if v > 1.10 else 'H4Rt<=1.10'

    result = regime_breakdown(patc, [d1_phase, ratio_high_low_h4, 'Direction'])
    print(f"\n{'Phase':<6} {'H4_R':<11} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 2:
            print(f"{key[0]:<6} {key[1]:<11} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # ========================================================
    # 2. PatA × D1_ADX22 分析
    # ========================================================
    print("\n" + "=" * 70)
    print("2. PatA × D1_ADX22 分析")
    print("=" * 70)

    # PatA全体（参考）
    ov_pata = bt_overview(pata)
    print(f"\n[PatA全体] N={ov_pata['n']} / WR={ov_pata['wr_pct']}% / "
          f"PF={ov_pata['pf']} / Net=${ov_pata['net_usd']}")

    # PatAのD1_ADX分布
    print("\n--- 2-A. PatA内 D1_ADX 分布 ---")
    vals = sorted(to_float(r.get('D1_ADX', 0)) for r in pata)
    n = len(vals)
    if n > 0:
        print(f"  N={n}")
        print(f"  min={vals[0]:.2f} / max={vals[-1]:.2f}")
        print(f"  P25={vals[n//4]:.2f} / P50={vals[n//2]:.2f} / "
              f"P75={vals[3*n//4]:.2f}")
        print(f"  mean={statistics.mean(vals):.2f}")

    # PatA × D1_ATR_Cross_Dir(BU/PD/NONE) × Direction（v2との接続確認）
    print("\n--- 2-B. PatA × D1_ATR_Cross_Dir(BU/PD/NONE) × Direction "
          "(v2との接続) ---")
    result = regime_breakdown(pata, [d1_phase, 'Direction'])
    print(f"\n{'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
              f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # 標準ADX区分 (弱/中/強/激強) × Direction
    print("\n--- 2-C. PatA × D1_ADX 標準4区分 × Direction ---")
    def adx_label(row):
        return adx_strength_label(to_float(row.get('D1_ADX', 0)))

    result = regime_breakdown(pata, [adx_label, 'Direction'])
    print(f"\n{'ADX強度':<14} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        print(f"{key[0]:<14} {key[1]:<5} {ov['n']:>4} "
              f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatA四分位
    print("\n--- 2-D. PatA × D1_ADX 四分位 × Direction ---")
    bin_func, ranges, cuts = quartile_bins(pata, 'D1_ADX')
    print(f"四分位 cuts: {[round(c, 2) for c in cuts]}")
    print(f"Q1=[{ranges[0][0]:.2f}-{ranges[0][1]:.2f}] / "
          f"Q2=[{ranges[1][0]:.2f}-{ranges[1][1]:.2f}] / "
          f"Q3=[{ranges[2][0]:.2f}-{ranges[2][1]:.2f}] / "
          f"Q4=[{ranges[3][0]:.2f}-{ranges[3][1]:.2f}]")
    if bin_func:
        result = regime_breakdown(pata, [bin_func, 'Direction'])
        print(f"\n{'Bin':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
        for key in sorted(result.keys()):
            ov = result[key]
            print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatA × ADX × DI方向整合
    print("\n--- 2-E. PatA × D1_ADX(標準4) × D1_DI_Dir × Direction ---")
    result = regime_breakdown(pata, [adx_label, 'D1_DI_Dir', 'Direction'])
    print(f"\n{'ADX強度':<14} {'DI':<3} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<3} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatA × ADX × BU/PD/NONE
    print("\n--- 2-F. PatA × D1_ADX(標準4) × D1_ATR_Cross_Dir × Direction ---")
    result = regime_breakdown(pata, [adx_label, d1_phase, 'Direction'])
    print(f"\n{'ADX強度':<14} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<6} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # DI Spread の絶対値（整合度）
    print("\n--- 2-G. PatA × D1_ADX(標準4) × DI_Spread絶対値中央値分割 × Direction ---")
    # PatA内のDI_Spread絶対値中央値
    spreads = [abs(to_float(r.get('D1_DI_Spread', 0))) for r in pata]
    spread_median = statistics.median(spreads)
    print(f"  PatA D1_DI_Spread絶対値 中央値: {spread_median:.2f}")

    def spread_bin(row):
        s = abs(to_float(row.get('D1_DI_Spread', 0)))
        return f'Spread>{spread_median:.1f}' if s > spread_median else f'Spread<={spread_median:.1f}'

    result = regime_breakdown(pata, [adx_label, spread_bin, 'Direction'])
    print(f"\n{'ADX強度':<14} {'Spread':<14} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<14} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # ========================================================
    # 3. フィルター追加候補シミュレーション
    # ========================================================
    print("\n" + "=" * 70)
    print("3. フィルター追加候補シミュレーション")
    print("=" * 70)

    base = bt_overview(rows)
    print(f"\n[基準] N={base['n']} / WR={base['wr_pct']}% / "
          f"PF={base['pf']} / Net=${base['net_usd']}")

    # v2マップ既知のボツ群（PatternByPhase基準: D1_ATR_Cross_Dir）
    def is_patc_pd_buy(r):
        return (r.get('Pattern') == 'PatC' and
                d1_phase(r) == 'PD' and
                r.get('Direction') == 'BUY')

    def is_patc_none_buy(r):
        return (r.get('Pattern') == 'PatC' and
                d1_phase(r) == 'NONE' and
                r.get('Direction') == 'BUY')

    def is_patd_pd_buy(r):
        return (r.get('Pattern') == 'PatD' and
                d1_phase(r) == 'PD' and
                r.get('Direction') == 'BUY')

    def is_patb_midh_sell(r):
        return (r.get('Pattern') == 'PatB' and
                zone_detail(r) == 'MID-H' and
                r.get('Direction') == 'SELL')

    def is_cross_none_sell(r):
        return d1_phase(r) == 'NONE' and r.get('Direction') == 'SELL'

    def v2_existing_filters(r):
        return (is_patd_pd_buy(r) or is_patc_pd_buy(r) or
                is_patc_none_buy(r) or is_patb_midh_sell(r) or
                is_cross_none_sell(r))

    print("\n--- 3-A. v2 既知フィルター（PatD/C×PD×BUY + PatC×NONE×BUY + "
          "PatB×MID-H×SELL + NONE×SELL）---")
    kept = [r for r in rows if not v2_existing_filters(r)]
    excluded = [r for r in rows if v2_existing_filters(r)]
    kept_ov = bt_overview(kept)
    excl_ov = bt_overview(excluded)
    print(f"除外: {len(excluded)}件 / PF={excl_ov['pf']} / "
          f"Net=${excl_ov['net_usd']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    # 候補1: PatC × Phase=BU でない × SELL = SELL は PD 専用ロジックなので BU/NONE で死亡
    def is_patc_sell_not_pd(r):
        return (r.get('Pattern') == 'PatC' and
                r.get('Direction') == 'SELL' and
                d1_phase(r) != 'PD')

    print("\n--- 3-B. v2既知 + PatC×SELL×(BU|NONE) 追加 ---")
    def comp_v2_patc_sell(r):
        return v2_existing_filters(r) or is_patc_sell_not_pd(r)
    kept = [r for r in rows if not comp_v2_patc_sell(r)]
    excluded = [r for r in rows if comp_v2_patc_sell(r)]
    kept_ov = bt_overview(kept)
    excl_ov = bt_overview(excluded)
    print(f"除外: {len(excluded)}件 / PF={excl_ov['pf']} / Net=${excl_ov['net_usd']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    # 候補2: PatC × H4_ATR_Ratio 高帯 BUY/SELL 分離
    def is_patc_h4_ratio_q4_sell(r):
        if r.get('Pattern') != 'PatC' or r.get('Direction') != 'SELL':
            return False
        return to_float(r.get('H4_ATR_Ratio_Median', 0)) > 1.243

    print("\n--- 3-C. PatC × H4_Ratio Q4(>1.243) × SELL 単体検証 ---")
    target = [r for r in rows if is_patc_h4_ratio_q4_sell(r)]
    rest = [r for r in rows if not is_patc_h4_ratio_q4_sell(r)]
    if target:
        t_ov = bt_overview(target)
        r_ov = bt_overview(rest)
        print(f"対象: {len(target)}件 / PF={t_ov['pf']} / "
              f"WR={t_ov['wr_pct']}% / Net=${t_ov['net_usd']}")
        print(f"残存: {len(rest)}件 / PF={r_ov['pf']} / Net=${r_ov['net_usd']}")
        print(f"PF差: {r_ov['pf'] - base['pf']:+.2f}")

    # 候補3: PatC × H4_ATR_Ratio Q2(0.97-1.10) × BUY = 結果から死亡帯
    def is_patc_h4_ratio_q2_buy(r):
        if r.get('Pattern') != 'PatC' or r.get('Direction') != 'BUY':
            return False
        v = to_float(r.get('H4_ATR_Ratio_Median', 0))
        return 0.97 < v <= 1.104

    print("\n--- 3-D. PatC × H4_Ratio Q2(0.97-1.10) × BUY 単体検証 ---")
    target = [r for r in rows if is_patc_h4_ratio_q2_buy(r)]
    rest = [r for r in rows if not is_patc_h4_ratio_q2_buy(r)]
    if target:
        t_ov = bt_overview(target)
        r_ov = bt_overview(rest)
        print(f"対象: {len(target)}件 / PF={t_ov['pf']} / "
              f"WR={t_ov['wr_pct']}% / Net=${t_ov['net_usd']}")
        print(f"残存: {len(rest)}件 / PF={r_ov['pf']} / Net=${r_ov['net_usd']}")
        print(f"PF差: {r_ov['pf'] - base['pf']:+.2f}")

    # 候補4: PatA × D1_ADX<20 単体検証
    def is_pata_weak_adx(r):
        return (r.get('Pattern') == 'PatA' and
                to_float(r.get('D1_ADX', 0)) < 20)

    print("\n--- 3-E. PatA × D1_ADX<20 単体検証 ---")
    target = [r for r in rows if is_pata_weak_adx(r)]
    rest = [r for r in rows if not is_pata_weak_adx(r)]
    if target:
        t_ov = bt_overview(target)
        r_ov = bt_overview(rest)
        print(f"対象: {len(target)}件 / PF={t_ov['pf']} / "
              f"WR={t_ov['wr_pct']}% / Net=${t_ov['net_usd']}")
        print(f"残存: {len(rest)}件 / PF={r_ov['pf']} / Net=${r_ov['net_usd']}")
        print(f"PF差: {r_ov['pf'] - base['pf']:+.2f}")

    # 候補5: PatA × UP × ADX<20 × SELL ←結果から死亡帯
    def is_pata_up_weak_sell(r):
        return (r.get('Pattern') == 'PatA' and
                r.get('D1_DI_Dir') == 'UP' and
                to_float(r.get('D1_ADX', 0)) < 20 and
                r.get('Direction') == 'SELL')

    print("\n--- 3-F. PatA × UP × ADX<20 × SELL 単体検証 ---")
    target = [r for r in rows if is_pata_up_weak_sell(r)]
    rest = [r for r in rows if not is_pata_up_weak_sell(r)]
    if target:
        t_ov = bt_overview(target)
        r_ov = bt_overview(rest)
        print(f"対象: {len(target)}件 / PF={t_ov['pf']} / "
              f"WR={t_ov['wr_pct']}% / Net=${t_ov['net_usd']}")
        print(f"残存: {len(rest)}件 / PF={r_ov['pf']} / Net=${r_ov['net_usd']}")
        print(f"PF差: {r_ov['pf'] - base['pf']:+.2f}")

    # 全部入りシミュレーション
    print("\n--- 3-G. 全部入り: v2既知 + PatC×SELL×(BU|NONE) + PatC×H4Rt×Q2×BUY + "
          "PatA×UP×Weak×SELL ---")
    def comp_all(r):
        return (v2_existing_filters(r) or
                is_patc_sell_not_pd(r) or
                is_patc_h4_ratio_q2_buy(r) or
                is_pata_up_weak_sell(r))
    kept = [r for r in rows if not comp_all(r)]
    excluded = [r for r in rows if comp_all(r)]
    kept_ov = bt_overview(kept)
    excl_ov = bt_overview(excluded)
    print(f"除外: {len(excluded)}件 / PF={excl_ov['pf']} / Net=${excl_ov['net_usd']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    # ========================================================
    # 4. 追加: 機能パターン側の境界確認（PatAの強帯/弱帯）
    # ========================================================
    print("\n" + "=" * 70)
    print("4. 機能パターン側の境界確認")
    print("=" * 70)

    # PatA × ADX強度 × BU/PD/NONE クロス
    print("\n--- 4-A. PatA × ADX強度 × Phase × Direction (機能セル探索) ---")
    result = regime_breakdown(pata, [adx_label, d1_phase, 'Direction'])
    print(f"\n{'ADX強度':<14} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    sorted_keys = sorted(result.keys(), key=lambda k: -result[k]['pf'])
    for key in sorted_keys:
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<6} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    print("\n[完了]")


if __name__ == '__main__':
    run_analysis()
