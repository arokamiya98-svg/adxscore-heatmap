#!/usr/bin/env python3
"""
generate_d1_env_json.py
───────────────────────
D1環境札 Widget 用 JSON 生成（SPEC: data/scriptable/SPEC_d1_env_widget_v1.md §3）

入力: mt5_data/daily/daily_aggregate.csv（UTF-8-sig・VPS正本・読み取りのみ）
出力: docs/d1_env.json

生成ロジック（SPEC §3 の表に準拠）:
  adx_state       : d1_adx22 < 20 → "RANGE"（方向を出さない）/ >= 20 → d1_di_dir
  di_spread       : 最新 d1_di_spread（符号付き・負=DI-優勢）
  spread_range_5d : 直近5営業日の d1_di_spread の min/max
  spread_label    : |spread| 段階  <5 拮抗 / 5〜10 揺らぎ / 10〜16 優勢 / ≥16 一方通行
  atr_ratio       : 最新 d1_atr22_42_ratio
  atr_cross_dir   : ratio >= 1.0 → "UP"（拡張）/ < 1.0 → "DOWN"（収束）
  atr_cross_days  : 1.0跨ぎの直近位置からの営業日数。範囲内に跨ぎ無し → 99

実装メモ（2026-07-10 ブン）:
  ⚠️ 土曜行の除外 — daily_aggregate.csv には土曜行が混ざる（VPS EA は
     土曜JST朝も稼働し、D1値は金曜バーの複製になる。例: 2026-07-04 行は
     2026-07-03 と同一のD1値）。EA の d1_cross_bars は D1バー数＝営業日
     ベースなので、CSV行数を素で数えると土曜行の分だけズレる。
     → D1系列は weekday>=5（土日）の行を除外してから数える。
     spread_range_5d も同じ除外後系列の直近5行（=真の直近5営業日）を使う。
  ・カウント規約 — クロス後最初の同サイド行を「0日目」とする
     （= 同サイド営業日行数 - 1）。突合実績: signal_fires.csv #416
     （2026-07-08 発火, d1_cross_bars=21, cross_dir=BU）と一致。
  ・動脈原則 — データ増加が常態のため固定件数 assert は置かない。
  ・ラベル分類は表示値（丸め後）で行い、数値とラベルの見た目矛盾を防ぐ。
"""

import csv
import json
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DAILY_AGG = ROOT / "mt5_data" / "daily" / "daily_aggregate.csv"
OUT_JSON = ROOT / "docs" / "d1_env.json"

CROSS_DAYS_CAP = 99  # 跨ぎ無し/超長期は 99 固定（widget側で "99+" 表示）


def load_business_rows(path):
    """daily_aggregate.csv を読み、土日行を除外した営業日行リストを返す。

    各要素: {"date": date, "spread": float, "ratio": float, "row": dict}
    パース不能行は黙ってスキップ（動脈は増加が常態・防御的に）。
    """
    rows = []
    with open(path, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                d = datetime.strptime(r["date"], "%Y-%m-%d").date()
                spread = float(r["d1_di_spread"])
                ratio = float(r["d1_atr22_42_ratio"])
            except (KeyError, ValueError, TypeError):
                continue
            if d.weekday() >= 5:  # 土日行=金曜D1バーの複製 → 除外
                continue
            rows.append({"date": d, "spread": spread, "ratio": ratio, "row": r})
    return rows


def spread_label(abs_spread):
    """|spread| の段階ラベル（SPEC §3・2026-03〜07実測102日の四分位ベース）"""
    if abs_spread < 5:
        return "拮抗"
    if abs_spread < 10:
        return "揺らぎ"
    if abs_spread < 16:
        return "優勢"
    return "一方通行"


def atr_cross_days(ratios):
    """ratio系列（古→新）を最新から遡り、1.0跨ぎからの営業日数を返す。

    クロス後最初の同サイド行を0日目とする（EA d1_cross_bars と同規約）。
    データ範囲内に跨ぎが無ければ 99。
    """
    latest_up = ratios[-1] >= 1.0
    same_side = 0
    for r in reversed(ratios):
        if (r >= 1.0) == latest_up:
            same_side += 1
        else:
            return min(same_side - 1, CROSS_DAYS_CAP)
    return CROSS_DAYS_CAP


def main():
    if not DAILY_AGG.exists():
        print(f"❌ 入力が見つかりません: {DAILY_AGG}", file=sys.stderr)
        print("   git pull --rebase origin main で VPS プールを受信してください。", file=sys.stderr)
        return 1

    rows = load_business_rows(DAILY_AGG)
    if not rows:
        print(f"❌ 有効行ゼロ: {DAILY_AGG}", file=sys.stderr)
        return 1

    latest = rows[-1]
    lr = latest["row"]

    adx22 = round(float(lr["d1_adx22"]), 1)
    di_plus = round(float(lr["d1_di_plus"]), 1)
    di_minus = round(float(lr["d1_di_minus"]), 1)
    di_spread = round(latest["spread"], 1)
    atr_ratio = round(latest["ratio"], 2)

    # adx_state: ADX閾値未達=RANGE（方向を出さない）/ 達 → DI方向そのまま
    adx_state = "RANGE" if adx22 < 20 else lr["d1_di_dir"].strip()

    # 直近5営業日の spread レンジ（土日除外後系列の末尾5行）
    last5 = [r["spread"] for r in rows[-5:]]
    range_5d = {"min": round(min(last5), 1), "max": round(max(last5), 1)}

    out = {
        "updated": latest["date"].isoformat(),
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "adx22": adx22,
        "adx_state": adx_state,
        "di_plus": di_plus,
        "di_minus": di_minus,
        "di_spread": di_spread,
        "spread_range_5d": range_5d,
        "spread_label": spread_label(abs(di_spread)),
        "atr_ratio": atr_ratio,
        "atr_cross_dir": "UP" if latest["ratio"] >= 1.0 else "DOWN",
        "atr_cross_days": atr_cross_days([r["ratio"] for r in rows]),
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"  🏷  d1_env.json: {out['updated']} {out['adx_state']} ADX{out['adx22']} "
          f"DI{out['di_spread']:+.1f}({out['spread_label']}) "
          f"ATR {out['atr_cross_dir']} {out['atr_cross_days']}日 → {OUT_JSON.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
