#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Yahoo DX-Y.NYB vs MT5 USDIndex の ADX(56)/DIスプレッド物差し検証
  1. Yahoo chart API から 1h×3mo 取得（null bar除外・形成中バー除外）
  2. Wilder ADX(56)/DI± を計算（widget実装と同式）
  3. MT5 CSV (DXY_ADX_Timeseries_v1.csv) と時刻オフセット自動検出で突合
  4. spread の相関・平均絶対差・深さラベル一致率を報告
"""
import json
import ssl
import statistics
import urllib.request
from datetime import datetime, timezone, timedelta

# Homebrew Python 3.14 の証明書未設定対策（検証スクリプト用途につき許容）
SSL_CTX = ssl._create_unverified_context()

MT5_CSV = "/Users/aro/Desktop/ADXSCORE/data/dxy/DXY_ADX_Timeseries_v1.csv"
PERIOD = 56

def fetch_yahoo():
    url = ("https://query1.finance.yahoo.com/v8/finance/chart/DX-Y.NYB"
           "?interval=1h&range=3mo")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=20, context=SSL_CTX) as r:
        d = json.load(r)
    res = d["chart"]["result"][0]
    ts = res["timestamp"]
    q = res["indicators"]["quote"][0]
    bars = []
    for i in range(len(ts)):
        h, l, c = q["high"][i], q["low"][i], q["close"][i]
        if h is None or l is None or c is None:
            continue
        bars.append({"t": datetime.fromtimestamp(ts[i], timezone.utc),
                     "h": h, "l": l, "c": c})
    # 形成中バー（最終）を落とす
    return bars[:-1]

def wilder_adx(bars, period):
    """widget実装（コー）と同式。各バー時点の adx, di+, di- 系列を返す"""
    n = len(bars)
    tr = [0.0]*n; dmp = [0.0]*n; dmm = [0.0]*n
    for i in range(1, n):
        h, l, pc = bars[i]["h"], bars[i]["l"], bars[i-1]["c"]
        tr[i] = max(h - l, abs(h - pc), abs(l - pc))
        up = h - bars[i-1]["h"]
        dn = bars[i-1]["l"] - l
        dmp[i] = up if (up > dn and up > 0) else 0.0
        dmm[i] = dn if (dn > up and dn > 0) else 0.0
    out = [None]*n
    if n < period*2 + 1:
        return out
    s_tr = sum(tr[1:period+1]); s_p = sum(dmp[1:period+1]); s_m = sum(dmm[1:period+1])
    dx_hist = []
    adx = None
    for i in range(period+1, n):
        s_tr = s_tr - s_tr/period + tr[i]
        s_p = s_p - s_p/period + dmp[i]
        s_m = s_m - s_m/period + dmm[i]
        dip = 100*s_p/s_tr if s_tr > 0 else 0
        dim = 100*s_m/s_tr if s_tr > 0 else 0
        dx = 100*abs(dip-dim)/(dip+dim) if (dip+dim) > 0 else 0
        if adx is None:
            dx_hist.append(dx)
            if len(dx_hist) == period:
                adx = sum(dx_hist)/period
        else:
            adx = (adx*(period-1) + dx)/period
        if adx is not None:
            out[i] = {"adx": adx, "dip": dip, "dim": dim, "spread": dip-dim}
    return out

def depth(sp):
    a = abs(round(sp, 1))
    return "拮抗" if a < 2 else ("揺らぎ" if a < 5 else ("優勢" if a < 10 else "一方通行"))

def main():
    bars = fetch_yahoo()
    print(f"Yahoo bars(有効): {len(bars)}  {bars[0]['t']} 〜 {bars[-1]['t']} UTC")
    calc = wilder_adx(bars, PERIOD)

    # MT5側読み込み
    import csv, io
    with open(MT5_CSV, encoding="utf-16") as f:
        mt5 = {}
        for r in csv.DictReader(f):
            t = datetime.strptime(r["Time"], "%Y.%m.%d %H:%M")
            mt5[t] = {"adx": float(r["ADX"]), "spread": float(r["DI_Plus"]) - float(r["DI_Minus"]),
                      "close": float(r["Close"])}
    print(f"MT5 rows: {len(mt5)}")

    # 時刻オフセット検出（MT5サーバー時刻 = UTC+X）: close相関が最大のXを採用
    yahoo_by_t = {b["t"].replace(tzinfo=None): i for i, b in enumerate(bars)}
    best = None
    for off in range(0, 5):
        pairs = []
        for mt, mv in mt5.items():
            yt = mt - timedelta(hours=off)
            i = yahoo_by_t.get(yt)
            if i is not None:
                pairs.append((mv["close"], bars[i]["c"]))
        if len(pairs) < 100:
            continue
        diffs = [abs(a-b) for a, b in pairs]
        mad = statistics.mean(diffs)
        if best is None or mad < best[1]:
            best = (off, mad, len(pairs))
    off, mad, np_ = best
    print(f"時刻オフセット検出: MT5 = UTC+{off}（close平均絶対差 {mad:.4f}, N={np_}）")

    # spread突合
    pairs = []
    for mt, mv in mt5.items():
        yt = mt - timedelta(hours=off)
        i = yahoo_by_t.get(yt)
        if i is not None and calc[i] is not None:
            pairs.append((mt, mv, calc[i]))
    pairs.sort()
    print(f"\nADX/spread突合可能バー: {len(pairs)}")
    sp_m = [p[1]["spread"] for p in pairs]
    sp_y = [p[2]["spread"] for p in pairs]
    adx_m = [p[1]["adx"] for p in pairs]
    adx_y = [p[2]["adx"] for p in pairs]

    def corr(a, b):
        ma, mb = statistics.mean(a), statistics.mean(b)
        cov = sum((x-ma)*(y-mb) for x, y in zip(a, b))
        va = sum((x-ma)**2 for x in a); vb = sum((y-mb)**2 for y in b)
        return cov/(va**0.5 * vb**0.5) if va > 0 and vb > 0 else 0

    print(f"spread: 相関={corr(sp_m, sp_y):.3f}  平均絶対差={statistics.mean(abs(a-b) for a,b in zip(sp_m,sp_y)):.2f}")
    print(f"ADX56 : 相関={corr(adx_m, adx_y):.3f}  平均絶対差={statistics.mean(abs(a-b) for a,b in zip(adx_m,adx_y)):.2f}")

    match = sum(1 for a, b in zip(sp_m, sp_y) if depth(a) == depth(b))
    print(f"深さラベル一致率: {match}/{len(pairs)} = {match/len(pairs)*100:.1f}%")

    # 不一致の内訳（隣接帯ズレか飛びズレか）
    order = ["拮抗", "揺らぎ", "優勢", "一方通行"]
    adjacent = sum(1 for a, b in zip(sp_m, sp_y)
                   if depth(a) != depth(b) and abs(order.index(depth(a)) - order.index(depth(b))) == 1)
    print(f"不一致のうち隣接帯ズレ: {adjacent}/{len(pairs)-match}")

    # 終端比較
    mt, mv, yv = pairs[-1]
    print(f"\n終端バー {mt}(MT5時刻): MT5 spread={mv['spread']:+.1f}({depth(mv['spread'])}) "
          f"/ Yahoo spread={yv['spread']:+.1f}({depth(yv['spread'])})")

if __name__ == "__main__":
    main()
