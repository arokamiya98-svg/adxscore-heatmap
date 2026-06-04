"""
analyze_pattern_by_phase.py — Pattern × D1局面 詳細クロス分析（46周期版）

入力: data/bt/ATR_WidthSignal_BT_h4adx46.csv
前処理: 6時間重複削除
出力: PATTERN_REGIME_MAP_v2_PatternByPhase.md 用の数値テーブル
"""

import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, '/Users/aro/Desktop/ADXSCORE/scripts')
from analyze_bt import (
    load_bt_csv, bt_overview, regime_breakdown, zone_detail, to_float
)


CSV_PATH = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_h4adx46.csv'


# ============================================================
# 6時間重複削除（v2マップと同じ方針）
# ============================================================

def parse_dt(s):
    s = (s or '').strip().strip('"')
    for fmt in ('%Y.%m.%d %H:%M:%S', '%Y.%m.%d %H:%M', '%Y-%m-%d %H:%M:%S'):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def filter_6h(rows):
    """6時間以内の連発を削除（同方向のみ、後発を捨てる）"""
    rows_sorted = sorted(
        rows,
        key=lambda r: (parse_dt(r.get('OpenTime')) or datetime.min)
    )
    kept = []
    last_open_by_dir = {}
    for r in rows_sorted:
        dt = parse_dt(r.get('OpenTime'))
        d = r.get('Direction', '')
        if dt is None:
            kept.append(r)
            continue
        last = last_open_by_dir.get(d)
        if last is None or (dt - last).total_seconds() >= 6 * 3600:
            kept.append(r)
            last_open_by_dir[d] = dt
    return kept


# ============================================================
# D1局面ラベル（修正版: D1_ATR_Cross_Dir は元々 BU/PD/NONE）
# ============================================================

def d1_phase_label(row):
    """D1_ATR_Cross_Dir の値そのまま BU/PD/NONE"""
    c = row.get('D1_ATR_Cross_Dir', '').strip().upper()
    if c in ('BU', 'PD', 'NONE'):
        return c
    return 'NONE'


def d1_di_dir(row):
    return row.get('D1_DI_Dir', '').strip() or 'NONE'


def d1_combined(row):
    """UP×PD / DN×BU など v2マップ準拠の複合ラベル"""
    di = d1_di_dir(row)
    ph = d1_phase_label(row)
    return f"{di}×{ph}"


# ============================================================
# Pattern × D1_Phase クロス
# ============================================================

def pattern_by_phase(rows, direction):
    """Pattern × D1_Phase の表（指定 Direction）

    Returns: dict[(Pattern, Phase), overview]
    """
    sub = [r for r in rows if r.get('Direction') == direction]
    return regime_breakdown(sub, ['Pattern', d1_phase_label])


def pattern_by_phase_zone(rows, direction):
    """Pattern × D1_Phase × Zone(細分) の3軸表"""
    sub = [r for r in rows if r.get('Direction') == direction]
    return regime_breakdown(sub, ['Pattern', d1_phase_label, zone_detail])


def pattern_by_phase_di(rows, direction):
    """Pattern × D1_DI_Dir × D1_Phase（DN/UP局面分離も見たい）"""
    sub = [r for r in rows if r.get('Direction') == direction]
    return regime_breakdown(sub, ['Pattern', d1_di_dir, d1_phase_label])


# ============================================================
# 表示
# ============================================================

PATTERNS = ['PatA', 'PatB', 'PatC', 'PatD', 'PatE']
PHASES = ['BU', 'PD', 'NONE']


def print_cross_matrix(rows, direction, label):
    print(f"\n{'='*70}")
    print(f"  {label}: {direction}")
    print(f"{'='*70}")
    m = pattern_by_phase(rows, direction)
    print(f"\n{'Pattern':<8} {'Phase':<6} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
    print("-" * 50)
    for pat in PATTERNS:
        for ph in PHASES:
            k = (pat, ph)
            if k in m:
                s = m[k]
                print(f"{pat:<8} {ph:<6} {s['n']:>4} {s['wr_pct']:>6.1f} {s['pf']:>7.2f} {s['net_usd']:>10.2f}")
            else:
                print(f"{pat:<8} {ph:<6} {'-':>4} {'-':>6} {'-':>7} {'-':>10}")
    return m


def print_phase_di(rows, direction, label):
    """Pattern × DI_Dir × Phase の補助表"""
    print(f"\n{'-'*70}")
    print(f"  {label}: {direction}  (Pattern × D1_DI_Dir × D1_Phase)")
    print(f"{'-'*70}")
    m = pattern_by_phase_di(rows, direction)
    items = sorted([(k, v) for k, v in m.items() if v['n'] >= 3],
                   key=lambda x: (x[0][0], x[0][1], x[0][2]))
    print(f"\n{'Pattern':<8} {'DI':<5} {'Phase':<6} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
    print("-" * 55)
    for k, s in items:
        pat, di, ph = k
        print(f"{pat:<8} {di:<5} {ph:<6} {s['n']:>4} {s['wr_pct']:>6.1f} {s['pf']:>7.2f} {s['net_usd']:>10.2f}")
    return m


def print_phase_zone(rows, direction, target_cells, label):
    """指定の (Pattern, Phase) セルを Zone細分で深掘り"""
    print(f"\n{'-'*70}")
    print(f"  {label} 3軸深掘り: {direction}")
    print(f"{'-'*70}")
    m = pattern_by_phase_zone(rows, direction)
    for (pat, ph) in target_cells:
        print(f"\n  [{pat} × {ph} × {direction}]")
        zones = ['LOW', 'MID-L', 'MID-H', 'HIGH']
        printed = False
        for z in zones:
            k = (pat, ph, z)
            if k in m and m[k]['n'] >= 3:
                s = m[k]
                print(f"    Zone={z:<5} N={s['n']:>3} WR={s['wr_pct']:>5.1f}% PF={s['pf']:>6.2f} Net=${s['net_usd']:>8.2f}")
                printed = True
        if not printed:
            print(f"    (各 Zone N<3、深掘り不可)")
    return m


# ============================================================
# Pattern全体（局面横断）の確認用
# ============================================================

def print_pattern_overall(rows):
    print(f"\n{'='*70}")
    print(f"  Pattern × Direction 全体 (局面横断、参考)")
    print(f"{'='*70}")
    m = regime_breakdown(rows, ['Pattern', 'Direction'])
    items = sorted(m.items(), key=lambda x: (x[0][0], x[0][1]))
    print(f"\n{'Pattern':<8} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
    print("-" * 50)
    for k, s in items:
        if s['n'] >= 1:
            print(f"{k[0]:<8} {k[1]:<5} {s['n']:>4} {s['wr_pct']:>6.1f} {s['pf']:>7.2f} {s['net_usd']:>10.2f}")


# ============================================================
# v2マップ追補: 新規ボツ候補抽出
# ============================================================

def extract_new_bad_phase_cells(rows, min_n=8, max_pf=0.7):
    """N≥min_n PF≤max_pf の (Pattern, Phase, Direction) を抽出"""
    bad = []
    for direction in ['BUY', 'SELL']:
        m = pattern_by_phase(rows, direction)
        for (pat, ph), s in m.items():
            if s['n'] >= min_n and s['pf'] <= max_pf:
                bad.append({
                    'Pattern': pat, 'Phase': ph, 'Dir': direction,
                    'N': s['n'], 'WR': s['wr_pct'],
                    'PF': s['pf'], 'Net': s['net_usd']
                })
    return sorted(bad, key=lambda x: x['PF'])


def extract_strong_cells(rows, min_n=8, min_pf=1.5):
    """機能セル抽出"""
    good = []
    for direction in ['BUY', 'SELL']:
        m = pattern_by_phase(rows, direction)
        for (pat, ph), s in m.items():
            if s['n'] >= min_n and s['pf'] >= min_pf:
                good.append({
                    'Pattern': pat, 'Phase': ph, 'Dir': direction,
                    'N': s['n'], 'WR': s['wr_pct'],
                    'PF': s['pf'], 'Net': s['net_usd']
                })
    return sorted(good, key=lambda x: -x['PF'])


# ============================================================
# main
# ============================================================

def main():
    print(f"Loading: {CSV_PATH}")
    rows_all = load_bt_csv(CSV_PATH)
    print(f"Loaded: {len(rows_all)} rows (raw)")

    rows = filter_6h(rows_all)
    print(f"After 6h filter: {len(rows)} rows")

    print("\n" + "=" * 70)
    print(f"  Overview (after 6h filter)")
    print("=" * 70)
    ov = bt_overview(rows)
    print(f"  N={ov['n']}  WR={ov['wr_pct']}%  PF={ov['pf']}  Net=${ov['net_usd']}")
    print(f"  avg SL={ov['avg_sl_pips']} pips  avg TP={ov['avg_tp_pips']} pips")

    # 1. Direction × D1_Phase 全体分布
    print(f"\n{'='*70}")
    print(f"  Direction × D1_Phase 分布 (サンプル数把握用)")
    print(f"{'='*70}")
    dist = regime_breakdown(rows, ['Direction', d1_phase_label])
    print(f"\n{'Dir':<6} {'Phase':<6} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
    print("-" * 50)
    for k in sorted(dist.keys()):
        s = dist[k]
        print(f"{k[0]:<6} {k[1]:<6} {s['n']:>4} {s['wr_pct']:>6.1f} {s['pf']:>7.2f} {s['net_usd']:>10.2f}")

    # 2. Pattern全体（参考）
    print_pattern_overall(rows)

    # 3. メイン: BUY/SELL クロス表
    m_buy = print_cross_matrix(rows, 'BUY', '1-1. BUY側 Pattern × D1_Phase クロス表')
    m_sell = print_cross_matrix(rows, 'SELL', '1-2. SELL側 Pattern × D1_Phase クロス表')

    # 4. DI方向別の補助（DN局面か UP局面かを見る）
    print_phase_di(rows, 'BUY', '補助1. BUY')
    print_phase_di(rows, 'SELL', '補助2. SELL')

    # 5. 3軸深掘り (BUY側: N≥10 のセル全部)
    print(f"\n{'='*70}")
    print(f"  3. Pattern × Phase × Zone 3軸深掘り (N≥10セル)")
    print(f"{'='*70}")

    target_buy = [(pat, ph) for (pat, ph), s in m_buy.items() if s['n'] >= 10]
    print_phase_zone(rows, 'BUY', target_buy, '3-1. BUY')

    target_sell = [(pat, ph) for (pat, ph), s in m_sell.items() if s['n'] >= 10]
    print_phase_zone(rows, 'SELL', target_sell, '3-2. SELL')

    # 6. 新規ボツ・機能候補
    print(f"\n{'='*70}")
    print(f"  4. v2マップ追補: 新規ボツ候補 (Pattern × Phase × Dir, N≥8 PF≤0.7)")
    print(f"{'='*70}")
    bad_new = extract_new_bad_phase_cells(rows)
    if bad_new:
        print(f"\n{'Pattern':<8} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
        for b in bad_new:
            print(f"{b['Pattern']:<8} {b['Phase']:<6} {b['Dir']:<5} {b['N']:>4} {b['WR']:>6.1f} {b['PF']:>7.2f} {b['Net']:>10.2f}")
    else:
        print("  (該当なし)")

    # ボツ候補の参考: 若干広めの基準
    print(f"\n{'='*70}")
    print(f"  4b. 参考: N≥6 PF≤0.85 のボツ寄り候補")
    print(f"{'='*70}")
    bad_loose = extract_new_bad_phase_cells(rows, min_n=6, max_pf=0.85)
    if bad_loose:
        print(f"\n{'Pattern':<8} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
        for b in bad_loose:
            print(f"{b['Pattern']:<8} {b['Phase']:<6} {b['Dir']:<5} {b['N']:>4} {b['WR']:>6.1f} {b['PF']:>7.2f} {b['Net']:>10.2f}")

    print(f"\n{'='*70}")
    print(f"  5. 機能セル (Pattern × Phase × Dir, N≥8 PF≥1.5)")
    print(f"{'='*70}")
    good_cells = extract_strong_cells(rows)
    if good_cells:
        print(f"\n{'Pattern':<8} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
        for g in good_cells:
            print(f"{g['Pattern']:<8} {g['Phase']:<6} {g['Dir']:<5} {g['N']:>4} {g['WR']:>6.1f} {g['PF']:>7.2f} {g['Net']:>10.2f}")

    # 参考: 機能セル 緩め
    print(f"\n{'='*70}")
    print(f"  5b. 参考: N≥6 PF≥1.3 の機能寄り候補")
    print(f"{'='*70}")
    good_loose = extract_strong_cells(rows, min_n=6, min_pf=1.3)
    if good_loose:
        print(f"\n{'Pattern':<8} {'Phase':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>7} {'Net$':>10}")
        for g in good_loose:
            print(f"{g['Pattern']:<8} {g['Phase']:<6} {g['Dir']:<5} {g['N']:>4} {g['WR']:>6.1f} {g['PF']:>7.2f} {g['Net']:>10.2f}")


if __name__ == '__main__':
    main()
