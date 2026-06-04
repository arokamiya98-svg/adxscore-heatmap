"""
analyze_bt.py — BT/CSV分析関数群（カイの道具）

ADXSCORE プロジェクトの BT CSV を分析するための関数群。
pandas を使わず標準ライブラリのみで実装（Mac環境 8GB 配慮）。

使い方:
    from analyze_bt import load_bt_csv, bt_overview, ...
    rows = load_bt_csv('data/bt/ATR_WidthSignal_BT_NEW.csv')
    print(bt_overview(rows))

CLI:
    python3 scripts/analyze_bt.py [csv_path]
"""

import csv
import io
import statistics
import sys
from collections import defaultdict
from pprint import pprint


# ============================================================
# 基本ユーティリティ
# ============================================================

def to_float(s, default=0.0):
    """文字列を float に変換（失敗時は default）"""
    try:
        return float(s)
    except (ValueError, TypeError):
        return default


def load_bt_csv(path):
    """BT CSV を読み込み。UTF-16/UTF-8 自動判別。BOM除去込み。

    Returns: list[dict] (各行が dict、列名 → 文字列値)
    """
    encodings = ['utf-16', 'utf-16-le', 'utf-8-sig', 'utf-8']
    for enc in encodings:
        try:
            with open(path, encoding=enc) as f:
                content = f.read().lstrip('﻿')
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            if rows and len(rows[0]) > 1:
                return rows
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise RuntimeError(f"Failed to load CSV: {path}")


def zone_detail(row):
    """H1_ATR_Zone を MID-L / MID-H / LOW / HIGH に細分化"""
    zone = row.get('H1_ATR_Zone', '')
    if zone != 'NORMAL':
        return zone  # LOW or HIGH
    ratio = to_float(row.get('H1_ATR_Ratio_Median', 0))
    return 'MID-L' if ratio <= 1.0 else 'MID-H'


# ============================================================
# 集計関数
# ============================================================

def bt_overview(rows):
    """全体傾向: 件数、WR、PF、Net、SL/TP平均

    Returns: dict
    """
    n = len(rows)
    if n == 0:
        return {'n': 0, 'wins': 0, 'losses': 0, 'wr_pct': 0,
                'pf': 0, 'net_usd': 0, 'avg_sl_pips': 0, 'avg_tp_pips': 0}

    wins = [r for r in rows if r.get('Result') == 'WIN']
    losses = [r for r in rows if r.get('Result') == 'LOSS']

    total_profit = sum(to_float(r.get('Profit_USD')) for r in rows)
    win_profit = sum(to_float(r.get('Profit_USD')) for r in wins)
    loss_profit = sum(to_float(r.get('Profit_USD')) for r in losses)

    pf = (win_profit / abs(loss_profit)) if loss_profit != 0 else float('inf')
    wr = len(wins) / n * 100 if n > 0 else 0

    return {
        'n': n,
        'wins': len(wins),
        'losses': len(losses),
        'wr_pct': round(wr, 1),
        'pf': round(pf, 2),
        'net_usd': round(total_profit, 2),
        'avg_sl_pips': round(statistics.mean(to_float(r.get('SL_Pips')) for r in rows), 1),
        'avg_tp_pips': round(statistics.mean(to_float(r.get('TP_Pips')) for r in rows), 1),
    }


def regime_breakdown(rows, by_columns):
    """指定列でグループ化、各群の overview を返す

    Args:
        by_columns: list of column names (or callable: row -> key)

    Returns: dict[key_tuple, overview_dict]
    """
    groups = defaultdict(list)
    for r in rows:
        key_parts = []
        for c in by_columns:
            if callable(c):
                key_parts.append(c(r))
            else:
                key_parts.append(r.get(c, ''))
        groups[tuple(key_parts)].append(r)

    return {key: bt_overview(group) for key, group in groups.items()}


def pattern_zone_map(rows):
    """Pattern × Zone(細分) × Direction のマップ

    Returns: dict[(Pattern, Zone_Detail, Direction), overview]
    """
    return regime_breakdown(rows, ['Pattern', zone_detail, 'Direction'])


def regime_d1_breakdown(rows):
    """D1局面 (D1_DI_Dir × D1_ATR_Cross_Dir) の分布

    PATTERN_REGIME_MAP の「UP×PD」「DN×BU」等のフォーマット
    """
    return regime_breakdown(rows, ['D1_DI_Dir', 'D1_ATR_Cross_Dir'])


def bad_patterns(rows, min_n=5, max_pf=0.7, max_net=-50):
    """ダメパターン抽出: N>=min_n & (PF<=max_pf or Net<=max_net)

    Returns: list[dict] (PF昇順)
    """
    pmap = pattern_zone_map(rows)
    bad = []
    for key, stats in pmap.items():
        if stats['n'] < min_n:
            continue
        if stats['pf'] <= max_pf or stats['net_usd'] <= max_net:
            bad.append({'key': key, **stats})
    return sorted(bad, key=lambda x: x['pf'])


def good_patterns(rows, min_n=5, min_pf=1.3):
    """機能パターン抽出: N>=min_n & PF>=min_pf

    Returns: list[dict] (PF降順)
    """
    pmap = pattern_zone_map(rows)
    good = []
    for key, stats in pmap.items():
        if stats['n'] < min_n:
            continue
        if stats['pf'] >= min_pf:
            good.append({'key': key, **stats})
    return sorted(good, key=lambda x: -x['pf'])


# ============================================================
# 世代2 専用: フィルターラベル・DI動態・周期比較
# ============================================================

FILTER_COLS_DEFAULT = [
    'Filter_Cross_None_Sell',
    'Filter_PatD_Sell',
    'Filter_PatC_MidH',
    'Filter_UpNoneMidH',
    'Filter_DI_Spread_Tight',
]


def filter_label_summary(rows, filter_cols=None):
    """フィルターラベル別の効果

    各フィルターについて:
    - excluded_only: 該当(TRUE)だけのoverview
    - after_filter: 該当除外した残りのoverview
    - pf_improvement: フィルター適用でPFがどれだけ改善するか

    Returns: dict
    """
    if filter_cols is None:
        filter_cols = FILTER_COLS_DEFAULT

    if not rows:
        return {'note': 'no rows'}

    base = bt_overview(rows)
    result = {'baseline': base}

    for col in filter_cols:
        if col not in rows[0]:
            result[col] = {'note': f'column {col} not in CSV (世代1?)'}
            continue
        excluded = [r for r in rows if r.get(col) == 'TRUE']
        kept = [r for r in rows if r.get(col) != 'TRUE']
        kept_ov = bt_overview(kept) if kept else None
        result[col] = {
            'excluded_only': bt_overview(excluded) if excluded else None,
            'after_filter': kept_ov,
            'pf_improvement': round(kept_ov['pf'] - base['pf'], 2) if kept_ov else None,
            'n_excluded': len(excluded),
        }

    # 全フィルターを併用適用
    if all(col in rows[0] for col in filter_cols):
        kept_all = [r for r in rows
                    if not any(r.get(c) == 'TRUE' for c in filter_cols)]
        if kept_all:
            kept_all_ov = bt_overview(kept_all)
            result['ALL_FILTERS_APPLIED'] = {
                'after_filter': kept_all_ov,
                'pf_improvement': round(kept_all_ov['pf'] - base['pf'], 2),
                'n_excluded': len(rows) - len(kept_all),
            }

    return result


def di_velocity_analysis(rows):
    """DI動態 (vel3/vel8/slope) の四分位別 WR/PF

    Returns: dict[col, {q1_lowest, q4_highest}]
    """
    if not rows or 'H4_DI_Plus_Vel3' not in rows[0]:
        return {'note': 'DI動態列なし (世代1 CSV?)'}

    cols = [
        'H1_DI_Plus_Vel3', 'H1_DI_Minus_Vel3',
        'H1_DI_Plus_Vel8', 'H1_DI_Minus_Vel8',
        'H1_DI_Plus_Slope', 'H1_DI_Minus_Slope',
        'H4_DI_Plus_Vel3', 'H4_DI_Minus_Vel3',
        'H4_DI_Plus_Vel8', 'H4_DI_Minus_Vel8',
        'H4_DI_Plus_Slope', 'H4_DI_Minus_Slope',
    ]
    result = {}
    for col in cols:
        if col not in rows[0]:
            continue
        sorted_vals = sorted(rows, key=lambda r: to_float(r.get(col)))
        n = len(sorted_vals)
        if n < 8:
            continue
        q1 = sorted_vals[:n // 4]
        q4 = sorted_vals[3 * n // 4:]
        result[col] = {
            'q1_lowest': bt_overview(q1),
            'q4_highest': bt_overview(q4),
            'q1_range': (to_float(q1[0].get(col)), to_float(q1[-1].get(col))),
            'q4_range': (to_float(q4[0].get(col)), to_float(q4[-1].get(col))),
        }
    return result


def adx_period_compare(rows_a, rows_b, label_a='A', label_b='B'):
    """2つのBT結果を比較（H4_ADX=30 vs =46 など）

    Returns: dict
    """
    ov_a = bt_overview(rows_a)
    ov_b = bt_overview(rows_b)
    return {
        label_a: ov_a,
        label_b: ov_b,
        'fire_count_diff': ov_a['n'] - ov_b['n'],
        'pf_diff': round(ov_a['pf'] - ov_b['pf'], 2),
        'wr_diff_pct': round(ov_a['wr_pct'] - ov_b['wr_pct'], 1),
        'net_diff_usd': round(ov_a['net_usd'] - ov_b['net_usd'], 2),
    }


# ============================================================
# 表示ヘルパー
# ============================================================

def print_pattern_map(rows, sort_by='pf', desc=True, min_n=5):
    """Pattern × Zone × Direction のマップを表形式で出力"""
    pmap = pattern_zone_map(rows)
    items = [(k, v) for k, v in pmap.items() if v['n'] >= min_n]
    items.sort(key=lambda x: x[1][sort_by], reverse=desc)
    print(f"\n{'Pattern':<8} {'Zone':<6} {'Dir':<5} {'N':>4} {'WR%':>6} {'PF':>6} {'Net$':>9}")
    print("-" * 50)
    for key, stats in items:
        pat, zone, direction = key
        print(f"{pat:<8} {zone:<6} {direction:<5} {stats['n']:>4} "
              f"{stats['wr_pct']:>6.1f} {stats['pf']:>6.2f} {stats['net_usd']:>9.2f}")


# ============================================================
# CLI
# ============================================================

def main():
    if len(sys.argv) < 2:
        path = '/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_NEW.csv'
    else:
        path = sys.argv[1]

    rows = load_bt_csv(path)
    print(f"=== Loaded: {len(rows)} rows from {path} ===\n")

    print("--- Overview ---")
    pprint(bt_overview(rows))

    print("\n--- D1 Regime Breakdown ---")
    for key, stats in sorted(regime_d1_breakdown(rows).items(),
                              key=lambda x: -x[1]['n']):
        print(f"  {key}: {stats}")

    print("\n--- Bad Patterns (Top 6) ---")
    for bp in bad_patterns(rows)[:6]:
        print(f"  {bp}")

    print("\n--- Good Patterns (Top 10) ---")
    for gp in good_patterns(rows)[:10]:
        print(f"  {gp}")

    if rows and 'Filter_Cross_None_Sell' in rows[0]:
        print("\n--- Filter Label Summary ---")
        pprint(filter_label_summary(rows))
    else:
        print("\n(世代1 CSV: フィルターラベル列なし、filter_label_summary スキップ)")

    if rows and 'H4_DI_Plus_Vel3' in rows[0]:
        print("\n--- DI Velocity Analysis (要約) ---")
        di = di_velocity_analysis(rows)
        for col, data in di.items():
            if isinstance(data, dict) and 'q1_lowest' in data:
                print(f"  {col}:")
                print(f"    Q1 ({data['q1_range']}): WR={data['q1_lowest']['wr_pct']}% PF={data['q1_lowest']['pf']}")
                print(f"    Q4 ({data['q4_range']}): WR={data['q4_highest']['wr_pct']}% PF={data['q4_highest']['pf']}")
    else:
        print("\n(世代1 CSV: DI動態列なし、di_velocity_analysis スキップ)")


if __name__ == '__main__':
    main()
