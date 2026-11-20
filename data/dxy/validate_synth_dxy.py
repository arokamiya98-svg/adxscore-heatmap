#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
合成DXY（Exness FX5ペア, SEK除外）vs HFM USDIndex の ADX(56)/DIスプレッド物差し検証
  指示書: data/scriptable/コー_impl_dxy_card_v3_synth.md §3.2
  親SPEC: data/scriptable/SPEC_dxy_env_card_v1.md（深さラベル <2/2-5/5-10/>=10, 小数1桁丸め後判定）

  1. 両CSV（UTF-16）読込
  2. 時刻オフセット検出: ISO週ごとに HFM(サーバー時刻) − Exness(GMT+0) のオフセット 0..4h を
     Close 1h 変化率の相関最大で決定（validate_yahoo_dxy.py のオフセット検出を変化率相関へ拡張）
     → EU DST 規則（最終日曜切替）と照合
  3. H1確定バー単位で spread 相関/平均絶対差、深さラベル一致率＋混同行列、di_dir一致率、
     滞在率、ADX56相関/平均差、Close変化率相関 を 全体/年別/半年別 に出力
  4. D1単位（JST日付の最終確定バー＝dxy_env.csv 方式）のラベル一致率
  5. 合成側の滞在率保存分位点による閾値再提案（ラベル一致不足時の参考）
"""
import csv
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timedelta

BASE = "/Users/aro/Desktop/ADXSCORE/data/dxy/"
HFM_CSV = BASE + "DXY_ADX_Timeseries_v1.csv"
SYN_CSV = BASE + "DXY_Synth_Timeseries_v1.csv"
ORDER = ["拮抗", "揺らぎ", "優勢", "一方通行"]
TH = (2.0, 5.0, 10.0)


def load(path):
    d = {}
    with open(path, encoding="utf-16") as f:
        for r in csv.DictReader(f):
            t = datetime.strptime(r["Time"], "%Y.%m.%d %H:%M")
            dip, dim = float(r["DI_Plus"]), float(r["DI_Minus"])
            d[t] = {"close": float(r["Close"]), "adx": float(r["ADX"]),
                    "dip": dip, "dim": dim, "spread": dip - dim}
    return d


def depth(sp, th=TH):
    a = abs(round(sp, 1))
    return ORDER[0] if a < th[0] else ORDER[1] if a < th[1] else ORDER[2] if a < th[2] else ORDER[3]


def di_dir(sp):  # EA と同規約: spread>0 → USD_UP / それ以外 USD_DN
    return "UP" if sp > 0 else "DN"


def corr(a, b):
    if len(a) < 3:
        return float("nan")
    ma, mb = statistics.mean(a), statistics.mean(b)
    c = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    va = sum((x - ma) ** 2 for x in a)
    vb = sum((y - mb) ** 2 for y in b)
    return c / (va * vb) ** 0.5 if va > 0 and vb > 0 else float("nan")


def rets(d):
    ks = sorted(d)
    return {b: d[b]["close"] / d[a]["close"] - 1
            for a, b in zip(ks, ks[1:]) if b - a == timedelta(hours=1)}


def last_sunday(y, m):
    nxt = datetime(y + (m == 12), m % 12 + 1, 1)
    d = nxt - timedelta(days=1)
    return d - timedelta(days=(d.weekday() + 1) % 7)


def eu_rule_offset(t_utc):
    """EET/EEST: 夏時間(最終日曜Mar 01:00UTC〜最終日曜Oct 01:00UTC)=+3, それ以外=+2"""
    y = t_utc.year
    s = last_sunday(y, 3) + timedelta(hours=1)
    e = last_sunday(y, 10) + timedelta(hours=1)
    return 3 if s <= t_utc < e else 2


def detect_offsets(hfm, syn):
    hr, sr = rets(hfm), rets(syn)
    wk = defaultdict(list)
    for t in hr:
        wk[t.isocalendar()[:2]].append(t)
    out = {}
    for k in sorted(wk):
        best = None
        for off in range(0, 5):
            a, b = [], []
            for t in wk[k]:
                u = t - timedelta(hours=off)
                if u in sr:
                    a.append(hr[t]); b.append(sr[u])
            if len(a) >= 30:
                c = corr(a, b)
                if best is None or c > best[1]:
                    best = (off, c, len(a))
        out[k] = best
    return out, hr, sr


def summarize(pairs, hr_pairs, label):
    sp_h = [p[1]["spread"] for p in pairs]
    sp_s = [p[2]["spread"] for p in pairs]
    ad_h = [p[1]["adx"] for p in pairs]
    ad_s = [p[2]["adx"] for p in pairs]
    n = len(pairs)
    lab_h = [depth(x) for x in sp_h]
    lab_s = [depth(x) for x in sp_s]
    m_lab = sum(a == b for a, b in zip(lab_h, lab_s))
    m_dir = sum(di_dir(a) == di_dir(b) for a, b in zip(sp_h, sp_s))
    adj = sum(1 for a, b in zip(lab_h, lab_s) if a != b and abs(ORDER.index(a) - ORDER.index(b)) == 1)
    return {
        "label": label, "n": n,
        "sp_corr": corr(sp_h, sp_s),
        "sp_mad": statistics.mean(abs(a - b) for a, b in zip(sp_h, sp_s)),
        "sp_absratio": statistics.mean(abs(b) for b in sp_s) / statistics.mean(abs(a) for a in sp_h),
        "lab": m_lab / n, "adj": adj, "miss": n - m_lab,
        "dir": m_dir / n,
        "adx_corr": corr(ad_h, ad_s),
        "adx_diff": statistics.mean(b - a for a, b in zip(ad_h, ad_s)),
        "adx_mad": statistics.mean(abs(b - a) for a, b in zip(ad_h, ad_s)),
        "ret_corr": corr([x[0] for x in hr_pairs], [x[1] for x in hr_pairs]) if hr_pairs else float("nan"),
        "stay_h": Counter(lab_h), "stay_s": Counter(lab_s),
        "conf": Counter(zip(lab_h, lab_s)),
    }


def fmt_row(r):
    return (f"| {r['label']} | {r['n']} | {r['ret_corr']:.3f} | {r['sp_corr']:.3f} | {r['sp_mad']:.2f} | "
            f"{r['lab']*100:.1f}% | {r['dir']*100:.1f}% | {r['adx_corr']:.3f} | {r['adx_diff']:+.2f} |")


def main():
    hfm, syn = load(HFM_CSV), load(SYN_CSV)
    print(f"HFM rows={len(hfm)} {min(hfm)}〜{max(hfm)} / SYN rows={len(syn)} {min(syn)}〜{max(syn)}")

    # --- 2. オフセット検出 ---
    offs, hr, sr = detect_offsets(hfm, syn)
    mism = 0
    print("\n## 週別オフセット（切替点と低相関週のみ表示）")
    prev = None
    for k, b in offs.items():
        if b is None:
            continue
        monday = datetime.fromisocalendar(k[0], k[1], 3)  # 水曜で代表
        rule = eu_rule_offset(monday)
        if b[0] != rule:
            mism += 1
        if b[0] != prev or b[1] < 0.95:
            print(f"  {k} best=+{b[0]}h corr={b[1]:.3f} N={b[2]} EUrule=+{rule}")
        prev = b[0]
    print(f"  EU DST規則との不一致週: {mism}/{sum(1 for b in offs.values() if b)}")

    def to_utc(t_srv):
        # サーバー時刻→UTC。EU規則で +2/+3（切替はUTC 01:00 だがサーバー時刻差は高々1h、境界は週末のため影響なし）
        u = t_srv - timedelta(hours=2)
        return t_srv - timedelta(hours=eu_rule_offset(u))

    # --- 3. H1 突合 ---
    pairs = []
    for t, hv in sorted(hfm.items()):
        u = to_utc(t)
        if u in syn:
            pairs.append((u, hv, syn[u]))
    ret_pairs = [(u, hr[t], sr[u]) for t in hr for u in [to_utc(t)] if u in sr]
    print(f"\n突合H1バー: {len(pairs)} / HFM {len(hfm)}  (変化率ペア {len(ret_pairs)})")

    groups = {"全体": (lambda u: True)}
    for y in (2024, 2025, 2026):
        groups[f"{y}"] = (lambda u, y=y: u.year == y)
    for y in (2024, 2025, 2026):
        for hh in (1, 2):
            groups[f"{y}H{hh}"] = (lambda u, y=y, hh=hh: u.year == y and (u.month <= 6) == (hh == 1))
    results = []
    for g, f in groups.items():
        p = [x for x in pairs if f(x[0])]
        rp = [(a, b) for (u, a, b) in ret_pairs if f(u)]
        if len(p) > 50:
            results.append(summarize(p, rp, g))

    print("\n| 区間 | N | Close変化率相関 | spread相関 | |spread差| | 深さ一致 | di_dir一致 | ADX相関 | ADX差(合成−HFM) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in results:
        print(fmt_row(r))

    tot = results[0]
    print(f"\n合成|spread|/HFM|spread| 平均比 = {tot['sp_absratio']:.3f}")
    print(f"ADX 平均絶対差 = {tot['adx_mad']:.2f}")
    print(f"ラベル不一致 {tot['miss']} 中 隣接帯ズレ {tot['adj']}")

    print("\n## 滞在率（全体）")
    for lab in ORDER:
        print(f"  {lab}: HFM {tot['stay_h'][lab]/tot['n']*100:.1f}%  合成 {tot['stay_s'][lab]/tot['n']*100:.1f}%")

    print("\n## 混同行列（行=HFM, 列=合成, 行内%）")
    print("| HFM＼合成 | " + " | ".join(ORDER) + " | 行N | 一致率 |")
    print("|---|---|---|---|---|---|---|")
    for a in ORDER:
        rn = sum(tot["conf"][(a, b)] for b in ORDER)
        cells = " | ".join(f"{tot['conf'][(a,b)]/rn*100:.1f}%" for b in ORDER)
        print(f"| {a} | {cells} | {rn} | {tot['conf'][(a,a)]/rn*100:.1f}% |")

    # di_dir 不一致の |spread| 帯
    dmis = Counter(depth(h["spread"]) for _, h, s in pairs if di_dir(h["spread"]) != di_dir(s["spread"]))
    print("\n## di_dir不一致の HFM深さ帯内訳: " + ", ".join(f"{k}:{dmis[k]}" for k in ORDER))

    # 回帰（合成spread ≈ a*HFM + b）
    xs = [h["spread"] for _, h, s in pairs]; ys = [s["spread"] for _, h, s in pairs]
    mx, my = statistics.mean(xs), statistics.mean(ys)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    print(f"\n回帰: 合成spread = {slope:.3f} × HFM + {my - slope*mx:+.3f}")

    # --- 5. 滞在率保存分位点（合成側の閾値再提案） ---
    abs_h = sorted(abs(round(x, 1)) for x in xs)
    abs_s = sorted(abs(round(y, 1)) for y in ys)
    cum = []
    acc = 0
    for lab in ORDER[:-1]:
        acc += tot["stay_h"][lab] / tot["n"]
        cum.append(acc)
    q = lambda arr, p: arr[min(len(arr) - 1, int(p * len(arr)))]
    th_s = tuple(round(q(abs_s, c), 1) for c in cum)
    m2 = sum(depth(x) == depth(y, th_s) for x, y in zip(xs, ys))
    print(f"\n## 滞在率保存分位点: HFM累積 {[round(c,3) for c in cum]} → 合成閾値 {th_s} "
          f"(HFM側同分位 {tuple(round(q(abs_h,c),1) for c in cum)})")
    print(f"  再閾値でのH1ラベル一致率: {m2/len(xs)*100:.1f}%（元 {tot['lab']*100:.1f}%）")

    # --- 4. D1単位（JST日付の最終確定バー） ---
    def d1(series_utc):
        last = {}
        for u in sorted(series_utc):
            last[(u + timedelta(hours=9)).date()] = series_utc[u]
        return last
    hfm_utc = {to_utc(t): v for t, v in hfm.items()}
    syn_ov = {u: v for u, v in syn.items() if min(hfm_utc) - timedelta(hours=1) <= u <= max(hfm_utc)}
    dh, ds = d1(hfm_utc), d1(syn_ov)
    days = sorted(set(dh) & set(ds))
    for nm, dd in (("全JST日", days), ("土曜除外(営業日)", [d for d in days if d.weekday() < 5])):
        lm = sum(depth(dh[d]["spread"]) == depth(ds[d]["spread"]) for d in dd)
        dm = sum(di_dir(dh[d]["spread"]) == di_dir(ds[d]["spread"]) for d in dd)
        spc = corr([dh[d]["spread"] for d in dd], [ds[d]["spread"] for d in dd])
        lm2 = sum(depth(dh[d]["spread"]) == depth(ds[d]["spread"], th_s) for d in dd)
        print(f"\n## D1({nm}) N={len(dd)}: 深さ一致 {lm/len(dd)*100:.1f}% / di_dir一致 {dm/len(dd)*100:.1f}% "
              f"/ spread相関 {spc:.3f} / 再閾値時 深さ一致 {lm2/len(dd)*100:.1f}%")
    only_s = [d for d in ds if d not in dh and d >= min(dh)]
    print(f"  合成のみ存在するJST日(重なり期間内): {len(only_s)}  曜日内訳 {Counter(d.weekday() for d in only_s)}")

    # --- 6. 原因切り分け（追加診断） ---
    import random
    hfm_by_utc = {to_utc(t): (t, x) for t, x in hfm.items()}
    ks = sorted(u for u in hfm_by_utc if u in syn)
    # 6a. 時間ラグ: ずらすと悪化するなら位相ズレではない
    print("\n## 6a. ラグ別（合成を +lag h ずらす）: lag / spread相関 / |差| / 深さ一致")
    for lag in (-3, -1, 0, 1, 3):
        a, b = [], []
        for u in ks:
            w = u + timedelta(hours=lag)
            if w in syn:
                a.append(hfm_by_utc[u][1]["spread"]); b.append(syn[w]["spread"])
        lm = sum(depth(x) == depth(y) for x, y in zip(a, b)) / len(a)
        print(f"  {lag:+d}h  {corr(a,b):.3f}  {statistics.mean(abs(x-y) for x,y in zip(a,b)):.2f}  {lm*100:.1f}%")
    # 6b. HFMサーバー時刻別: 差の1h変化量と|差|水準（日次セッション切れ目の影響）
    print("\n## 6b. HFMサーバー時刻別: |Δ差|(1h) / |差|水準 / N")
    byh, lvl, prev = defaultdict(list), defaultdict(list), None
    for u in ks:
        t, x = hfm_by_utc[u]
        d = syn[u]["spread"] - x["spread"]
        lvl[t.hour].append(abs(d))
        if prev is not None and u - prev[0] <= timedelta(hours=4):
            byh[t.hour].append(abs(d - prev[1]))
        prev = (u, d)
    for hh in sorted(lvl):
        print(f"  {hh:02d}h  {statistics.mean(byh[hh]) if byh[hh] else float('nan'):.3f}  "
              f"{statistics.mean(lvl[hh]):.2f}  {len(lvl[hh])}")
    blk = defaultdict(lambda: [0, 0])
    for u in ks:
        t, x = hfm_by_utc[u]
        k = "02-05" if t.hour <= 5 else "06-11" if t.hour < 12 else "12-17" if t.hour < 18 else "18-23"
        blk[k][0] += depth(x["spread"]) == depth(syn[u]["spread"]); blk[k][1] += 1
    print("  深さ一致 時間帯別: " + ", ".join(f"{k}:{v[0]/v[1]*100:.1f}%" for k, v in sorted(blk.items())))
    # 6c. di_dir一致（HFM拮抗帯＝方向非表示を除外）
    nd = [(x, syn[u]["spread"]) for u in ks for x in [hfm_by_utc[u][1]["spread"]] if depth(x) != ORDER[0]]
    print(f"\n## 6c. di_dir一致（HFM非拮抗のみ）: {sum(di_dir(a)==di_dir(b) for a,b in nd)/len(nd)*100:.1f}% N={len(nd)}")
    # 6d. 一致率の天井: 実際の差系列を循環シフトして HFM に足す / iidガウスでMAD別
    random.seed(1)
    diffs = [syn[u]["spread"] - hfm_by_utc[u][1]["spread"] for u in ks]
    xs2 = [hfm_by_utc[u][1]["spread"] for u in ks]
    sh = []
    for _ in range(5):
        o = random.randint(1000, len(diffs) - 1000)
        dd = diffs[o:] + diffs[:o]
        sh.append(sum(depth(x) == depth(x + e) for x, e in zip(xs2, dd)) / len(xs2) * 100)
    print("\n## 6d. 一致率の天井（同じ大きさの誤差を無相関に足した場合）")
    print("  実差系列シフト: " + ", ".join(f"{r:.1f}%" for r in sh))
    for mad in (0.5, 1.0, 1.6):
        r = sum(depth(x) == depth(x + random.gauss(0, mad * 1.2533)) for x in xs2) / len(xs2)
        print(f"  iidノイズ MAD={mad}: {r*100:.1f}%")


if __name__ == "__main__":
    main()
