"""
30 vs 46 フィルター適用後 比較
- 6h重複削除
- 9本フィルター適用
- 適用前後の overview / パターン別 / フィルター個別効果
"""
import sys
from datetime import datetime, timedelta
from collections import defaultdict

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import load_bt_csv, bt_overview, to_float, zone_detail


def parse_time(s):
    """OpenTime: '2024.01.02 20:00' (秒なし) or '2024.01.02 20:00:00' に対応"""
    fmts = ['%Y.%m.%d %H:%M:%S', '%Y.%m.%d %H:%M',
            '%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M']
    for f in fmts:
        try:
            return datetime.strptime(s, f)
        except (ValueError, TypeError):
            continue
    return None


def filter_6h_duplicates(rows):
    """同方向で 6h 以内の発火を間引く（先発火優先）"""
    by_dir = defaultdict(list)
    for r in rows:
        by_dir[r.get('Direction', '')].append(r)

    kept_global = []
    for direction, group in by_dir.items():
        sorted_g = sorted(group, key=lambda r: parse_time(r.get('OpenTime', '')) or datetime.min)
        kept = []
        last_t = None
        for r in sorted_g:
            t = parse_time(r.get('OpenTime', ''))
            if t is None:
                continue
            if last_t is None or (t - last_t) >= timedelta(hours=6):
                kept.append(r)
                last_t = t
        kept_global.extend(kept)
    return kept_global


def is_mid_h(row):
    return (row.get('H1_ATR_Zone') == 'NORMAL'
            and to_float(row.get('H1_ATR_Ratio_Median')) > 1.0)


def is_mid_l(row):
    return (row.get('H1_ATR_Zone') == 'NORMAL'
            and to_float(row.get('H1_ATR_Ratio_Median')) <= 1.0)


# ===== 9本フィルター: ヒットしたら True =====
def f1_none_sell(r):
    return r.get('D1_ATR_Cross_Dir') == 'NONE' and r.get('Direction') == 'SELL'

def f2_patb_midh_sell(r):
    return (r.get('Pattern') == 'PatB' and is_mid_h(r)
            and r.get('Direction') == 'SELL')

def f3_patd_pd_buy(r):
    return (r.get('Pattern') == 'PatD' and r.get('D1_ATR_Cross_Dir') == 'PD'
            and r.get('Direction') == 'BUY')

def f4_up_none_midh_patc_buy(r):
    return (r.get('D1_DI_Dir') == 'UP' and r.get('D1_ATR_Cross_Dir') == 'NONE'
            and is_mid_h(r) and r.get('Pattern') == 'PatC'
            and r.get('Direction') == 'BUY')

def f5_up_bu_midh_patb_buy(r):
    return (r.get('D1_DI_Dir') == 'UP' and r.get('D1_ATR_Cross_Dir') == 'BU'
            and is_mid_h(r) and r.get('Pattern') == 'PatB'
            and r.get('Direction') == 'BUY')

def f6_up_pd_midh_patc_buy(r):
    return (r.get('D1_DI_Dir') == 'UP' and r.get('D1_ATR_Cross_Dir') == 'PD'
            and is_mid_h(r) and r.get('Pattern') == 'PatC'
            and r.get('Direction') == 'BUY')

def f7_di_spread_tight_sell(r):
    return (abs(to_float(r.get('H4_DI_Spread'))) < 1.0
            and r.get('Direction') == 'SELL')

def f8_patc_none_sell(r):
    return (r.get('Pattern') == 'PatC' and r.get('D1_ATR_Cross_Dir') == 'NONE'
            and r.get('Direction') == 'SELL')

def f9_pata_weak_up_sell(r):
    return (r.get('Pattern') == 'PatA' and to_float(r.get('D1_ADX')) < 20.0
            and r.get('D1_DI_Dir') == 'UP' and r.get('Direction') == 'SELL')


FILTERS = [
    ('F1', f1_none_sell, 'NONE×SELL全P'),
    ('F2', f2_patb_midh_sell, 'PatB×MID-H×SELL'),
    ('F3', f3_patd_pd_buy, 'PatD×PD×BUY'),
    ('F4', f4_up_none_midh_patc_buy, 'UP×NONE×MID-H×PatC×BUY'),
    ('F5', f5_up_bu_midh_patb_buy, 'UP×BU×MID-H×PatB×BUY'),
    ('F6', f6_up_pd_midh_patc_buy, 'UP×PD×MID-H×PatC×BUY'),
    ('F7', f7_di_spread_tight_sell, '|H4DI_Spread|<1×SELL'),
    ('F8', f8_patc_none_sell, 'PatC×NONE×SELL'),
    ('F9', f9_pata_weak_up_sell, 'PatA×ADX<20×UP×SELL'),
]


def any_filter_hit(r):
    return any(f(r) for _, f, _ in FILTERS)


def filter_hit_breakdown(rows):
    result = {}
    for name, f, desc in FILTERS:
        hit = [r for r in rows if f(r)]
        result[name] = {
            'desc': desc,
            'n_hit': len(hit),
            'hit_overview': bt_overview(hit) if hit else None,
        }
    return result


def per_pattern_dir_overview(rows):
    groups = defaultdict(list)
    for r in rows:
        key = (r.get('Pattern', ''), r.get('Direction', ''))
        groups[key].append(r)
    return {k: bt_overview(v) for k, v in groups.items()}


def run(csv_path, label):
    print(f"\n========== {label}: {csv_path} ==========")
    rows = load_bt_csv(csv_path)
    print(f"raw rows: {len(rows)}")
    rows_6h = filter_6h_duplicates(rows)
    print(f"after 6h filter: {len(rows_6h)}")

    ov_pre = bt_overview(rows_6h)
    print(f"\n[フィルター前 overview]")
    print(f"  N={ov_pre['n']}, WR={ov_pre['wr_pct']}%, PF={ov_pre['pf']}, Net=${ov_pre['net_usd']}")

    hit_bd = filter_hit_breakdown(rows_6h)
    print(f"\n[フィルター個別ヒット件数 (6h後の集合に対して)]")
    for name, info in hit_bd.items():
        ov = info['hit_overview']
        if ov:
            print(f"  {name} ({info['desc']}): N={ov['n']} WR={ov['wr_pct']}% PF={ov['pf']} Net=${ov['net_usd']}")
        else:
            print(f"  {name} ({info['desc']}): N=0")

    rows_filtered = [r for r in rows_6h if not any_filter_hit(r)]
    ov_post = bt_overview(rows_filtered)
    print(f"\n[9本フィルター適用後 overview]")
    print(f"  N={ov_post['n']}, WR={ov_post['wr_pct']}%, PF={ov_post['pf']}, Net=${ov_post['net_usd']}")
    print(f"  除外件数: {ov_pre['n'] - ov_post['n']}")

    pat_dir = per_pattern_dir_overview(rows_filtered)
    print(f"\n[フィルター後 Pattern×Direction (N>=3)]")
    items = sorted([(k, v) for k, v in pat_dir.items() if v['n'] >= 3],
                   key=lambda x: -x[1]['pf'])
    for k, v in items:
        print(f"  {k}: N={v['n']} WR={v['wr_pct']}% PF={v['pf']} Net=${v['net_usd']}")

    return {
        'label': label,
        'raw_n': len(rows),
        'after_6h': rows_6h,
        'filtered': rows_filtered,
        'overview_pre': ov_pre,
        'overview_post': ov_post,
        'hit_breakdown': hit_bd,
        'pat_dir_post': pat_dir,
    }


if __name__ == '__main__':
    res30 = run('/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx30.csv', '30版')
    res46 = run('/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv', '46版')

    print("\n\n========== 30 vs 46 結論サマリ ==========")
    print(f"\n[フィルター前 (6h後)]")
    print(f"  30版: N={res30['overview_pre']['n']} WR={res30['overview_pre']['wr_pct']}% PF={res30['overview_pre']['pf']} Net=${res30['overview_pre']['net_usd']}")
    print(f"  46版: N={res46['overview_pre']['n']} WR={res46['overview_pre']['wr_pct']}% PF={res46['overview_pre']['pf']} Net=${res46['overview_pre']['net_usd']}")

    print(f"\n[フィルター後 (9本適用)]")
    print(f"  30版: N={res30['overview_post']['n']} WR={res30['overview_post']['wr_pct']}% PF={res30['overview_post']['pf']} Net=${res30['overview_post']['net_usd']}")
    print(f"  46版: N={res46['overview_post']['n']} WR={res46['overview_post']['wr_pct']}% PF={res46['overview_post']['pf']} Net=${res46['overview_post']['net_usd']}")

    print(f"\n[除外効率]")
    e30 = res30['overview_pre']['n'] - res30['overview_post']['n']
    e46 = res46['overview_pre']['n'] - res46['overview_post']['n']
    print(f"  30版: {res30['overview_pre']['n']} -> {res30['overview_post']['n']} ({e30}件除外, {e30/res30['overview_pre']['n']*100:.1f}%)")
    print(f"  46版: {res46['overview_pre']['n']} -> {res46['overview_post']['n']} ({e46}件除外, {e46/res46['overview_pre']['n']*100:.1f}%)")
