#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DXY DI拮抗度（スプレッド深さ） × XAUUSDシグナル精度 v2
v1（カイ）の突合・dedupe・成績機構を再利用して物差しを揃える。

問い: USD_UP×BUY最強（v1発見）は、DI優勢の「深さ」に対して単調か？
      USD_DN×SELL最弱は、浅い拮抗で死ぬのか深い一方通行で死ぬのか？

深さ段階（実測分布から・D1環境札と同じ意味論／DXY ADX56スケール）:
  拮抗<2 / 揺らぎ2-5 / 優勢5-10 / 一方通行>=10
"""
import statistics
from collections import defaultdict
from datetime import datetime

import analyze_dxy_x_signals_v1 as v1

DEPTH_KEYS = ['拮抗<2', '揺らぎ2-5', '優勢5-10', '一方通行>=10']


def depth_band(spread_abs):
    if spread_abs < 2:
        return '拮抗<2'
    if spread_abs < 5:
        return '揺らぎ2-5'
    if spread_abs < 10:
        return '優勢5-10'
    return '一方通行>=10'


def load_dxy_with_depth():
    rows = v1.load_csv(v1.DXY_CSV)[v1.WARMUP_DROP:]
    series = {}
    for r in rows:
        t = v1.parse_dt(r['Time'])
        if t is None:
            continue
        dip = v1.to_float(r['DI_Plus'])
        dim = v1.to_float(r['DI_Minus'])
        s = dip - dim
        series[t] = {
            't': t,
            'di': 'USD_UP' if s > 0 else 'USD_DN',
            'depth': depth_band(abs(s)),
            'spread': s,
        }
    return series


def main():
    dxy = load_dxy_with_depth()

    # --- ベースレート ---
    n = len(dxy)
    print(f'=== DXY DI深さ ベースレート (N={n}) ===')
    cnt = defaultdict(int)
    for s in dxy.values():
        cnt[(s['di'], s['depth'])] += 1
        cnt[('*', s['depth'])] += 1
    print('深さ滞在率  : ' + '  '.join(
        f'{d}:{v1.pct(cnt[("*", d)], n)}' for d in DEPTH_KEYS))
    for di in ('USD_UP', 'USD_DN'):
        print(f'  {di}: ' + '  '.join(
            f'{d}:{v1.pct(cnt[(di, d)], n)}' for d in DEPTH_KEYS))

    # --- BT 読み込み・突合（v1と同一機構）---
    bt_raw_all = v1.load_csv(v1.BT_CSV)
    bt_dd_all = v1.dedupe_6h(bt_raw_all)

    def attach(rows):
        out = []
        for r in rows:
            hit = v1.join_dxy(dxy, v1.parse_dt(r['OpenTime']))
            if hit:
                r = dict(r)
                r['_di'] = hit['di']
                r['_depth'] = hit['depth']
                out.append(r)
        return out

    bt_raw = attach(bt_raw_all)
    bt_dd = attach(bt_dd_all)
    print(f'\nBT突合: 生 {len(bt_raw)}/{len(bt_raw_all)}  '
          f'dedupe {len(bt_dd)}/{len(bt_dd_all)}')

    def key_di_depth(r):
        return f"{r['_di']} {r['_depth']}"

    keys_all = [f'{di} {d}' for di in ('USD_UP', 'USD_DN')
                for d in DEPTH_KEYS]

    for xdir in ('BUY', 'SELL'):
        v1.bt_table([r for r in bt_dd if r['Direction'] == xdir],
                    [r for r in bt_raw if r['Direction'] == xdir],
                    key_di_depth, keys_all,
                    f'=== [BT] XAU {xdir} × DXY DI方向×深さ ===')

    # フィルター通過相当（v4 9本を再現・v1と同一）
    bt_dd_pass = [r for r in bt_dd if not v1.any_filter_hit(r)]
    bt_raw_pass = [r for r in bt_raw if not v1.any_filter_hit(r)]
    for xdir in ('BUY', 'SELL'):
        v1.bt_table([r for r in bt_dd_pass if r['Direction'] == xdir],
                    [r for r in bt_raw_pass if r['Direction'] == xdir],
                    key_di_depth, keys_all,
                    f'=== [BT/フィルター通過] XAU {xdir} × DI方向×深さ ===')

    # --- 頑健性: BUY×USD_UP の深さ勾配を期間半割り ---
    print('\n=== 頑健性チェック: BUY×USD_UP 深さ勾配（期間半割り）===')
    half = datetime(2025, 1, 1)
    for label, cond in (('2024', lambda t: t < half),
                        ('2025+', lambda t: t >= half)):
        sub_dd = [r for r in bt_dd
                  if r['Direction'] == 'BUY' and r['_di'] == 'USD_UP'
                  and cond(v1.parse_dt(r['OpenTime']))]
        sub_raw = [r for r in bt_raw
                   if r['Direction'] == 'BUY' and r['_di'] == 'USD_UP'
                   and cond(v1.parse_dt(r['OpenTime']))]
        v1.bt_table(sub_dd, sub_raw, lambda r: r['_depth'], DEPTH_KEYS,
                    f'--- {label} ---')

    # --- FW signal_fires ---
    fw_all = v1.load_csv(v1.FW_CSV)
    fw = []
    for r in fw_all:
        hit = v1.join_dxy(dxy, v1.parse_dt(r['time_server']))
        if hit:
            r = dict(r)
            r['_di'] = hit['di']
            r['_depth'] = hit['depth']
            fw.append(r)
    print(f'\nFW突合: {len(fw)}/{len(fw_all)}')

    for xdir in ('BUY', 'SELL'):
        v1.fw_table([r for r in fw if r['direction'] == xdir],
                    key_di_depth, keys_all,
                    f'=== [FW] XAU {xdir} × DXY DI方向×深さ ===')

    fw_pass = [r for r in fw if r.get('pass_all') == 'TRUE']
    for xdir in ('BUY', 'SELL'):
        v1.fw_table([r for r in fw_pass if r['direction'] == xdir],
                    key_di_depth, keys_all,
                    f'=== [FW/pass_all] XAU {xdir} × DI方向×深さ ===')


if __name__ == '__main__':
    main()
