"""
パターン別 ATR_RATIO 相性検証（あろさん仮説3点）

仮説1【最優先】: PatD はトレンド無いとハマる → ATR_Ratio>1 で勝ちやすい？
仮説2【裏取り】: PatA = 低ATR(凪) が強い
仮説3【裏取り】: PatB = ATR上オールラウンダー、下落波の一時的下げで良いポジ

対象: data/bt/ATR_WidthSignal_BT_h4adx46.csv (6h重複削除後)
"""
import sys
from collections import defaultdict

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import load_bt_csv, to_float, bt_overview
from compare_30_46_filtered import filter_6h_duplicates


# ========== 共通ユーティリティ ==========

def overview_short(rows):
    ov = bt_overview(rows)
    if ov['n'] == 0:
        return 'N=  0'
    return (f"N={ov['n']:>3} WR={ov['wr_pct']:>5.1f}% "
            f"PF={ov['pf']:>5.2f} Net=${ov['net_usd']:>+7.1f}")


def bin_3way(rows, col, lo=0.95, hi=1.10):
    """ATR_Ratio を 凪(<0.95) / 中(0.95-1.10) / 拡張(>1.10)"""
    bins = {'凪(<0.95)': [], '中(0.95-1.10)': [], '拡張(>1.10)': []}
    for r in rows:
        v = to_float(r.get(col))
        if v < lo:
            bins['凪(<0.95)'].append(r)
        elif v <= hi:
            bins['中(0.95-1.10)'].append(r)
        else:
            bins['拡張(>1.10)'].append(r)
    return bins


def cross_table(rows, pattern, ratio_col, ratio_label):
    """Pattern × ATR_Ratio 3区分 × Direction の表"""
    pat_rows = [r for r in rows if r.get('Pattern') == pattern]
    print(f"\n  ▼ {pattern} × {ratio_label} × Direction")
    print(f"    {'帯':<14} {'Dir':<5} {'overview':<50}")
    print(f"    " + "-"*70)
    bins = bin_3way(pat_rows, ratio_col)
    for bname, brows in bins.items():
        if not brows:
            print(f"    {bname:<14} {'ALL':<5} N=0")
            continue
        # ALL
        print(f"    {bname:<14} {'ALL':<5} {overview_short(brows)}")
        for d in ['BUY', 'SELL']:
            sub = [r for r in brows if r.get('Direction') == d]
            note = '' if len(sub) >= 5 else '  (※小サンプル)'
            print(f"    {'':<14} {d:<5} {overview_short(sub)}{note}")
    return bins


# ========== 仮説1: PatD ==========

def hypothesis_1_patD(rows):
    print("=" * 75)
    print("仮説1【最優先】 PatD × ATR_Ratio: 拡張中なら勝ちやすい？")
    print("=" * 75)

    pat_rows = [r for r in rows if r.get('Pattern') == 'PatD']
    print(f"\n  [PatD 全体]: {overview_short(pat_rows)}")
    print(f"  [PatD × Dir]:")
    for d in ['BUY', 'SELL']:
        sub = [r for r in pat_rows if r.get('Direction') == d]
        print(f"    {d}: {overview_short(sub)}")

    # 1-1: H1_ATR_Ratio_Median 帯別 × Direction
    print(f"\n--- 1-1. PatD × H1_ATR_Ratio_Median 帯別 × Direction ---")
    h1_bins = cross_table(rows, 'PatD', 'H1_ATR_Ratio_Median', 'H1_ATR_Ratio')

    # 1-2: H4_ATR_Ratio_Median 帯別 × Direction
    print(f"\n--- 1-2. PatD × H4_ATR_Ratio_Median 帯別 × Direction ---")
    h4_bins = cross_table(rows, 'PatD', 'H4_ATR_Ratio_Median', 'H4_ATR_Ratio')

    # 1-3: 既存F3 (PatD × PD × BUY) との整合
    print(f"\n--- 1-3. 既存F3 (PatD × PD × BUY) との整合 ---")
    f3 = [r for r in rows if r.get('Pattern') == 'PatD'
          and r.get('D1_ATR_Cross_Dir') == 'PD'
          and r.get('Direction') == 'BUY']
    print(f"  PatD × D1_PD × BUY 全体: {overview_short(f3)}")
    print(f"  ↓ H1_ATR_Ratio 帯別:")
    f3_bins = bin_3way(f3, 'H1_ATR_Ratio_Median')
    for bname, brows in f3_bins.items():
        note = '  (小)' if len(brows) < 5 else ''
        print(f"    {bname:<14} {overview_short(brows)}{note}")

    # 補足: D1_ATR_Cross_Dir × ATR_Ratio で PatD を見る
    print(f"\n--- 1-4. PatD × D1_ATR_Cross_Dir × H1_ATR_Ratio (深掘り) ---")
    print(f"    {'Cross':<6} {'帯':<14} {'Dir':<5} {'overview':<50}")
    print(f"    " + "-"*70)
    for cross in ['BU', 'PD', 'NONE']:
        sub = [r for r in pat_rows if r.get('D1_ATR_Cross_Dir') == cross]
        if not sub:
            continue
        bins = bin_3way(sub, 'H1_ATR_Ratio_Median')
        for bname, brows in bins.items():
            for d in ['BUY', 'SELL']:
                bd = [r for r in brows if r.get('Direction') == d]
                if len(bd) >= 3:
                    note = '' if len(bd) >= 5 else '  (小)'
                    print(f"    {cross:<6} {bname:<14} {d:<5} {overview_short(bd)}{note}")

    return h1_bins, h4_bins


# ========== 仮説2: PatA ==========

def hypothesis_2_patA(rows):
    print("\n" + "=" * 75)
    print("仮説2【裏取り】 PatA × ATR_Ratio: 凪が強い？")
    print("=" * 75)

    pat_rows = [r for r in rows if r.get('Pattern') == 'PatA']
    print(f"\n  [PatA 全体]: {overview_short(pat_rows)}")
    print(f"  [PatA × Dir]:")
    for d in ['BUY', 'SELL']:
        sub = [r for r in pat_rows if r.get('Direction') == d]
        print(f"    {d}: {overview_short(sub)}")

    # 2-1: H1 ATR_Ratio 帯別
    print(f"\n--- 2-1. PatA × H1_ATR_Ratio × Direction ---")
    h1_bins = cross_table(rows, 'PatA', 'H1_ATR_Ratio_Median', 'H1_ATR_Ratio')

    # 2-2: H4 ATR_Ratio 帯別
    print(f"\n--- 2-2. PatA × H4_ATR_Ratio × Direction ---")
    h4_bins = cross_table(rows, 'PatA', 'H4_ATR_Ratio_Median', 'H4_ATR_Ratio')

    return h1_bins, h4_bins


# ========== 仮説3: PatB ==========

def hypothesis_3_patB(rows):
    print("\n" + "=" * 75)
    print("仮説3【裏取り】 PatB × ATR_Ratio: オールラウンダー＋下落波の一時下げで活きる？")
    print("=" * 75)

    pat_rows = [r for r in rows if r.get('Pattern') == 'PatB']
    print(f"\n  [PatB 全体]: {overview_short(pat_rows)}")
    print(f"  [PatB × Dir]:")
    for d in ['BUY', 'SELL']:
        sub = [r for r in pat_rows if r.get('Direction') == d]
        print(f"    {d}: {overview_short(sub)}")

    # 3-1: H1 ATR_Ratio 帯別 (オールラウンダー検証)
    print(f"\n--- 3-1. PatB × H1_ATR_Ratio × Direction (帯間バラつき確認) ---")
    h1_bins = cross_table(rows, 'PatB', 'H1_ATR_Ratio_Median', 'H1_ATR_Ratio')

    # 3-2: D1_DI_Dir × D1_ATR_Cross_Dir × PatB (下落波の一時下げ検証)
    print(f"\n--- 3-2. PatB × D1_DI_Dir × D1_ATR_Cross_Dir (下落波/PD局面検証) ---")
    print(f"    {'DI':<4} {'Cross':<6} {'Dir':<5} {'overview':<50}")
    print(f"    " + "-"*70)
    for di in ['UP', 'DN']:
        for cross in ['BU', 'PD', 'NONE']:
            sub = [r for r in pat_rows
                   if r.get('D1_DI_Dir') == di and r.get('D1_ATR_Cross_Dir') == cross]
            if not sub:
                continue
            for d in ['BUY', 'SELL']:
                sub_d = [r for r in sub if r.get('Direction') == d]
                if not sub_d:
                    continue
                note = '' if len(sub_d) >= 5 else '  (小)'
                print(f"    {di:<4} {cross:<6} {d:<5} {overview_short(sub_d)}{note}")

    # 3-3: PatB × DN_DI 単体 (下落相場 PatB の挙動)
    print(f"\n--- 3-3. PatB × D1_DI_Dir × Direction (下落相場での挙動) ---")
    for di in ['UP', 'DN']:
        sub = [r for r in pat_rows if r.get('D1_DI_Dir') == di]
        for d in ['BUY', 'SELL']:
            sub_d = [r for r in sub if r.get('Direction') == d]
            note = '' if len(sub_d) >= 5 else '  (小)'
            print(f"    DI={di} {d}: {overview_short(sub_d)}{note}")

    return h1_bins


# ========== 補足: 全パターン × ATR_Ratio summary ==========

def summary_all_patterns(rows):
    print("\n" + "=" * 75)
    print("補足: 全パターン × H1_ATR_Ratio 帯別 × Dir (横並び比較)")
    print("=" * 75)
    print(f"\n  {'Pattern':<8} {'帯':<14} {'Dir':<5} {'overview':<50}")
    print(f"  " + "-"*75)
    for pat in ['PatA', 'PatB', 'PatC', 'PatD', 'PatE']:
        pat_rows = [r for r in rows if r.get('Pattern') == pat]
        if not pat_rows:
            continue
        bins = bin_3way(pat_rows, 'H1_ATR_Ratio_Median')
        for bname, brows in bins.items():
            for d in ['BUY', 'SELL']:
                sub = [r for r in brows if r.get('Direction') == d]
                if len(sub) >= 5:
                    print(f"  {pat:<8} {bname:<14} {d:<5} {overview_short(sub)}")


# ========== Main ==========

def main():
    print("=" * 75)
    print("パターン別 ATR_RATIO 相性検証（あろさん仮説3点）")
    print("=" * 75)

    path = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'
    rows_raw = load_bt_csv(path)
    rows = filter_6h_duplicates(rows_raw)

    print(f"\n[前提]")
    print(f"  入力: {path}")
    print(f"  raw N={len(rows_raw)}, 6h後 N={len(rows)}")
    ov = bt_overview(rows)
    print(f"  6h後 baseline: WR={ov['wr_pct']}% PF={ov['pf']} Net=${ov['net_usd']}")

    # パターン分布
    pat_counts = defaultdict(int)
    for r in rows:
        pat_counts[r.get('Pattern', '?')] += 1
    print(f"  Pattern分布:")
    for pat in sorted(pat_counts.keys()):
        print(f"    {pat}: {pat_counts[pat]} ({pat_counts[pat]/len(rows)*100:.1f}%)")

    # 仮説1
    hypothesis_1_patD(rows)
    # 仮説2
    hypothesis_2_patA(rows)
    # 仮説3
    hypothesis_3_patB(rows)
    # 補足
    summary_all_patterns(rows)

    print("\n" + "=" * 75)
    print("完了")
    print("=" * 75)


if __name__ == '__main__':
    main()
