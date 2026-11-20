#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
合成DXY検証 v2: 「環境把握」軸での再評価（D1単位）
  前編: validate_synth_dxy.py（H1突合・EU DSTオフセット確定）
  目的: DXY札＝相場の環境把握（今のGOLDの動きはドル要因か / 一時的か長期化か）
        → H1の4段ラベル一致ではなく、D1の「読み」が HFM と合成で同じになるかを見る

  D1定義: dxy_env.csv 方式＝JST日付ごとの最終確定H1バー（JST 23:00開始足）。土日(JST)除外。
  HFM正解: 〜2026-07-14 は DXY_ADX_Timeseries_v1.csv から再構成、
           2026-07-15〜 は mt5_data/daily/dxy_env.csv の git 履歴（各日付の最新・非当日行の値）
  合成   : DXY_Synth_Timeseries_v1.csv（UTC）

  1. 方向(di_dir) D1一致・方向レジームの区間/転換日/チャタリング
  2. 流れ有無(|spread|>=5) 2値・方向×流れ 3状態
  3. 流れ区間の長さ分布・「長期化」読み（経過日数段階）の一致
  4. 死に帯（analyze_dxy_di_depth_v2.py）の合成spreadでの再現
  5. 直近 2026-07-15〜11-12 の D1札並び
"""
import csv
import io
import json
import os
import statistics
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_synth_dxy as v  # noqa: E402  load / depth / eu_rule_offset / corr

REPO = "/Users/aro/Desktop/ADXSCORE"
ENV_PATH = "mt5_data/daily/dxy_env.csv"
CUT = date(2026, 7, 14)          # Timeseries 側の最終日
RECENT = (date(2026, 7, 15), date(2026, 11, 12))
FLOW_TH = 5.0
CACHE = os.environ.get("DXY_ENV_CACHE")  # 任意: git履歴キャッシュ(json)


# ---------------------------------------------------------------- 入力
def to_utc(t_srv):
    u = t_srv - timedelta(hours=2)
    return t_srv - timedelta(hours=v.eu_rule_offset(u))


def d1_last(series_utc):
    last = {}
    for u in sorted(series_utc):
        last[(u + timedelta(hours=9)).date()] = series_utc[u]["spread"]
    return last


def env_history():
    """dxy_env.csv 全git版 → 日付ごとに『最新の非当日行』の spread（無ければ最新の当日行）"""
    if CACHE and os.path.exists(CACHE):
        hist = json.load(open(CACHE))
    else:
        log = subprocess.run(["git", "-C", REPO, "log", "--format=%h %cI", "--", ENV_PATH],
                             capture_output=True, text=True).stdout.split()
        hist = []
        for h, ts in zip(log[::2], log[1::2]):
            t = subprocess.run(["git", "-C", REPO, "show", f"{h}:{ENV_PATH}"],
                               capture_output=True).stdout.decode("utf-8-sig", "replace")
            hist.append((h, ts, t))
    best = {}  # date -> (prio, ts, spread)  prio 1=非当日行
    for h, ts, t in hist:
        rows = list(csv.DictReader(io.StringIO(t.lstrip("﻿"))))
        for i, r in enumerate(rows):
            k = (1 if i < len(rows) - 1 else 0, ts)
            d = date.fromisoformat(r["date"])
            if d not in best or k > best[d][0]:
                best[d] = (k, float(r["dxy_di_spread"]))
    return {d: x[1] for d, x in best.items()}


# ---------------------------------------------------------------- ラベル
def r1(x):
    return round(x, 1)


def ddir(s):
    return "UP" if s > 0 else "DN"


def flow(s):
    return abs(r1(s)) >= FLOW_TH


def st3(s):
    return ("UP流" if s > 0 else "DN流") if flow(s) else "無"


def depth4(s):
    return v.depth(s)


def runs(seq):
    """[(value, start_idx, length)]"""
    out = []
    for i, x in enumerate(seq):
        if out and out[-1][0] == x:
            out[-1][2] += 1
        else:
            out.append([x, i, 1])
    return [tuple(r) for r in out]


def transitions(seq, min_after=1):
    """転換 index と新方向。min_after: 転換後の区間が何日以上続いたものだけ数えるか"""
    rs = runs(seq)
    return [(s, x) for (x, s, n) in rs[1:] if n >= min_after]


def match_transitions(th, ts, win=5):
    """同じ新方向の転換を ±win 営業日で最近傍1対1マッチ。戻り: offsets(合成−HFM), 未対応HFM, 未対応合成"""
    cand = sorted(((abs(j - i), i, j) for i, xi in th for j, xj in ts
                   if xi == xj and abs(j - i) <= win))
    uh, us, offs = set(), set(), []
    for _, i, j in cand:
        if i in uh or j in us:
            continue
        uh.add(i); us.add(j); offs.append(j - i)
    return offs, len(th) - len(uh), len(ts) - len(us)


def pctl(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(p * len(a)))] if a else float("nan")


def pct(x, n):
    return f"{x / n * 100:.1f}%" if n else "-"


# ---------------------------------------------------------------- 本体
def main():
    hfm = v.load(v.HFM_CSV)
    syn = v.load(v.SYN_CSV)
    hfm_utc = {to_utc(t): x for t, x in hfm.items()}
    dh_ts = d1_last(hfm_utc)
    ds_all = d1_last(syn)
    env = env_history()

    # 先頭200本ウォームアップ相当（約2週）を捨てる
    start = date(2024, 1, 15)
    # HFM正解 D1 = Timeseries(〜07-14) + dxy_env(07-15〜)
    dh = {d: s for d, s in dh_ts.items() if start <= d <= CUT}
    for d, s in env.items():
        if d > CUT:
            dh[d] = s
    days = sorted(d for d in dh if d in ds_all and d.weekday() < 5)
    H = [dh[d] for d in days]
    S = [ds_all[d] for d in days]
    N = len(days)
    print(f"D1営業日 N={N}  {days[0]}〜{days[-1]}  (Timeseries由来 {sum(d<=CUT for d in days)} / dxy_env由来 {sum(d>CUT for d in days)})")

    # 0. dxy_env と Timeseries 再構成の整合（重なり期間）
    ov = sorted(d for d in env if d <= CUT and d in dh_ts and d.weekday() < 5)
    if ov:
        diffs = [abs(env[d] - dh_ts[d]) for d in ov]
        print(f"[整合] dxy_env vs Timeseries再構成 重なり{len(ov)}日 ({ov[0]}〜{ov[-1]}): "
              f"|spread差| 中央 {statistics.median(diffs):.2f} 平均 {statistics.mean(diffs):.2f} / "
              f"方向一致 {pct(sum(ddir(env[d])==ddir(dh_ts[d]) for d in ov), len(ov))} / "
              f"流れ有無一致 {pct(sum(flow(env[d])==flow(dh_ts[d]) for d in ov), len(ov))}")

    segs = {"全期間": lambda d: True,
            "2024": lambda d: d.year == 2024, "2025": lambda d: d.year == 2025,
            "2026(〜7/14)": lambda d: d.year == 2026 and d <= CUT,
            "直近(7/15〜)": lambda d: d > CUT}

    # 1. 方向
    print("\n## 1. 方向 / 2. 流れ有無 / 3状態 / 4段 D1一致率")
    print("| 区間 | N | 方向 | 流れ有無(2値) | 方向×流れ(3状態) | 4段ラベル(参考) | spread相関 |")
    print("|---|---|---|---|---|---|---|")
    for nm, f in segs.items():
        ix = [i for i, d in enumerate(days) if f(d)]
        n = len(ix)
        print(f"| {nm} | {n} | {pct(sum(ddir(H[i])==ddir(S[i]) for i in ix), n)} | "
              f"{pct(sum(flow(H[i])==flow(S[i]) for i in ix), n)} | "
              f"{pct(sum(st3(H[i])==st3(S[i]) for i in ix), n)} | "
              f"{pct(sum(depth4(H[i])==depth4(S[i]) for i in ix), n)} | "
              f"{v.corr([H[i] for i in ix], [S[i] for i in ix]):.3f} |")
    # 方向不一致の内訳（HFM 4段帯）
    dm = Counter(depth4(h) for h, s in zip(H, S) if ddir(h) != ddir(s))
    print("方向不一致の HFM帯内訳: " + ", ".join(f"{k}:{dm[k]}" for k in v.ORDER))
    nz = [(h, s) for h, s in zip(H, S) if depth4(h) != "拮抗"]
    print(f"方向一致（HFM拮抗日を除く・札が方向を出す日）: {pct(sum(ddir(a)==ddir(b) for a,b in nz), len(nz))} N={len(nz)}")
    nf = [(h, s) for h, s in zip(H, S) if flow(h)]
    print(f"方向一致（HFM流れ有り日のみ）: {pct(sum(ddir(a)==ddir(b) for a,b in nf), len(nf))} N={len(nf)}")

    # 1b. 方向レジームの区間と転換
    dH, dS = [ddir(x) for x in H], [ddir(x) for x in S]
    for lab, seqH, seqS in (("方向(UP/DN)", dH, dS),):
        rH, rS = runs(seqH), runs(seqS)
        print(f"\n## 1b. {lab} 区間")
        for nm, rr in (("HFM", rH), ("合成", rS)):
            L = [n for _, _, n in rr]
            short = [n for _, _, n in rr[1:-1] if n <= 2]
            print(f"  {nm}: 区間数 {len(rr)} / 長さ 中央 {statistics.median(L)} 平均 {statistics.mean(L):.1f} p75 {pctl(L,.75)} 最大 {max(L)} / "
                  f"1〜2日の挟まり区間(チャタリング) {len(short)}（1日 {short.count(1)} / 2日 {short.count(2)}）")
        for ma in (1, 3):
            th, ts = transitions(seqH, ma), transitions(seqS, ma)
            offs, mh, ms = match_transitions(th, ts)
            ao = [abs(o) for o in offs]
            dist = Counter(offs)
            print(f"  転換（転換後{ma}日以上続いたもの）: HFM {len(th)} / 合成 {len(ts)} / 対応 {len(offs)} "
                  f"（未対応HFM {mh} / 合成の余計な転換 {ms}）")
            if offs:
                print(f"    ズレ(合成−HFM, 営業日) 中央|ズレ| {statistics.median(ao)} / 0日 {pct(ao.count(0),len(ao))} / "
                      f"≤1日 {pct(sum(a<=1 for a in ao),len(ao))} / ≤2日 {pct(sum(a<=2 for a in ao),len(ao))} / "
                      f"分布 {dict(sorted(dist.items()))}")
        # 区間単位の再現
        print("  HFM区間の再現（区間内で合成が同方向の日の割合）:")
        print("  | HFM区間長 | 区間数 | 被覆率平均 | 被覆≥80% | 被覆≥50% |")
        print("  |---|---|---|---|---|")
        for lo, hi, nm in ((1, 2, "1-2日"), (3, 5, "3-5日"), (6, 10, "6-10日"), (11, 999, "11日+"), (3, 999, "3日+計")):
            cov = [sum(seqS[k] == x for k in range(s, s + n)) / n for x, s, n in rH if lo <= n <= hi]
            if cov:
                print(f"  | {nm} | {len(cov)} | {statistics.mean(cov)*100:.0f}% | "
                      f"{pct(sum(c>=.8 for c in cov),len(cov))} | {pct(sum(c>=.5 for c in cov),len(cov))} |")
        # 日数加重: 3日以上の区間に属する日の割合
        print(f"  HFMの日のうち3日以上続く方向区間に属する割合: {pct(sum(n for _,_,n in rH if n>=3), N)} / 合成 {pct(sum(n for _,_,n in rS if n>=3), N)}")

    # 2. 流れ有無 混同行列 / 3状態
    print("\n## 2. 流れ有無（|spread|≥5）混同行列 行=HFM 列=合成")
    fH, fS = [flow(x) for x in H], [flow(x) for x in S]
    c2 = Counter(zip(fH, fS))
    for a in (True, False):
        rn = c2[(a, True)] + c2[(a, False)]
        print(f"  {'流れ有' if a else '流れ無'}: 流れ有 {c2[(a,True)]} ({pct(c2[(a,True)],rn)}) / 流れ無 {c2[(a,False)]} ({pct(c2[(a,False)],rn)}) / 行N {rn}")
    print(f"  滞在率 流れ有: HFM {pct(sum(fH),N)} 合成 {pct(sum(fS),N)}")
    print("\n## 2b. 3状態 混同行列 行=HFM 列=合成")
    K3 = ["UP流", "DN流", "無"]
    sH, sS = [st3(x) for x in H], [st3(x) for x in S]
    c3 = Counter(zip(sH, sS))
    for a in K3:
        rn = sum(c3[(a, b)] for b in K3)
        print(f"  {a}: " + " / ".join(f"{b} {c3[(a,b)]}({pct(c3[(a,b)],rn)})" for b in K3) + f" / 行N {rn}")
    # 流れ有無が食い違った日の HFM |spread|
    mis = [abs(h) for h, s in zip(H, S) if flow(h) != flow(s)]
    print(f"  2値不一致日の HFM|spread|: 中央 {statistics.median(mis):.2f} / 3〜7帯の割合 {pct(sum(3<=m<7 for m in mis),len(mis))}")
    # 逆方向の流れ（UP流⇔DN流）
    print(f"  流れの向きが真逆（UP流⇔DN流）: {c3[('UP流','DN流')]+c3[('DN流','UP流')]} 日")

    # 3. 流れ区間の長さ
    print("\n## 3. 流れ有り区間（同じ向きの流れが連続）の長さ")
    def flow_runs(seq):
        return [n for x, s, n in runs(seq) if x != "無"]
    for nm, seq in (("HFM", sH), ("合成", sS)):
        L = flow_runs(seq)
        b = Counter("1" if n == 1 else "2" if n == 2 else "3-5" if n <= 5 else "6-10" if n <= 10 else "11+" for n in L)
        print(f"  {nm}: 区間数 {len(L)} / 中央 {statistics.median(L)} 平均 {statistics.mean(L):.1f} p75 {pctl(L,.75)} p90 {pctl(L,.9)} 最大 {max(L)} / "
              f"分布 1日:{b['1']} 2日:{b['2']} 3-5:{b['3-5']} 6-10:{b['6-10']} 11+:{b['11+']} / 流れ日の総数 {sum(L)}")
    # 経過日数の読み: 無 / 流れ1-4日目 / 流れ5日目以上(長期化)
    def age_read(seq):
        out, cnt = [], 0
        for i, x in enumerate(seq):
            cnt = cnt + 1 if i and x == seq[i - 1] and x != "無" else (1 if x != "無" else 0)
            out.append("無" if x == "無" else f"{x[:2]}-{'長期(5日+)' if cnt >= 5 else '新しい(1-4日)'}")
        return out
    aH, aS = age_read(sH), age_read(sS)
    print(f"  「一時/長期化」の読み一致（無 / 向き×{{新しい1-4日, 長期5日+}} の5状態）: {pct(sum(a==b for a,b in zip(aH,aS)),N)}")
    ca = Counter(zip(aH, aS))
    keys = sorted(set(aH) | set(aS))
    for a in keys:
        rn = sum(ca[(a, b)] for b in keys)
        if rn:
            print(f"    {a}: " + " / ".join(f"{b} {ca[(a,b)]}" for b in keys if ca[(a, b)]) + f" / 行N {rn} 一致 {pct(ca[(a,a)],rn)}")
    # HFM長期区間（5日以上）の再現
    lr = [(x, s, n) for x, s, n in runs(sH) if x != "無" and n >= 5]
    cov = [sum(sS[k] == x for k in range(s, s + n)) / n for x, s, n in lr]
    rev = [sum(sS[k] == ("DN流" if x == "UP流" else "UP流") for k in range(s, s + n)) for x, s, n in lr]
    print(f"  HFM長期流れ区間(5日+) {len(lr)} 個: 合成が同じ流れの日の割合 平均 {statistics.mean(cov)*100:.0f}% / "
          f"被覆≥70% {pct(sum(c>=.7 for c in cov),len(cov))} / 区間内に逆向きの流れが出た区間 {sum(r>0 for r in rev)}")
    # 合成側でも5日以上の流れ区間が重なるか（長期化の認知が立つか）
    sr = [(x, s, n) for x, s, n in runs(sS) if x != "無" and n >= 5]
    hit = sum(any(xs == x and s2 < s + n and s < s2 + n2 for xs, s2, n2 in sr) for x, s, n in lr)
    print(f"  HFM長期区間のうち、合成にも同じ向きの5日+区間が重なるもの: {hit}/{len(lr)}")
    hit2 = sum(any(xh == x and s2 < s + n and s < s2 + n2 for xh, s2, n2 in lr) for x, s, n in sr)
    print(f"  逆向き: 合成長期区間 {len(sr)} 個のうち HFM 5日+区間と重なるもの: {hit2}/{len(sr)}")

    # 「長期化」の頑健な読み: 直近5営業日のうち同じ向きの流れ日が3日以上
    def roll_read(seq, w=5, k=3):
        out = []
        for i in range(len(seq)):
            win = seq[max(0, i - w + 1):i + 1]
            out.append("UP継続" if win.count("UP流") >= k else "DN継続" if win.count("DN流") >= k else "-")
        return out
    rH5, rS5 = roll_read(sH), roll_read(sS)
    c5 = Counter(zip(rH5, rS5))
    print(f"  5日窓（直近5営業日中 同じ向きの流れ≥3日＝継続中）の読み一致: {pct(sum(a==b for a,b in zip(rH5,rS5)),N)} "
          f"/ 継続中日数 HFM {sum(x!='-' for x in rH5)} 合成 {sum(x!='-' for x in rS5)}")
    for a in ("UP継続", "DN継続", "-"):
        rn = sum(c5[(a, b)] for b in ("UP継続", "DN継続", "-"))
        print(f"    {a}: " + " / ".join(f"{b} {c5[(a,b)]}" for b in ("UP継続", "DN継続", "-")) + f" / 行N {rn} 一致 {pct(c5[(a,a)],rn)}")
    # 札の矢印が逆向きに出る日（両方とも方向表示＝非拮抗 かつ 方向逆）
    opp = [d for d, h, s in zip(days, H, S) if depth4(h) != "拮抗" and depth4(s) != "拮抗" and ddir(h) != ddir(s)]
    print(f"\n## 札の矢印が逆に出る日（両方非拮抗×方向逆）: {len(opp)}/{N} ({pct(len(opp),N)}) 帯内訳 "
          f"{Counter(depth4(dh[d])+'→'+depth4(ds_all[d]) for d in opp)}")

    # 判定
    dir_ok = sum(a == b for a, b in zip(dH, dS)) / N
    flow_ok = sum(a == b for a, b in zip(fH, fS)) / N
    th, ts = transitions(dH, 1), transitions(dS, 1)
    offs, _, _ = match_transitions(th, ts)
    th3, ts3 = transitions(dH, 3), transitions(dS, 3)
    offs3, _, _ = match_transitions(th3, ts3)
    print(f"\n## 判定  方向 {dir_ok*100:.1f}% (≥90) / 2値 {flow_ok*100:.1f}% (≥80) / "
          f"転換ズレ中央 全転換 {statistics.median([abs(o) for o in offs])} 日・3日+転換 {statistics.median([abs(o) for o in offs3])} 日 (≤1)")

    # 5. 直近表
    print("\n## 5. 直近 D1 札（HFM=dxy_env / 合成）")
    print("| 日付 | 曜 | HFM spread | HFM札 | 合成 spread | 合成札 | 方向 | 流れ |")
    print("|---|---|---|---|---|---|---|---|")
    W = "月火水木金土日"
    def card(s):
        lab = depth4(s)
        return lab if lab == "拮抗" else f"{'⬆' if s > 0 else '⬇'}{lab}"
    for d in days:
        if RECENT[0] <= d <= RECENT[1]:
            h, s = dh[d], ds_all[d]
            print(f"| {d} | {W[d.weekday()]} | {h:+.1f} | {card(h)} | {s:+.1f} | {card(s)} | "
                  f"{'○' if ddir(h)==ddir(s) else '×'} | {'○' if flow(h)==flow(s) else '×'} |")

    # 4. 死に帯の再現
    deathzone(syn)


def deathzone(syn):
    import analyze_dxy_di_depth_v2 as dv2
    import analyze_dxy_x_signals_v1 as v1
    keys = sorted(syn)[v1.WARMUP_DROP:]
    ser = {}
    for u in keys:
        s = syn[u]["spread"]
        t = u + timedelta(hours=v.eu_rule_offset(u))  # UTC→HFMサーバー時刻
        ser[t] = {"t": t, "di": "USD_UP" if s > 0 else "USD_DN", "depth": dv2.depth_band(abs(s)), "spread": s}
    hfm_ser = dv2.load_dxy_with_depth()
    bt_all = v1.load_csv(v1.BT_CSV)
    bt_dd = v1.dedupe_6h(bt_all)
    keys_all = [f"{di} {d}" for di in ("USD_UP", "USD_DN") for d in dv2.DEPTH_KEYS]

    def attach(rows, dmap, tcol):
        out = []
        for r in rows:
            hit = v1.join_dxy(dmap, v1.parse_dt(r[tcol]))
            if hit:
                r = dict(r); r["_k"] = f"{hit['di']} {hit['depth']}"; out.append(r)
        return out

    print("\n## 4. 死に帯の再現（BT世代2 h4adx46, 6h dedupe / 全件）")
    for nm, m in (("HFM", hfm_ser), ("合成", ser)):
        dd, raw = attach(bt_dd, m, "OpenTime"), attach(bt_all, m, "OpenTime")
        print(f"\n### {nm}  突合 dedupe {len(dd)}/{len(bt_dd)}")
        for xdir in ("BUY", "SELL"):
            v1.bt_table([r for r in dd if r["Direction"] == xdir], [r for r in raw if r["Direction"] == xdir],
                        lambda r: r["_k"], keys_all, f"[BT] XAU {xdir}")
    # 同じシグナルに付くラベルの一致
    a, b = attach(bt_dd, hfm_ser, "OpenTime"), attach(bt_dd, ser, "OpenTime")
    ka = {r["OpenTime"] + r["Direction"]: r["_k"] for r in a}
    kb = {r["OpenTime"] + r["Direction"]: r["_k"] for r in b}
    com = [k for k in ka if k in kb]
    print(f"\n同一シグナルに付く 方向×深さ ラベル一致: {pct(sum(ka[k]==kb[k] for k in com), len(com))} N={len(com)}")
    for cell in ("BUY|USD_DN 揺らぎ2-5", "SELL|USD_UP 揺らぎ2-5"):
        xd, c = cell.split("|")
        hs = {k for k in com if k.endswith(xd) and ka[k] == c}
        ss = {k for k in com if k.endswith(xd) and kb[k] == c}
        print(f"  {cell}: HFMで該当 {len(hs)} / 合成で該当 {len(ss)} / 両方 {len(hs & ss)}")

    # FW（signal_fires, time_server）
    fw_all = v1.load_csv(v1.FW_CSV)
    print(f"\n## 4b. FW signal_fires（{len(fw_all)}件）")
    for nm, m in (("HFM(〜7/14)", hfm_ser), ("合成(同期間)", {t: x for t, x in ser.items() if t <= max(hfm_ser)}),
                  ("合成(全期間〜11/20)", ser)):
        fw = attach(fw_all, m, "time_server")
        for xdir in ("BUY", "SELL"):
            v1.fw_table([r for r in fw if r["direction"] == xdir], lambda r: r["_k"],
                        [k for k in keys_all if "揺らぎ" in k], f"[{nm}] FW {xdir} 揺らぎ帯 (突合{len(fw)})")


if __name__ == "__main__":
    main()
