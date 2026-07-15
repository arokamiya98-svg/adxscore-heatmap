"""
DXY ADX(56)レジーム × XAUUSD既存シグナル クロス解析 v1
担当: カイ / 指示書: data/dxy/KAI_DXY_ADX56_x_signals_spec.md

- A: data/dxy/DXY_ADX_Timeseries_v1.csv (UTF-16, H1, ADX56/DI/ATR Ratio)
- B: data/bt/ATR_WidthSignal_BT_h4adx46.csv (UTF-16, 947件, 6h dedupe -> 393)
- C: mt5_data/daily/signal_fires.csv (UTF-8-sig, 418件, time_serverで突合)

標準ライブラリのみ。結果フィッティング禁止。N<15は参考値。
"""
import csv
import io
import statistics
from collections import defaultdict, Counter
from datetime import datetime, timedelta

BASE = '/Users/aro/Desktop/ADXSCORE'
DXY_CSV = f'{BASE}/data/dxy/DXY_ADX_Timeseries_v1.csv'
BT_CSV = f'{BASE}/data/bt/ATR_WidthSignal_BT_h4adx46.csv'
FW_CSV = f'{BASE}/mt5_data/daily/signal_fires.csv'

WARMUP_DROP = 200  # ADX(56)ウォームアップ歪み: 先頭200本を捨てる（指示書許容）


# ============================================================
# 共通ユーティリティ
# ============================================================

def load_csv(path):
    """UTF-16 -> UTF-8-sig -> UTF-8 フォールバック読み込み"""
    for enc in ['utf-16', 'utf-8-sig', 'utf-8']:
        try:
            with open(path, encoding=enc) as f:
                content = f.read().lstrip('﻿')
            rows = list(csv.DictReader(io.StringIO(content)))
            if rows and len(rows[0]) > 1:
                return rows
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise RuntimeError(f'Failed to load: {path}')


def to_float(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def parse_dt(s):
    for f in ['%Y.%m.%d %H:%M:%S', '%Y.%m.%d %H:%M',
              '%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M']:
        try:
            return datetime.strptime(s.strip(), f)
        except (ValueError, TypeError, AttributeError):
            continue
    return None


def adx_band(adx):
    """段階化厳守: <20 / 20-25 / 25-30 / 30-35 / >=35"""
    if adx < 20:
        return '<20'
    if adx < 25:
        return '20-25'
    if adx < 30:
        return '25-30'
    if adx < 35:
        return '30-35'
    return '>=35'


BANDS = ['<20', '20-25', '25-30', '30-35', '>=35']


def wind(xau_dir, usd_dir):
    """順風: XAU BUY×USD_DN / XAU SELL×USD_UP。逆は向かい風"""
    if (xau_dir == 'BUY' and usd_dir == 'USD_DN') or \
       (xau_dir == 'SELL' and usd_dir == 'USD_UP'):
        return 'TAIL'  # 順風
    return 'HEAD'      # 向かい風


def pct(x, n):
    return f'{x / n * 100:.1f}%' if n else '-'


# ============================================================
# A. DXY 時系列
# ============================================================

def load_dxy():
    rows = load_csv(DXY_CSV)
    rows = rows[WARMUP_DROP:]  # ウォームアップ除去
    series = []
    for r in rows:
        t = parse_dt(r['Time'])
        if t is None:
            continue
        adx = to_float(r['ADX'])
        dip = to_float(r['DI_Plus'])
        dim = to_float(r['DI_Minus'])
        ratio = to_float(r['Ratio'])
        series.append({
            't': t, 'adx': adx,
            'band': adx_band(adx),
            'di': 'USD_UP' if dip > dim else 'USD_DN',
            'ratio': ratio,
        })
    return series


def dxy_base_rates(series, label, t0=None, t1=None):
    sub = [s for s in series
           if (t0 is None or s['t'] >= t0) and (t1 is None or s['t'] <= t1)]
    n = len(sub)
    print(f'\n--- ベースレート [{label}] N={n} '
          f'({sub[0]["t"]} 〜 {sub[-1]["t"]}) ---')
    cb = Counter(s['band'] for s in sub)
    cd = Counter(s['di'] for s in sub)
    cbd = Counter((s['band'], s['di']) for s in sub)
    print('ADX56帯   : ' + '  '.join(f'{b}:{pct(cb[b], n)}' for b in BANDS))
    print('DI方向    : ' + '  '.join(f'{d}:{pct(cd[d], n)}'
                                    for d in ['USD_UP', 'USD_DN']))
    print('帯×DI     :')
    for b in BANDS:
        row = '  '.join(f'{d}:{pct(cbd[(b, d)], n)}'
                        for d in ['USD_UP', 'USD_DN'])
        print(f'  {b:>6}: {row}')
    return {'n': n, 'band': cb, 'di': cd, 'band_di': cbd}


def dxy_ratio_dist(series):
    vals = sorted(s['ratio'] for s in series if s['ratio'] > 0)
    n = len(vals)
    excluded = len(series) - n
    def q(p):
        return vals[min(n - 1, int(n * p))]
    print(f'\n--- DXY ATR Ratio 分布 (Ratio=0 除外 {excluded}本) N={n} ---')
    print(f'p10={q(0.10):.3f} p25={q(0.25):.3f} p50={q(0.50):.3f} '
          f'p75={q(0.75):.3f} p90={q(0.90):.3f}')
    low = sum(1 for v in vals if v < 0.70)
    mid = sum(1 for v in vals if 0.70 <= v <= 1.40)
    high = sum(1 for v in vals if v > 1.40)
    print(f'既存流儀 0.70/1.40 3区分: LOW {pct(low, n)} / '
          f'NORMAL {pct(mid, n)} / HIGH {pct(high, n)}')
    t1, t2 = q(1 / 3), q(2 / 3)
    print(f'参考: 三分位境界 = {t1:.3f} / {t2:.3f}')


# ============================================================
# 突合
# ============================================================

def build_dxy_map(series):
    return {s['t']: s for s in series}


def join_dxy(dxy_map, t):
    """H1 floor -> 直前バー最大3h遡り"""
    if t is None:
        return None
    base = t.replace(minute=0, second=0, microsecond=0)
    for back in range(0, 4):
        hit = dxy_map.get(base - timedelta(hours=back))
        if hit:
            return hit
    return None


# ============================================================
# B. BT世代2
# ============================================================

def dedupe_6h(rows):
    """同方向(BUY/SELL別)・6h以内連発は先発火のみ採用（既存規約の再現）"""
    srt = sorted(rows, key=lambda r: parse_dt(r['OpenTime']) or datetime.min)
    last = {'BUY': None, 'SELL': None}
    kept = []
    for r in srt:
        d = r['Direction']
        t = parse_dt(r['OpenTime'])
        if t is None:
            continue
        if last[d] is None or (t - last[d]) >= timedelta(hours=6):
            kept.append(r)
            last[d] = t
    return kept


def is_mid_h(r):
    return (r.get('H1_ATR_Zone') == 'NORMAL'
            and to_float(r.get('H1_ATR_Ratio_Median')) > 1.0)


def any_filter_hit(r):
    """v4 9本フィルター（compare_30_46_filtered.py の定義を再現）"""
    d, p = r.get('Direction'), r.get('Pattern')
    cross = r.get('D1_ATR_Cross_Dir')
    didir = r.get('D1_DI_Dir')
    if cross == 'NONE' and d == 'SELL':
        return True  # F1
    if p == 'PatB' and is_mid_h(r) and d == 'SELL':
        return True  # F2
    if p == 'PatD' and cross == 'PD' and d == 'BUY':
        return True  # F3
    if didir == 'UP' and cross == 'NONE' and is_mid_h(r) \
            and p == 'PatC' and d == 'BUY':
        return True  # F4
    if didir == 'UP' and cross == 'BU' and is_mid_h(r) \
            and p == 'PatB' and d == 'BUY':
        return True  # F5
    if didir == 'UP' and cross == 'PD' and is_mid_h(r) \
            and p == 'PatC' and d == 'BUY':
        return True  # F6
    if abs(to_float(r.get('H4_DI_Spread'))) < 1.0 and d == 'SELL':
        return True  # F7
    if p == 'PatC' and cross == 'NONE' and d == 'SELL':
        return True  # F8
    if p == 'PatA' and to_float(r.get('D1_ADX')) < 20.0 \
            and didir == 'UP' and d == 'SELL':
        return True  # F9
    return False


def h4_phase_auto(r):
    """H4 Phase Auto v2 の再現（凪離脱の特定用）"""
    ratio = to_float(r.get('H4_ATR_Ratio_Median'))
    diff = to_float(r.get('H4_ATR_Short')) - to_float(r.get('H4_ATR_Long'))
    cross = r.get('H4_Cross_Dir', '')
    if ratio <= 0:
        return '-'
    if ratio <= 0.97:
        if diff < -1.0:
            return '収束底'
        if diff > 1.0:
            return '凪離脱'
        return '凪'
    if cross == 'UP':
        return 'BU'
    if cross == 'DOWN':
        return 'PD'
    return '-'


def bt_perf(rows):
    """N, WR, PF, 平均pips（既存 bt_overview 流儀: Profit_USDベースPF）"""
    n = len(rows)
    if n == 0:
        return {'n': 0, 'wr': '-', 'pf': '-', 'avg_pips': '-'}
    wins = [r for r in rows if r.get('Result') == 'WIN']
    wp = sum(to_float(r['Profit_USD']) for r in wins)
    lp = sum(to_float(r['Profit_USD']) for r in rows
             if r.get('Result') == 'LOSS')
    pf = (wp / abs(lp)) if lp != 0 else float('inf')
    avg_pips = statistics.mean(to_float(r['Profit_Pips']) for r in rows)
    return {'n': n, 'wr': f'{len(wins) / n * 100:.1f}%',
            'pf': f'{pf:.2f}' if pf != float('inf') else 'inf',
            'avg_pips': f'{avg_pips:+.0f}'}


def fmt_perf(p, n_raw=None):
    raw = f'(生{n_raw}) ' if n_raw is not None else ''
    flag = ' *N<15参考値' if isinstance(p['n'], int) and 0 < p['n'] < 15 else ''
    return (f"N={p['n']} {raw}WR={p['wr']} PF={p['pf']} "
            f"avg={p['avg_pips']}pips{flag}")


def bt_table(rows_dedupe, rows_raw, keyfn, keys=None, title=''):
    """dedupe集合で成績、生集合でN併記"""
    gd = defaultdict(list)
    gr = defaultdict(list)
    for r in rows_dedupe:
        gd[keyfn(r)].append(r)
    for r in rows_raw:
        gr[keyfn(r)].append(r)
    if keys is None:
        keys = sorted(gd.keys(), key=lambda k: -len(gd[k]))
    print(f'\n{title}')
    for k in keys:
        if k not in gd and k not in gr:
            continue
        print(f'  {str(k):<28}: '
              f'{fmt_perf(bt_perf(gd.get(k, [])), len(gr.get(k, [])))}')


# ============================================================
# C. フォワード signal_fires
# ============================================================

def fw_perf(rows):
    n = len(rows)
    if n == 0:
        return {'n': 0, 'mfe_med': '-', 'mae_med': '-', 'mfe_gt_mae': '-'}
    mfe = [to_float(r['mfe_48h']) for r in rows]
    mae = [to_float(r['mae_48h']) for r in rows]
    gt = sum(1 for a, b in zip(mfe, mae) if a > b)
    return {'n': n,
            'mfe_med': f'{statistics.median(mfe):.1f}',
            'mae_med': f'{statistics.median(mae):.1f}',
            'mfe_gt_mae': f'{gt / n * 100:.0f}%'}


def fmt_fw(p):
    flag = ' *N<15参考値' if isinstance(p['n'], int) and 0 < p['n'] < 15 else ''
    return (f"N={p['n']} MFE中央={p['mfe_med']} MAE中央={p['mae_med']} "
            f"MFE>MAE率={p['mfe_gt_mae']}{flag}")


def fw_table(rows, keyfn, keys=None, title=''):
    g = defaultdict(list)
    for r in rows:
        g[keyfn(r)].append(r)
    if keys is None:
        keys = sorted(g.keys(), key=lambda k: -len(g[k]))
    print(f'\n{title}')
    for k in keys:
        if k in g:
            print(f'  {str(k):<28}: {fmt_fw(fw_perf(g[k]))}')


# ============================================================
# main
# ============================================================

def main():
    print('=' * 70)
    print('DXY ADX(56)レジーム × XAUUSDシグナル クロス解析 v1')
    print('=' * 70)

    # ---- A ----
    series = load_dxy()
    dxy_map = build_dxy_map(series)
    print(f'\nDXY系列: {len(series)}本（先頭{WARMUP_DROP}本ウォームアップ除去済）'
          f' {series[0]["t"]} 〜 {series[-1]["t"]}')

    base_full = dxy_base_rates(series, 'A全期間')
    dxy_ratio_dist(series)

    # ---- B ----
    bt_raw = load_csv(BT_CSV)
    bt_dd = dedupe_6h(bt_raw)
    print(f'\n\nBT世代2: 生{len(bt_raw)}件 -> 6h dedupe後 {len(bt_dd)}件')

    # 突合
    miss_raw, miss_dd = 0, 0
    for r in bt_raw:
        d = join_dxy(dxy_map, parse_dt(r['OpenTime']))
        r['_dxy'] = d
        if d is None:
            miss_raw += 1
    for r in bt_dd:
        if r['_dxy'] is None:
            miss_dd += 1
    bt_raw_j = [r for r in bt_raw if r['_dxy']]
    bt_dd_j = [r for r in bt_dd if r['_dxy']]
    print(f'突合除外（DXYバー無し・3h遡り不成立）: 生{miss_raw}件 / dedupe後{miss_dd}件')

    bt_t0 = min(parse_dt(r['OpenTime']) for r in bt_dd_j)
    bt_t1 = max(parse_dt(r['OpenTime']) for r in bt_dd_j)
    base_bt = dxy_base_rates(series, 'BT期間窓', bt_t0, bt_t1)

    # 発火時レジーム分布 vs ベースレート
    n_dd = len(bt_dd_j)
    cb = Counter(r['_dxy']['band'] for r in bt_dd_j)
    cd = Counter(r['_dxy']['di'] for r in bt_dd_j)
    print(f'\n--- BT発火時のDXYレジーム分布 (dedupe後 N={n_dd}) vs ベースレート(BT窓) ---')
    for b in BANDS:
        fire = cb[b] / n_dd * 100
        base = base_bt['band'][b] / base_bt['n'] * 100
        lift = fire / base if base else 0
        print(f'  ADX {b:>6}: 発火{fire:5.1f}% / 滞在{base:5.1f}% / lift {lift:.2f}')
    for d in ['USD_UP', 'USD_DN']:
        fire = cd[d] / n_dd * 100
        base = base_bt['di'][d] / base_bt['n'] * 100
        print(f'  {d}: 発火{fire:5.1f}% / 滞在{base:5.1f}% / lift {fire/base:.2f}')

    # フィルター後集合
    bt_dd_f = [r for r in bt_dd_j if not any_filter_hit(r)]
    print(f'\n9本フィルター通過後: {len(bt_dd_f)}件 '
          f'(除外{len(bt_dd_j) - len(bt_dd_f)}件)')
    print(f'全体成績 dedupe後: {fmt_perf(bt_perf(bt_dd_j), len(bt_raw_j))}')
    print(f'全体成績 フィルター後: {fmt_perf(bt_perf(bt_dd_f))}')

    # ---- レジーム別成績マップ (BT) ----
    print('\n' + '=' * 70)
    print('2. レジーム別成績マップ — BT世代2')
    print('=' * 70)

    bt_table(bt_dd_j, bt_raw_j, lambda r: r['_dxy']['band'], BANDS,
             '[B-1] ADX56帯（フィルター前・dedupe）')
    bt_table(bt_dd_f, bt_dd_f, lambda r: r['_dxy']['band'], BANDS,
             '[B-1f] ADX56帯（9本フィルター通過後）')

    keys_dd = [(d, x) for d in ['USD_UP', 'USD_DN'] for x in ['BUY', 'SELL']]
    bt_table(bt_dd_j, bt_raw_j,
             lambda r: (r['_dxy']['di'], r['Direction']), keys_dd,
             '[B-2] DXY DI方向 × XAU Direction（フィルター前・dedupe）')
    bt_table(bt_dd_f, bt_dd_f,
             lambda r: (r['_dxy']['di'], r['Direction']), keys_dd,
             '[B-2f] 同（9本フィルター通過後）')

    bt_table(bt_dd_j, bt_raw_j,
             lambda r: wind(r['Direction'], r['_dxy']['di']),
             ['TAIL', 'HEAD'],
             '[B-3] 順風(TAIL)/向かい風(HEAD)（フィルター前・dedupe）')
    bt_table(bt_dd_f, bt_dd_f,
             lambda r: wind(r['Direction'], r['_dxy']['di']),
             ['TAIL', 'HEAD'],
             '[B-3f] 同（9本フィルター通過後）')

    keys_bw = [(b, w) for b in BANDS for w in ['TAIL', 'HEAD']]
    bt_table(bt_dd_j, bt_raw_j,
             lambda r: (r['_dxy']['band'], wind(r['Direction'], r['_dxy']['di'])),
             keys_bw,
             '[B-4] ADX56帯 × 順逆（フィルター前・dedupe）')

    # 補助軸: DXY ATR Ratio 3区分
    def dxy_ratio_zone(r):
        v = r['_dxy']['ratio']
        if v <= 0:
            return 'NO_RATIO'
        if v < 0.70:
            return 'LOW'
        if v <= 1.40:
            return 'NORMAL'
        return 'HIGH'
    bt_table(bt_dd_j, bt_raw_j, dxy_ratio_zone,
             ['LOW', 'NORMAL', 'HIGH', 'NO_RATIO'],
             '[B-5] 補助軸: DXY ATR Ratio 3区分（フィルター前・dedupe）')

    # ---- H3: 既知の死亡帯とDXYレジーム ----
    print('\n' + '=' * 70)
    print('3. H3: 既知の死亡帯のDXYレジーム分布')
    print('=' * 70)

    def regime_dist(rows, label):
        n = len(rows)
        print(f'\n[{label}] N={n}' + (' *N<15参考値' if n < 15 else ''))
        if n == 0:
            return
        cb2 = Counter(r['_dxy']['band'] for r in rows)
        cd2 = Counter(r['_dxy']['di'] for r in rows)
        cw2 = Counter(wind(r['Direction'], r['_dxy']['di']) for r in rows)
        print('  ADX帯: ' + '  '.join(f'{b}:{cb2[b]}' for b in BANDS if cb2[b]))
        print('  DI   : ' + '  '.join(f'{d}:{cd2[d]}'
                                      for d in ['USD_UP', 'USD_DN']))
        print('  順逆 : ' + '  '.join(f'{w}:{cw2[w]}'
                                     for w in ['TAIL', 'HEAD']))
        print('  成績 : ' + fmt_perf(bt_perf(rows)))

    none_sell = [r for r in bt_dd_j
                 if r['D1_ATR_Cross_Dir'] == 'NONE' and r['Direction'] == 'SELL']
    regime_dist(none_sell, 'Cross=NONE × SELL（BT死亡帯 PF0.24）')

    nagi = [r for r in bt_dd_j if h4_phase_auto(r) == '凪離脱']
    regime_dist(nagi, '凪離脱（H4 Phase Auto再現 PF0.49帯）')

    patd_sell = [r for r in bt_dd_j
                 if r['Pattern'] == 'PatD' and r['Direction'] == 'SELL']
    regime_dist(patd_sell, 'PatD × SELL（BT側）')

    # ---- パターン別選好 ----
    print('\n' + '=' * 70)
    print('4. Pattern別 DXYレジーム選好（dedupe・2軸まで）')
    print('=' * 70)
    for pat in ['PatA', 'PatB', 'PatC', 'PatD', 'PatE']:
        sub = [r for r in bt_dd_j if r['Pattern'] == pat]
        subr = [r for r in bt_raw_j if r['Pattern'] == pat]
        if not sub:
            continue
        bt_table(sub, subr,
                 lambda r: wind(r['Direction'], r['_dxy']['di']),
                 ['TAIL', 'HEAD'], f'[{pat}] 順逆別 (dedupe N={len(sub)})')

    # ---- 期間半割り頑健性 ----
    print('\n' + '=' * 70)
    print('5. 期間半割り頑健性チェック（2024 vs 2025以降）— 順逆×Direction')
    print('=' * 70)
    split = datetime(2025, 1, 1)
    early = [r for r in bt_dd_j if parse_dt(r['OpenTime']) < split]
    late = [r for r in bt_dd_j if parse_dt(r['OpenTime']) >= split]
    early_r = [r for r in bt_raw_j if parse_dt(r['OpenTime']) < split]
    late_r = [r for r in bt_raw_j if parse_dt(r['OpenTime']) >= split]
    for label, sub, subr in [('2024', early, early_r),
                             ('2025以降', late, late_r)]:
        print(f'\n### {label} (dedupe N={len(sub)})')
        bt_table(sub, subr,
                 lambda r: wind(r['Direction'], r['_dxy']['di']),
                 ['TAIL', 'HEAD'], '順逆')
        bt_table(sub, subr,
                 lambda r: (wind(r['Direction'], r['_dxy']['di']),
                            r['Direction']),
                 [(w, d) for w in ['TAIL', 'HEAD'] for d in ['BUY', 'SELL']],
                 '順逆 × Direction')

    # ---- C. フォワード ----
    print('\n' + '=' * 70)
    print('6. フォワード signal_fires（MFE/MAE 48h評価）')
    print('=' * 70)
    fw = load_csv(FW_CSV)
    fw_miss = 0
    for r in fw:
        d = join_dxy(dxy_map, parse_dt(r['time_server']))
        r['_dxy'] = d
        r['Direction'] = r.get('direction', '')
        if d is None:
            fw_miss += 1
    fw_j = [r for r in fw if r['_dxy'] and to_float(r.get('bars_traced')) > 0]
    dropped_trace = len(fw) - fw_miss - len(fw_j)
    print(f'\nFW: {len(fw)}件 -> 突合除外{fw_miss}件, '
          f'追跡0本除外{dropped_trace}件 -> 有効{len(fw_j)}件')
    fw_t0 = min(parse_dt(r['time_server']) for r in fw_j)
    fw_t1 = max(parse_dt(r['time_server']) for r in fw_j)
    dxy_base_rates(series, 'FW期間窓', fw_t0, fw_t1)

    nfw = len(fw_j)
    cb3 = Counter(r['_dxy']['band'] for r in fw_j)
    print(f'\n--- FW発火時のADX56帯分布 (N={nfw}) ---')
    print('  ' + '  '.join(f'{b}:{pct(cb3[b], nfw)}' for b in BANDS))

    fw_table(fw_j, lambda r: r['_dxy']['band'], BANDS,
             '[C-1] ADX56帯（全FW）')
    fw_table(fw_j, lambda r: (r['_dxy']['di'], r['Direction']), keys_dd,
             '[C-2] DXY DI × XAU Direction（全FW）')
    fw_table(fw_j, lambda r: wind(r['Direction'], r['_dxy']['di']),
             ['TAIL', 'HEAD'], '[C-3] 順逆（全FW）')

    fw_pass = [r for r in fw_j if r.get('pass_all') == 'TRUE']
    fw_fail = [r for r in fw_j if r.get('pass_all') != 'TRUE']
    print(f'\npass_all=TRUE: {len(fw_pass)}件 / FALSE: {len(fw_fail)}件')
    fw_table(fw_pass, lambda r: wind(r['Direction'], r['_dxy']['di']),
             ['TAIL', 'HEAD'], '[C-3p] 順逆（pass_all=TRUEのみ）')
    fw_table(fw_pass, lambda r: r['_dxy']['band'], BANDS,
             '[C-1p] ADX56帯（pass_all=TRUEのみ）')

    # H3 FW側: PatD SELL
    patd_fw = [r for r in fw_j
               if r.get('pattern') == 'PatD' and r['Direction'] == 'SELL'
               and r.get('pass_all') == 'TRUE']
    print(f'\n[H3-FW] PatD×SELL×pass_all (フォワード犯人 0/11): N={len(patd_fw)}')
    for r in patd_fw:
        d = r['_dxy']
        w = wind('SELL', d['di'])
        print(f"  {r['time_server']}  ADX{d['adx']:.1f}({d['band']}) "
              f"{d['di']} {w}  mfe48={r['mfe_48h']} mae48={r['mae_48h']}")

    # ADX<20 (H2) FW側
    fw_table(fw_j, lambda r: ('ADX<20' if r['_dxy']['band'] == '<20'
                              else 'ADX>=20'),
             ['ADX<20', 'ADX>=20'], '[H2-FW] 拮抗帯 vs それ以外（全FW）')


if __name__ == '__main__':
    main()
