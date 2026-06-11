#!/usr/bin/env python3
"""
observe_signal_quality.py — マニの部屋 初回構造観察

研究目的（固定）:
  日時+価格をキーとして、エントリー時点の市場環境を後付け取得し、
  どの市場環境で期待値が発生しているかを研究する。

このスクリプトの観察対象:
  1. 「消されたシグナル」検出 = 実損益マイナス × h1_mfe_usd_48h 大
     → 決済判断で消されてしまったシグナルの構造抽出
  2. シグナルトレード比率 + シグナルの質評価
     → h1_pattern × h1_atr_zone × h4_phase_auto の組み合わせ別 MAE/MFE 分布
     → 「シグナル評価のための勝率」は研究目的に合致（集計ではなく構造発見）
  3. 今通じてないシグナルトレード
     → 時系列での MFE 中央値変化（環境変化の検出）

集計レポートではなく、**構造発見** のための観察スクリプト。
"""
import csv
from collections import defaultdict
from pathlib import Path
from statistics import median

CSV_PATH = "data/mani_room/enriched/trades_enriched_full.csv"

# シグナル候補パターン (v4 mq5 系で発火するパターン名)
SIGNAL_PATTERNS = {"RISING_DECEL", "EXPANDING", "RISING_ACCEL"}


def load_trades(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def safe_float(s, default=None):
    if s is None or s == "":
        return default
    try:
        return float(s)
    except ValueError:
        return default


def safe_int(s, default=None):
    if s is None or s == "":
        return default
    try:
        return int(float(s))
    except ValueError:
        return default


def is_signal_candidate(r):
    """h1_pattern が v4 系シグナル発火パターンならシグナル候補"""
    return r.get("h1_pattern", "") in SIGNAL_PATTERNS


def section(title):
    print(f"\n{'='*70}")
    print(f" {title}")
    print(f"{'='*70}")


def print_kv(rows, max_label=24):
    for label, val in rows:
        print(f"  {label:<{max_label}} {val}")


# ============================================================
# 観察 1: 「消されたシグナル」検出 (D)
# ============================================================
def observe_killed_signals(trades):
    section("[D] 決済判断で消されたシグナル候補")
    print("  抽出条件: 実損益 ≤ 0 かつ h1_mfe_usd_48h が大")
    print()

    killed = []
    for r in trades:
        pnl_jpy = safe_float(r.get("損益"), default=0) or 0
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        if mfe is None:
            continue
        if pnl_jpy <= 0:
            killed.append((mfe, r))

    killed.sort(key=lambda x: -x[0])

    print(f"  該当件数: {len(killed)} / 全 {len(trades)} 件")
    print()
    print(f"  上位10件 (h1_mfe_usd_48h 大きい順):")
    print(f"  {'-' * 110}")
    print(f"  {'ID':4} {'entry_jst':17} {'dir':5} {'pnl_jpy':>8}  "
          f"{'mfe48h':>7} {'mae48h':>7} {'mfe_idx':>4}  "
          f"{'pattern':14} {'zone':7} {'h4_phase':8} {'d1_phase':6}")
    print(f"  {'-' * 110}")
    for mfe, r in killed[:10]:
        mae = safe_float(r.get("h1_mae_usd_48h"), 0) or 0
        mfe_idx = safe_int(r.get("h1_mfe_bar_idx_48h"), 0)
        print(f"  {r['trade_id']:4} {r['entry_jst']:17} {r['direction']:5} "
              f"{safe_float(r.get('損益'), 0):>8.0f}  "
              f"{mfe:>7.1f} {mae:>7.1f} {mfe_idx:>4}  "
              f"{r.get('h1_pattern',''):14} {r.get('h1_atr_zone',''):7} "
              f"{r.get('h4_phase_auto',''):8} {r.get('d1_phase',''):6}")

    # 「決済判断と MFE のギャップ」を構造で見る
    if killed:
        mfes = [mfe for mfe, _ in killed]
        print()
        print(f"  消されたシグナル候補の MFE 分布:")
        print(f"    中央値: {median(mfes):.1f} USD")
        print(f"    最大値: {max(mfes):.1f} USD")
        print(f"    100 USD 超: {sum(1 for m in mfes if m > 100)} 件")
        print(f"    300 USD 超: {sum(1 for m in mfes if m > 300)} 件")
        print(f"    → これらは「48h追えてたら取れた可能性」のあるシグナル")


# ============================================================
# 観察 2: シグナル候補 vs 非シグナル の構造比較
# ============================================================
def observe_signal_vs_nonsignal(trades):
    section("[シグナル評価] h1_pattern 別の MAE/MFE 分布")

    by_pattern = defaultdict(list)
    for r in trades:
        p = r.get("h1_pattern", "?")
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        mae = safe_float(r.get("h1_mae_usd_48h"))
        pnl = safe_float(r.get("損益"), 0) or 0
        if mfe is None or mae is None:
            continue
        by_pattern[p].append((mfe, mae, pnl))

    print(f"\n  パターン別件数 + MFE/MAE 中央値:")
    print(f"  {'-' * 95}")
    print(f"  {'pattern':16} {'件数':>4}  "
          f"{'mfe中央':>8} {'mae中央':>8} {'mfe/mae':>7}  "
          f"{'勝(pnl>0)':>9} {'負(pnl<0)':>9} {'分(pnl=0)':>9}")
    print(f"  {'-' * 95}")
    for p, vals in sorted(by_pattern.items(), key=lambda x: -len(x[1])):
        mfes = [v[0] for v in vals]
        maes = [v[1] for v in vals]
        pnls = [v[2] for v in vals]
        wins = sum(1 for p_ in pnls if p_ > 0)
        loses = sum(1 for p_ in pnls if p_ < 0)
        flats = sum(1 for p_ in pnls if p_ == 0)
        mfe_med = median(mfes)
        mae_med = median(maes)
        ratio = mfe_med / mae_med if mae_med > 0 else float("inf")
        signal_mark = "★" if p in SIGNAL_PATTERNS else " "
        print(f"  {signal_mark}{p:15} {len(vals):>4}  "
              f"{mfe_med:>8.1f} {mae_med:>8.1f} {ratio:>7.2f}  "
              f"{wins:>9} {loses:>9} {flats:>9}")
    print(f"\n  ★ = v4 シグナル発火候補パターン")
    print(f"  mfe/mae 比 が大 = 「シグナルが本来持つ期待値（48h視点）」が高い")


# ============================================================
# 観察 3: ATR Zone × Pattern の構造
# ============================================================
def observe_zone_pattern_cross(trades):
    section("[BT世代2検証] h1_atr_zone × h1_pattern クロス")

    by_cross = defaultdict(list)
    for r in trades:
        z = r.get("h1_atr_zone", "?")
        p = r.get("h1_pattern", "?")
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        mae = safe_float(r.get("h1_mae_usd_48h"))
        if mfe is None or mae is None:
            continue
        by_cross[(z, p)].append((mfe, mae))

    print(f"\n  (ATR Zone, Pattern) 別件数 + MFE/MAE 中央値:")
    print(f"  {'-' * 75}")
    print(f"  {'zone':8} {'pattern':16} {'件数':>4}  {'mfe中央':>8} {'mae中央':>8} {'mfe/mae':>7}")
    print(f"  {'-' * 75}")
    for (z, p), vals in sorted(by_cross.items(), key=lambda x: -len(x[1])):
        mfes = [v[0] for v in vals]
        maes = [v[1] for v in vals]
        mfe_med = median(mfes)
        mae_med = median(maes)
        ratio = mfe_med / mae_med if mae_med > 0 else float("inf")
        bt_note = ""
        if z == "NORMAL" and p == "RISING_DECEL":
            bt_note = "  ← BT世代2「最強」候補"
        elif z == "HIGH" and p == "RISING_DECEL":
            bt_note = "  ← BT世代2「罠」候補"
        elif z == "HIGH" and p == "EXPANDING":
            bt_note = "  ← BT世代2 第2強"
        print(f"  {z:8} {p:16} {len(vals):>4}  "
              f"{mfe_med:>8.1f} {mae_med:>8.1f} {ratio:>7.2f}{bt_note}")


# ============================================================
# 観察 4: 凪離脱フェイク検証
# ============================================================
def observe_nagi_riddatsu(trades):
    section("[BT世代2検証] h4_phase_auto 別の MAE/MFE 分布（凪離脱フェイク検証）")

    by_phase = defaultdict(list)
    for r in trades:
        ph = r.get("h4_phase_auto", "?")
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        mae = safe_float(r.get("h1_mae_usd_48h"))
        if mfe is None or mae is None:
            continue
        by_phase[ph].append((mfe, mae))

    print(f"\n  h4_phase_auto 別件数 + MFE/MAE 中央値:")
    print(f"  {'-' * 80}")
    print(f"  {'h4_phase_auto':14} {'件数':>4}  {'mfe中央':>8} {'mae中央':>8} {'mfe/mae':>7}  注釈")
    print(f"  {'-' * 80}")
    for ph, vals in sorted(by_phase.items(), key=lambda x: -len(x[1])):
        mfes = [v[0] for v in vals]
        maes = [v[1] for v in vals]
        mfe_med = median(mfes)
        mae_med = median(maes)
        ratio = mfe_med / mae_med if mae_med > 0 else float("inf")
        note = ""
        if ph == "凪離脱":
            note = "← BT世代2 PF0.49 のフェイク帯"
        elif ph == "BU":
            note = "← BU期、PatD仮説1の主戦場"
        elif ph == "PD":
            note = "← PD期"
        elif ph == "収束底":
            note = "← 収束末期"
        print(f"  {ph:14} {len(vals):>4}  "
              f"{mfe_med:>8.1f} {mae_med:>8.1f} {ratio:>7.2f}  {note}")


# ============================================================
# 観察 5: D1 Phase 別の構造
# ============================================================
def observe_d1_phase(trades):
    section("[D1 大局フェーズ別] MFE/MAE 分布")

    by_phase = defaultdict(list)
    for r in trades:
        ph = r.get("d1_phase", "?")
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        mae = safe_float(r.get("h1_mae_usd_48h"))
        if mfe is None or mae is None:
            continue
        by_phase[ph].append((mfe, mae))

    print(f"\n  d1_phase 別件数 + MFE/MAE 中央値:")
    print(f"  {'-' * 60}")
    print(f"  {'d1_phase':10} {'件数':>4}  {'mfe中央':>8} {'mae中央':>8} {'mfe/mae':>7}")
    print(f"  {'-' * 60}")
    for ph, vals in sorted(by_phase.items(), key=lambda x: -len(x[1])):
        mfes = [v[0] for v in vals]
        maes = [v[1] for v in vals]
        mfe_med = median(mfes)
        mae_med = median(maes)
        ratio = mfe_med / mae_med if mae_med > 0 else float("inf")
        print(f"  {ph:10} {len(vals):>4}  "
              f"{mfe_med:>8.1f} {mae_med:>8.1f} {ratio:>7.2f}")


# ============================================================
# 観察 6: 時系列での MFE 中央値変化（「今通じてない」の検出）
# ============================================================
def observe_time_drift(trades):
    section("[環境変化検出] 月別 MFE 中央値の推移")
    print("  「シグナルが今も機能しているか」「環境変化が起きているか」の構造観察")

    by_month = defaultdict(list)
    for r in trades:
        date = r.get("entry_jst", "")
        if not date:
            continue
        ym = date[:7]  # yyyy-mm
        mfe = safe_float(r.get("h1_mfe_usd_48h"))
        mae = safe_float(r.get("h1_mae_usd_48h"))
        if mfe is None or mae is None:
            continue
        is_sig = is_signal_candidate(r)
        by_month[ym].append((mfe, mae, is_sig))

    print(f"\n  月別:")
    print(f"  {'-' * 75}")
    print(f"  {'月':10} {'件数':>4} {'シグ候補':>8}  {'mfe中央':>8} {'mae中央':>8} {'mfe/mae':>7}")
    print(f"  {'-' * 75}")
    for ym in sorted(by_month.keys()):
        vals = by_month[ym]
        mfes = [v[0] for v in vals]
        maes = [v[1] for v in vals]
        sigs = sum(1 for v in vals if v[2])
        mfe_med = median(mfes)
        mae_med = median(maes)
        ratio = mfe_med / mae_med if mae_med > 0 else float("inf")
        print(f"  {ym:10} {len(vals):>4} {sigs:>8}  "
              f"{mfe_med:>8.1f} {mae_med:>8.1f} {ratio:>7.2f}")


def main():
    if not Path(CSV_PATH).exists():
        print(f"[ERROR] CSV が無い: {CSV_PATH}")
        return

    trades = load_trades(CSV_PATH)
    print(f"読込: {CSV_PATH} ({len(trades)} 件)")

    observe_killed_signals(trades)
    observe_signal_vs_nonsignal(trades)
    observe_zone_pattern_cross(trades)
    observe_nagi_riddatsu(trades)
    observe_d1_phase(trades)
    observe_time_drift(trades)

    print()
    print("=" * 70)
    print(" 構造観察 完了")
    print("=" * 70)
    print()
    print("【提案ルール再確認】")
    print("  この観察は「集計レポート」ではなく「構造発見」のため。")
    print("  次の観察を提案する場合、必ず「何の仮説検証に使うか」を明示すること。")


if __name__ == "__main__":
    main()
