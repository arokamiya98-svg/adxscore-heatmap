"""
analyze_bt_gen2.py — BT世代2 (H4_ADX 30 vs 46) 周期比較分析

6h重複削除後の両CSVを構造比較し、ボツフィルター作れ高を評価する。

使い方:
    python3 scripts/analyze_bt_gen2.py
"""

import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import (
    load_bt_csv, bt_overview, zone_detail, regime_breakdown,
    pattern_zone_map, regime_d1_breakdown, bad_patterns, good_patterns,
    filter_label_summary, to_float
)

DATA_DIR = '/Users/aro/Desktop/ADXSCORE/data/bt'
PATH_30 = f'{DATA_DIR}/ATR_WidthSignal_BT_h4adx30.csv'
PATH_46 = f'{DATA_DIR}/ATR_WidthSignal_BT_h4adx46.csv'


# ============================================================
# 6h重複削除
# ============================================================

def parse_dt(s):
    return datetime.strptime(s.strip(), '%Y.%m.%d %H:%M')


def dedupe_6h(rows):
    """同方向（BUY/SELL別）で6h以内連発は最初の1件のみ採用"""
    sorted_rows = sorted(rows, key=lambda r: parse_dt(r['OpenTime']))
    last_open = {'BUY': None, 'SELL': None}
    kept = []
    for r in sorted_rows:
        d = r['Direction']
        ot = parse_dt(r['OpenTime'])
        if last_open[d] is None or (ot - last_open[d]).total_seconds() >= 6 * 3600:
            kept.append(r)
            last_open[d] = ot
    return kept


# ============================================================
# 拡張統計
# ============================================================

def regime_full_key(row):
    """局面の完全キー: D1_DI_Dir + D1_ATR_Cross_Dir + zone_detail + Pattern + Direction"""
    return (
        row.get('D1_DI_Dir', ''),
        row.get('D1_ATR_Cross_Dir', ''),
        zone_detail(row),
        row.get('Pattern', ''),
        row.get('Direction', ''),
    )


def full_regime_map(rows):
    """完全局面マップ: (DI_Dir, Cross_Dir, Zone, Pattern, Dir) -> overview"""
    groups = defaultdict(list)
    for r in rows:
        groups[regime_full_key(r)].append(r)
    return {key: bt_overview(group) for key, group in groups.items()}


def bad_patterns_full(rows, min_n=10, max_pf=0.7):
    """N>=10 & PF<=0.7 の完全局面ボツ"""
    fmap = full_regime_map(rows)
    bad = []
    for key, stats in fmap.items():
        if stats['n'] >= min_n and stats['pf'] <= max_pf:
            bad.append({'key': key, **stats})
    return sorted(bad, key=lambda x: x['pf'])


def grey_zone_patterns(rows, min_n=15, pf_low=0.8, pf_high=0.95):
    """グレーゾーン: PF 0.8〜0.95"""
    pmap = pattern_zone_map(rows)
    grey = []
    for key, stats in pmap.items():
        if stats['n'] >= min_n and pf_low <= stats['pf'] <= pf_high:
            grey.append({'key': key, **stats})
    return sorted(grey, key=lambda x: x['pf'])


def good_patterns_full(rows, min_n=20, min_pf=1.5):
    """N>=20 & PF>=1.5 の機能パターン"""
    pmap = pattern_zone_map(rows)
    good = []
    for key, stats in pmap.items():
        if stats['n'] >= min_n and stats['pf'] >= min_pf:
            good.append({'key': key, **stats})
    return sorted(good, key=lambda x: -x['pf'])


def single_axis_breakdown(rows, col):
    """単軸（1列）のbreakdown"""
    return regime_breakdown(rows, [col])


def cross_dir_x_direction(rows):
    """D1_ATR_Cross_Dir × Direction（Cross=NONE×SELLが世代1の最大死亡帯だった）"""
    return regime_breakdown(rows, ['D1_ATR_Cross_Dir', 'Direction'])


def simulate_filter_exclusion(rows, exclude_keys, key_func):
    """指定キー群を除外したシミュレーション

    Args:
        rows: 全行
        exclude_keys: 除外する key の set
        key_func: row -> key を返す関数
    """
    kept = [r for r in rows if key_func(r) not in exclude_keys]
    excluded = [r for r in rows if key_func(r) in exclude_keys]
    return {
        'kept': bt_overview(kept),
        'excluded': bt_overview(excluded),
        'n_excluded': len(excluded),
    }


# ============================================================
# レポート生成補助
# ============================================================

def fmt_key(key):
    """tuple key を人間可読に"""
    if isinstance(key, tuple):
        return ' × '.join(str(k) if k else '?' for k in key)
    return str(key)


def print_section(title, char='='):
    bar = char * 70
    print(f'\n{bar}\n{title}\n{bar}')


# ============================================================
# メイン分析
# ============================================================

def main():
    print_section('BT世代2 構造分析 (H4_ADX 30 vs 46 / 6h重複削除版)')

    # 読み込み + 6h削除
    rows_30_raw = load_bt_csv(PATH_30)
    rows_46_raw = load_bt_csv(PATH_46)
    rows_30 = dedupe_6h(rows_30_raw)
    rows_46 = dedupe_6h(rows_46_raw)

    print(f'\n30版: {len(rows_30_raw)} -> {len(rows_30)} (-{len(rows_30_raw)-len(rows_30)})')
    print(f'46版: {len(rows_46_raw)} -> {len(rows_46)} (-{len(rows_46_raw)-len(rows_46)})')

    # 期間
    if rows_30:
        d30 = sorted([parse_dt(r['OpenTime']) for r in rows_30])
        print(f'30版 期間: {d30[0]} 〜 {d30[-1]}')
    if rows_46:
        d46 = sorted([parse_dt(r['OpenTime']) for r in rows_46])
        print(f'46版 期間: {d46[0]} 〜 {d46[-1]}')

    # Overview
    print_section('1. Overview 比較')
    ov_30 = bt_overview(rows_30)
    ov_46 = bt_overview(rows_46)
    print(f"30版: {ov_30}")
    print(f"46版: {ov_46}")

    # D1局面分布
    print_section('2. D1局面分布 (DI_Dir × Cross_Dir)')
    print('\n--- 30版 ---')
    for key, stats in sorted(regime_d1_breakdown(rows_30).items(), key=lambda x: -x[1]['n']):
        print(f"  {fmt_key(key):<20} N={stats['n']:>3} WR={stats['wr_pct']:>5}% PF={stats['pf']:>5} Net={stats['net_usd']:+.1f}")
    print('\n--- 46版 ---')
    for key, stats in sorted(regime_d1_breakdown(rows_46).items(), key=lambda x: -x[1]['n']):
        print(f"  {fmt_key(key):<20} N={stats['n']:>3} WR={stats['wr_pct']:>5}% PF={stats['pf']:>5} Net={stats['net_usd']:+.1f}")

    # Cross_Dir × Direction (世代1の最強発見の再検証)
    print_section('3. D1_ATR_Cross_Dir × Direction (世代1: NONE×SELL=PF0.21)')
    print('\n--- 30版 ---')
    for key, stats in sorted(cross_dir_x_direction(rows_30).items(), key=lambda x: x[1]['pf']):
        if stats['n'] >= 5:
            print(f"  {fmt_key(key):<20} N={stats['n']:>3} WR={stats['wr_pct']:>5}% PF={stats['pf']:>5} Net={stats['net_usd']:+.1f}")
    print('\n--- 46版 ---')
    for key, stats in sorted(cross_dir_x_direction(rows_46).items(), key=lambda x: x[1]['pf']):
        if stats['n'] >= 5:
            print(f"  {fmt_key(key):<20} N={stats['n']:>3} WR={stats['wr_pct']:>5}% PF={stats['pf']:>5} Net={stats['net_usd']:+.1f}")

    # ボツパターン (Pattern×Zone×Dir レベル)
    print_section('4. ボツパターン Pattern×Zone×Dir (N>=10, PF<=0.7)')
    print('\n--- 30版 ---')
    bad_30 = [b for b in bad_patterns(rows_30, min_n=10, max_pf=0.7, max_net=-9999)]
    for b in bad_30:
        print(f"  {fmt_key(b['key']):<30} N={b['n']:>3} WR={b['wr_pct']:>5}% PF={b['pf']:>5} Net={b['net_usd']:+.1f}")
    print(f'  合計: {len(bad_30)}個 / 除外件数: {sum(b["n"] for b in bad_30)}')

    print('\n--- 46版 ---')
    bad_46 = [b for b in bad_patterns(rows_46, min_n=10, max_pf=0.7, max_net=-9999)]
    for b in bad_46:
        print(f"  {fmt_key(b['key']):<30} N={b['n']:>3} WR={b['wr_pct']:>5}% PF={b['pf']:>5} Net={b['net_usd']:+.1f}")
    print(f'  合計: {len(bad_46)}個 / 除外件数: {sum(b["n"] for b in bad_46)}')

    # ボツパターン (完全局面レベル)
    print_section('5. 完全局面ボツ (DI_Dir×Cross_Dir×Zone×Pattern×Dir, N>=10, PF<=0.7)')
    print('\n--- 30版 ---')
    fbad_30 = bad_patterns_full(rows_30, min_n=10, max_pf=0.7)
    for b in fbad_30[:15]:
        print(f"  {fmt_key(b['key'])}\n    N={b['n']} WR={b['wr_pct']}% PF={b['pf']} Net={b['net_usd']:+.1f}")
    print(f'  合計: {len(fbad_30)}個 / 除外件数: {sum(b["n"] for b in fbad_30)}')

    print('\n--- 46版 ---')
    fbad_46 = bad_patterns_full(rows_46, min_n=10, max_pf=0.7)
    for b in fbad_46[:15]:
        print(f"  {fmt_key(b['key'])}\n    N={b['n']} WR={b['wr_pct']}% PF={b['pf']} Net={b['net_usd']:+.1f}")
    print(f'  合計: {len(fbad_46)}個 / 除外件数: {sum(b["n"] for b in fbad_46)}')

    # グレーゾーン
    print_section('6. グレーゾーン Pattern×Zone×Dir (N>=15, PF 0.80-0.95)')
    print('\n--- 30版 ---')
    for g in grey_zone_patterns(rows_30):
        print(f"  {fmt_key(g['key']):<30} N={g['n']:>3} WR={g['wr_pct']:>5}% PF={g['pf']:>5} Net={g['net_usd']:+.1f}")
    print('\n--- 46版 ---')
    for g in grey_zone_patterns(rows_46):
        print(f"  {fmt_key(g['key']):<30} N={g['n']:>3} WR={g['wr_pct']:>5}% PF={g['pf']:>5} Net={g['net_usd']:+.1f}")

    # 機能パターン
    print_section('7. 機能パターン Pattern×Zone×Dir (N>=20, PF>=1.5)')
    print('\n--- 30版 ---')
    for g in good_patterns_full(rows_30, min_n=20, min_pf=1.5):
        print(f"  {fmt_key(g['key']):<30} N={g['n']:>3} WR={g['wr_pct']:>5}% PF={g['pf']:>5} Net={g['net_usd']:+.1f}")
    print('\n--- 46版 ---')
    for g in good_patterns_full(rows_46, min_n=20, min_pf=1.5):
        print(f"  {fmt_key(g['key']):<30} N={g['n']:>3} WR={g['wr_pct']:>5}% PF={g['pf']:>5} Net={g['net_usd']:+.1f}")

    # フィルターラベル別効果
    print_section('8. フィルターラベル別の効果（世代2 mq5 埋め込み版）')
    print('\n--- 30版 ---')
    fls_30 = filter_label_summary(rows_30)
    for col, data in fls_30.items():
        if col == 'baseline':
            print(f"  baseline: N={data['n']} PF={data['pf']} Net={data['net_usd']:+.1f}")
            continue
        if 'note' in data:
            print(f"  {col}: {data['note']}")
            continue
        af = data.get('after_filter')
        ex = data.get('excluded_only')
        if af and ex:
            print(f"  {col}:")
            print(f"    excluded only: N={ex['n']} PF={ex['pf']} Net={ex['net_usd']:+.1f}")
            print(f"    after filter:  N={af['n']} PF={af['pf']} Net={af['net_usd']:+.1f} (improve {data['pf_improvement']:+})")

    print('\n--- 46版 ---')
    fls_46 = filter_label_summary(rows_46)
    for col, data in fls_46.items():
        if col == 'baseline':
            print(f"  baseline: N={data['n']} PF={data['pf']} Net={data['net_usd']:+.1f}")
            continue
        if 'note' in data:
            print(f"  {col}: {data['note']}")
            continue
        af = data.get('after_filter')
        ex = data.get('excluded_only')
        if af and ex:
            print(f"  {col}:")
            print(f"    excluded only: N={ex['n']} PF={ex['pf']} Net={ex['net_usd']:+.1f}")
            print(f"    after filter:  N={af['n']} PF={af['pf']} Net={af['net_usd']:+.1f} (improve {data['pf_improvement']:+})")

    # 単軸 NONE×SELL 確認
    print_section('9. 周期で逆転するパターンの検出 (Pattern×Zone×Dir, N>=10両方)')
    pmap_30 = pattern_zone_map(rows_30)
    pmap_46 = pattern_zone_map(rows_46)
    common = [k for k in pmap_30 if k in pmap_46
              and pmap_30[k]['n'] >= 10 and pmap_46[k]['n'] >= 10]

    flips = []
    for k in common:
        s30, s46 = pmap_30[k], pmap_46[k]
        diff = s46['pf'] - s30['pf']
        if abs(diff) >= 0.4:
            flips.append((k, s30, s46, diff))
    flips.sort(key=lambda x: -abs(x[3]))
    for k, s30, s46, diff in flips[:15]:
        marker = '46が良化' if diff > 0 else '30が良化'
        print(f"  {fmt_key(k)}")
        print(f"    30: N={s30['n']} PF={s30['pf']} Net={s30['net_usd']:+.1f}")
        print(f"    46: N={s46['n']} PF={s46['pf']} Net={s46['net_usd']:+.1f} (Δ={diff:+.2f}, {marker})")

    # 共通ボツ（両方で死んでる）
    print_section('10. 周期間共通ボツ (両方で N>=8 & PF<=0.8)')
    pmap_30 = pattern_zone_map(rows_30)
    pmap_46 = pattern_zone_map(rows_46)
    common_bad = []
    for k in pmap_30:
        if k in pmap_46:
            s30, s46 = pmap_30[k], pmap_46[k]
            if s30['n'] >= 8 and s46['n'] >= 8 and s30['pf'] <= 0.8 and s46['pf'] <= 0.8:
                common_bad.append((k, s30, s46))
    common_bad.sort(key=lambda x: x[1]['pf'] + x[2]['pf'])
    for k, s30, s46 in common_bad:
        print(f"  {fmt_key(k)}")
        print(f"    30: N={s30['n']} PF={s30['pf']} Net={s30['net_usd']:+.1f}")
        print(f"    46: N={s46['n']} PF={s46['pf']} Net={s46['net_usd']:+.1f}")

    # ボツ除外シミュレーション
    print_section('11. ボツ除外シミュレーション (Pattern×Zone×Dir N>=10 PF<=0.7 を全停止)')

    def pattern_key(r):
        return (r.get('Pattern'), zone_detail(r), r.get('Direction'))

    # 30版
    exclude_30 = set(b['key'] for b in bad_30)
    sim_30 = simulate_filter_exclusion(rows_30, exclude_30, pattern_key)
    print(f"\n--- 30版 (除外対象: {len(exclude_30)}パターン, {sim_30['n_excluded']}件) ---")
    print(f"  除外群:   N={sim_30['excluded']['n']} PF={sim_30['excluded']['pf']} Net={sim_30['excluded']['net_usd']:+.1f}")
    print(f"  残存群:   N={sim_30['kept']['n']} PF={sim_30['kept']['pf']} Net={sim_30['kept']['net_usd']:+.1f}")
    print(f"  PF変化: {ov_30['pf']} -> {sim_30['kept']['pf']} (Δ={sim_30['kept']['pf']-ov_30['pf']:+.2f})")

    # 46版
    exclude_46 = set(b['key'] for b in bad_46)
    sim_46 = simulate_filter_exclusion(rows_46, exclude_46, pattern_key)
    print(f"\n--- 46版 (除外対象: {len(exclude_46)}パターン, {sim_46['n_excluded']}件) ---")
    print(f"  除外群:   N={sim_46['excluded']['n']} PF={sim_46['excluded']['pf']} Net={sim_46['excluded']['net_usd']:+.1f}")
    print(f"  残存群:   N={sim_46['kept']['n']} PF={sim_46['kept']['pf']} Net={sim_46['kept']['net_usd']:+.1f}")
    print(f"  PF変化: {ov_46['pf']} -> {sim_46['kept']['pf']} (Δ={sim_46['kept']['pf']-ov_46['pf']:+.2f})")

    # Filter_DI_Spread_Tight の詳細（5/5事例）
    print_section('12. Filter_DI_Spread_Tight 分解 (5/5事例追跡)')
    for label, rows in [('30', rows_30), ('46', rows_46)]:
        tight = [r for r in rows if r.get('Filter_DI_Spread_Tight') == 'TRUE']
        loose = [r for r in rows if r.get('Filter_DI_Spread_Tight') != 'TRUE']
        print(f'\n--- {label}版 ---')
        print(f"  Tight (TRUE):  N={len(tight)} -> {bt_overview(tight) if tight else 'なし'}")
        print(f"  Loose (FALSE): N={len(loose)} -> {bt_overview(loose) if loose else 'なし'}")
        # Tightの中で Direction別
        if tight:
            for d in ['BUY', 'SELL']:
                sub = [r for r in tight if r.get('Direction') == d]
                if sub:
                    print(f"    Tight × {d}: {bt_overview(sub)}")


if __name__ == '__main__':
    main()
