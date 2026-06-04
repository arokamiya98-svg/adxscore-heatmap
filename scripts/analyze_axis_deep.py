"""
analyze_axis_deep.py — 46周期版 二軸追加分析

分析1: PatC × ATR_RATIO（H1 / H4それぞれ）の機能/死亡帯
分析2: PatA × D1_ADX22 強度 × Direction
分析3: フィルター追加候補シミュレーション

ベース: data/bt/ATR_WidthSignal_BT_h4adx46.csv (6h削除後 393件)
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


# ============================================================
# 6h重複削除（v2の方法に揃える）
# ============================================================

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


# ============================================================
# ATR_Ratio 区分（四分位）
# ============================================================

def quartile_bins(rows, col, n_bins=4):
    """colの四分位を求めて、各行に bin ラベルを返す関数を生成

    Returns: (bin_func, ranges)
    """
    vals = sorted(to_float(r.get(col, 0)) for r in rows)
    n = len(vals)
    if n == 0:
        return None, []
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
    """5区分"""
    return quartile_bins(rows, col, n_bins=5)


# ============================================================
# D1_ADX 強度区分（標準 + 実測四分位）
# ============================================================

def adx_strength_label(adx_val):
    """ADX強度 標準区分（業界標準: <20弱, 20-25中, 25-40強, >40激強）

    XAUUSD D1 ADX22 は値が大きく出やすいので、業界標準で切る
    """
    if adx_val < 20:
        return '1_弱(<20)'
    elif adx_val < 25:
        return '2_中(20-25)'
    elif adx_val < 40:
        return '3_強(25-40)'
    else:
        return '4_激強(>=40)'


# ============================================================
# 分析実行
# ============================================================

def run_analysis():
    print("=" * 60)
    print("46周期版 二軸追加分析（PatC×ATR_RATIO / PatA×D1_ADX22）")
    print("=" * 60)

    rows = load_bt_csv(CSV_PATH)
    print(f"\n[元データ] {len(rows)}件")

    rows = dedupe_6h(rows)
    print(f"[6h削除後] {len(rows)}件\n")

    # PatC / PatA サブセット
    patc = [r for r in rows if r.get('Pattern') == 'PatC']
    pata = [r for r in rows if r.get('Pattern') == 'PatA']
    print(f"PatC件数: {len(patc)} / PatA件数: {len(pata)}")

    # ============================================================
    # 0. ATR_RATIO 分布確認
    # ============================================================
    print("\n" + "=" * 60)
    print("0. ATR_RATIO 分布（全体）")
    print("=" * 60)

    for col in ['H1_ATR_Ratio_Median', 'H4_ATR_Ratio_Median']:
        vals = sorted(to_float(r.get(col, 0)) for r in rows)
        n = len(vals)
        print(f"\n{col}:")
        print(f"  min={vals[0]:.3f} / max={vals[-1]:.3f}")
        print(f"  P25={vals[n//4]:.3f} / P50={vals[n//2]:.3f} / "
              f"P75={vals[3*n//4]:.3f}")
        print(f"  mean={statistics.mean(vals):.3f} / "
              f"median={statistics.median(vals):.3f}")

    # ============================================================
    # 1. PatC × ATR_RATIO 分析
    # ============================================================
    print("\n" + "=" * 60)
    print("1. PatC × ATR_RATIO 分析")
    print("=" * 60)

    # PatCのATR_RATIO分布
    print("\n--- 1-A. PatC内 ATR_RATIO 分布 ---")
    for col in ['H1_ATR_Ratio_Median', 'H4_ATR_Ratio_Median']:
        vals = sorted(to_float(r.get(col, 0)) for r in patc)
        n = len(vals)
        if n > 0:
            print(f"\n{col} (PatC N={n}):")
            print(f"  min={vals[0]:.3f} / max={vals[-1]:.3f}")
            print(f"  P25={vals[n//4]:.3f} / P50={vals[n//2]:.3f} / "
                  f"P75={vals[3*n//4]:.3f}")

    # PatC × H1_ATR_Ratio 四分位
    print("\n--- 1-B. PatC × H1_ATR_Ratio (四分位) × Direction ---")
    bin_func, ranges, cuts = quartile_bins(patc, 'H1_ATR_Ratio_Median')
    print(f"四分位 cuts: {[round(c, 3) for c in cuts]}")
    print(f"範囲: Q1=[{ranges[0][0]:.3f}-{ranges[0][1]:.3f}] / "
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

    # PatC × H4_ATR_Ratio 四分位
    print("\n--- 1-C. PatC × H4_ATR_Ratio (四分位) × Direction ---")
    bin_func, ranges, cuts = quartile_bins(patc, 'H4_ATR_Ratio_Median')
    print(f"四分位 cuts: {[round(c, 3) for c in cuts]}")
    print(f"範囲: Q1=[{ranges[0][0]:.3f}-{ranges[0][1]:.3f}] / "
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

    # PatC × H1_ATR_Ratio 5区分
    print("\n--- 1-D. PatC × H1_ATR_Ratio (5区分) × Direction ---")
    bin_func, ranges, cuts = quintile_bins(patc, 'H1_ATR_Ratio_Median')
    print(f"5区分 cuts: {[round(c, 3) for c in cuts]}")
    if bin_func:
        result = regime_breakdown(patc, [bin_func, 'Direction'])
        print(f"\n{'Bin':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
        for key in sorted(result.keys()):
            ov = result[key]
            print(f"{key[0]:<6} {key[1]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # 局面相互作用: PatC × Phase × H1_ATR_Ratio 中央値で2分割
    print("\n--- 1-E. PatC × Phase × H1_ATR_Ratio 2分割 (中央値1.0境界) ---")
    def ratio_high_low(row):
        v = to_float(row.get('H1_ATR_Ratio_Median', 0))
        return 'High(>1.0)' if v > 1.0 else 'Low(<=1.0)'

    result = regime_breakdown(patc, ['D1_Pair_Phase', ratio_high_low, 'Direction'])
    print(f"\n{'Phase':<6} {'Ratio':<11} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<6} {key[1]:<11} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # ============================================================
    # 2. PatA × D1_ADX22 分析
    # ============================================================
    print("\n" + "=" * 60)
    print("2. PatA × D1_ADX22 分析")
    print("=" * 60)

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

    # 標準ADX区分 (弱/中/強/激強)
    print("\n--- 2-B. PatA × D1_ADX 標準4区分 × Direction ---")
    def adx_label(row):
        return adx_strength_label(to_float(row.get('D1_ADX', 0)))

    result = regime_breakdown(pata, [adx_label, 'Direction'])
    print(f"\n{'ADX強度':<14} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        print(f"{key[0]:<14} {key[1]:<5} {ov['n']:>4} "
              f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatA四分位（実測カスタム）
    print("\n--- 2-C. PatA × D1_ADX 四分位 × Direction ---")
    bin_func, ranges, cuts = quartile_bins(pata, 'D1_ADX')
    print(f"四分位 cuts: {[round(c, 2) for c in cuts]}")
    print(f"範囲: Q1=[{ranges[0][0]:.2f}-{ranges[0][1]:.2f}] / "
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
    print("\n--- 2-D. PatA × D1_ADX(標準4) × D1_DI_Dir × Direction ---")
    result = regime_breakdown(pata, [adx_label, 'D1_DI_Dir', 'Direction'])
    print(f"\n{'ADX強度':<14} {'DI':<3} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<3} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # PatA × ADX × Phase
    print("\n--- 2-E. PatA × D1_ADX(標準4) × D1_Pair_Phase × Direction ---")
    result = regime_breakdown(pata, [adx_label, 'D1_Pair_Phase', 'Direction'])
    print(f"\n{'ADX強度':<14} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>9}")
    for key in sorted(result.keys()):
        ov = result[key]
        if ov['n'] >= 3:
            print(f"{key[0]:<14} {key[1]:<6} {key[2]:<5} {ov['n']:>4} "
                  f"{ov['wr_pct']:>6.1f} {ov['pf']:>7.2f} {ov['net_usd']:>9.2f}")

    # ============================================================
    # 3. フィルター追加候補シミュレーション
    # ============================================================
    print("\n" + "=" * 60)
    print("3. フィルター追加候補シミュレーション")
    print("=" * 60)

    base = bt_overview(rows)
    print(f"\n[基準] N={base['n']} / WR={base['wr_pct']}% / "
          f"PF={base['pf']} / Net=${base['net_usd']}")

    # PatC × Phase × Direction 既知のボツ
    def is_patc_pd_buy(r):
        return (r.get('Pattern') == 'PatC' and
                r.get('D1_Pair_Phase') == 'PD' and
                r.get('Direction') == 'BUY')

    def is_patc_none_buy(r):
        return (r.get('Pattern') == 'PatC' and
                r.get('D1_Pair_Phase') == 'NONE' and
                r.get('Direction') == 'BUY')

    def is_patd_pd_buy(r):
        return (r.get('Pattern') == 'PatD' and
                r.get('D1_Pair_Phase') == 'PD' and
                r.get('Direction') == 'BUY')

    def is_patb_midh_sell(r):
        return (r.get('Pattern') == 'PatB' and
                zone_detail(r) == 'MID-H' and
                r.get('Direction') == 'SELL')

    def is_cross_none_sell(r):
        return r.get('D1_ATR_Cross_Dir') == 'NONE' and r.get('Direction') == 'SELL'

    # v2マップ既知フィルター
    def v2_existing_filters(r):
        return (is_patd_pd_buy(r) or is_patc_pd_buy(r) or
                is_patc_none_buy(r) or is_patb_midh_sell(r) or
                is_cross_none_sell(r))

    print("\n--- 3-A. v2 既知フィルター（PatD/C×PD×BUY + PatC×NONE×BUY + "
          "PatB×MID-H×SELL + NONE×SELL）---")
    kept = [r for r in rows if not v2_existing_filters(r)]
    excluded = [r for r in rows if v2_existing_filters(r)]
    kept_ov = bt_overview(kept)
    print(f"除外: {len(excluded)}件 / PF={bt_overview(excluded)['pf']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    # 候補追加: PatC × ATR_Ratio 高帯（仮: H1_Ratio > 1.4 等）
    # (1-Bの結果次第で確定するが、ここでは仮シミュレーション)

    # 候補1: PatC SELL 限定 BU/NONE 局面 死亡帯
    def is_patc_sell_not_pd(r):
        return (r.get('Pattern') == 'PatC' and
                r.get('Direction') == 'SELL' and
                r.get('D1_Pair_Phase') != 'PD')

    print("\n--- 3-B. v2既知 + PatC×SELL×(BU|NONE) 追加 ---")
    def comp_v2_patc_sell(r):
        return v2_existing_filters(r) or is_patc_sell_not_pd(r)

    kept = [r for r in rows if not comp_v2_patc_sell(r)]
    excluded = [r for r in rows if comp_v2_patc_sell(r)]
    kept_ov = bt_overview(kept)
    excl_ov = bt_overview(excluded)
    print(f"除外: {len(excluded)}件 / PF={excl_ov['pf']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    # 候補2: PatA × D1_ADX 弱 × ? (2-Bの結果次第)
    # 一旦 PatA × D1_ADX<20 で見る
    def is_pata_weak_adx(r):
        return (r.get('Pattern') == 'PatA' and
                to_float(r.get('D1_ADX', 0)) < 20)

    print("\n--- 3-C. PatA × D1_ADX<20 単体検証（フィルター候補確認）---")
    target = [r for r in rows if is_pata_weak_adx(r)]
    rest = [r for r in rows if not is_pata_weak_adx(r)]
    if target:
        t_ov = bt_overview(target)
        r_ov = bt_overview(rest)
        print(f"対象: {len(target)}件 / PF={t_ov['pf']} / Net=${t_ov['net_usd']}")
        print(f"残存: {len(rest)}件 / PF={r_ov['pf']} / Net=${r_ov['net_usd']}")
        print(f"PF差: {r_ov['pf'] - base['pf']:+.2f}")

    # 候補3: 全部入り
    print("\n--- 3-D. v2既知 + PatC×SELL×(BU|NONE) + PatA×ADX<20 ---")
    def comp_all(r):
        return v2_existing_filters(r) or is_patc_sell_not_pd(r) or is_pata_weak_adx(r)
    kept = [r for r in rows if not comp_all(r)]
    excluded = [r for r in rows if comp_all(r)]
    kept_ov = bt_overview(kept)
    excl_ov = bt_overview(excluded)
    print(f"除外: {len(excluded)}件 / PF={excl_ov['pf']}")
    print(f"残存: {len(kept)}件 / PF={kept_ov['pf']} / "
          f"Net=${kept_ov['net_usd']} / WR={kept_ov['wr_pct']}%")
    print(f"PF改善: {kept_ov['pf'] - base['pf']:+.2f}")

    print("\n[完了]")


if __name__ == '__main__':
    run_analysis()
